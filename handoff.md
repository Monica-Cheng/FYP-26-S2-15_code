# 🚀 PROJECT HANDOFF DOCUMENT

## WiseWorkout — 17 June 2026

---

## 1. PROJECT IDENTITY

- **App name:** WiseWorkout
- **One-line description:** AI-powered adaptive fitness tracker that recommends, schedules, and adjusts workout plans based on the user's health profile, goals, and behaviour
- **Core problem:** People don't stick to fitness plans because apps are too rigid. WiseWorkout adapts — compressing sessions when the user is busy, pausing for injuries, and learning from missed workouts
- **Target users:** Anyone from beginners to enthusiasts, 15–55 years old, iOS and Android
- **Target platforms:** iOS (primary demo device) + Android
- **Current stage:** MVP — functionally complete for demo, some features stubbed
- **Demo date:** 20 June 2026 (assessor demo, physical iPhone)
- **Final submission:** 15 August 2026
- **GitHub:** https://github.com/Monica-Cheng/FYP-26-S2-15_code
- **Local path:** /Users/monicacheng/Documents/FYP-26-S2-15_code
- **FYP code:** FYP-26-S2-15

---

## 2. FULL TECH STACK

### Frontend

- **Flutter 3.44.0 / Dart** — mobile app (iOS + Android)
- **State management:** StatefulWidget everywhere. Riverpod is installed but ONLY used for `routerProvider`. Do NOT add Riverpod elsewhere.
- **Navigation:** go_router ^14.2.7 — declarative routing, GoRoute list in `lib/core/router.dart`

### Backend / BaaS

- **Firebase Core** ^3.6.0
- **Firebase Auth** ^5.3.1 — email/password only
- **Cloud Firestore** ^5.4.4 — primary database
- **Firebase Messaging** ^15.1.3 — FCM installed but push sending not implemented (no Cloud Functions yet)
- **Cloud Functions** ^5.1.3 — installed but no functions deployed yet

### AI / LLM

- **OpenAI GPT-4o-mini** — called directly from Flutter via HTTP (Dart `http` package). NOT through Cloud Functions. API key stored in `.env` file loaded via `flutter_dotenv`. Used for: WiseCoach chat, post-session AI summary, post-cardio AI summary.

### Key packages (pubspec.yaml)

```yaml
cupertino_icons: ^1.0.8
firebase_core: ^3.6.0
firebase_auth: ^5.3.1
cloud_firestore: ^5.4.4
firebase_messaging: ^15.1.3
cloud_functions: ^5.1.3
go_router: ^14.2.7
flutter_riverpod: ^2.5.1
fl_chart: ^0.69.0
lottie: ^3.1.2
shared_preferences: ^2.3.2
intl: ^0.19.0
google_sign_in: ^6.2.1
http: ^1.2.0
flutter_dotenv: ^5.1.0
url_launcher: ^6.3.0
share_plus: ^10.1.4
path_provider: ^2.1.5
```

### Dev tools

- VS Code + Android Studio
- GitHub (version control)
- Taiga (sprint management)
- Figma (UI/UX design)
- Firebase Console (backend monitoring)

### Third-party APIs

- OpenAI API (GPT-4o-mini) — direct REST calls from Flutter
- Google Maps / Geolocator — NOT YET INSTALLED (needed for outdoor GPS cardio, deferred)

---

## 3. PROJECT FOLDER STRUCTURE

