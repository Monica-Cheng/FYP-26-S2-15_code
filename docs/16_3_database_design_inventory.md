# 16.3 Database Design Inventory

Repository scope only. This inventory is based strictly on current code evidence in this repository so the final report-level database design does not contradict the implementation.

## 1. Firestore Collections and Subcollections Found in Code

| Collection path | Parent | Purpose | File path evidence | Feature using it |
|---|---|---|---|---|
| `users/{userId}` | Root collection | Main user profile, onboarding, preferences, tracked plan state, calorie goals, XP totals, profile metadata | `lib/services/firestore_service.dart`, `lib/core/constants.dart`, many reads in `lib/screens/home`, `settings`, `profile`, `plans`, `progress` | Authenticated user profile, onboarding, home dashboard, settings, plans, progress |
| `users/{userId}/sessions/{sessionId}` | Subcollection under `users/{userId}` | Stores completed gym sessions and manually logged activities | `lib/services/firestore_service.dart` | Gym session tracking, manual activity logging, progress analytics, home dashboard |
| `users/{userId}/xpEvents/{xpEventId}` | Subcollection under `users/{userId}` | Stores XP history records | `lib/services/firestore_service.dart` | Gym session XP logging, progress XP history |
| `users/{userId}/customRoutines/{routineId}` | Subcollection under `users/{userId}` | Stores a private copy of user-created custom routines | `lib/services/firestore_service.dart` | Custom routine builder |
| `plans/{planId}` | Root collection | Stores workout plans, including custom routines promoted into the shared plans catalog | `lib/services/firestore_service.dart`, `lib/screens/plans/**` | Plans hub, explore, plan match, tracked plan, routine builder |
| `businessPartners/{partnerId}` | Root collection | Stores verified business partner / professional profiles for discovery | `lib/services/firestore_service.dart`, `lib/screens/coach/find_professional_screen.dart` | Find Professional |
| `exercises/{exerciseId}` | Root collection constant only | Declared as a collection constant but not queried or written in code | `lib/core/constants.dart` | Not used in runtime code |
| `challenges/{challengeId}` | Root collection constant only | Declared as a collection constant but not queried or written in code | `lib/core/constants.dart` | Not used in runtime code |

### Hardcoded or sample data affecting schema understanding

| Source | Nature | Notes |
|---|---|---|
| `lib/screens/plans/explore_screen.dart` | Hardcoded catalog plan list | Provides a non-Firestore plan shape with fields such as `id`, `name`, `level`, `sport`, `goal`, `daysPerWeek`, `totalWeeks`, `description`, `coach`, `saves`, `isCatalogOnly`. |
| `lib/screens/plans/plan_match_screen.dart` | Hardcoded preview data | Shows session preview structure with `day`, `session`, `exercises`, but this preview is not saved to Firestore. |
| `lib/screens/club/club_screen.dart` | Hardcoded community data | Leaderboard/challenge/friends UI uses local constants, not Firestore. |
| Seed JSON / fixture files | Not found | No Firestore seed scripts or schema JSON files were found in the repository. |

## 2. Document ID Strategy

| Collection path | Document ID strategy | Evidence |
|---|---|---|
| `users/{userId}` | Firebase Auth UID | `createUserProfile`, `updateUserProfile`, `getUserProfile` all use `.doc(uid)` in `lib/services/firestore_service.dart` |
| `users/{userId}/sessions/{sessionId}` | Auto-generated | `saveGymSession` and `saveManualActivity` both use `.add(...)` in `lib/services/firestore_service.dart` |
| `users/{userId}/xpEvents/{xpEventId}` | Auto-generated | `saveXpEvent` uses `.add(...)` in `lib/services/firestore_service.dart` |
| `users/{userId}/customRoutines/{routineId}` | Auto-generated | `saveCustomRoutine` writes private routine copy with `.add(...)` in `lib/services/firestore_service.dart` |
| `plans/{planId}` for custom routines | Auto-generated | `saveCustomRoutine` also writes a discoverable plan using `.add(...)` in `lib/services/firestore_service.dart` |
| `plans/{planId}` for existing catalog plans | Unclear from code | Existing plans are only read via `getPlans()` and `getTrackedPlan()`. The source of original plan IDs is not shown in repository code. |
| `businessPartners/{partnerId}` | Unclear from code | Only queried, never written, so ID strategy is not visible in code. |
| `exercises/{exerciseId}` | Unclear from code | Collection constant exists, but no reads/writes. |
| `challenges/{challengeId}` | Unclear from code | Collection constant exists, but no reads/writes. |

## 3. Field Inventory by Collection

## 3.1 `users/{userId}`

