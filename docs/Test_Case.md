# WiseWorkout Implementation Audit for System Testing Preparation

**Generated:** 2026-06-12  
**Scope:** Repository audit only. This document is based strictly on code visible in this repository and does not assume external services or missing repos.  
**Purpose:** Working implementation inventory to support later System Testing documentation. This is **not** the final report.

---

## 1. Project structure summary

### 1.1 Main folders

| Folder | Purpose observed |
|---|---|
| `lib/` | Main Flutter application code |
| `lib/core/` | Theme, route constants, `GoRouter` setup, shared constants |
| `lib/screens/` | Screen-level UI and most feature logic |
| `lib/services/` | Firebase Auth and Firestore data access |
| `lib/models/` | Present but empty |
| `lib/providers/` | Present but empty |
| `lib/widgets/` | Present but effectively unused for major feature logic |
| `android/` | Android Flutter host project |
| `ios/` | iOS Flutter host project |
| `test/` | Flutter test folder with one smoke test |
| `docs/` | Technical documentation files |

### 1.2 Main app entry points

| Entry point | Evidence | Notes |
|---|---|---|
| Flutter app bootstrap | `lib/main.dart` | Loads `.env`, initializes Firebase, starts `ProviderScope`, builds `MaterialApp.router` |
| Splash entry flow | `lib/screens/splash_screen.dart` | Checks current auth state and onboarding completion, then routes to walkthrough, onboarding, or home |
| Android host entry | `android/app/src/main/kotlin/com/wiseworkout/wise_workout/MainActivity.kt` | Standard Flutter Android host |
| iOS host entry | `ios/Runner/AppDelegate.swift` | Standard Flutter iOS host |

### 1.3 Main routing/navigation files

| File | Role |
|---|---|
| `lib/core/router.dart` | Central route constants and `GoRouter` route table |
| `lib/screens/home/home_screen.dart` | Main 5-tab shell using `IndexedStack` for Home, Plans, Coach, Club, Progress |
| `lib/screens/splash_screen.dart` | Startup navigation decision point |

### 1.4 Main Firebase/config files

| File | Role |
|---|---|
| `firebase.json` | FlutterFire project configuration output |
| `lib/firebase_options.dart` | Generated Firebase platform options |
| `pubspec.yaml` | Declared Flutter/Firebase/OpenAI-related dependencies |
| `.env` | Loaded at runtime for OpenAI API key usage from app code |
| `android/app/src/main/AndroidManifest.xml` | Android app manifest |
| `ios/Runner/Info.plist` | iOS app plist |

### 1.5 Main service/repository/provider/controller files

| File | Type | Notes |
|---|---|---|
| `lib/services/auth_service.dart` | Service | Wraps Firebase Auth + Google Sign-In |
| `lib/services/firestore_service.dart` | Service | Central Firestore reads/writes for profile, plans, sessions, XP, routines, business partners |
| `lib/core/router.dart` | Provider | Contains `routerProvider`; this is the only substantive Riverpod provider found |
| `lib/providers/` | Provider layer | Empty; no feature providers implemented |
| Controllers | Screen-local only | Most features use `TextEditingController`, timers, and `setState` directly inside screens |

### 1.6 Main feature screen groups

| Folder | Main screens |
|---|---|
| `lib/screens/auth/` | Login, register, forgot password |
| `lib/screens/onboarding/` | Walkthrough, onboarding steps 1-3 |
| `lib/screens/home/` | Home dashboard, manual activity log |
| `lib/screens/plans/` | Plans hub, plan match, explore, detail, schedule, build routine, gym session, post-session summary |
| `lib/screens/coach/` | WiseCoach chat, find professional |
| `lib/screens/progress/` | Progress dashboard, activity detail |
| `lib/screens/profile/` | Profile, edit profile |
| `lib/screens/settings/` | Settings, health profile |
| `lib/screens/club/` | Club/community screen |

---

## 2. Implemented feature inventory

Status meanings used here:

- **Implemented**: visible end-to-end app logic exists in this repository
- **Partially implemented**: some UI/data logic exists, but there are placeholders, hardcoded data, or missing real integrations
- **Not found**: no implementation was found in this repository
- **Unclear**: code hints exist, but behavior cannot be confirmed cleanly from repository contents alone

### 2.1 Authentication and access

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Email/password login | Implemented | `lib/screens/auth/login_screen.dart`, `AuthService.signInWithEmailPassword()` | Guest, Registered End User | Standard Firebase Auth login flow with user-friendly error mapping |
| Google sign-in | Implemented | `lib/screens/auth/login_screen.dart`, `register_screen.dart`, `AuthService.signInWithGoogle()` | Guest, Registered End User | Uses Google Sign-In to authenticate into Firebase |
| Email/password registration | Implemented | `lib/screens/auth/register_screen.dart`, `AuthService.registerWithEmailPassword()` | Guest | Navigates new user into onboarding |
| Password reset | Implemented | `lib/screens/auth/forgot_password_screen.dart`, `AuthService.sendPasswordReset()` | Guest, Registered End User | Sends Firebase password reset email |
| Logout | Implemented | `lib/screens/settings/settings_screen.dart`, `AuthService.signOut()` | Registered End User | Logs out of both Firebase Auth and Google Sign-In |
| Route guarding for unauthenticated users | Implemented | `lib/core/router.dart`, `lib/screens/splash_screen.dart` | Guest | Public routes allowed; private routes redirect to login |
| Suspended user handling | Partially implemented | `lib/screens/auth/login_screen.dart` | Registered End User | UI handles Firebase `user-disabled`, but no admin suspension flow exists here |

### 2.2 Onboarding and profile capture

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Onboarding walkthrough | Implemented | `lib/screens/onboarding/onboarding_walkthrough_screen.dart` | Guest | Introductory walkthrough before auth/onboarding |
| Onboarding step 1 body profile | Implemented | `lib/screens/onboarding/onboarding_step1_screen.dart`, `FirestoreService.saveOnboardingStep1()` | Registered End User | Captures display name, DOB, biological sex, height, weight, preferred units |
| Health connection onboarding cards | Partially implemented | `lib/screens/onboarding/onboarding_step1_screen.dart` | Registered End User | UI marks Apple Health / Google Health Connect / wearable as connected, but code explicitly says real device setup is for a future update |
| Onboarding step 2 goals survey | Implemented | `lib/screens/onboarding/onboarding_step2_screen.dart`, `FirestoreService.saveOnboardingStep2()` | Registered End User | Saves goal, sport preference, experience, equipment, training days, session length |
| Onboarding step 3 permission preferences | Partially implemented | `lib/screens/onboarding/onboarding_step3_screen.dart`, `FirestoreService.saveOnboardingStep3()` | Registered End User | Saves flags such as `notificationsEnabled`, `locationEnabled`, `motionEnabled`, but does not call native permission APIs |
| Mark onboarding complete | Implemented | `FirestoreService.markOnboardingComplete()` | Registered End User | Writes `onboardingComplete: true` into user profile |

### 2.3 Home and dashboard

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Main 5-tab app shell | Implemented | `lib/screens/home/home_screen.dart` | Registered End User | Tabs: Home, Plans, Coach, Club, Progress |
| Personalized home dashboard | Implemented | `lib/screens/home/home_screen.dart`, `FirestoreService.getUserProfile()`, `getUserCalorieGoal()`, `getTodaysCalories()`, `calculateStreak()`, `getSessionDates()` | Registered End User | Shows greeting, streak, calorie ring, tracked plan info, week calendar |
| Live user profile stream on home | Implemented | `lib/screens/home/home_screen.dart` | Registered End User | Uses `FirebaseFirestore.instance.collection('users').doc(uid).snapshots()` directly to react to tracked plan/day changes |
| Today's tracked session preview | Implemented | `lib/screens/home/home_screen.dart`, `FirestoreService.getTrackedPlan()`, `checkAndAdvanceDay()` | Registered End User | Loads current day’s session from tracked plan |