```
lib/
├── core/
│   ├── app_theme.dart          # ALL colors, shadows, decorations (WW.primary etc)
│   ├── constants.dart          # Firestore collection names (Collections.users etc)
│   └── router.dart             # All GoRoute definitions + Routes class
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   ├── register_screen.dart
│   │   └── forgot_password_screen.dart
│   ├── onboarding/
│   │   ├── onboarding_walkthrough_screen.dart
│   │   ├── onboarding_step1_screen.dart    # Personal info
│   │   ├── onboarding_step2_screen.dart    # Goals & preferences
│   │   └── onboarding_step3_screen.dart    # Permissions
│   ├── home/
│   │   ├── home_screen.dart               # Today's Plan card, XP ring, missed banner
│   │   └── missed_checkin_screen.dart     # Missed workout reason logging
│   ├── plans/
│   │   ├── plans_screen.dart              # Plans tab hub (Start Cardio, Train cards, All Plans)
│   │   ├── explore_screen.dart            # Explore catalog
│   │   ├── plan_match_screen.dart         # AI plan recommendation
│   │   ├── plan_detail_screen.dart        # Plan detail (Explore view + saved view)
│   │   ├── plan_schedule_screen.dart      # Full plan schedule with week tabs
│   │   ├── build_routine_screen.dart      # Build + Edit custom routine
│   │   ├── gym_session_screen.dart        # Active gym session (sets/reps logging)
│   │   └── post_session_summary_screen.dart # Session complete summary + share
│   ├── cardio/
│   │   ├── cardio_setup_screen.dart       # Activity + mode picker before cardio
│   │   └── cardio_session_screen.dart     # Indoor cardio timer screen
│   ├── coach/
│   │   └── coach_screen.dart             # WiseCoach chat + Find a Professional
│   ├── club/
│   │   └── club_screen.dart              # Leaderboard + challenges (hardcoded)
│   ├── progress/
│   │   └── progress_screen.dart          # Charts, Activities, XP History, Check-ins tabs
│   ├── profile/
│   │   ├── profile_screen.dart
│   │   └── edit_profile_screen.dart
│   └── settings/
│       ├── settings_screen.dart
│       ├── health_profile_screen.dart    # Injury, calorie goals, weight goals
│       └── manual_activity_log_screen.dart
├── services/
│   ├── auth_service.dart                 # Firebase Auth wrapper
│   └── firestore_service.dart            # ALL Firestore reads/writes
├── widgets/
│   └── share_card_widget.dart            # Branded share card for post-session share
└── main.dart
```

**Naming conventions:**

- Files: snake_case
- Classes: PascalCase
- All Firestore calls go through `firestore_service.dart` ONLY (no direct Firestore calls in widgets, except `missed_checkin_screen.dart` which has one direct write — acceptable)
- Colors: always `WW.primary`, `WW.teal` etc from `app_theme.dart` — NEVER hardcode hex

---

## 4. ARCHITECTURE & PATTERNS

### Overall pattern

Feature-first folder structure. No Clean Architecture layers. Simple: Screen → FirestoreService → Firestore.

### State management

- All screens use `StatefulWidget` + `setState`
- Riverpod ONLY for `routerProvider` in `main.dart`
- NO BLoC, NO ChangeNotifier, NO Provider (except Riverpod for router)

### Data flow

```
Widget (StatefulWidget)
  → FirestoreService().someMethod()
    → Firebase Firestore
      → Returns data
  → setState(() => _data = data)
```

### Navigation

- GoRouter with flat route list (no nested ShellRoutes)
- HomeScreen is a shell with IndexedStack for 5 tabs (Home, Plans, Coach, Club, Progress)
- Tab navigation: `context.go(Routes.home)`
- Stack navigation: `context.push(Routes.planDetail, extra: plan)`
- Pass data between screens via GoRouter `extra` parameter (Map<String, dynamic>)
- Screen reads extra via `GoRouterState.of(context).extra` in `initState` postFrameCallback

### Environment variables

- `.env` file in project root (not committed to git)
- Loaded via `flutter_dotenv` in `main.dart`
- Contains: `OPENAI_API_KEY`
- `firebase_options.dart` — auto-generated, DO NOT MODIFY

### Key rules (NEVER BREAK THESE)

1. Never hardcode hex colors — always use WW.X from app_theme.dart
2. Never call Firebase directly in widgets — always through firestore_service.dart
3. Never use Riverpod except for routerProvider
4. Never modify: firebase_options.dart, app_theme.dart (add only), constants.dart (add only)
5. ios/ and android/ folders: only modify when explicitly needed for native plugins

---

## 5. DATABASE / FIRESTORE SCHEMA

### `users/{uid}`

```
displayName: String
email: String
dob: String (ISO date)
heightCm: int
weightKg: double
biologicalSex: String
primaryGoal: String         # 'lose_weight', 'build_muscle', 'general_fitness'
sportPreference: String
experienceLevel: String     # 'beginner', 'intermediate', 'advanced'
equipmentAvailable: String
daysPerWeek: int
sessionLength: int
notificationsEnabled: bool
locationEnabled: bool
motionEnabled: bool
onboardingComplete: bool
totalXp: int
weeklyXp: int
level: int
calorieGoalActive: bool
dailyCalorieGoal: int
weeklyCalorieGoal: int
monthlyCalorieGoal: int
goalWeight: double          # user's target weight in kg
goalDate: String            # ISO date for weight goal target
weightGoalActive: bool      # whether weight goal tracking is on
trackedPlanId: String
trackedPlanName: String
savedPlanIds: [String]      # array of saved Explore plan IDs
overridePlanId: String      # temporary — cleared after gym session loads
overrideDayIndex: int       # temporary — cleared after gym session loads
```

### `users/{uid}/planProgress/{planId}`