These fields are denormalized into the main user document. Some are written by onboarding, some by settings/profile flows, and some by tracking logic.

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `displayName` | `String` | Optional initially, required by onboarding step 1 UI | `"Monica"` | `onboarding_step1_screen.dart`, `health_profile_screen.dart`, `edit_profile_screen.dart` | `home_screen.dart`, `profile_screen.dart`, `settings/health_profile_screen.dart` | User-visible name |
| `dob` | `String` ISO date/datetime | Optional | `"2001-03-12"` or full ISO string | `onboarding_step1_screen.dart`, `health_profile_screen.dart` | `health_profile_screen.dart` | Date of birth |
| `biologicalSex` | `String` | Optional | `"Female"` | `onboarding_step1_screen.dart`, `health_profile_screen.dart` | `health_profile_screen.dart` | Body/health profile metadata |
| `heightCm` | `num` | Optional | `168`, `168.2` | `onboarding_step1_screen.dart`, `health_profile_screen.dart` | `health_profile_screen.dart` | Canonical stored height |
| `weightKg` | `num` | Optional | `62.5` | `onboarding_step1_screen.dart`, `health_profile_screen.dart` | `health_profile_screen.dart` | Canonical stored weight |
| `preferredUnits` | `String` | Optional | `"metric"` | `onboarding_step1_screen.dart` | Not explicitly read later | Unit preference |
| `healthConnected` | `bool` | Optional | `true` | `onboarding_step1_screen.dart` | Not explicitly read later | Health app connection flag |
| `wearableConnected` | `bool` | Optional | `true` | `onboarding_step1_screen.dart` | Not explicitly read later | Wearable connection flag |
| `primaryGoal` | `String` | Optional | `"Build Muscle"` | `onboarding_step2_screen.dart` | `health_profile_screen.dart` | User fitness goal |
| `sportPreference` | `String` | Optional | `"Gym only"` | `onboarding_step2_screen.dart` | `health_profile_screen.dart` | Preferred workout mode |
| `experienceLevel` | `String` | Optional | `"Beginner"` | `onboarding_step2_screen.dart` | `health_profile_screen.dart` | Training experience |
| `equipmentAvailable` | `List<String>` | Optional | `["Gym with weights"]` | `onboarding_step2_screen.dart` | Not explicitly read later | Available equipment |
| `daysPerWeek` | `int` | Optional | `3` | `onboarding_step2_screen.dart` | `health_profile_screen.dart` | Training frequency |
| `sessionLength` | `String` | Optional | `"45-60 min"` | `onboarding_step2_screen.dart` | Not explicitly read later | Target session duration |
| `notificationsEnabled` | `bool` | Optional | `true` | `onboarding_step3_screen.dart`, `settings_screen.dart` | `settings_screen.dart` | Push notification preference |
| `locationEnabled` | `bool` | Optional | `true` | `onboarding_step3_screen.dart` | Not explicitly read later | Location permission preference |
| `motionEnabled` | `bool` | Optional | `true` | `onboarding_step3_screen.dart` | Not explicitly read later | Motion permission preference |
| `onboardingComplete` | `bool` | Optional | `true` | `FirestoreService.markOnboardingComplete` | `splash_screen.dart` | Determines post-login routing |
| `workoutReminders` | `bool` | Optional | `true` | `settings_screen.dart` | `settings_screen.dart` | Notification preference |
| `streakAlerts` | `bool` | Optional | `true` | `settings_screen.dart` | `settings_screen.dart` | Notification preference |
| `wiseCoachMessages` | `bool` | Optional | `true` | `settings_screen.dart` | `settings_screen.dart` | Notification preference |
| `username` | `String` | Optional | `"@monica"` or `"monica"` | `edit_profile_screen.dart` | `edit_profile_screen.dart` | Profile identifier |
| `hometown` | `String` | Optional | `"Singapore"` | `edit_profile_screen.dart` | `profile_screen.dart`, `edit_profile_screen.dart` | Profile metadata |
| `bio` | `String` | Optional | `"Runner and lifter"` | `edit_profile_screen.dart` | `profile_screen.dart`, `edit_profile_screen.dart` | Profile biography |
| `calorieGoalActive` | `bool` | Optional | `true` | `health_profile_screen.dart` | `FirestoreService.getUserCalorieGoal`, `health_profile_screen.dart` | Enables calorie goal tracking |
| `dailyCalorieGoal` | `int` | Optional | `500` | `health_profile_screen.dart` | `FirestoreService.getUserCalorieGoal`, `home_screen.dart`, `health_profile_screen.dart` | Daily burn target |
| `weeklyCalorieGoal` | `int` | Optional | `3500` | `health_profile_screen.dart` | `health_profile_screen.dart` | Weekly burn target |
| `monthlyCalorieGoal` | `int` | Optional | `14000` | `health_profile_screen.dart` | `health_profile_screen.dart` | Monthly burn target |
| `goalWeight` | `double` | Optional | `58.0` | `health_profile_screen.dart` | `health_profile_screen.dart` | Goal body weight |
| `goalDate` | `String` ISO date or `Timestamp` | Optional | `"2026-09-01"` | `health_profile_screen.dart` | `health_profile_screen.dart` | Goal deadline |
| `totalXp` | `int` | Optional, system-maintained | `1200` | `FirestoreService.addXpToUser` | `profile_screen.dart`, `progress_screen.dart` | Total lifetime XP |
| `weeklyXp` | `int` | Optional, system-maintained | `300` | `FirestoreService.addXpToUser` | Not explicitly read in runtime UI | Weekly XP total |
| `level` | `int` | Optional, system-maintained | `3` | `FirestoreService.addXpToUser` | `profile_screen.dart`, `progress_screen.dart` | Current user level |
| `trackedPlanId` | `String` | Optional | `"abc123plan"` | `FirestoreService.trackPlan`, `plan_detail_screen.dart`, `plan_schedule_screen.dart` | `home_screen.dart`, `plan_detail_screen.dart`, `FirestoreService.getTrackedPlan` | Active tracked plan reference |
| `trackedPlanName` | `String` | Optional | `"Beginner Push Pull Legs"` | `FirestoreService.trackPlan`, `plan_detail_screen.dart`, `plan_schedule_screen.dart` | `home_screen.dart` | Denormalized active plan name |
| `trackingStartDate` | `Timestamp` | Optional | server timestamp | `FirestoreService.trackPlan` | Not explicitly read later | When plan tracking started |
| `currentDayIndex` | `int` | Optional | `1` | `FirestoreService.trackPlan`, `checkAndAdvanceDay`, `plan_schedule_screen.dart` | `home_screen.dart`, `gym_session_screen.dart`, `plan_schedule_screen.dart` | Current session pointer within tracked plan |
| `lastCompletedDate` | `String` date | Optional | `"2026-06-12"` | `FirestoreService.markSessionComplete` | `home_screen.dart`, `checkAndAdvanceDay` | Last tracked session completion date |
| `lastCompletedDayIndex` | `int` | Optional | `3` | `FirestoreService.markSessionComplete` | `checkAndAdvanceDay` | Prevents duplicate day advancement |
| `compressedDays` | `List<int>` | Optional | `[2, 5]` | `plan_schedule_screen.dart` | `home_screen.dart`, `gym_session_screen.dart`, `plan_schedule_screen.dart` | Indicates tracked-plan days compressed to primary exercises |
| `breakModeActive` | `bool` | Optional | `true` | `plan_schedule_screen.dart` | `plan_schedule_screen.dart` | Paused plan state |
| `breakStartDate` | `String` date | Optional | `"2026-06-12"` | `plan_schedule_screen.dart` | `plan_schedule_screen.dart` | Break period start |
| `breakEndDate` | `String` date | Optional | `"2026-06-15"` | `plan_schedule_screen.dart` | `plan_schedule_screen.dart` | Break period end |
| `breakDays` | `int` | Optional | `3` | `plan_schedule_screen.dart` | `plan_schedule_screen.dart` | Planned break length |
| `planMatchGoal` | `String` | Optional | `"Build Muscle"` | `plan_match_screen.dart` | `plan_match_screen.dart` | Saved plan match preference |
| `planMatchSport` | `String` | Optional | `"Both"` | `plan_match_screen.dart` | `plan_match_screen.dart` | Saved plan match preference |
| `planMatchLevel` | `String` | Optional | `"Beginner"` | `plan_match_screen.dart` | `plan_match_screen.dart` | Saved plan match preference |
| `planMatchEquipment` | `List<String>` | Optional | `["Gym with weights"]` | `plan_match_screen.dart` | `plan_match_screen.dart` | Saved plan match preference |
| `planMatchDays` | `int` | Optional | `3` | `plan_match_screen.dart` | `plan_match_screen.dart` | Saved plan match preference |

