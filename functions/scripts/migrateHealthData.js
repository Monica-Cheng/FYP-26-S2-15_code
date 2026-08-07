#!/usr/bin/env node
// functions/scripts/migrateHealthData.js
//
// One-time migration: bundles each users/{uid}'s plaintext injuries/dob/
// biologicalSex/heightCm/weightKg/goalWeight/weightGoalActive/
// dailyCalorieGoal/weeklyCalorieGoal/monthlyCalorieGoal/calorieGoalActive
// into a single encrypted users/{uid}.encryptedHealthData blob (same
// AES-256-GCM format the getHealthData/updateHealthData Cloud Functions
// in ../index.js use — iv.authTag.ciphertext, all 3 parts base64), and
// maintains the new plaintext injuryCount field the same way
// updateHealthData() does.
//
// NOT deployed — this is a standalone Node script, run manually against
// the live project with a service-account credential. It is not required
// by ../index.js and exports nothing Cloud Functions would recognize, so
// `firebase deploy --only functions` never picks it up.
//
// The encrypt/decrypt logic here is a deliberate, separate copy of
// encryptHealthData()/decryptHealthData() in ../index.js, not a shared
// import — ../index.js calls initializeApp()/defineSecret() at module
// load time in a way that's meant for the Cloud Functions runtime, not a
// one-off script invocation, so duplicating the small pure functions
// here (and keeping HEALTH_DATA_FIELDS below in sync by hand — see that
// constant's own comment in ../index.js) is simpler and safer than
// trying to reuse the module directly.
//
// RECOVERY CASE (added after a real incident): the Cloud Functions were
// deployed before this script ever ran, so the live app started calling
// updateHealthData() on its own — creating a PARTIAL encryptedHealthData
// blob for any user who touched Health Profile in the meantime (e.g.
// toggling calorie tracking creates a blob containing only
// {calorieGoalActive}, missing injuries/dob/everything else, since
// updateHealthData() merges onto whatever existed before — which was
// nothing). The original version of this script treated "blob already
// exists" as "already migrated, skip" — which is exactly wrong for these
// partial blobs: it would permanently skip them, leaving injuries/dob/
// etc. missing from the blob (and injuryCount stuck at 0) forever, since
// plaintext deletion would eventually make recovery from plaintext
// impossible too.
//
// Fixed behavior: an existing blob is only skipped if it's COMPLETE —
// i.e. it already has every field the plaintext doc currently has. If
// it's missing any field plaintext still has, the blob is treated as
// PARTIAL/incomplete and is fully rebuilt (overwritten) from current
// plaintext values, exactly like a fresh migration. A field's VALUE
// differing between plaintext and an existing (but otherwise complete)
// blob is deliberately NOT treated as "incomplete" — that could be a
// genuine edit made through the app since the blob was created, and this
// script only recovers truly MISSING keys, never second-guesses a
// present one. This recovery logic assumes plaintext fields are still
// fully intact — it has no way to recover a field that's already been
// deleted from plaintext, so always run this BEFORE ever using
// --delete-plaintext on a given user.
//
// Fully idempotent, safe to re-run at any stage. Per user, one of 4
// things happens each run, decided independently of what any PREVIOUS
// run already did to that same user:
//
//   - No encryptedHealthData yet: encrypt + write it (+ injuryCount)
//     from current plaintext, and ALSO delete the old plaintext fields
//     in the same write if --delete-plaintext was passed alongside
//     --commit.
//   - encryptedHealthData exists but is missing a field plaintext still
//     has (the recovery case above): rebuild + overwrite it (+
//     injuryCount) from current plaintext, same as a fresh migration —
//     also deletes plaintext in the same write if --delete-plaintext was
//     passed alongside --commit.
//   - encryptedHealthData exists and already has everything plaintext
//     currently has, AND --delete-plaintext is passed: don't touch/
//     re-encrypt the blob, just delete any of the 11 plaintext fields
//     still lingering on that user's doc.
//   - encryptedHealthData exists and already has everything plaintext
//     currently has, and --delete-plaintext is NOT passed: nothing to
//     do, skipped entirely.
//
// Every user gets a printed line in EVERY run (including dry runs),
// covering all 4 cases above (including the "already complete, skipped"
// case) — so a plain dry run alone is a full audit: which users have no
// blob yet, which have a partial blob needing recovery, and which are
// already fully migrated.
//
// This means you can either do it all in one pass (--commit
// --delete-plaintext together) or two separate passes with a manual
// verification step in between (--commit first, confirm the data looks
// right, then --commit --delete-plaintext later) — see the step-by-step
// instructions at the bottom of this file, which use the safer two-pass
// approach.
//
// USAGE
// -----
//   HEALTH_DATA_ENCRYPTION_KEY=<the same hex key already set via
//     `firebase functions:secrets:set HEALTH_DATA_ENCRYPTION_KEY`> \
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//   node functions/scripts/migrateHealthData.js [--commit] [--delete-plaintext]
//
// With no flags: a dry run — prints exactly what every mode above would
// do for every user, writes nothing at all. Always run this first.