```
planId: String
currentDayIndex: int
lastCompletedDate: String   # yyyy-MM-dd
lastCompletedDayIndex: int
compressedDays: [int]       # list of day indices that are compressed
breakModeActive: bool
breakStartDate: String
breakEndDate: String
breakDays: int
trackingStartDate: Timestamp
overrideDayIndex: int       # temporary — cleared after use
```

### `users/{uid}/customRoutines/{auto-id}`

```
name: String
sessions: [session maps]    # same structure as plans sessions
isCustom: bool
createdAt: Timestamp
```

### `users/{uid}/sessions/{auto-id}` (completed workout sessions)

```
type: String                # 'gym' or 'cardio' or 'manual'
sessionName: String
activity: String            # cardio only: 'Run', 'Walk', 'Cycle'
mode: String                # cardio only: 'indoor', 'outdoor'
date: Timestamp
createdAt: Timestamp
durationSeconds: int
exercises: [exercise maps]  # gym only
totalSets: int
totalVolume: double
caloriesBurned: int
xpEarned: int
isManuallyLogged: bool
```

### `users/{uid}/missedSessions/{date}` (date = yyyy-MM-dd of missed day)

```
reason: String              # 'busy', 'sick', 'injured', 'rest', 'skip'
planId: String
dayIndex: int
date: String
timestamp: Timestamp
```

### `users/{uid}/weightLogs/{date}` (date = yyyy-MM-dd)

```
weightKg: double
date: String
timestamp: Timestamp
```

### `plans/{planId}`

```
name: String
level: String               # 'Beginner', 'Intermediate', 'Advanced', 'Custom'
type: String                # 'Gym', 'Running', 'Hybrid'
daysPerWeek: int
durationWeeks: int
description: String
shortDescription: String
isCustom: bool
createdBy: String           # uid — for custom plans
savedCount: int
sessions: [                 # array of session maps
  {
    name: String            # e.g. 'Push A'
    day: String             # e.g. 'Day 1'
    type: String            # 'gym' or 'rest' or 'cardio'
    isRestDay: bool
    estimatedMinutes: int
    exercises: [
      {
        name: String
        muscle: String
        restTime: int       # seconds
        sets: int OR [      # int for seeded plans, List for custom
          { type: String, kg: String, reps: String }
        ]
        reps: int
        tag: String         # 'Primary' or 'Accessory'
        isCardio: bool      # true for cardio blocks
        cardioActivity: String  # 'Run', 'Walk', 'Cycle'
        cardioMinutes: int
      }
    ]
  }
]
designedBy: {               # optional, Explore plans only
  name: String
  title: String
  credential: String
  quote: String
}
createdAt: Timestamp
```

### Collections.X constants (from constants.dart)

```dart
static const String users = 'users';
static const String plans = 'plans';
static const String sessions = 'sessions';
static const String customRoutines = 'customRoutines';
static const String planProgress = 'planProgress';
// (check constants.dart for full list)
```

---

## 6. FEATURE STATUS TABLE

