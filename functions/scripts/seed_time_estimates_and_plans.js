#!/usr/bin/env node
// functions/scripts/seed_time_estimates_and_plans.js
//
// ONE-TIME SEED SCRIPT. Safe to delete after it's been run and verified —
// nothing else in functions/ imports or depends on this file, and
// `firebase deploy --only functions` never picks it up (same as the other
// one-off scripts alongside it, e.g. migrate_running_to_cardio.js).
//
// Pairs with the new time-estimate system (estTimePerSet field, seconds;
// a session's estimatedMinutes is now a COMPUTED value = sum over its
// exercises of sets_count × (estTimePerSet + restTime) for strength, or
// cardioMinutes directly for cardio, converted to minutes and rounded —
// see build_routine_screen.dart's _computeEstimatedMinutes() and
// compress_utils.dart's estimatedMinutesAfterCompression() for the same
// formula implemented Flutter-side). The admin dashboard
// (admin/wiseworkout-admin/) was explicitly out of scope for the code
// change this pairs with, so there is currently no UI to author
// estTimePerSet on an official plan — this script exists specifically to
// backfill the one remaining official plan by hand, and to seed 3 new
// example plans (one per type: Gym/Cardio/Combine) with the field already
// populated, since none currently exist for Combine or Cardio.
//
// WHAT THIS DOES
// --------------
//   A. Updates plans/ih0namDPOl5qOKo2jzNR ("Beginner Push Pull Legs"):
//      adds a judgment-call estTimePerSet (seconds) to each of its 13
//      existing exercises — compound lifts (Bench Press, Overhead Press,
//      Pull-ups, Barbell Row, Squat, Romanian Deadlift) get 50-60s,
//      isolation/accessory movements get 30-40s — and recomputes each
//      training session's estimatedMinutes from the new formula,
//      replacing the old manually-typed 45/45/50.
//   B. Creates 3 NEW plan documents, matching the exact field shape of
//      the existing plan doc (name/level/type/daysPerWeek/durationWeeks/
//      description/equipment[]/goals[]/isActive/sessions[]/designedBy/
//      matchLevel/matchGoals[]/matchSport/imageUrl/featured):
//        1. "Intermediate Upper/Lower Split" — Gym, 4 days/week.
//        2. "Cardio Kickstart" — Cardio, 3 days/week, mixed Run/Cycle/Walk.
//        3. "Strength & Conditioning Combine" — Combine, 3 days/week,
//           each training day mixes real strength exercises with a
//           cardio finisher block.
//      Every strength exercise name/muscle in all 3 new plans is copied
//      verbatim from the real `exercises` collection (queried live by
//      this script, not hardcoded here, so it always reflects whatever
//      is actually in the catalog at run time) — see
//      REQUIRED_CATALOG_NAMES below; the script aborts before writing
//      anything if any of them is missing. Cardio blocks are NOT matched
//      against the exercises catalog — that collection has no cardio-
//      block concept (isCardio/cardioActivity/cardioMinutes aren't
//      fields on any catalog doc), and no real cardio plan in this app
//      has ever done that; cardio block names instead follow the same
//      "${cardioActivity} ${minutes}min" convention every real cardio
//      plan already uses (confirmed on the "5K Beginner Runner" plan
//      from an earlier investigation this session, e.g. "Run 25min").
//      cardioActivity values are 'Run'/'Walk'/'Cycle', matching the
//      admin dashboard's own CARDIO_ACTIVITIES enum and real existing
//      data — not the catalog's separate "Treadmill Run"/"Stationary
//      Bike"/etc. entries, which are a different, unrelated set of
//      catalog rows (machine-based cardio exercises for anti-cheat/
//      injury-filter lookups on THOSE specific movements, not a source
//      for the cardioActivity field).
//
// PLACEHOLDER DATA — must be reviewed/replaced by the project owner:
//   - imageUrl is left as an empty string "" on all 3 new plans,
//     deliberately NOT a fabricated URL — this script has no way to
//     verify a guessed image URL actually resolves to a real, relevant
//     photo, and a broken/wrong link is worse than no link at all. The
//     app already renders a graceful icon fallback for an empty/failed
//     imageUrl everywhere (confirmed in an earlier investigation this
//     session — _PlanImageOrIcon/ImageThumb-style fallbacks), so this is
//     a clean, obviously-incomplete state rather than a misleading one.
//   - designedBy on all 3 new plans is fabricated placeholder flavor
//     text (name/title/credential/quote), explicitly requested as such —
//     replace with a real coach or adjust tone as needed.
//
// USAGE
// -----
//   cd functions
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//   node scripts/seed_time_estimates_and_plans.js
//
// With no flags: DRY RUN — prints the full before/after JSON for the
// existing-plan update and the full JSON of all 3 new plan documents,
// writes nothing. Always run this first and read the output before
// doing anything else.
//
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
//   node scripts/seed_time_estimates_and_plans.js --confirm
//
// Only with --confirm does it actually write.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const COMMIT = process.argv.includes("--confirm");