### Important schema note

- There is an inconsistency in weight field naming:
  - Most code writes and reads `weightKg`.
  - `FirestoreService.saveGymSession()` and `ManualActivityLogScreen._loadUserWeight()` attempt to read `weight`, not `weightKg`.
  - Evidence: `lib/services/firestore_service.dart`, `lib/screens/home/manual_activity_log_screen.dart`.

## 3.2 `users/{userId}/sessions/{sessionId}`

This subcollection stores both gym sessions and manual activities.

### Common fields

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `type` | `String` | Required | `"gym"`, `"manual"` | `saveGymSession`, `saveManualActivity` | `progress_screen.dart`, `activity_detail_screen.dart`, weekly stats logic | Session discriminator |
| `date` | `Timestamp` | Required | server timestamp or `Timestamp.fromDate(...)` | `saveGymSession`, `saveManualActivity` | Home, progress, streak, daily calorie, session date queries | Main session date |
| `createdAt` | `Timestamp` | Required | server timestamp | `saveGymSession`, `saveManualActivity` | Not explicitly read later | Creation audit |
| `caloriesBurned` | `int` | Required | `320` | `saveGymSession`, `saveManualActivity` | Home, progress, weekly stats, activity detail | Calorie metric |
| `durationSeconds` | `int` | Optional for manual, required in writes | `2700` | `saveGymSession`, `saveManualActivity` | Progress, activity detail | Duration in seconds |
| `xpEarned` | `int` | Required | `180` or `0` | `saveGymSession`, `saveManualActivity` | Progress, activity detail | XP gained from session |
| `isManuallyLogged` | `bool` | Required | `false`, `true` | `saveGymSession`, `saveManualActivity` | Progress, activity detail | Distinguishes manual entries |