### 2.4 Plans and training management

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Plans hub | Implemented | `lib/screens/plans/plans_screen.dart` | Registered End User | Main entry to plan features |
| Load plans from Firestore | Implemented | `FirestoreService.getPlans()`, `plans_screen.dart`, `explore_screen.dart`, `plan_match_screen.dart` | Registered End User | Plans collection is queried and used across plan flows |
| Fallback plans when Firestore unavailable/empty | Implemented | `lib/screens/plans/plans_screen.dart` | Registered End User | Uses hardcoded fallback list |
| Track a plan | Implemented | `FirestoreService.trackPlan()`, `plan_detail_screen.dart`, `plan_match_screen.dart` | Registered End User | Stores `trackedPlanId`, `trackedPlanName`, `trackingStartDate`, `currentDayIndex` |
| Untrack a plan | Implemented | `lib/screens/plans/plan_detail_screen.dart`, `plan_schedule_screen.dart` | Registered End User | Clears tracked plan fields |
| View plan details | Implemented | `lib/screens/plans/plan_detail_screen.dart` | Registered End User | Displays description, sessions, equipment, goals, track/untrack actions |
| Plan schedule / week view | Implemented | `lib/screens/plans/plan_schedule_screen.dart` | Registered End User | Displays multi-week schedule and current day position |
| Break mode for tracked plan | Implemented | `lib/screens/plans/plan_schedule_screen.dart` | Registered End User | Stores `breakModeActive`, `breakStartDate`, `breakEndDate`, `breakDays` in user profile |
| Session compression mode | Implemented | `lib/screens/plans/plan_schedule_screen.dart`, `gym_session_screen.dart` | Registered End User | Stores `compressedDays`; compressed sessions filter out accessory exercises |
| Explore plans screen | Partially implemented | `lib/screens/plans/explore_screen.dart` | Registered End User | Combines Firestore plans with hardcoded catalog plans; comments say catalog extras are “coming soon” / not yet in Firestore |
| Plan Match recommendation flow | Implemented | `lib/screens/plans/plan_match_screen.dart` | Registered End User | Saves user preferences and picks best plan using local scoring algorithm over Firestore plans |
| Build custom routine | Implemented | `lib/screens/plans/build_routine_screen.dart`, `FirestoreService.saveCustomRoutine()` | Registered End User | Creates user-defined gym routine and stores it in Firestore |
| Edit custom routine | Implemented | `build_routine_screen.dart`, `FirestoreService.updateCustomRoutine()` | Registered End User | Updates existing custom plan in `plans` |
| Save plan to library | Partially implemented | `lib/screens/plans/plan_detail_screen.dart` | Registered End User | Buttons exist, but snackbars say “Save to library coming soon” |
| Cardio plan/tracking entry CTA | Partially implemented | `lib/screens/plans/plans_screen.dart` | Registered End User | “Start Cardio” button exists, but snackbar says “Cardio tracking coming soon” |

### 2.5 Workout execution and logging

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Active gym session tracker | Implemented | `lib/screens/plans/gym_session_screen.dart` | Registered End User | Tracks exercise-by-exercise flow, set completion, timer, rest timer, notes |
| Save completed gym session | Implemented | `FirestoreService.saveGymSession()` | Registered End User | Writes cleaned exercise data into `users/{uid}/sessions` |
| Automatic session stats calculation | Implemented | `FirestoreService.saveGymSession()` | Registered End User | Calculates total sets, volume, calories burned, XP earned |
| XP awarding for gym sessions | Implemented | `FirestoreService.addXpToUser()`, `saveXpEvent()`, `gym_session_screen.dart` | Registered End User | Awards XP and stores XP history after gym session save |
| Mark session complete for tracked plan progression | Implemented | `FirestoreService.markSessionComplete()`, `checkAndAdvanceDay()` | Registered End User | Uses `lastCompletedDate` and `lastCompletedDayIndex` to progress plan days |
| Rest day handling in tracked plan | Implemented | `gym_session_screen.dart` | Registered End User | Detects `isRestDay` in current session and changes flow |
| Post-session summary screen | Implemented | `lib/screens/plans/post_session_summary_screen.dart` | Registered End User | Summarizes completed gym session and generates AI message |
| Manual activity logging | Implemented | `lib/screens/home/manual_activity_log_screen.dart`, `FirestoreService.saveManualActivity()` | Registered End User | User selects activity, intensity, date, duration, optional distance/notes, then saves manual session |
| Manual calorie estimation | Implemented | `manual_activity_log_screen.dart` | Registered End User | Uses MET table and stored user weight to estimate calories |
| Delete manual activity | Partially implemented | `lib/screens/progress/activity_detail_screen.dart` | Registered End User | Delete UI exists, but snackbar says “Delete coming soon” |
| Dedicated live GPS cardio tracking | Not found | Repository-wide search; `plans_screen.dart` only has placeholder CTA | Registered End User | No geolocation, map, pace, route capture, or live outdoor session logic was found |