const crypto = require("crypto");
// Modular subpath imports, not `require("firebase-admin")` — same pattern
// ../index.js already uses. The installed firebase-admin version (14.x)
// has no `admin.credential`/`admin.firestore` namespace on the top-level
// CJS require at all (applicationDefault/cert/initializeApp are flat
// top-level exports instead, and getFirestore/FieldValue live only under
// "firebase-admin/firestore") — using the same modular imports ../index.js
// already relies on (and is known to work against this exact install)
// avoids relying on a compat API this version doesn't actually have.
const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const COMMIT = process.argv.includes("--commit");
const DELETE_PLAINTEXT = process.argv.includes("--delete-plaintext");

// Keep this in sync by hand with HEALTH_DATA_FIELDS in ../index.js — see
// that constant's own comment for why this script keeps a separate copy
// rather than importing it.
const HEALTH_DATA_FIELDS = [
  "injuries",
  "injuryFilteringEnabled",
  "dob",
  "biologicalSex",
  "heightCm",
  "weightKg",
  "goalWeight",
  "weightGoalActive",
  "dailyCalorieGoal",
  "weeklyCalorieGoal",
  "monthlyCalorieGoal",
  "calorieGoalActive",
];

/**
 * Same algorithm/format as encryptHealthData() in ../index.js — see that
 * function's own doc comment for the full reasoning (AES-256-GCM,
 * per-call random IV, iv.authTag.ciphertext base64 layout).
 *
 * @param {object} data
 * @param {string} keyHex
 * @return {string}
 */
function encryptHealthData(data, keyHex) {
  const key = Buffer.from(keyHex, "hex");
  if (key.length !== 32) {
    throw new Error(
        "HEALTH_DATA_ENCRYPTION_KEY must be a 32-byte hex-encoded key " +
        "(64 hex characters) — the exact same value already set via " +
        "`firebase functions:secrets:set HEALTH_DATA_ENCRYPTION_KEY`.",
    );
  }
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(data), "utf8"),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();
  return [iv, authTag, ciphertext]
      .map((buf) => buf.toString("base64"))
      .join(".");
}

/**
 * Reverses encryptHealthData() — same format/algorithm decryptHealthData()
 * in ../index.js uses. Needed here (added for the recovery case) to
 * inspect what an EXISTING blob already contains, so this script can tell
 * a complete blob apart from a partial one instead of treating "a blob
 * exists at all" as "already fully migrated." Throws on malformed/
 * tampered/wrong-key ciphertext rather than returning a partial object.
 *
 * @param {string} encrypted
 * @param {string} keyHex
 * @return {object}
 */
function decryptHealthData(encrypted, keyHex) {
  const key = Buffer.from(keyHex, "hex");
  if (key.length !== 32) {
    throw new Error(
        "HEALTH_DATA_ENCRYPTION_KEY must be a 32-byte hex-encoded key " +
        "(64 hex characters).",
    );
  }
  const parts = (encrypted || "").split(".");
  if (parts.length !== 3) {
    throw new Error("encryptedHealthData is malformed (expected 3 parts).");
  }
  const [ivB64, authTagB64, ciphertextB64] = parts;
  const iv = Buffer.from(ivB64, "base64");
  const authTag = Buffer.from(authTagB64, "base64");
  const ciphertext = Buffer.from(ciphertextB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(authTag);
  const plaintext = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]).toString("utf8");
  return JSON.parse(plaintext);
}