### Gym session-specific fields

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `sessionName` | `String` | Required for gym | `"Push A"` | `saveGymSession` | Progress, activity detail | Workout session name |
| `exercises` | `List<Map>` | Optional but normally present | See nested structure below | `saveGymSession` | Activity detail, post-session displays via route data | Completed exercise summary |
| `totalSets` | `int` | Required | `12` | `saveGymSession` | Progress, activity detail | Number of completed sets |
| `totalVolume` | `double` | Required | `4520.0` | `saveGymSession` | Progress, activity detail, weekly stats | Summed load volume |

### Manual activity-specific fields

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `activityKey` | `String` | Required for manual | `"running"` | `saveManualActivity` | Not prominently displayed later | Internal activity identifier |
| `activityName` | `String` | Required for manual | `"Running"` | `saveManualActivity` | Progress, activity detail | User-facing activity name |
| `intensity` | `String` | Required for manual | `"moderate"` | `saveManualActivity` | Activity detail | Intensity label |
| `durationMinutes` | `int` | Required for manual | `30` | `saveManualActivity` | Progress, activity detail | Duration in minutes |
| `distance` | `double` | Optional | `5.2` | `saveManualActivity` | Activity detail | Distance if relevant |
| `notes` | `String` | Optional | `"Evening run"` | `saveManualActivity` | Activity detail | Free-text notes |

### Nested `exercises` structure in gym sessions

Persisted structure after `saveGymSession()` is cleaned and reduced:

| Field path | Type | Example | Purpose |
|---|---|---|---|
| `exercises[].name` | `String` | `"Bench Press"` | Exercise name |
| `exercises[].muscle` | `String` | `"Chest"` | Muscle group |
| `exercises[].sets` | `List<Map>` | `[{kg: 80.0, reps: 8, done: true}]` | Completed sets only |
| `exercises[].sets[].kg` | `double?` | `80.0` | Logged load |
| `exercises[].sets[].reps` | `int?` | `8` | Logged reps |
| `exercises[].sets[].done` | `bool` | `true` | Completion flag |

### Route-only session data not persisted to Firestore

`GymSessionScreen` passes richer `sessionData` to `PostSessionSummaryScreen`, including fields like `elapsedSeconds` and potentially exercise notes/current set state. `saveGymSession()` persists a cleaned subset only. Evidence: `lib/screens/plans/gym_session_screen.dart`, `lib/screens/plans/post_session_summary_screen.dart`.

### Read-only but not written session fields

`ActivityDetailScreen` reads `wiseCoachSummary`, but no code writes this field to Firestore. This suggests the screen supports a richer target schema than the current persisted implementation. Evidence: `lib/screens/progress/activity_detail_screen.dart`.

## 3.3 `users/{userId}/xpEvents/{xpEventId}`

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `amount` | `int` | Required | `180` | `FirestoreService.saveXpEvent`, called from `gym_session_screen.dart` | `progress_screen.dart` | XP amount |
| `reason` | `String` | Required | `"Completed Push A · 12 sets"` | `saveXpEvent` call in `gym_session_screen.dart` | `progress_screen.dart` | Human-readable reason |
| `type` | `String` | Required | `"gym"` | `saveXpEvent` call in `gym_session_screen.dart` | `progress_screen.dart` | Event type |
| `date` | `Timestamp` | Required | server timestamp | `FirestoreService.saveXpEvent` | `progress_screen.dart` | Event timestamp |