### 2.6 Progress and analytics

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Progress dashboard | Implemented | `lib/screens/progress/progress_screen.dart` | Registered End User | Has Charts, Activities, XP History subtabs |
| Weekly chart data aggregation | Implemented | `FirestoreService.getWeeklySessionStats()` | Registered End User | Aggregates calories, volume, total sessions, gym sessions, cardio sessions |
| Recent activity history | Implemented | `FirestoreService.getRecentSessions()`, `progress_screen.dart` | Registered End User | Loads latest 20 sessions |
| XP history | Implemented | `FirestoreService.getXpEvents()`, `progress_screen.dart` | Registered End User | Displays user XP event list |
| Streak calculation | Implemented | `FirestoreService.calculateStreak()` | Registered End User | Based on session dates in Firestore |
| Activity detail view | Implemented | `lib/screens/progress/activity_detail_screen.dart` | Registered End User | Shows session detail, stats, exercise list for gym, notes for manual logs |
| Time filter controls in progress | Partially implemented | `progress_screen.dart` | Registered End User | UI for week/month/year exists, but loaded data is weekly-only in current backend method |

### 2.7 WiseCoach and AI

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| WiseCoach chat screen | Implemented | `lib/screens/coach/coach_screen.dart` | Registered End User | Sends user chat history to OpenAI Chat Completions |
| OpenAI-powered coach responses | Implemented | `_sendToOpenAI()` in `coach_screen.dart` | Registered End User | Uses `gpt-4o-mini` with system prompt from app code |
| Quick reply prompts | Implemented | `coach_screen.dart` | Registered End User | Predefined quick prompts in UI |
| Post-workout AI summary | Implemented | `_generateWiseCoachSummary()` in `post_session_summary_screen.dart` | Registered End User | Uses OpenAI to create a short summary after gym session |
| Free message limits / subscription enforcement | Unclear | `lib/core/constants.dart` only | Registered End User | Constants such as `freeMessageLimit` exist, but enforcement logic was not found |

### 2.8 Social, club, and partner features

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Club screen shell | Partially implemented | `lib/screens/club/club_screen.dart` | Registered End User | Screen exists with Leaderboard, Challenges, Friends subtabs |
| Leaderboard | Partially implemented | `club_screen.dart` | Registered End User | Data is hardcoded in `_kLeaderboard` |
| Challenges listing | Partially implemented | `club_screen.dart` | Registered End User | Hardcoded challenge cards and discover cards |
| Friends list | Partially implemented | `club_screen.dart`, `profile_screen.dart` | Registered End User | Hardcoded friend data; actions say “coming soon” |
| Create challenge | Partially implemented | `club_screen.dart` | Registered End User | Action exists, snackbar says “Create challenge coming soon” |
| Join challenge | Partially implemented | `club_screen.dart` | Registered End User | Action exists, snackbar says “Challenge join coming soon” |
| Search in club | Partially implemented | `club_screen.dart` | Registered End User | Search action exists, snackbar says “Search coming soon” |
| Badge system | Partially implemented | `lib/screens/profile/profile_screen.dart` | Registered End User | Badge UI exists but is hardcoded and interactive actions are placeholders |
| Find professionals | Implemented | `lib/screens/coach/find_professional_screen.dart`, `FirestoreService.getBusinessPartners()` | Registered End User, Business Partner | Loads approved and visible business partners from Firestore and allows contact via email |
| Business partner onboarding/edit flow | Not found | Repository-wide search | Business partners are query targets only; no partner-side app flow found |

