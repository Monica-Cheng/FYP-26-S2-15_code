# Admin Plan Document Schema — `plans` Collection

This is the exact Firestore document shape the WiseWorkout Flutter app expects
when reading from the top-level `plans` collection (Explore, Plan Match, Plan
Detail, Plan Schedule, and the actual gym/cardio session screens). It is meant
for whoever builds plan-creation into the admin (React) dashboard.

Every field below was confirmed directly against either:
- the Flutter app's own write code (`lib/screens/plans/build_routine_screen.dart`),
- its read code (`lib/screens/plans/plan_detail_screen.dart`,
  `lib/screens/plans/plan_schedule_screen.dart`,
  `lib/screens/plans/gym_session_screen.dart`), or
- the real documents currently live in production Firestore.

Nothing here is guessed or carried over from stale documentation.

---

## 1. Top-level plan document fields

| Field | Type | Example | Notes |
|---|---|---|---|
| `name` | `string` | `"5K Beginner Runner"` | |
| `level` | `string` | `"Beginner"` | One of `"Beginner"`, `"Intermediate"`, `"Advanced"` in every real plan seen. |
| `type` | `string` | `"Running"` | **Field name is `type`, not `sport`.** Real values seen: `"Gym"`, `"Running"`. |
| `daysPerWeek` | `int` | `3` | Should match the actual count of non-rest days in `sessions[]`. |
| `durationWeeks` | `int` | `8` | **Field name is `durationWeeks`, not `totalWeeks`.** |
| `description` | `string` | `"An 8-week beginner..."` | Free text, shown on the plan detail screen. |
| `equipment` | `array<string>` | `["Running shoes"]` | |
| `goals` | `array<string>` | `["Improve Endurance", "General Fitness"]` | **Field name is `goals` (plural array), not a single `goal` string.** |
| `isActive` | `bool` | `true` | Present on all 3 real curated plans as `true`. **Not actually read/filtered on anywhere in the current app** (confirmed by searching the whole codebase) — but set it to `true` anyway for forward-compatibility/consistency with existing data. |
| `matchGoals` | `array<string>` | `["Improve Endurance", "Lose Weight"]` | Used by the "Match Me" plan-matching quiz (`plan_match_screen.dart`) to score this plan against a user's stated goal. |
| `matchSport` | `string` | `"Running"` | Used by the same matching quiz. Fuzzy-matched against the user's sport preference — use a plain value like `"Gym"` or `"Running"`, not a phrase like `"Gym only"` (a real inconsistency found and fixed in production data during this work). |
| `matchLevel` | `string` | `"Beginner"` | Used by the same matching quiz — exact match against the user's stated level. |
| `designedBy` | `map` | see below | Optional but present on every real curated plan. |
| `imageUrl` | `string` | `"https://storage.googleapis.com/.../plan-thumb.jpg"` | **Optional.** A Firebase Storage URL or external image URL for the plan's leading thumbnail (shown e.g. on the Plans tab's Current Plan card). Not present on any real curated plan yet. If omitted, null, empty, or the URL fails to load, the app falls back to a default icon — this is **not a blocking requirement** for the admin team, just recommended for a nicer visual. Irrelevant for user-built custom routines (`isCustom: true`), which always show a fixed icon regardless of this field. |
| `sessions` | `array<map>` | see §2 | The actual weekly training template. |

### `designedBy` shape

```json
{
  "name": "Coach Amara Osei",
  "title": "Certified Running Coach",
  "credential": "UKA Level 2, RRCA Certified",
  "quote": "Consistency beats intensity — show up three times a week and the 5K takes care of itself."
}
```
All four sub-fields are plain strings, shown on the plan detail screen as the "designed by" attribution card.

### Fields that must NOT be set on an admin-created plan

- **`isCustom`** — do not set this at all (or explicitly set it to `false`/omit it). `isCustom: true` is written exclusively by the app's own in-app "Build Routine" flow (`FirestoreService.saveCustomRoutine()`) for a user's private, self-built routines. If an admin-created plan is accidentally saved with `isCustom: true`, it will **never appear in Explore** — it will only be visible to whichever `createdBy` uid happens to match (see below), exactly the bug that caused several test/placeholder plans to silently vanish from Explore during this project.
- **`createdBy`** — **omit this field entirely.** Confirmed directly against all 3 real curated plans currently in production (`Intermediate Hypertrophy`, `Beginner Push Pull Legs`, `5K Beginner Runner`): **none of them have a `createdBy` field at all.** There is no "admin/system uid" placeholder convention in use — admin-authored plans are simply plans with no `createdBy` field, which is exactly what lets `isCustom != true` correctly select them for Explore regardless of who's logged in.
- **`createdAt`** — also absent on all 3 real curated plans (unlike user-created custom routines, which always get a real `FieldValue.serverTimestamp()`). Optional to include, not required by any app code.