/**
 * Queues (or, in dry-run mode, just logs) whatever this one user needs
 * this run — see the file header for the 4 possible outcomes. Batches
 * writes at Firestore's 500-per-batch limit, same chunking convention
 * sendAdminBroadcast() in ../index.js already uses.
 *
 * @param {FirebaseFirestore.QueryDocumentSnapshot} doc
 * @param {string} keyHex
 * @param {{batch: FirebaseFirestore.WriteBatch, count: number}} batchState
 * @param {FirebaseFirestore.Firestore} db
 * @return {Promise<"migrated"|"recovered"|"plaintext-deleted"|"skipped">}
 */
async function processUser(doc, keyHex, batchState, db) {
  const data = doc.data();
  const presentFields = HEALTH_DATA_FIELDS.filter((f) =>
    Object.prototype.hasOwnProperty.call(data, f));
  const rawBlob = typeof data.encryptedHealthData === "string" &&
      data.encryptedHealthData !== "" ?
    data.encryptedHealthData :
    null;

  // Whether an existing blob is missing any field the plaintext doc
  // still has — the recovery case. null blob = treated the same as "no
  // blob" further down (never "complete").
  let blobIsIncomplete = false;
  if (rawBlob) {
    let existingBlobData;
    try {
      existingBlobData = decryptHealthData(rawBlob, keyHex);
    } catch (err) {
      console.error(
          `users/${doc.id}: encryptedHealthData exists but failed to ` +
          `decrypt (${err.message}) — leaving it untouched, skipping.`,
      );
      return "skipped";
    }
    blobIsIncomplete = presentFields.some((f) =>
      !Object.prototype.hasOwnProperty.call(existingBlobData, f));
  }

  if (rawBlob && !blobIsIncomplete) {
    // Blob already has everything plaintext currently offers — nothing
    // to recover. Still honor --delete-plaintext if it was asked for.
    if (DELETE_PLAINTEXT && presentFields.length > 0) {
      console.log(
          `${COMMIT ? "Deleting plaintext for" : "Would delete plaintext for"} ` +
          `users/${doc.id}: ${presentFields.join(", ")}`,
      );
      if (COMMIT) {
        const update = {};
        for (const field of presentFields) {
          update[field] = FieldValue.delete();
        }
        await queueWrite(doc.ref, update, batchState, db);
      }
      return "plaintext-deleted";
    }
    console.log(
        `users/${doc.id}: encryptedHealthData already complete — skipped.`,
    );
    return "skipped";
  }

  // Either no blob yet, or an existing blob missing fields plaintext
  // still has (recovery case) — in both cases, (re)build the blob fully
  // from CURRENT plaintext values, since plaintext is still fully intact
  // (deletion is a separate, later, explicitly-gated stage) and is the
  // authoritative source here. This OVERWRITES any partial blob the live
  // app may have already created — see the recovery-case comment at the
  // top of this file for why that's the correct fix, not a regression.
  const healthData = {};
  for (const field of presentFields) healthData[field] = data[field];
  const injuries = Array.isArray(healthData.injuries) ?
    healthData.injuries :
    [];
  const injuryCount = injuries.length;

  const verb = rawBlob ?
    (COMMIT ? "Recovering" : "Would recover") :
    (COMMIT ? "Migrating" : "Would migrate");
  console.log(
      `${verb} users/${doc.id}: ` +
      `${presentFields.join(", ") || "(no health fields present)"} ` +
      `→ injuryCount=${injuryCount}` +
      (rawBlob ? " (overwriting incomplete existing blob)" : "") +
      (DELETE_PLAINTEXT ?
        ` (and delete: ${presentFields.join(", ") || "(nothing to delete)"})` :
        ""),
  );

  if (COMMIT) {
    const update = {
      encryptedHealthData: encryptHealthData(healthData, keyHex),
      injuryCount,
    };
    if (DELETE_PLAINTEXT) {
      for (const field of presentFields) {
        update[field] = FieldValue.delete();
      }
    }
    await queueWrite(doc.ref, update, batchState, db);
  }
  return rawBlob ? "recovered" : "migrated";
}

async function queueWrite(ref, update, batchState, db) {
  batchState.batch.update(ref, update);
  batchState.count++;
  if (batchState.count >= 500) {
    await batchState.batch.commit();
    batchState.batch = db.batch();
    batchState.count = 0;
  }
}