| Feature                                    | Screen/File                                       | Status         | Notes                                                             |
| ------------------------------------------ | ------------------------------------------------- | -------------- | ----------------------------------------------------------------- |
| Splash screen                              | splash_screen.dart                                | ✅ Done        |                                                                   |
| Onboarding walkthrough                     | onboarding_walkthrough_screen.dart                | ✅ Done        |                                                                   |
| Onboarding survey (3 steps)                | onboarding_step1/2/3_screen.dart                  | ✅ Done        |                                                                   |
| Login / Register / Forgot password         | auth/ screens                                     | ✅ Done        |                                                                   |
| Home screen — Today's Plan card            | home_screen.dart                                  | ✅ Done        | Shows tracked plan day                                            |
| Home screen — XP ring                      | home_screen.dart                                  | ✅ Done        |                                                                   |
| Home screen — missed session banner        | home_screen.dart                                  | ✅ Done        | Amber banner, fires once per missed day                           |
| Missed workout check-in screen             | missed_checkin_screen.dart                        | ✅ Done        | 5 reasons, logs to missedSessions                                 |
| Plans tab hub                              | plans_screen.dart                                 | ✅ Done        | Start Cardio, Plan Match, Explore, Build cards                    |
| Start Cardio button                        | plans_screen.dart                                 | ✅ Done        | Navigates to cardio_setup_screen                                  |
| Explore plans catalog                      | explore_screen.dart                               | ✅ Done        | Filters custom plans out, fromExplore flag                        |
| Save to My Plans                           | plan_detail_screen.dart                           | ✅ Done        | savedPlanIds on user doc                                          |
| Unsave / Remove from My Plans              | plan_detail_screen.dart                           | ✅ Done        | Confirm dialog + pop                                              |
| Plan Match (AI recommendation)             | plan_match_screen.dart                            | ✅ Done        | Rule-based, not true AI                                           |
| Plan detail — Explore view                 | plan_detail_screen.dart                           | ✅ Done        | Shows discovery info + coach card                                 |
| Plan detail — saved plan view              | plan_detail_screen.dart                           | ✅ Done        | Strips discovery info, Start buttons on days                      |
| Coach card ("Designed with")               | plan_detail_screen.dart                           | ✅ Done        | Shows if designedBy field exists in Firestore                     |
| Track This Plan                            | plan_detail_screen.dart                           | ✅ Done        | Sets trackedPlanId on user doc                                    |
| Untrack Plan                               | plan_detail_screen.dart                           | ✅ Done        |                                                                   |
| Plan Schedule (week view)                  | plan_schedule_screen.dart                         | ✅ Done        | Week pill selector, day cards                                     |
| Compress session                           | plan_schedule_screen.dart                         | ✅ Done        | Per-plan, stored in planProgress                                  |
| Break Mode                                 | plan_schedule_screen.dart                         | ✅ Done        | Per-plan, auto-expires                                            |
| Restart from Day 1                         | plan_schedule_screen.dart                         | ✅ Done        | Confirm dialog, resets planProgress                               |
| Build custom routine                       | build_routine_screen.dart                         | ✅ Done        | Day tabs, exercise search, cardio blocks                          |
| Edit custom routine                        | build_routine_screen.dart                         | ✅ Done        | Pre-fills existing data, updates Firestore                        |
| Delete custom routine                      | plan_detail_screen.dart                           | ✅ Done        | Deletes from plans/ and customRoutines/                           |
| Add Exercise (gym)                         | build_routine_screen.dart                         | ✅ Done        | Searchable library, muscle filter                                 |
| Add Cardio Block                           | build_routine_screen.dart                         | ✅ Done        | Run/Walk/Cycle + CupertinoPicker duration                         |
| Cardio machines in exercise library        | build_routine_screen.dart                         | ✅ Done        | Treadmill Run, Stationary Bike, Rowing, Elliptical, Stair Climber |
| Three-dot menu overlay (exercise card)     | build_routine_screen.dart                         | ✅ Done        | Uses Flutter Overlay, floats above ListView                       |
| Unlimited day tabs                         | build_routine_screen.dart                         | ✅ Done        | No 7-day cap                                                      |
| Per-plan progress storage                  | firestore_service.dart                            | ✅ Done        | planProgress/{planId} subcollection                               |
| Start session from any plan day            | plan_detail_screen.dart + gym_session_screen.dart | ✅ Done        | overridePlanId + overrideDayIndex on user doc                     |
| Gym session screen                         | gym_session_screen.dart                           | ✅ Done        | Sets/reps logging, rest timer, notes                              |
| Cardio exercise placeholder in gym session | gym_session_screen.dart                           | ✅ Done        | Shows Start Cardio card instead of set table                      |
| Post-session summary (gym)                 | post_session_summary_screen.dart                  | ✅ Done        | Stats, muscles, PBs, WiseCoach, share                             |
| Post-session summary (cardio)              | post_session_summary_screen.dart                  | ✅ Done        | Duration/Calories/Activity/Goal, HR placeholder                   |
| Share session card                         | post_session_summary_screen.dart                  | ✅ Done        | Off-tree render → PNG → native share sheet                        |
| Cardio setup screen                        | cardio_setup_screen.dart                          | ✅ Done        | Activity picker, indoor/outdoor, goal picker                      |
| Indoor cardio timer                        | cardio_session_screen.dart                        | ✅ Done        | MET calories, progress bar, pause/resume/+5min                    |
| Outdoor GPS cardio                         | —                                                 | ⏸ Stubbed      | Shows "coming soon" snackbar, redirects to indoor                 |
| WiseCoach chat                             | coach_screen.dart                                 | ✅ Done        | OpenAI GPT-4o-mini, conversation history                          |
| Find a Professional                        | coach_screen.dart                                 | ✅ Done        | Static list of professionals                                      |
| Club tab — leaderboard                     | club_screen.dart                                  | ⏸ Stubbed      | All hardcoded data                                                |
| Club tab — challenges                      | club_screen.dart                                  | ⏸ Stubbed      | All hardcoded data                                                |
| Progress — Charts tab                      | progress_screen.dart                              | ✅ Done        | Calories chart, gym volume chart, stat cards                      |
| Progress — Track Weight                    | progress_screen.dart                              | ✅ Done        | Line chart, goal line, log weight bottom sheet                    |
| Progress — Activities tab                  | progress_screen.dart                              | ✅ Done        | Session log with filter                                           |
| Progress — XP History tab                  | progress_screen.dart                              | ✅ Done        | XP log entries                                                    |
| Progress — Check-ins tab                   | progress_screen.dart                              | ✅ Done        | Missed session log, change reason                                 |
| Profile screen                             | profile_screen.dart                               | ✅ Done        |                                                                   |
| Edit profile                               | edit_profile_screen.dart                          | ✅ Done        |                                                                   |
| Health Profile — injury                    | health_profile_screen.dart                        | ⏸ Stubbed      | "Injury tracking coming soon"                                     |
| Health Profile — calorie goals             | health_profile_screen.dart                        | ✅ Done        | Separate from weight goals now                                    |
| Health Profile — weight goals              | health_profile_screen.dart                        | ✅ Done        | Separate section, own save button                                 |
| Settings screen                            | settings_screen.dart                              | ✅ Done        |                                                                   |
| Manual activity log                        | manual_activity_log_screen.dart                   | ✅ Done        |                                                                   |
| Apple HealthKit integration                | —                                                 | ❌ Not started | Next priority — needs ios/ changes + health package               |
| Google Health Connect                      | —                                                 | ❌ Not started | After HealthKit                                                   |
| Local notifications                        | —                                                 | ❌ Not started | flutter_local_notifications, needs ios/ + android/ changes        |
| Push notifications (server-side)           | —                                                 | ❌ Not started | Needs Cloud Functions                                             |
| Weight loss goal countdown on Home         | home_screen.dart                                  | ❌ Not started | goalDate field exists, UI not built                               |
| Month/Year charts in Progress              | progress_screen.dart                              | ⚠️ Broken      | Shows same weekly data for all filters                            |
| Weekly XP reset                            | —                                                 | ❌ Not started | Needs Cloud Function                                              |
| Personal bests detection                   | post_session_summary_screen.dart                  | ✅ Done        | Compares against session history                                  |
| XP system                                  | firestore_service.dart                            | ✅ Done        | +15 XP per set, addXpToUser()                                     |
| Badge system                               | post_session_summary_screen.dart                  | ⏸ Stubbed      | UI exists, logic hardcoded                                        |