const EXISTING_PLAN_ID = "ih0namDPOl5qOKo2jzNR";

// ---------------------------------------------------------------------------
// Formula — mirrors build_routine_screen.dart's _computeEstimatedMinutes()
// and compress_utils.dart's estimatedMinutesAfterCompression() exactly.
// ---------------------------------------------------------------------------
function sessionEstimatedMinutes(exercises) {
  let totalSeconds = 0;
  for (const ex of exercises) {
    if (ex.isCardio === true) {
      totalSeconds += (ex.cardioMinutes || 0) * 60;
    } else {
      const setsCount = Array.isArray(ex.sets) ? ex.sets.length : (ex.sets || 0);
      totalSeconds += setsCount * ((ex.estTimePerSet || 0) + (ex.restTime || 0));
    }
  }
  return Math.round(totalSeconds / 60);
}

function restDay(dayNum) {
  return {
    estimatedMinutes: 0,
    exercises: [],
    isRestDay: true,
    name: "Rest",
    type: "rest",
    day: `Day ${dayNum}`,
  };
}

function trainingDay(dayNum, name, exercises) {
  return {
    estimatedMinutes: sessionEstimatedMinutes(exercises),
    exercises,
    isRestDay: false,
    name,
    type: "gym",
    day: `Day ${dayNum}`,
  };
}

function cardioBlock(cardioActivity, minutes) {
  return {
    name: `${cardioActivity} ${minutes}min`,
    muscle: "Cardio",
    restTime: 0,
    tag: "Primary",
    sets: [{type: "N", kg: "", reps: String(minutes)}],
    isCardio: true,
    cardioActivity,
    cardioMinutes: minutes,
  };
}

// ---------------------------------------------------------------------------
// Part A — existing plan's new estTimePerSet values (seconds), keyed by
// exercise name exactly as stored on plans/ih0namDPOl5qOKo2jzNR today.
// Compound lifts: 50-60s. Isolation/accessory: 30-40s. Judgment call, per
// the task's own guidance range.
// ---------------------------------------------------------------------------
const EXISTING_PLAN_EST_TIME_PER_SET = {
  "Bench Press": 55,
  "Overhead Press": 50,
  "Incline Dumbbell Press": 35,
  "Tricep Pushdown": 30,
  "Lateral Raise": 30,
  "Pull-ups": 55,
  "Barbell Row": 50,
  "Cable Row": 35,
  "Face Pull": 30,
  "Bicep Curl": 30,
  "Squat": 60,
  "Romanian Deadlift": 55,
  "Leg Press": 40,
  "Leg Curl": 30,
  "Calf Raise": 30,
};

// ---------------------------------------------------------------------------
// Part B — every strength exercise name the 3 new plans use, pulled from
// the real exercises catalog (queried live below — this list is just
// which ones to select, not a hardcoded copy of their data). The script
// aborts before writing anything if any of these is missing from the
// live catalog at run time.
// ---------------------------------------------------------------------------
const REQUIRED_CATALOG_NAMES = [
  "Bench Press", "Barbell Row", "Overhead Press", "Lateral Raise",
  "Barbell Curl", "Tricep Pushdown", "Squat", "Romanian Deadlift",
  "Leg Press", "Leg Curl", "Calf Raise", "Incline DB Press",
  "Lat Pulldown", "Cable Fly", "Face Pull", "Hammer Curl",
  "Skull Crusher", "Front Squat", "Deadlift", "Walking Lunges",
  "Leg Extension", "Hip Thrust",
];