async function main() {
  const keyHex = process.env.HEALTH_DATA_ENCRYPTION_KEY;
  if (!keyHex) {
    console.error(
        "Set HEALTH_DATA_ENCRYPTION_KEY to the same key value already " +
        "set via `firebase functions:secrets:set " +
        "HEALTH_DATA_ENCRYPTION_KEY` — run " +
        "`firebase functions:secrets:access HEALTH_DATA_ENCRYPTION_KEY " +
        "--project wiseworkout-fyp2615` to read back the currently-set " +
        "value if you don't have it handy.",
    );
    process.exit(1);
  }

  initializeApp({
    credential: applicationDefault(),
  });
  const db = getFirestore();

  console.log(
      `Mode: ${COMMIT ? "COMMIT (will write)" : "DRY RUN (no writes)"}` +
      (DELETE_PLAINTEXT ? " + DELETE PLAINTEXT" : ""),
  );

  const usersSnap = await db.collection("users").get();
  console.log(`Found ${usersSnap.size} user document(s).`);

  const batchState = {batch: db.batch(), count: 0};
  const counts = {migrated: 0, recovered: 0, "plaintext-deleted": 0, skipped: 0};

  for (const doc of usersSnap.docs) {
    const outcome = await processUser(doc, keyHex, batchState, db);
    counts[outcome]++;
  }

  if (COMMIT && batchState.count > 0) {
    await batchState.batch.commit();
  }

  console.log(
      `Done. ${counts.migrated} user(s) ` +
      `${COMMIT ? "migrated" : "would be migrated"} (no prior blob), ` +
      `${counts.recovered} ` +
      `${COMMIT ? "recovered" : "would be recovered"} (had a partial/incomplete blob), ` +
      `${counts["plaintext-deleted"]} ` +
      `${COMMIT ? "had plaintext deleted" : "would have plaintext deleted"} ` +
      "(already-complete blob), " +
      `${counts.skipped} skipped (already fully migrated, no delete requested).`,
  );
  if (!COMMIT) {
    console.log("This was a dry run — nothing was written. Re-run with --commit to apply.");
  }
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});

// ---------------------------------------------------------------------------
// FULL STEP-BY-STEP RUN INSTRUCTIONS (two-pass approach, recommended)
// ---------------------------------------------------------------------------
//
// 1. Get a service-account credential (separate from android/app/
//    google-services.json — that file is NOT valid for this):
//      Firebase Console -> Project Settings -> Service Accounts ->
//      "Generate new private key" -> save the downloaded JSON somewhere
//      OUTSIDE the repo (never commit it).
//
// 2. Get the encryption key value (the same one set via
//    `firebase functions:secrets:set HEALTH_DATA_ENCRYPTION_KEY`):
//      firebase functions:secrets:access HEALTH_DATA_ENCRYPTION_KEY \
//        --project wiseworkout-fyp2615
//
// 3. Dry run first, always — this alone is a full audit of every user's
//    current state (no blob / partial blob needing recovery / already
//    complete), since every user gets a printed line either way:
//      cd functions
//      HEALTH_DATA_ENCRYPTION_KEY=<key from step 2> \
//      GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//      node scripts/migrateHealthData.js
//    Read the printed output carefully — one line per user. Look
//    specifically for "Would recover ... (overwriting incomplete
//    existing blob)" lines — those are users the live app already wrote
//    a partial blob for; confirm the field list and injuryCount shown
//    for each looks right before proceeding.
//
// 4. Once the dry run looks correct, write the encrypted blob (plaintext
//    fields are NOT touched at this stage — old and new coexist):
//      HEALTH_DATA_ENCRYPTION_KEY=<key> \
//      GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//      node scripts/migrateHealthData.js --commit
//
// 5. Verify: open a few migrated/recovered users in the Firebase Console
//    and confirm encryptedHealthData/injuryCount look right, and spot-
//    check the app itself (Health Profile screen, WiseCoach referral
//    nudge, cardio calorie calc — see the main report's Test
//    Instructions for exactly what to check).
//
// 6. ONLY after step 5 looks right, remove the old plaintext fields —
//    this correctly targets users already migrated/recovered in step 4
//    (it does NOT re-encrypt them, just deletes their lingering
//    plaintext, per the "already complete + --delete-plaintext" case
//    above):
//      HEALTH_DATA_ENCRYPTION_KEY=<key> \
//      GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//      node scripts/migrateHealthData.js --commit --delete-plaintext