## 3.4 `users/{userId}/customRoutines/{routineId}`

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `name` | `String` | Required | `"My Custom Routine"` | `FirestoreService.saveCustomRoutine` | Not read directly later in repo | Private routine name |
| `createdAt` | `Timestamp` | Required | server timestamp | `saveCustomRoutine` | Not read directly later | Audit timestamp |
| `sessions` | `List<Map>` | Required | See plan session structure below | `saveCustomRoutine` | Not read directly later in repo | Embedded routine schedule |
| `isCustom` | `bool` | Required | `true` | `saveCustomRoutine` | Not read directly later | Marks routine as custom |

## 3.5 `plans/{planId}`

This collection mixes:
- Firestore-backed plans read by the app
- custom routines copied into plans
- hardcoded catalog field expectations in the UI

### Fields definitely written for custom routines

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `name` | `String` | Required | `"My Custom Routine"` | `saveCustomRoutine`, `updateCustomRoutine` | Plans screens, plan detail, plan match, plan schedule | Plan name |
| `level` | `String` | Required in custom write | `"Custom"` | `saveCustomRoutine` | `plans_screen.dart`, `plan_detail_screen.dart` | Difficulty / label |
| `type` | `String` | Required in custom write | `"Gym"` | `saveCustomRoutine` | Plans screens, plan detail, plan match | Plan type |
| `daysPerWeek` | `int` | Required | `3` | `saveCustomRoutine`, `updateCustomRoutine` | Plans screens, plan detail, plan match | Weekly frequency |
| `description` | `String` | Required in custom write | `"Custom routine created by user"` | `saveCustomRoutine` | `plan_detail_screen.dart` | Plan description |
| `isCustom` | `bool` | Required | `true` | `saveCustomRoutine` | `plan_detail_screen.dart`, `build_routine_screen.dart` | Custom plan marker |
| `createdBy` | `String` | Required in custom write | Firebase UID | `saveCustomRoutine` | Not explicitly read later | Creator reference |
| `sessions` | `List<Map>` | Required | See below | `saveCustomRoutine`, `updateCustomRoutine` | Home, gym session, plan detail, plan schedule, build routine | Embedded schedule/workout definition |
| `createdAt` | `Timestamp` | Required | server timestamp | `saveCustomRoutine` | Not explicitly read later | Audit timestamp |
| `updatedAt` | `Timestamp` | Optional | server timestamp | `updateCustomRoutine` | Not explicitly read later | Audit timestamp |

### Additional plan fields read or expected by screens

These may exist on seeded/manual Firestore plans or on hardcoded catalog plans.

| Field | Type | Example | Read where | Notes |
|---|---|---|---|---|
| `durationWeeks` | `int` | `8` | `plan_detail_screen.dart`, `plan_match_screen.dart` | Not written by custom routine save |
| `equipment` | `List<String>` | `["Barbell", "Bench"]` | `plan_detail_screen.dart` | Plan requirements |
| `goals` | `List<String>` | `["Build Muscle"]` | `plan_detail_screen.dart` | Plan outcomes |
| `goal` | `String` | `"Lose Weight"` | `explore_screen.dart` | Used by hardcoded catalog filter |
| `sport` | `String` | `"Running"` | `explore_screen.dart` | Used by hardcoded catalog and filtering |
| `coach` | `String` | `"WiseWorkout"` | `explore_screen.dart` | Display field in catalog UI |
| `saves` | `int` | `143` | `explore_screen.dart` | Display metric in catalog UI |
| `isCatalogOnly` | `bool` | `true` | `explore_screen.dart` | Hardcoded UI data only |
| `matchGoals` | `List<String>` | `["build muscle"]` | `plan_match_screen.dart` | Matching metadata |
| `matchSport` | `String` | `"Both"` | `plan_match_screen.dart` | Matching metadata |
| `matchLevel` | `String` | `"Beginner"` | `plan_match_screen.dart` | Matching metadata |

### Embedded `sessions` structure in plans

Plan sessions are embedded arrays, not separate documents.

| Field path | Type | Example | Read/write evidence | Purpose |
|---|---|---|---|---|
| `sessions[]` | `List<Map>` | See below | Written in `build_routine_screen.dart`, read in plan/home/gym screens | Schedule array |
| `sessions[].name` | `String` | `"Push A"` | `build_routine_screen.dart`, `gym_session_screen.dart`, `plan_detail_screen.dart` | Session name |
| `sessions[].day` | `String` | `"Day 1"` | `build_routine_screen.dart`, `plan_detail_screen.dart` | Day label |
| `sessions[].type` | `String` | `"gym"` | `build_routine_screen.dart` | Session type |
| `sessions[].isRestDay` | `bool` | `false` | `build_routine_screen.dart`, `gym_session_screen.dart`, `home_screen.dart` | Rest day marker |
| `sessions[].estimatedMinutes` | `int` | `45` | Read in `home_screen.dart`, `plan_detail_screen.dart` | Optional display duration, not written by custom builder |
| `sessions[].exercises` | `List<Map>` | See below | Written in `build_routine_screen.dart`, read widely | Embedded exercise list |