---

## 7. KNOWN BUGS & ERRORS LOG

| #   | File                      | Symptom                                                                                                                                       | Decision                                           |
| --- | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| 1   | progress_screen.dart      | Month/Year filter shows same weekly data                                                                                                      | Fix later                                          |
| 2   | gym_session_screen.dart   | Cardio blocks within gym session open cardio_setup_screen but after cardio finishes, user goes to post-cardio summary not back to gym session | Known limitation — mixed session summary not built |
| 3   | home_screen.dart          | Weight stored as "30kg" string in some accounts → MET defaults to 70kg                                                                        | Fix later                                          |
| 4   | Various                   | `withOpacity()` deprecated warnings throughout                                                                                                | Ignore — pre-existing                              |
| 5   | plan_schedule_screen.dart | Empty day cards when plan has no sessions array                                                                                               | Fix later                                          |
| 6   | gym_session_screen.dart   | Session counter shows "59 sessions this week" — likely counting all-time not weekly                                                           | Investigate later                                  |

---

## 8. KEY DECISIONS MADE (DO NOT CHANGE)

| Decision                                                    | Why                                                                                                  | Rejected alternative                                             |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| StatefulWidget for all state                                | Simplicity for solo FYP developer                                                                    | BLoC, Provider                                                   |
| go_router for navigation                                    | Declarative, supports extra param for data passing                                                   | Navigator 2.0                                                    |
| All DB calls through firestore_service.dart                 | Single source of truth, easier to audit                                                              | Direct Firestore calls in widgets                                |
| WW.X color system only                                      | Consistency, easy theming                                                                            | Hardcoded hex                                                    |
| MET formula for cardio calories                             | Phone-based, no device needed                                                                        | Heart rate based (needs wearable)                                |
| Per-plan progress in planProgress/{planId} subcollection    | Prevents compress/completion state bleeding across plans                                             | Single user doc fields                                           |
| overridePlanId + overrideDayIndex on user doc               | gym_session_screen is self-loading — needs a way to tell it which plan/day to load for free sessions | Passing extra via router (gym_session reads nothing from router) |
| Off-tree rendering for share card                           | Offstage skips painting so toImage() fails; PipelineOwner off-tree guarantees paint                  | Positioned(left: -9999), Offstage                                |
| Directory.systemTemp instead of path_provider               | path_provider uses JNI which fails on Android emulator                                               | getTemporaryDirectory()                                          |
| fromExplore flag injected at navigation                     | Same plan_detail_screen used for both Explore and All Plans — flag determines which layout           | Separate screens                                                 |
| savedPlanIds array on user doc                              | Simple, no extra collection needed                                                                   | Separate savedPlans subcollection                                |
| Cardio indoor = timer only (no accelerometer)               | Accelerometer-based distance is inaccurate without calibration; HealthKit will provide this later    | Accelerometer step counting                                      |
| goalWeight and weightGoalActive separate from calorie goals | UX clarity — different intent, different save action                                                 | Combined in one card                                             |