### 2.9 Profile and settings

| Feature | Status | Relevant files/classes/functions | User role | Notes |
|---|---|---|---|---|
| Profile screen | Implemented | `lib/screens/profile/profile_screen.dart` | Registered End User | Loads display name, hometown, bio, level, total XP |
| Edit profile | Implemented | `lib/screens/profile/edit_profile_screen.dart`, `FirestoreService.updateUserProfile()` | Registered End User | Updates display name, username, hometown, bio |
| Health profile screen | Implemented | `lib/screens/settings/health_profile_screen.dart` | Registered End User | Loads/saves body metrics and calorie-goal-related profile fields |
| Notification preference toggles | Implemented | `lib/screens/settings/settings_screen.dart`, `FirestoreService.updateUserProfile()` | Registered End User | Persists preference flags in Firestore |
| About-you / devices / units / workout time settings | Partially implemented | `settings_screen.dart` | Registered End User | Present in UI, but several options only show “coming soon” snackbars |
| Photo upload/avatar update | Partially implemented | `profile_screen.dart`, `edit_profile_screen.dart`, `health_profile_screen.dart` | Registered End User | UI affordances exist, but snackbars say photo upload is coming soon |
| Calorie goals editing | Implemented | `health_profile_screen.dart` | Registered End User | Reads/writes calorie goal fields in user profile |
| Injury tracking | Partially implemented | `health_profile_screen.dart` | Registered End User | UI mentions “Injury tracking coming soon” |

### 2.10 Roles explicitly visible in this repository

| Role | Status | Evidence |
|---|---|---|
| Guest | Implemented | Login, register, walkthrough, forgot password flows |
| Registered End User | Implemented | Main app features across plans, sessions, progress, settings |
| Business Partner | Partially implemented | `businessPartners` collection is read and displayed to users, but no partner-side interface exists |
| System Admin | Not found | No admin dashboard, admin route, or admin codebase found |

---

## 3. Backend and database inventory

### 3.1 Firebase services used

| Firebase service | Status | Evidence | Notes |
|---|---|---|---|
| Firebase Core | Implemented | `lib/main.dart`, `lib/firebase_options.dart` | App initializes Firebase on startup |
| Firebase Auth | Implemented | `lib/services/auth_service.dart`, auth screens | Email/password and Google sign-in used |
| Cloud Firestore | Implemented | `lib/services/firestore_service.dart`, `home_screen.dart`, progress/plans screens | Main app database |
| Firebase Cloud Messaging | Declared but not implemented in app logic | `pubspec.yaml` only | Dependency present, but no runtime usage found |
| Cloud Functions | Declared but not implemented in app logic | `pubspec.yaml` only | Dependency present, but no `FirebaseFunctions` usage found |
| Firebase Storage | Configured at options level only | `lib/firebase_options.dart` | No storage API usage found |

### 3.2 Firestore collections referenced in code

| Collection/path | Status | Evidence | Notes |
|---|---|---|---|
| `users` | Implemented | `FirestoreService`, `home_screen.dart` | Primary user profile documents |
| `users/{uid}/sessions` | Implemented | `saveGymSession()`, `saveManualActivity()`, recent/today/stats methods | Stores gym and manual activity sessions |
| `users/{uid}/xpEvents` | Implemented | `saveXpEvent()`, `getXpEvents()` | Stores XP event history |
| `users/{uid}/customRoutines` | Implemented | `saveCustomRoutine()` | Stores private custom routine copy |
| `plans` | Implemented | `getPlans()`, `getTrackedPlan()`, `saveCustomRoutine()`, `updateCustomRoutine()` | Used for shared plan catalog and custom routines |
| `businessPartners` | Implemented | `getBusinessPartners()` | Used for “Find a Professional” |
| `exercises` | Referenced constant only | `lib/core/constants.dart` | No actual queries found |
| `challenges` | Referenced constant only | `lib/core/constants.dart` | No actual queries found |