### Embedded exercise structure inside plan sessions

| Field path | Type | Example | Read/write evidence | Purpose |
|---|---|---|---|---|
| `sessions[].exercises[].name` | `String` | `"Bench Press"` | Written in `build_routine_screen.dart`, read in home/gym/plan detail | Exercise name |
| `sessions[].exercises[].muscle` | `String` | `"Chest"` | Written in `build_routine_screen.dart`, read in home/gym/plan detail | Muscle group |
| `sessions[].exercises[].restTime` | `int` | `90` | Written in `build_routine_screen.dart`, read in `gym_session_screen.dart` | Rest timer default |
| `sessions[].exercises[].note` | `String` | `"Keep elbows tucked"` | Written in `build_routine_screen.dart`, read when editing | Exercise note |
| `sessions[].exercises[].tag` | `String` | `"Primary"` | Written in `build_routine_screen.dart`, read in home/gym/plan detail | Used for compressed-day filtering |
| `sessions[].exercises[].sets` | `List<Map>` or `int` depending on source | `[{type:"N",kg:"",reps:""}]` or `3` | Builder writes list-of-maps; some plan readers assume numeric count | Set configuration |
| `sessions[].exercises[].reps` | `int` | `10` | Read in `home_screen.dart`, `plan_detail_screen.dart` | Some non-custom plan documents may store top-level reps |

### Embedded set structure in custom routines

| Field path | Type | Example | Purpose |
|---|---|---|---|
| `sessions[].exercises[].sets[].type` | `String` | `"W"`, `"N"`, `"D"` | Warmup / normal / drop-set marker |
| `sessions[].exercises[].sets[].kg` | `String` | `"60"` | Planned/set weight input |
| `sessions[].exercises[].sets[].reps` | `String` | `"8"` | Planned/set reps input |

## 3.6 `businessPartners/{partnerId}`

| Field | Type | Required / optional | Example value | Written where | Read where | Purpose |
|---|---|---|---|---|---|---|
| `isApproved` | `bool` | Required for queryability | `true` | Not written in repo | `FirestoreService.getBusinessPartners` | Approval filter |
| `isVisible` | `bool` | Required for queryability | `true` | Not written in repo | `getBusinessPartners` | Visibility filter |
| `name` | `String` | Optional | `"John Tan"` | Not written in repo | `find_professional_screen.dart` | Display name |
| `displayName` | `String` | Optional alternative | `"John Tan"` | Not written in repo | `find_professional_screen.dart` | Alternate display name |
| `type` | `String` | Optional but used in filters | `"Trainer"` | Not written in repo | `find_professional_screen.dart` | Professional type |
| `bio` | `String` | Optional | `"Certified strength coach"` | Not written in repo | `find_professional_screen.dart` | Description |
| `email` | `String` | Optional | `"coach@example.com"` | Not written in repo | `find_professional_screen.dart` | Contact email |
| `certifications` | `List<String>` | Optional | `["NASM CPT"]` | Not written in repo | `find_professional_screen.dart` | Credential display |

## 3.7 `challenges` / leaderboard-related data

| Finding | Evidence | Notes |
|---|---|---|
| Firestore collection constant exists | `lib/core/constants.dart` | `Collections.challenges` declared |
| Runtime reads/writes | Not found | `club_screen.dart` uses hardcoded challenge and leaderboard data only |
| Diagram implication | Mention carefully | Current repository does not prove a live Firestore `challenges` schema yet |

## 4. Relationships Between Data Entities

- One `users/{userId}` document belongs to one authenticated Firebase user.
- One user has many `users/{userId}/sessions/{sessionId}` documents.
- One user has many `users/{userId}/xpEvents/{xpEventId}` documents.
- One user has many `users/{userId}/customRoutines/{routineId}` documents.
- One user may track one active plan at a time through:
  - `users/{userId}.trackedPlanId`
  - `users/{userId}.trackedPlanName`