---

## 9. DEFERRED / FUTURE FEATURES

| Feature                                     | Why deferred                                                           | Placeholder in code                                 | Dependency                                |
| ------------------------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------- | ----------------------------------------- |
| Outdoor GPS cardio                          | Needs geolocator + flutter_map + OpenStreetMap                         | Snackbar "GPS coming soon", redirects to indoor     | None                                      |
| Mixed gym+cardio session summary            | Complex — cardio block mid-gym-session ends at cardio summary, not gym | Known limitation, no workaround                     | Cardio session flow                       |
| Apple HealthKit                             | Needs ios/ native config + health package — doing next                 | Heart rate shows "Connect Apple Health" placeholder | iOS entitlements                          |
| Google Health Connect                       | After HealthKit                                                        | Same placeholder                                    | HealthKit done first                      |
| Local notifications                         | Needs flutter_local_notifications + ios/ + android/ config             | FCM installed but no sending                        | None                                      |
| Cloud Functions (FCM push)                  | Node.js/TypeScript, needs Firebase paid plan                           | firebase_messaging installed                        | Local notif first                         |
| Weekly XP reset                             | Needs Cloud Function cron job                                          | weeklyXp field exists                               | Cloud Functions                           |
| Admin dashboard                             | Separate React project                                                 | Not started                                         | None                                      |
| BLE heart rate                              | Complex hardware integration                                           | Not started                                         | HealthKit first                           |
| Weight goal countdown on Home               | Home screen already has goalDate field but no UI                       | goalDate stored in Firestore                        | None                                      |
| Body measurements tracking                  | No clear UI for displaying data                                        | Not started                                         | None                                      |
| Month/Year chart fix                        | Data query needs restructuring                                         | Filter buttons exist, show wrong data               | None                                      |
| Missed workout navigation to compress/break | Currently just shows snackbar advice                                   | Snackbar with text                                  | Plan schedule compress/break already done |
| Edit button for Explore/generated plans     | Only custom plans should be editable                                   | Edit button hidden for non-custom ✅                | None                                      |
| Restart Plan button context                 | Currently only in Plan Schedule for tracked plan                       | ✅ Done                                             | None                                      |
| Run plan week display                       | Plans only have 7 days of data in Firestore                            | Week pill selector already works                    | More plan data                            |

---

## 10. ENVIRONMENT & CONFIGURATION

### Firebase

- Project ID: (check `firebase_options.dart` — do NOT paste here)
- Services used: Firestore, Auth, Messaging, Functions (installed not deployed)
- **CRITICAL:** Firestore security rules expire **25 June 2026** — must update in Firebase Console before then

### Environment variables

- `.env` file in project root (gitignored)
- Contains: `OPENAI_API_KEY=sk-...`
- Loaded in `main.dart` via `await dotenv.load(fileName: '.env')`

### Run commands

```bash
# Android emulator (daily dev)
flutter run -d emulator-5554

# Real iPhone (demo day)
flutter run -d 00008140-000D04CC0E61801C

# Check connected devices
flutter devices

# Full rebuild (needed when adding native plugins)
flutter clean && flutter pub get && flutter run

# Push to GitHub
git add . && git commit -m "message" && git push
```

### Setup on fresh machine

1. Install Flutter 3.44.0
2. Install Android Studio + Android SDK
3. Install Xcode (for iOS)
4. Run `flutter pub get`
5. Add `.env` file with OpenAI API key
6. Run `flutterfire configure` if firebase_options.dart is missing
7. For iOS: `cd ios && pod install`

### Known platform quirks

- `share_plus` requires full `flutter run` after adding (not just hot restart) — native plugin registration
- `path_provider` on Android emulator fails with JNI error — workaround in place using `Directory.systemTemp`
- iOS demo device ID: `00008140-000D04CC0E61801C`

---