---

## 2. `sessions[]` entry shape

One entry per calendar day of the week — a real curated plan always has **7 entries** (`Day 1` through `Day 7`), including explicit rest days.

| Field | Type | Notes |
|---|---|---|
| `day` | `string` | `"Day 1"` through `"Day 7"`. |
| `name` | `string` | Session name (`"Easy Run"`, `"Push A"`) or `"Rest"` for a rest day. |
| `type` | `string` | `"gym"` for every training day (**even a day that's entirely cardio** — real app-written data always uses `"gym"` here, not `"cardio"`) or `"rest"` for a rest day. This field is not actually branched on anywhere in the current app's read code — `isRestDay` below is what actually matters — but match the existing convention anyway. |
| `isRestDay` | `bool` | The field that actually controls behavior — `true` means this day is skipped/shown as Rest, and `exercises` should be an empty array. |
| `estimatedMinutes` | `int` | Shown as a rough duration estimate on the schedule screen. `0` for rest days. |
| `exercises` | `array<map>` | See §3. Empty array `[]` for a rest day. |

---

## 3. `exercises[]` — TWO distinct shapes

An exercise entry is **either** a normal gym exercise **or** a cardio block —
they are structurally different and the app tells them apart by the presence
of `isCardio: true`.

### 3a. Normal GYM exercise

```json
{
  "name": "Bench Press",
  "muscle": "Chest",
  "restTime": 90,
  "reps": 8,
  "sets": 4,
  "tag": "Primary"
}
```

| Field | Type | Notes |
|---|---|---|
| `name` | `string` | |
| `muscle` | `string` | One of the app's 8 fixed categories: `Chest`, `Back`, `Shoulders`, `Arms`, `Legs`, `Core`, `Glutes`, `Cardio`. |
| `restTime` | `int` | Seconds. |
| `reps` | `int` | Target rep count. |
| `sets` | `int` **or** `array<map>` | Either a plain count (`4`), or a fully-specified list of individual sets: `[{"type": "N", "kg": "", "reps": ""}, ...]` (`type` is one of `"W"` warm-up / `"N"` normal / `"D"` drop-set). Both forms are handled by the app's own set-parsing code — a plain int is simpler and is what the two other real curated plans use. |
| `tag` | `string` | `"Primary"` or `"Accessory"` — used by the session-compression feature to decide which exercises can be trimmed for a shorter workout. |

### 3b. CARDIO block

```json
{
  "name": "Run 25min",
  "muscle": "Cardio",
  "restTime": 0,
  "note": "",
  "tag": "Primary",
  "sets": [{ "type": "N", "kg": "", "reps": "25" }],
  "isCardio": true,
  "cardioActivity": "Run",
  "cardioMinutes": 25
}
```

| Field | Type | Notes |
|---|---|---|
| `name` | `string` | **Format: `"<Activity> <N>min"`** — e.g. `"Run 25min"`, `"Cycle 45min"`. Matches exactly what the app's own "Add Cardio Block" UI generates. |
| `muscle` | `string` | Always the literal string `"Cardio"`. |
| `restTime` | `int` | Always `0` for a cardio block. |
| `note` | `string` | Always `""` in real app-written data (present but unused for cardio). |
| `tag` | `string` | `"Primary"` (real app-written cardio blocks are always tagged Primary, never Accessory). |
| `sets` | `array<map>` | **Always exactly one entry**: `[{"type": "N", "kg": "", "reps": "<minutes as a string>"}]` — `kg` is always an empty string, `reps` holds the duration in minutes *as a string*, not a number. |
| `isCardio` | `bool` | **Must be `true`. This is the field that actually determines cardio vs. gym behavior everywhere in the app** — the gym session screen, exercise info navigation, and injury filtering all branch on this exact field. |
| `cardioActivity` | `string` | One of `"Run"`, `"Walk"`, `"Cycle"` — the app's fixed activity type set. |
| `cardioMinutes` | `int` | The real numeric duration (should match the string in `sets[0].reps`, just as a number instead of a string). |

### ⚠️ Cautionary example — the exact bug this document exists to prevent

The original `"5K Running Plan"` document (deleted and replaced during this
session) had exercise entries shaped like this:

```json
{
  "name": "Easy Run",
  "muscle": "Cardio",
  "note": "25-30 min at conversational pace",
  "restTime": 0,
  "reps": 1,
  "sets": 1,
  "tag": "Primary"
}
```

This is **missing `isCardio: true`** entirely (and used an invented
`reps`/`sets: 1` shape instead of the real cardio `sets` array format above).
Because nothing in the app ever reads `muscle == 'Cardio'` as a signal on its
own — only the explicit `isCardio: true` flag — the app treated this as a
**broken gym exercise** instead of a cardio block: no duration, no cardio
activity, and it wouldn't render or behave correctly anywhere it was used.
**Every cardio exercise entry an admin creates must include `isCardio: true`,
`cardioActivity`, and `cardioMinutes`, in addition to the cardio-shaped
`sets` array above — omitting any of these reproduces this exact bug.**

---

## 4. Complete, valid example — full real plan document

This is the actual `plans/{docId}` document created during this session
(`doc ID: nuRL47iPom4seI5rwPBO`), reproduced in full as a working end-to-end
reference. It demonstrates the top-level shape, rest days, a single-block
cardio day, and a multi-block cardio day (warm-up → interval effort →
cool-down, each its own properly-shaped cardio block) all together.

```json
{
  "name": "5K Beginner Runner",
  "level": "Beginner",
  "type": "Running",
  "daysPerWeek": 3,
  "durationWeeks": 8,
  "description": "An 8-week beginner-to-intermediate running plan building from an easy 25-minute run to a confident 5K. Mixes easy runs, structured intervals, and a weekly long run — increase each run's duration gradually week to week as it starts to feel comfortable.",
  "equipment": ["Running shoes"],
  "goals": ["Improve Endurance", "General Fitness"],
  "isActive": true,
  "matchGoals": ["Improve Endurance", "Lose Weight", "General Fitness"],
  "matchSport": "Running",
  "matchLevel": "Beginner",
  "designedBy": {
    "name": "Coach Amara Osei",
    "title": "Certified Running Coach",
    "credential": "UKA Level 2, RRCA Certified",
    "quote": "Consistency beats intensity — show up three times a week and the 5K takes care of itself."
  },
  "sessions": [
    {
      "day": "Day 1",
      "name": "Easy Run",
      "type": "gym",
      "isRestDay": false,
      "estimatedMinutes": 25,
      "exercises": [
        {
          "name": "Run 25min",
          "muscle": "Cardio",
          "restTime": 0,
          "note": "",
          "tag": "Primary",
          "sets": [{ "type": "N", "kg": "", "reps": "25" }],
          "isCardio": true,
          "cardioActivity": "Run",
          "cardioMinutes": 25
        }
      ]
    },
    {
      "day": "Day 2",
      "name": "Rest",
      "type": "rest",
      "isRestDay": true,
      "estimatedMinutes": 0,
      "exercises": []
    },
    {
      "day": "Day 3",
      "name": "Intervals",
      "type": "gym",
      "isRestDay": false,
      "estimatedMinutes": 30,
      "exercises": [
        {
          "name": "Run 10min",
          "muscle": "Cardio",
          "restTime": 0,
          "note": "",
          "tag": "Primary",
          "sets": [{ "type": "N", "kg": "", "reps": "10" }],
          "isCardio": true,
          "cardioActivity": "Run",
          "cardioMinutes": 10
        },
        {
          "name": "Run 15min",
          "muscle": "Cardio",
          "restTime": 0,
          "note": "",
          "tag": "Primary",
          "sets": [{ "type": "N", "kg": "", "reps": "15" }],
          "isCardio": true,
          "cardioActivity": "Run",
          "cardioMinutes": 15
        },
        {
          "name": "Run 5min",
          "muscle": "Cardio",
          "restTime": 0,
          "note": "",
          "tag": "Primary",
          "sets": [{ "type": "N", "kg": "", "reps": "5" }],
          "isCardio": true,
          "cardioActivity": "Run",
          "cardioMinutes": 5
        }
      ]
    },
    {
      "day": "Day 4",
      "name": "Rest",
      "type": "rest",
      "isRestDay": true,
      "estimatedMinutes": 0,
      "exercises": []
    },
    {
      "day": "Day 5",
      "name": "Long Run",
      "type": "gym",
      "isRestDay": false,
      "estimatedMinutes": 45,
      "exercises": [
        {
          "name": "Run 45min",
          "muscle": "Cardio",
          "restTime": 0,
          "note": "",
          "tag": "Primary",
          "sets": [{ "type": "N", "kg": "", "reps": "45" }],
          "isCardio": true,
          "cardioActivity": "Run",
          "cardioMinutes": 45
        }
      ]
    },
    {
      "day": "Day 6",
      "name": "Rest",
      "type": "rest",
      "isRestDay": true,
      "estimatedMinutes": 0,
      "exercises": []
    },
    {
      "day": "Day 7",
      "name": "Rest",
      "type": "rest",
      "isRestDay": true,
      "estimatedMinutes": 0,
      "exercises": []
    }
  ]
}
```

For a GYM-exercise-only example (no cardio at all), see the real
`"Beginner Push Pull Legs"` plan already in production — its `Day 1`/`Day 3`/
`Day 5` sessions use §3a's plain gym-exercise shape exclusively (Bench Press,
Overhead Press, Squat, etc., each with `sets` as a plain int).
