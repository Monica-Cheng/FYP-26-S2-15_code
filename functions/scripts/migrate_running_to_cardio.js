#!/usr/bin/env node
// functions/scripts/migrate_running_to_cardio.js
//
// ONE-TIME MIGRATION. Safe to delete after it's been run and verified —
// nothing else in functions/ imports or depends on this file, and
// `firebase deploy --only functions` never picks it up (same as
// migrateHealthData.js alongside it).
//
// Pairs with the plans.type rename in ../index.js (normalizeOfficialPlanData/
// requireValidPlanType, VALID_PLAN_TYPES = ["Gym", "Cardio", "Combine"]) —
// that change only affects how NEW writes through adminCreateOfficialPlan/
// adminUpdatePlan are validated going forward; it does nothing to the
// "Running" strings already sitting in existing documents. This script is
// the one-time data-side fix for those existing documents.
//
// WHAT THIS TOUCHES
// ------------------
//   a. plans/{id} — any doc where type === "Running" and/or
//      matchSport === "Running" (checked independently; only a field that
//      itself actually equals "Running" is changed to "Cardio" — if
//      matchSport ever diverges from type, e.g. holds free text like
//      "running club", it's left alone).
//   b. users/{id} — any doc where sportPreference === "running" (lowercase)
//      is changed to "cardio". "gym" and "both" are NOT touched — renaming
//      "both" to something like "combine" is a UI/matching-algorithm
//      decision for a later phase, out of scope here.
//
// WHAT THIS DELIBERATELY DOES NOT TOUCH
// --------------------------------------
//   - plans/{id}.sessions[].type — lowercase 'gym'/'rest' per-day field
//     embedded on the plan doc. Different namespace, same field name,
//     unrelated to the plan-level type/matchSport rename.
//   - sessions/{id}.type — lowercase 'gym'/'cardio'/'combined' on the
//     separate top-level `sessions` collection (logged workouts, not
//     plans). Already uses the string "cardio" today for a completely
//     different meaning (a session composed of cardio blocks) — do not
//     confuse this with plans/{id}.type's "Cardio".
//
// USAGE
// -----
//   cd functions
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//   node scripts/migrate_running_to_cardio.js
//
// With no flags: DRY RUN — prints every doc that WOULD change (with doc
// IDs and the exact field(s)/values involved) and writes nothing. Always
// run this first and read the output before doing anything else.
//
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//   node scripts/migrate_running_to_cardio.js --confirm
//
// Only with --confirm does it actually write. Idempotent — re-running
// after a --confirm pass finds nothing left to change (every matched
// field will already read "Cardio"/"cardio"), so it's safe to re-run at
// any point, including accidentally without --confirm.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const COMMIT = process.argv.includes("--confirm");

async function queueWrite(ref, update, batchState, db) {
  batchState.batch.update(ref, update);
  batchState.count++;
  if (batchState.count >= 500) {
    await batchState.batch.commit();
    batchState.batch = db.batch();
    batchState.count = 0;
  }
}

async function migratePlans(db, batchState) {
  const snap = await db.collection("plans").get();
  console.log(`\nplans/: found ${snap.size} document(s).`);

  let matched = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const update = {};

    if (data.type === "Running") update.type = "Cardio";
    if (data.matchSport === "Running") update.matchSport = "Cardio";

    if (Object.keys(update).length === 0) continue;

    matched++;
    const fieldSummary = Object.keys(update)
        .map((f) => `${f}: "Running" -> "${update[f]}"`)
        .join(", ");
    console.log(
        `${COMMIT ? "Updating" : "Would update"} plans/${doc.id}: ${fieldSummary}`,
    );

    if (COMMIT) {
      await queueWrite(doc.ref, update, batchState, db);
    }
  }

  console.log(
      `plans/: ${matched} document(s) ${COMMIT ? "updated" : "would be updated"}.`,
  );
  return matched;
}

async function migrateUsers(db, batchState) {
  const snap = await db.collection("users")
      .where("sportPreference", "==", "running")
      .get();
  console.log(`\nusers/: found ${snap.size} document(s) with sportPreference == "running".`);

  for (const doc of snap.docs) {
    console.log(
        `${COMMIT ? "Updating" : "Would update"} users/${doc.id}: ` +
        `sportPreference: "running" -> "cardio"`,
    );
    if (COMMIT) {
      await queueWrite(doc.ref, {sportPreference: "cardio"}, batchState, db);
    }
  }

  console.log(
      `users/: ${snap.size} document(s) ${COMMIT ? "updated" : "would be updated"}.`,
  );
  return snap.size;
}

async function main() {
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  console.log(`Mode: ${COMMIT ? "COMMIT (will write)" : "DRY RUN (no writes)"}`);

  const batchState = {batch: db.batch(), count: 0};

  const plansChanged = await migratePlans(db, batchState);
  const usersChanged = await migrateUsers(db, batchState);

  if (COMMIT && batchState.count > 0) {
    await batchState.batch.commit();
  }

  console.log(
      `\nDone. ${plansChanged} plan doc(s) and ${usersChanged} user doc(s) ` +
      `${COMMIT ? "updated" : "would be updated"}.`,
  );
  if (!COMMIT) {
    console.log("This was a dry run — nothing was written. Re-run with --confirm to apply.");
  }
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