- One `plans/{planId}` document may be tracked by many different users through `trackedPlanId`.
- One `plans/{planId}` document contains many embedded `sessions[]`.
- One embedded plan session contains many embedded `exercises[]`.
- One embedded exercise contains many embedded `sets[]`.
- One session document belongs to one user only; there is no cross-user session collection.
- One XP event belongs to one user only.
- One business partner may be viewed and contacted by many users, but there is no stored join or booking collection in current code.
- Challenge / leaderboard relationships are not modeled in Firestore runtime code; current social data is hardcoded UI.

## 5. Query Patterns and Index Needs

| Code location | Collection path | Query pattern | Fields used | Composite index likely needed? | Notes |
|---|---|---|---|---|---|
| `FirestoreService.getTodaysSessions` | `users/{uid}/sessions` | `where(date >= midnight)` | `date` | No | Single-field range query |
| `FirestoreService.getRecentSessions` | `users/{uid}/sessions` | `orderBy(date desc).limit(limit)` | `date` | No | Simple ordered query |
| `FirestoreService.getTodaysCalories` | `users/{uid}/sessions` | `where(date >= midnight)` | `date` | No | Same as today sessions |
| `FirestoreService.calculateStreak` | `users/{uid}/sessions` | `orderBy(date desc)` | `date` | No | Simple ordered query |
| `FirestoreService.getSessionDates` | `users/{uid}/sessions` | `where(date >= cutoff)` | `date` | No | Single-field range query |
| `FirestoreService.getWeeklySessionStats` | `users/{uid}/sessions` | `where(date >= weekStart)` | `date` | No | Single-field range query |
| `FirestoreService.getXpEvents` | `users/{uid}/xpEvents` | `orderBy(date desc).limit(limit)` | `date` | No | Simple ordered query |
| `FirestoreService.getPlans` | `plans` | full collection read | none | No | Reads all plans |
| `FirestoreService.getTrackedPlan` | `plans/{planId}` | direct doc lookup | document ID | No | Uses ID from user document |
| `FirestoreService.getBusinessPartners` | `businessPartners` | `where(isApproved == true).where(isVisible == true)` | `isApproved`, `isVisible` | Possibly | Two equality filters may need an index depending on Firestore index behavior/config |
| `home_screen.dart` live listener | `users/{uid}` | document snapshot stream | document ID | No | Direct document listener |

### Practical index note for report

- The current codebase mainly uses simple subcollection queries on `date`.
- The most index-sensitive query is the `businessPartners` dual-filter query.
- If future queries combine multiple filters with `orderBy`, additional composite indexes will likely be required.

## 6. Data Duplication / Embedded Data

### Embedded arrays and maps

- Plan schedules are embedded inside `plans/{planId}.sessions`.
- Exercises are embedded inside each plan session as `sessions[].exercises`.
- Set data is embedded inside each exercise as `sets[]`.
- Completed gym session exercise summaries are embedded inside `users/{uid}/sessions/{sessionId}.exercises`.
- Custom routine definitions are duplicated:
  - private copy in `users/{uid}/customRoutines`
  - shared/discoverable copy in `plans`

### Denormalized user fields

- `trackedPlanName` duplicates plan name from `plans/{planId}` for easy dashboard display.
- `displayName`, `level`, `totalXp`, `weeklyXp`, `calorieGoalActive`, and calorie goal fields are stored directly on the user document for direct access.
- `planMatch*` fields store a snapshot of matching preferences on the user document instead of a separate preferences document.

### Calculated totals stored in documents

- Session-level totals stored in session documents:
  - `totalSets`
  - `totalVolume`
  - `caloriesBurned`
  - `xpEarned`
- User-level totals stored in user document:
  - `totalXp`
  - `weeklyXp`
  - `level`
- Why this design makes sense in Firestore:
  - avoids expensive recomputation on every screen load
  - supports dashboard reads with fewer queries
  - matches Firestore’s document-oriented style
  - simplifies mobile UI performance

## 7. Target Database Design Recommendation

This is a clean report-level recommendation aligned with the current codebase and FYP scope. It is intentionally simplified for academic presentation.

### Recommended top-level collections

#### `users`

Key fields:
- `displayName`
- `dob`
- `biologicalSex`
- `heightCm`
- `weightKg`
- `preferredUnits`
- `healthConnected`
- `wearableConnected`
- `primaryGoal`
- `sportPreference`
- `experienceLevel`
- `equipmentAvailable`
- `daysPerWeek`
- `sessionLength`
- `notificationsEnabled`
- `locationEnabled`
- `motionEnabled`
- `onboardingComplete`
- `username`
- `hometown`
- `bio`
- `calorieGoalActive`
- `dailyCalorieGoal`
- `weeklyCalorieGoal`
- `monthlyCalorieGoal`
- `goalWeight`
- `goalDate`
- `totalXp`
- `weeklyXp`
- `level`
- `trackedPlanId`
- `trackedPlanName`
- `trackingStartDate`
- `currentDayIndex`
- `lastCompletedDate`
- `lastCompletedDayIndex`
- `compressedDays`
- `breakModeActive`
- `breakStartDate`
- `breakEndDate`
- `breakDays`
- `planMatchGoal`
- `planMatchSport`
- `planMatchLevel`
- `planMatchEquipment`
- `planMatchDays`