### 3.3 Main user profile fields observed

This is not a formal schema, but these profile fields are visibly used in code:

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
- `calorieGoalActive`
- `dailyCalorieGoal`
- `weeklyCalorieGoal`
- `monthlyCalorieGoal`
- `goalWeight`
- `goalDate`
- `workoutReminders`
- `streakAlerts`
- `wiseCoachMessages`
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
- `totalXp`
- `weeklyXp`
- `level`
- `username`
- `hometown`
- `bio`
- `planMatchGoal`
- `planMatchSport`
- `planMatchLevel`
- `planMatchEquipment`
- `planMatchDays`

### 3.4 Session document shapes observed

#### Gym session fields written

- `type: 'gym'`
- `sessionName`
- `date`
- `createdAt`
- `durationSeconds`
- `exercises`
- `totalSets`
- `totalVolume`
- `caloriesBurned`
- `xpEarned`
- `isManuallyLogged: false`

#### Manual activity fields written

- `type: 'manual'`
- `activityKey`
- `activityName`
- `intensity`
- `durationMinutes`
- `durationSeconds`
- `distance`
- `notes`
- `caloriesBurned`
- `date`
- `createdAt`
- `isManuallyLogged: true`
- `xpEarned: 0`

### 3.5 Cloud Functions found

| Finding | Status | Evidence |
|---|---|---|
| Functions source directory | Not found | No `functions/` folder present |
| Client-side callable functions usage | Not found | No `FirebaseFunctions`, `HttpsCallable`, or `httpsCallable` usage found |
| `cloud_functions` dependency | Declared only | `pubspec.yaml` |

### 3.6 Security rules found

| Finding | Status | Evidence |
|---|---|---|
| Firestore security rules file | Not found | No `firestore.rules` file found |
| Storage rules file | Not found | No `storage.rules` file found |
| `.firebaserc` | Not found | No `.firebaserc` found in repo root scan |

### 3.7 Storage usage found

| Finding | Status | Evidence | Notes |
|---|---|---|---|
| Firebase storage bucket configured | Present in config | `lib/firebase_options.dart` | Bucket exists in generated config |
| Runtime Firebase Storage API usage | Not found | No `firebase_storage` package usage found | Photo upload is not implemented |

---

## 4. Existing tests inventory

### 4.1 Test files found

| Test file | Current coverage |
|---|---|
| `test/widget_test.dart` | Placeholder smoke test only |
| `ios/RunnerTests/RunnerTests.swift` | Default iOS host test target file present, but no app feature coverage relevant to Flutter app behavior was found from repository audit |

### 4.2 What each test currently covers

| Test file | What it actually does |
|---|---|
| `test/widget_test.dart` | Contains `testWidgets('App smoke test', ...)` but does not pump widgets or assert app behavior; effectively only a trivial passing placeholder |

### 4.3 Test commands available

| Command | Status | Notes |
|---|---|---|
| `flutter test` | Available and currently passes | Verified during this audit; output ended with `App smoke test` and `All tests passed!` |

### 4.4 Current automated test depth

Observed automated coverage is very limited:

- No unit tests for `AuthService`
- No unit tests for `FirestoreService`
- No widget tests for auth, onboarding, plans, coach, progress, or settings
- No integration tests directory such as `integration_test/`
- No backend tests for Firestore rules or Cloud Functions

---

## 5. Testing implications

### 5.1 Features that can be tested automatically

These are good candidates for automated widget/unit/integration tests based on current code structure:

| Feature area | Suggested automated testing suitability | Why |
|---|---|---|
| Route gating and splash navigation | High | Deterministic auth/profile-state navigation decisions |
| Auth form validation | High | Local validation and error-state rendering in login/register/forgot password |
| Onboarding survey progression | High | Mostly UI state and Firestore save calls |
| Manual activity calorie estimation | High | Pure calculation logic based on duration, MET values, and weight |
| FirestoreService calculations | High | Session volume, calories, streak, weekly stats, XP level calculations are code-driven |
| Plan Match scoring | High | Local scoring algorithm over plan data |
| Gym session UI progression | Medium | Timer/set flow can be widget-tested with fake async and mocked services |
| Progress screen rendering from mocked data | Medium | Can be widget-tested with fake session and XP data |

### 5.2 Features that need manual device testing

These should be manually tested on actual or simulator devices because UI flow, navigation, and device behavior matter:

| Feature area | Why manual testing is needed |
|---|---|
| Full auth-to-home onboarding journey | Multi-screen UX and Firebase-backed transitions |
| Main 5-tab shell | Navigation behavior and state retention across tabs |
| Gym session tracking UX | Timers, rest popups, set editing, long-screen interactions |
| Plan schedule break/compress actions | Modal interactions and multi-state visual updates |
| Progress charts and activity detail screens | Visual correctness of charting and detail layouts |
| Profile/settings editing | Form behavior, save feedback, and persistence |
| Find Professional contact flow | Requires device email app / URL launching behavior |
| OpenAI-powered coach chat and post-session summary | Real network behavior, loading/error states, response quality |

### 5.3 Features that need Firebase Emulator or mock services

| Feature area | Why emulator/mocks are useful |
|---|---|
| Firebase Auth login/register/reset flows | Avoid hitting production auth during automated tests |
| Firestore profile/onboarding saves | Prevent pollution of live project data |
| Plan tracking, session saves, XP events | Requires controlled seeded Firestore state |
| Progress calculations based on session history | Easier to verify with deterministic seeded documents |
| Business partner listing | Needs seeded `businessPartners` data |

### 5.4 Features depending on external APIs or physical/device permissions

| Feature area | Dependency type | Notes |
|---|---|---|
| WiseCoach chat | External API | Depends on OpenAI Chat Completions and valid `OPENAI_API_KEY` in `.env` |
| Post-session AI summary | External API | Same OpenAI dependency as coach chat |
| Google sign-in | External auth provider | Requires Google Sign-In platform configuration |
| Email password reset | External Firebase service | Depends on Firebase Auth email delivery |
| Contact professional via email | Device capability | Depends on `url_launcher` and email app availability |
| Health data onboarding | Physical/device-related but not truly integrated | UI exists, but native HealthKit/Health Connect APIs are not implemented |
| Notification/location/motion onboarding | Physical/device-related but not truly integrated | App stores preference flags only; actual OS permission requests are not implemented |

### 5.5 Important testing limitations discovered in this repository

- `firebase_messaging` is declared, but no actual FCM logic was found.
- `cloud_functions` is declared, but no Cloud Functions usage or source code was found.
- No real GPS tracking implementation was found.
- No real HealthKit / Google Health Connect implementation was found.
- Club/challenges/friends are largely hardcoded UI and placeholder actions.
- No admin dashboard or admin workflow code was found.
- No business partner self-service flow was found; only end-user discovery of partners exists.
- Platform manifests currently do **not** show the expected production permission declarations for location, notifications, or health access in the scanned files, which aligns with the absence of native permission integration code.

---

## 6. Practical summary for the later System Testing section

Based on the repository as it stands, the strongest system-testing targets are:

1. Authentication and access control
2. Onboarding data capture and onboarding completion routing
3. Plan discovery, plan match, plan tracking, and plan schedule management
4. Gym session execution, session save, XP update, and post-session summary flow
5. Manual activity logging and progress/history reflection
6. Profile/settings persistence
7. WiseCoach external API behavior and failure handling

The weakest or most placeholder-heavy areas are:

1. Club/challenges/friends
2. Health integration
3. GPS cardio tracking
4. Push notifications / FCM
5. Cloud Functions
6. Admin dashboard
7. Business partner back-office flow

These should be treated carefully in later documentation and marked according to what is actually implemented rather than what was originally planned.