async function buildNewPlans(db) {
  const catalogSnap = await db.collection("exercises").get();
  const byName = {};
  catalogSnap.docs.forEach((doc) => {
    const d = doc.data();
    if (d.name) byName[d.name] = d;
  });

  const missing = REQUIRED_CATALOG_NAMES.filter((n) => !byName[n]);
  if (missing.length > 0) {
    throw new Error(
        `Aborting — the following required exercise names are missing ` +
        `from the live exercises catalog: ${missing.join(", ")}. The ` +
        `catalog may have changed since this script was written.`,
    );
  }

  const ex = (name, sets, reps, restTime, estTimePerSet, tag) => ({
    name,
    muscle: byName[name].muscle,
    restTime,
    reps,
    sets,
    tag,
    estTimePerSet,
  });

  // ── New plan 1: Gym — "Intermediate Upper/Lower Split", 4 days/week ──────
  const upperLowerPlan = {
    name: "Intermediate Upper/Lower Split",
    level: "Intermediate",
    type: "Gym",
    daysPerWeek: 4,
    durationWeeks: 8,
    description: "A 4-day upper/lower split for lifters past the beginner " +
      "stage — alternates upper and lower body sessions twice per week " +
      "for balanced volume and recovery.",
    equipment: ["Barbell", "Dumbbells", "Cable machine", "Machine"],
    goals: ["Build Muscle", "Build Strength"],
    isActive: true,
    sessions: [
      trainingDay(1, "Upper A", [
        ex("Bench Press", 4, 8, 90, 55, "Primary"),
        ex("Barbell Row", 4, 8, 90, 50, "Primary"),
        ex("Overhead Press", 3, 10, 75, 45, "Primary"),
        ex("Lateral Raise", 3, 15, 45, 30, "Accessory"),
        ex("Barbell Curl", 3, 12, 45, 30, "Accessory"),
        ex("Tricep Pushdown", 3, 12, 45, 30, "Accessory"),
      ]),
      trainingDay(2, "Lower A", [
        ex("Squat", 4, 6, 120, 60, "Primary"),
        ex("Romanian Deadlift", 3, 10, 90, 50, "Primary"),
        ex("Leg Press", 3, 12, 75, 40, "Accessory"),
        ex("Leg Curl", 3, 12, 60, 30, "Accessory"),
        ex("Calf Raise", 4, 15, 45, 30, "Accessory"),
      ]),
      restDay(3),
      trainingDay(4, "Upper B", [
        ex("Incline DB Press", 4, 10, 75, 40, "Primary"),
        ex("Lat Pulldown", 4, 10, 75, 45, "Primary"),
        ex("Cable Fly", 3, 15, 45, 30, "Accessory"),
        ex("Face Pull", 3, 15, 45, 30, "Accessory"),
        ex("Hammer Curl", 3, 12, 45, 30, "Accessory"),
        ex("Skull Crusher", 3, 12, 45, 30, "Accessory"),
      ]),
      trainingDay(5, "Lower B", [
        ex("Front Squat", 4, 8, 105, 55, "Primary"),
        ex("Deadlift", 3, 6, 120, 60, "Primary"),
        ex("Walking Lunges", 3, 12, 60, 35, "Accessory"),
        ex("Leg Extension", 3, 15, 45, 30, "Accessory"),
        ex("Hip Thrust", 3, 12, 60, 35, "Accessory"),
      ]),
      restDay(6),
      restDay(7),
    ],
    designedBy: {
      name: "Coach Daniel Reyes",
      title: "Certified Strength Coach",
      credential: "NASM-CPT, CSCS",
      quote: "Upper/lower splits let you train hard and recover fast — the sweet spot for intermediate lifters.",
    },
    matchLevel: "Intermediate",
    matchGoals: ["Build Muscle", "Build Strength"],
    matchSport: "Gym",
    imageUrl: "",
    featured: false,
  };

  // ── New plan 2: Cardio — "Cardio Kickstart", 3 days/week ─────────────────
  const cardioPlan = {
    name: "Cardio Kickstart",
    level: "Beginner",
    type: "Cardio",
    daysPerWeek: 3,
    durationWeeks: 6,
    description: "A gentle 3-day introduction to cardio training, mixing " +
      "running, cycling and walking so nothing gets stale or overuses " +
      "the same joints two days running.",
    equipment: [],
    goals: ["Improve Endurance", "Lose Weight"],
    isActive: true,
    sessions: [
      trainingDay(1, "Easy Run", [cardioBlock("Run", 25)]),
      restDay(2),
      trainingDay(3, "Steady Cycle", [cardioBlock("Cycle", 35)]),
      restDay(4),
      trainingDay(5, "Recovery Walk", [cardioBlock("Walk", 40)]),
      restDay(6),
      restDay(7),
    ],
    designedBy: {
      name: "Coach Priya Nair",
      title: "Certified Cardio & Endurance Coach",
      credential: "ACE-CPT, RRCA Certified",
      quote: "Consistency beats intensity when you're just getting started — show up three times a week and the rest follows.",
    },
    matchLevel: "Beginner",
    matchGoals: ["Improve Endurance", "Lose Weight", "General Fitness"],
    matchSport: "Cardio",
    imageUrl: "",
    featured: false,
  };

  // ── New plan 3: Combine — "Strength & Conditioning Combine", 3 days/wk ───
  const combinePlan = {
    name: "Strength & Conditioning Combine",
    level: "Intermediate",
    type: "Combine",
    daysPerWeek: 3,
    durationWeeks: 8,
    description: "Real strength work paired with a cardio finisher every " +
      "session — for lifters who don't want to sacrifice conditioning to " +
      "build muscle, or vice versa.",
    equipment: ["Barbell", "Cable machine"],
    goals: ["Build Strength", "Improve Endurance"],
    isActive: true,
    sessions: [
      trainingDay(1, "Push + Cardio Finisher", [
        ex("Bench Press", 4, 8, 90, 55, "Primary"),
        ex("Overhead Press", 3, 10, 75, 45, "Primary"),
        cardioBlock("Cycle", 15),
      ]),
      restDay(2),
      trainingDay(3, "Pull + Cardio Finisher", [
        ex("Barbell Row", 4, 8, 90, 50, "Primary"),
        ex("Lat Pulldown", 3, 10, 75, 45, "Primary"),
        cardioBlock("Run", 15),
      ]),
      restDay(4),
      trainingDay(5, "Legs + Cardio Finisher", [
        ex("Squat", 4, 8, 120, 60, "Primary"),
        ex("Leg Press", 3, 12, 75, 40, "Primary"),
        cardioBlock("Walk", 20),
      ]),
      restDay(6),
      restDay(7),
    ],
    designedBy: {
      name: "Coach Marcus Webb",
      title: "Certified Hybrid Athlete Coach",
      credential: "NSCA-CSCS, USAW Level 1",
      quote: "You don't have to choose between strong and fit — train both, every session, and both improve.",
    },
    matchLevel: "Intermediate",
    matchGoals: ["Build Strength", "Improve Endurance", "General Fitness"],
    matchSport: "Combine",
    imageUrl: "",
    featured: false,
  };

  return [upperLowerPlan, cardioPlan, combinePlan];
}