## 11. CLOUD FUNCTIONS INVENTORY

| Function            | Trigger                  | Purpose                                                     | Status                                                |
| ------------------- | ------------------------ | ----------------------------------------------------------- | ----------------------------------------------------- |
| sendWorkoutReminder | Scheduled (daily cron)   | Send FCM push notification at user's preferred workout time | ❌ Not built                                          |
| resetWeeklyXp       | Scheduled (every Monday) | Reset weeklyXp to 0 for all users                           | ❌ Not built                                          |
| openAiProxy         | HTTP callable            | Proxy OpenAI calls server-side to hide API key              | ❌ Not built (currently called directly from Flutter) |

---

## 12. CURRENT SPRINT / ACTIVE WORK

### Sprint 5 — Week of 17 June 2026

### Last completed (17 June 2026 — massive session):

- Per-plan progress migration to planProgress/{planId} subcollection
- Edit Routine pre-fill fixed (stream-based)
- Custom plans filtered from Explore
- Save to My Plans + All Plans filter to savedPlanIds
- Start button on every saved plan day card
- overridePlanId/overrideDayIndex for free session start
- Coach card ("Designed with") on plan detail
- Discovery info hidden for saved plans
- Health profile purple banner removed
- Custom plan hero cleanup
- Build Routine: Add Cardio Block (CupertinoPicker), cardio card UI, overlay menu, unlimited days
- Cardio machine exercises in library
- Plan Schedule: Restart Plan button, week grouping verified
- Missed Workout Check-in screen + banner on Home
- Progress Check-ins tab
- Standalone cardio flow: setup screen → indoor timer → post-cardio summary
- Post-session share button (off-tree render, branded card image)
- Weight logging + line chart in Progress tab
- Health Profile: separated weight goal from calorie goal
- goalWeight stream in Progress so it updates live
- LineChart single-point fix

### In progress right now:

Nothing — all above is complete and pushed

### Next immediate tasks (in order):

1. **Apple HealthKit** — reads heart rate, steps, calories from Apple Health on iPhone
   - Needs: `health` Flutter package added to pubspec.yaml
   - Needs: `ios/Runner/Info.plist` — add HealthKit usage descriptions
   - Needs: `ios/Runner/Runner.entitlements` — add HealthKit entitlement
   - Reads: heart rate, step count, active energy burned
   - Shows: heart rate in post-cardio summary (replaces "Connect Apple Health" placeholder)
   - Must test on physical iPhone ONLY (not emulator)

2. **Local notifications** — daily workout reminder
   - Package: `flutter_local_notifications`
   - Needs: ios/ and android/ manifest changes
   - User sets preferred time in Settings
   - Fires daily at that time

3. **Full demo flow test** on physical iPhone (Device ID: `00008140-000D04CC0E61801C`)

### Blocked:

- HealthKit cannot be tested on Android emulator — must use physical iPhone
- Local notifications need physical device for full testing

---

## 13. WHAT THE NEXT CLAUDE SHOULD DO FIRST

**Immediate task: Apple HealthKit Integration**

Step 1 — Ask Claude Code to read these files and answer questions BEFORE writing any code:

```
Read AGENT.md and RULES.md first. Then read:
- pubspec.yaml
- ios/Runner/Info.plist
- ios/Runner/Runner.entitlements (if it exists)
- lib/screens/plans/post_session_summary_screen.dart
- lib/screens/cardio/cardio_session_screen.dart
- lib/services/firestore_service.dart

Answer only:
1. Is the 'health' package already in pubspec.yaml?
2. Does Runner.entitlements exist? If yes show its full contents.
3. In Info.plist, are there any NSHealthKit usage description keys?
4. In post_session_summary_screen.dart, show the heart rate
   placeholder card widget — every line.
5. In cardio_session_screen.dart, is there any health/heart rate
   related code? Show any matches.
```

Step 2 — Based on output, write prompt to:

- Add `health: ^12.0.0` (or latest) to pubspec.yaml
- Add HealthKit entitlement to Runner.entitlements
- Add NSHealthKitUsageDescription to Info.plist
- Create `lib/services/health_service.dart` that requests permissions and reads: heart rate (most recent), step count (today), active energy burned (today)
- In cardio_session_screen.dart — after starting timer, start polling heart rate every 5 seconds from HealthKit, display live in the stats row
- In post_session_summary_screen.dart — replace "Connect Apple Health to unlock" placeholder with actual avg/max heart rate if HealthKit data is available
- Must fail gracefully if HealthKit not available (Android, emulator, no Apple Watch)

Step 3 — Test ONLY on physical iPhone. Run:

```bash
flutter run -d 00008140-000D04CC0E61801C
```

---

## 14. VIBE CODING PREFERENCES

- **Code style:** Give Claude Code prompts only — do not show me the code directly in chat unless I ask. I run Claude Code and paste back the output.
- **Prompt style:** Always ask Claude Code to READ files first before changing anything. Always say "Do NOT change anything until you have read all files fully."
- **Step size:** Go step by step — not everything in one giant prompt. But if two things are tightly connected, do them together.
- **Understanding first:** Before writing any prompt that modifies code, always ask Claude Code understanding questions first. Never assume the code matches what was previously discussed.
- **Explanations:** Before giving a Claude Code prompt, briefly explain what the issue is and why the fix works. Keep it concise — 3-5 lines max.
- **Errors:** When something doesn't work, ask for the terminal output / error message before attempting a fix. Don't guess.
- **Decisions:** For UI/UX decisions, discuss with me first. For pure technical implementation decisions (how to structure the code), Claude can decide independently.
- **File safety:** Always specify exactly which files to modify. Always say "do not modify any other files."
- **New files:** Always specify "do not create any new files except [name]" when creating new files.
- **Rules reminder:** Every Claude Code prompt must start with "Read AGENT.md and RULES.md first."
- **Don't like:** Vague prompts that don't specify exact file names and method names. Generic advice without specifics.
- **Do like:** Prompts that reference exact line numbers, exact method names, exact field names. Prompts that check the code before changing it.

---

## 15. PROMPTING STYLE FOR CLAUDE CODE

Standard prompt template:

```
Read AGENT.md and RULES.md first. Then read these files completely
before changing anything:
- lib/core/app_theme.dart
- lib/services/firestore_service.dart
- [other relevant files]

Do NOT change anything until you have read all files fully.

Task: [clear, specific description]

[Exact code or method to add/change, with exact file and location]

Requirements:
- [requirement 1]
- [requirement 2]

RULES:
- Use WW colors only — never hardcode hex
- Do NOT use Riverpod
- Only modify: [exact file list]
- Do not create any new files except [name if needed]
- Do not modify any other files
```

For understanding prompts (before writing code):

```
Read AGENT.md and RULES.md first. Then read [files].
Do NOT change anything. Answer only:
1. [specific question]
2. [specific question]
```

---

## 16. IMPORTANT CONTEXT THAT DOESN'T FIT ELSEWHERE

### Weird but intentional things in the code

- `gym_session_screen.dart` reads ALL its data from Firestore itself (getTrackedPlan, getPlanProgress) — it does NOT receive data via GoRouter extra. This was intentional. The workaround for free sessions (not tracked plan) is writing overridePlanId + overrideDayIndex to the user doc, which gym_session reads and clears immediately.
- `post_session_summary_screen.dart` reads extra in BOTH initState AND build() — initState reads planId and cardio fields, build() reads sessionName/exercises/date every render. This is intentional — avoids stale state.
- `Directory.systemTemp` used instead of `getTemporaryDirectory()` for share card image — this is because path_provider fails with JNI error on Android emulator. Works on real devices.
- `share_plus` requires full cold `flutter run` after first install — hot restart is not enough to register native plugin.

### Firebase security

- Firestore rules expire **25 June 2026** — UPDATE IN FIREBASE CONSOLE BEFORE THEN
- Current rules: open read/write for authenticated users (dev rules)
- For production: need proper per-user rules

### Demo constraints

- Demo is on physical iPhone, Device ID: `00008140-000D04CC0E61801C`
- Demo uses real Firebase (not emulator)
- Assessor will check all 5 key requirements — see Section 12 for priority order
- Do NOT push breaking changes on June 19 evening or June 20 morning

### Assessor's 5 key requirements and current status

1. **Collect exercise data from sensors/wearables** — ✅ Gym logging, ✅ Indoor cardio timer, ❌ HealthKit (next task)
2. **Estimate exercise effects + analysis** — ✅ Calories (MET), ✅ Progress charts, ✅ Weight chart, ❌ Heart rate (needs HealthKit)
3. **Supply fitness advice + schedule plan** — ✅ Plan Match, ✅ Build Routine, ✅ WiseCoach, ✅ Weight goal tracking
4. **Remind user to exercise or take a break** — ✅ Missed check-in banner, ❌ Local notifications (pending)
5. **Connect with social media + competitions** — ✅ Share button (native share sheet + branded card), ⏸ Club tab hardcoded

### Team context

- Solo developer: Monica Cheng
- FYP supervisor: aware of scope
- Teammate helping with demo video recording (they have not run the app before — demo script provided separately)