#### `users/{userId}/sessions`

Key fields:
- `type`
- `sessionName`
- `activityKey`
- `activityName`
- `intensity`
- `durationMinutes`
- `durationSeconds`
- `distance`
- `notes`
- `date`
- `createdAt`
- `exercises`
- `totalSets`
- `totalVolume`
- `caloriesBurned`
- `xpEarned`
- `isManuallyLogged`
- `wiseCoachSummary`

#### `users/{userId}/xpEvents`

Key fields:
- `amount`
- `reason`
- `type`
- `date`

#### `users/{userId}/customRoutines`

Key fields:
- `name`
- `createdAt`
- `sessions`
- `isCustom`

#### `users/{userId}/coachMessages`

Recommended key fields:
- `role`
- `content`
- `createdAt`
- `sessionContext`
- `messageType`

Reason:
- Not implemented in current code, but fits the existing WiseCoach feature direction and database diagram clarity.

#### `plans`

Key fields:
- `name`
- `type`
- `level`
- `description`
- `daysPerWeek`
- `durationWeeks`
- `goals`
- `equipment`
- `matchGoals`
- `matchSport`
- `matchLevel`
- `createdBy`
- `isCustom`
- `sessions`
- `createdAt`
- `updatedAt`

#### `exercises`

Recommended key fields:
- `name`
- `muscle`
- `equipment`
- `difficulty`
- `instructions`
- `mediaUrl`

Reason:
- The runtime code currently uses embedded exercise definitions, but a top-level exercise library is consistent with `Collections.exercises`.

#### `challenges`

Recommended key fields:
- `name`
- `description`
- `type`
- `startDate`
- `endDate`
- `xpReward`
- `participants`
- `status`

Reason:
- Current social screen is hardcoded, but challenge collection is already reserved in constants.

#### `businessPartners`

Key fields:
- `displayName`
- `type`
- `bio`
- `email`
- `certifications`
- `isApproved`
- `isVisible`
- `createdAt`

#### `adminLogs` or `moderationLogs`

Recommended key fields:
- `actorId`
- `action`
- `targetCollection`
- `targetId`
- `timestamp`
- `notes`

Reason:
- Suitable for admin/business partner moderation in target architecture.

#### Storage metadata collection if needed

Suggested name:
- `mediaMetadata`

Recommended key fields:
- `ownerId`
- `entityType`
- `entityId`
- `storagePath`
- `downloadUrl`
- `createdAt`

Reason:
- Useful if profile images, exercise images, or partner media are added.

## 8. Diagram Preparation Notes

### Collections that should appear in the database diagram

- `users`
- `users/{userId}/sessions`
- `users/{userId}/xpEvents`
- `users/{userId}/customRoutines`
- `users/{userId}/coachMessages`
- `plans`
- `exercises`
- `challenges`
- `businessPartners`
- `adminLogs` or `moderationLogs`

### Collections that can be described in text only

- `mediaMetadata`
- notification preference fields inside `users`
- break-mode and compressed-day tracking fields inside `users`
- plan-matching preference fields inside `users`

### Recommended relationships to show with arrows

- `users` -> `sessions`
- `users` -> `xpEvents`
- `users` -> `customRoutines`
- `users` -> `coachMessages`
- `users.trackedPlanId` -> `plans`
- `plans` -> embedded `sessions[]`
- embedded `sessions[]` -> embedded `exercises[]`
- embedded `exercises[]` -> embedded `sets[]`
- `users` -> `businessPartners` as view/contact relationship if desired at conceptual level

### Recommended relationships to avoid showing

- Too many arrows from every user preference field to feature modules
- Arrows for hardcoded social UI data not backed by Firestore
- Multiple duplicate arrows from both `customRoutines` and `plans` to every embedded exercise/set node
- Arrows for optional future-only storage metadata unless the diagram becomes too sparse

### Best diagram style

- `draw.io` ERD style is the best fit for the final report.

Reason:
- Firestore is document-oriented, so a freeform ERD in draw.io gives better control than strict Mermaid ERD.
- Mermaid ERD can still work, but embedded arrays/maps are awkward to express cleanly.
- Mermaid `classDiagram` is less suitable than ERD style for collection/document relationships.