async function main() {
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  console.log(`Mode: ${COMMIT ? "COMMIT (will write)" : "DRY RUN (no writes)"}`);

  // ── Part A ────────────────────────────────────────────────────────────
  console.log(`\n=== Part A: updating plans/${EXISTING_PLAN_ID} ===`);
  const planRef = db.collection("plans").doc(EXISTING_PLAN_ID);
  const planSnap = await planRef.get();
  if (!planSnap.exists) {
    console.error(`plans/${EXISTING_PLAN_ID} does not exist — nothing to update.`);
  } else {
    const plan = planSnap.data();
    const newSessions = (plan.sessions || []).map((session) => {
      if (session.isRestDay) return session;
      const newExercises = (session.exercises || []).map((exercise) => {
        const estTimePerSet = EXISTING_PLAN_EST_TIME_PER_SET[exercise.name];
        if (estTimePerSet === undefined) {
          console.warn(
              `  WARNING: no estTimePerSet mapping for "${exercise.name}" ` +
              `— left unchanged (no field added).`,
          );
          return exercise;
        }
        return {...exercise, estTimePerSet};
      });
      const newEstimatedMinutes = sessionEstimatedMinutes(newExercises);
      console.log(
          `  ${session.day} "${session.name}": estimatedMinutes ` +
          `${session.estimatedMinutes} -> ${newEstimatedMinutes}`,
      );
      return {...session, exercises: newExercises, estimatedMinutes: newEstimatedMinutes};
    });

    console.log("\n  Full updated sessions[] that would be written:");
    console.log(JSON.stringify(newSessions, null, 2));

    if (COMMIT) {
      await planRef.update({sessions: newSessions});
      console.log(`  Updated plans/${EXISTING_PLAN_ID}.`);
    }
  }

  // ── Part B ────────────────────────────────────────────────────────────
  console.log("\n=== Part B: creating 3 new plans ===");
  const newPlans = await buildNewPlans(db);

  for (const plan of newPlans) {
    console.log(`\n  --- ${plan.type}: "${plan.name}" ---`);
    console.log(JSON.stringify(plan, null, 2));
  }

  if (COMMIT) {
    for (const plan of newPlans) {
      const ref = await db.collection("plans").add({
        ...plan,
        createdAt: FieldValue.serverTimestamp(),
      });
      console.log(`  Created plans/${ref.id} ("${plan.name}").`);
    }
  }

  console.log(
      `\nDone. ${COMMIT ? "Wrote" : "Would write"} 1 update + ` +
      `${newPlans.length} new plan document(s).`,
  );
  if (!COMMIT) {
    console.log("This was a dry run — nothing was written. Re-run with --confirm to apply.");
  }
}

main().catch((err) => {
  console.error("Seed script failed:", err);
  process.exit(1);
});
