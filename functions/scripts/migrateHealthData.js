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
// The encrypt logic here is a deliberate, separate copy of
// encryptHealthData() in ../index.js, not a shared import — ../index.js
// calls initializeApp()/defineSecret() at module load time in a way
// that's meant for the Cloud Functions runtime, not a one-off script
// invocation, so duplicating just the small pure encrypt function here
// (and keeping HEALTH_DATA_FIELDS below in sync by hand — see that
// constant's own comment in ../index.js) is simpler and safer than
// trying to reuse the module directly.
//
// Fully idempotent, safe to re-run at any stage. Per user, one of 3
// things happens each run, decided independently of what any PREVIOUS
// run already did to that same user:
//
//   - No encryptedHealthData yet: encrypt + write it (+ injuryCount),
//     and ALSO delete the old plaintext fields in the same write if
//     --delete-plaintext was passed alongside --commit.
//   - encryptedHealthData already exists (from an earlier run) AND
//     --delete-plaintext is passed: don't touch/re-encrypt the blob,
//     just delete any of the 11 plaintext fields still lingering on that
//     user's doc.
//   - encryptedHealthData already exists and --delete-plaintext is NOT
//     passed: nothing to do, skipped entirely.
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
const admin = require("firebase-admin");

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
 * Queues (or, in dry-run mode, just logs) whatever this one user needs
 * this run — see the file header for the 3 possible outcomes. Batches
 * writes at Firestore's 500-per-batch limit, same chunking convention
 * sendAdminBroadcast() in ../index.js already uses.
 *
 * @param {FirebaseFirestore.QueryDocumentSnapshot} doc
 * @param {string} keyHex
 * @param {{batch: FirebaseFirestore.WriteBatch, count: number}} batchState
 * @param {FirebaseFirestore.Firestore} db
 * @return {Promise<"migrated"|"plaintext-deleted"|"skipped">}
 */
async function processUser(doc, keyHex, batchState, db) {
  const data = doc.data();
  const alreadyHasBlob = typeof data.encryptedHealthData === "string" &&
      data.encryptedHealthData !== "";
  const presentFields = HEALTH_DATA_FIELDS.filter((f) =>
    Object.prototype.hasOwnProperty.call(data, f));

  if (alreadyHasBlob && !DELETE_PLAINTEXT) {
    return "skipped";
  }

  if (alreadyHasBlob && DELETE_PLAINTEXT) {
    if (presentFields.length === 0) return "skipped";
    console.log(
        `${COMMIT ? "Deleting plaintext for" : "Would delete plaintext for"} ` +
        `users/${doc.id}: ${presentFields.join(", ")}`,
    );
    if (COMMIT) {
      const update = {};
      for (const field of presentFields) {
        update[field] = admin.firestore.FieldValue.delete();
      }
      await queueWrite(doc.ref, update, batchState, db);
    }
    return "plaintext-deleted";
  }

  // No blob yet — encrypt + write it, optionally deleting plaintext in
  // the same write if both flags were passed together.
  const healthData = {};
  for (const field of presentFields) healthData[field] = data[field];
  const injuries = Array.isArray(healthData.injuries) ?
    healthData.injuries :
    [];
  const injuryCount = injuries.length;

  console.log(
      `${COMMIT ? "Migrating" : "Would migrate"} users/${doc.id}: ` +
      `${presentFields.join(", ") || "(no health fields present)"} ` +
      `→ injuryCount=${injuryCount}` +
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
        update[field] = admin.firestore.FieldValue.delete();
      }
    }
    await queueWrite(doc.ref, update, batchState, db);
  }
  return "migrated";
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

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
  const db = admin.firestore();

  console.log(
      `Mode: ${COMMIT ? "COMMIT (will write)" : "DRY RUN (no writes)"}` +
      (DELETE_PLAINTEXT ? " + DELETE PLAINTEXT" : ""),
  );

  const usersSnap = await db.collection("users").get();
  console.log(`Found ${usersSnap.size} user document(s).`);

  const batchState = {batch: db.batch(), count: 0};
  const counts = {migrated: 0, "plaintext-deleted": 0, skipped: 0};

  for (const doc of usersSnap.docs) {
    const outcome = await processUser(doc, keyHex, batchState, db);
    counts[outcome]++;
  }

  if (COMMIT && batchState.count > 0) {
    await batchState.batch.commit();
  }

  console.log(
      `Done. ${counts.migrated} user(s) ` +
      `${COMMIT ? "migrated" : "would be migrated"}, ` +
      `${counts["plaintext-deleted"]} ` +
      `${COMMIT ? "had plaintext deleted" : "would have plaintext deleted"}, ` +
      `${counts.skipped} skipped (already fully migrated for this mode).`,
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
// 3. Dry run first, always:
//      cd functions
//      HEALTH_DATA_ENCRYPTION_KEY=<key from step 2> \
//      GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//      node scripts/migrateHealthData.js
//    Read the printed output carefully — one line per user, showing
//    exactly which fields would be bundled and the resulting
//    injuryCount. Nothing is written yet.
//
// 4. Once the dry run looks correct, write the encrypted blob (plaintext
//    fields are NOT touched at this stage — old and new coexist):
//      HEALTH_DATA_ENCRYPTION_KEY=<key> \
//      GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//      node scripts/migrateHealthData.js --commit
//
// 5. Verify: open a few migrated users in the Firebase Console and
//    confirm encryptedHealthData/injuryCount look right, and spot-check
//    the app itself (Health Profile screen, WiseCoach referral nudge,
//    cardio calorie calc — see the main report's Test Instructions for
//    exactly what to check).
//
// 6. ONLY after step 5 looks right, remove the old plaintext fields —
//    this correctly targets users already migrated in step 4 (it does
//    NOT re-encrypt them, just deletes their lingering plaintext, per
//    the "already has blob + --delete-plaintext" case above):
//      HEALTH_DATA_ENCRYPTION_KEY=<key> \
//      GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//      node scripts/migrateHealthData.js --commit --delete-plaintext
