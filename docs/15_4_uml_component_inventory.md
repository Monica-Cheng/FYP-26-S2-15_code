# 15.4 UML Component Inventory

Repository scope only. This inventory is based strictly on current code evidence in this repository. It is intended to support an accurate UML Component Diagram for the report without contradicting the implemented codebase.

## 1. Mobile App Components

### 1.1 App entry and routing

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| WiseWorkout Mobile App Entry | `lib/main.dart` | `firebase_core`, `flutter_dotenv`, `flutter_riverpod`, `routerProvider`, `WW.theme` | Direct Firebase Core init | Loads `.env`, initializes Firebase, wraps app in `ProviderScope`, and bootstraps `MaterialApp.router`. |
| App Routing Component | `lib/core/router.dart` | `go_router`, `flutter_riverpod`, screen modules | Direct `FirebaseAuth.instance.currentUser` check | Central route registry and auth guard. It depends on all routed screens and directly references Firebase Auth for redirect logic. |
| Splash / launch gate | `lib/screens/splash_screen.dart` | `AuthService`, `FirestoreService`, routing constants | Calls `AuthService` and `FirestoreService` | Determines whether to send user to walkthrough, onboarding, or home. |

### 1.2 Authentication UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Authentication UI Component | `lib/screens/auth/login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart` | `AuthService`, `go_router`, theme | Calls `AuthService`; imports `firebase_auth` for exception typing | Supports email/password login, Google sign-in, registration, and password reset. No Firestore dependency is used directly here. |

### 1.3 Onboarding UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Walkthrough UI | `lib/screens/onboarding/onboarding_walkthrough_screen.dart` | routing, theme | No backend or external service calls | Marketing / intro walkthrough only. |
| Body Profile & Device Priming Component | `lib/screens/onboarding/onboarding_step1_screen.dart` | `AuthService`, `FirestoreService`, `intl`, routing | Calls `AuthService`, `FirestoreService` | Stores display name, DOB, sex, height/weight, unit preference, and health/wearable connection flags. |
| Goals Survey Component | `lib/screens/onboarding/onboarding_step2_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Stores fitness goals, sport preference, equipment, training days, and session length. |
| Permission Preference Component | `lib/screens/onboarding/onboarding_step3_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Stores notification/location/motion preference flags and marks onboarding complete. |

### 1.4 Home / dashboard UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Main Home Shell | `lib/screens/home/home_screen.dart` | `PlansScreen`, `CoachScreen`, `ClubScreen`, `ProgressScreen`, `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService`; direct `FirebaseFirestore.instance` snapshot listener | Implements the 5-tab shell with `IndexedStack`, floating action button, and custom bottom navigation. |
| Home Dashboard Tab | `lib/screens/home/home_screen.dart` | `AuthService`, `FirestoreService` | Calls `AuthService`, `FirestoreService`; direct Firestore listener | Loads greeting, streak, calorie goal, session dates, tracked plan state, and current session. |

### 1.5 Plans and workout UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Plans Hub Component | `lib/screens/plans/plans_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Lists plans, tracked plan card, and entry points to Plan Match, Explore, and Build Routine. |
| Explore Plans Component | `lib/screens/plans/explore_screen.dart` | `FirestoreService`, routing | Calls `FirestoreService` | Combines Firestore plans with hardcoded catalog plans. |
| Plan Match Component | `lib/screens/plans/plan_match_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Saves matching preferences to user profile and selects best plan from Firestore plans. |
| Plan Detail Component | `lib/screens/plans/plan_detail_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Displays plan content and tracks/untracks plans. |
| Plan Schedule Component | `lib/screens/plans/plan_schedule_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Handles tracked plan schedule, break mode, compressed days, and stop-tracking flow. |
| Custom Routine Builder Component | `lib/screens/plans/build_routine_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Creates or edits custom routines and persists them to Firestore. |

### 1.6 Gym session tracking UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Gym Session Tracking Component | `lib/screens/plans/gym_session_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `FirestoreService`; direct `FirebaseAuth.instance.currentUser` | Loads tracked workout session, tracks sets/rest/timer, saves completed session, awards XP, and routes to post-session summary. |
| Post-Session Summary Component | `lib/screens/plans/post_session_summary_screen.dart` | routing, `http`, `flutter_dotenv` | Direct HTTP call to OpenAI | Generates AI workout summary from session data passed through route extras. |

### 1.7 Manual activity logging UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Manual Activity Logging Component | `lib/screens/home/manual_activity_log_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Lets users manually log cardio/sport/gym activities and stores them as Firestore sessions. |

### 1.8 Coach / WiseCoach UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| WiseCoach Chat Component | `lib/screens/coach/coach_screen.dart` | `http`, `flutter_dotenv`, routing | Direct HTTP call to OpenAI | Chat UI sends prompts directly to OpenAI Chat Completions. |
| Find Professional Component | `lib/screens/coach/find_professional_screen.dart` | `FirestoreService`, `url_launcher`, routing | Calls `FirestoreService`; calls `launchUrl` / `canLaunchUrl` | Loads approved business partner profiles and opens mail client for contact. |

### 1.9 Progress / analytics UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Progress Analytics Component | `lib/screens/progress/progress_screen.dart` | `AuthService`, `FirestoreService`, `fl_chart`, routing | Calls `AuthService`, `FirestoreService`; uses `BarChart` | Loads weekly stats, sessions, level, and XP history, then renders charts. |
| Activity Detail Component | `lib/screens/progress/activity_detail_screen.dart` | routing, theme | No service call confirmed in current screen entry logic | Primarily renders details from route extra session data. |

### 1.10 Club / community UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Club / Community Component | `lib/screens/club/club_screen.dart` | theme only | No backend service calls | Leaderboard, challenges, and friends are hardcoded screen data in the current codebase. |

### 1.11 Profile / settings UI

| Component name | Related files / folders | Depends on | Direct calls / external use | Notes |
|---|---|---|---|---|
| Profile Component | `lib/screens/profile/profile_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Shows profile summary, level, XP, badges, and friends section. |
| Edit Profile Component | `lib/screens/profile/edit_profile_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Updates display name, username, hometown, and bio. |
| Settings Component | `lib/screens/settings/settings_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Reads and writes preference flags and handles logout. |
| Health Profile Component | `lib/screens/settings/health_profile_screen.dart` | `AuthService`, `FirestoreService`, routing | Calls `AuthService`, `FirestoreService` | Reads and updates body metrics, calorie goals, and stored onboarding preference fields. |

## 2. Service Components

### 2.1 AuthService

| Item | Details |
|---|---|
| File path evidence | `lib/services/auth_service.dart` |
| Main responsibilities | Sign in with email/password, sign in with Google, register with email/password, sign out, get current user, send password reset email, expose auth state stream |
| Public methods | `signInWithEmailPassword`, `signInWithGoogle`, `registerWithEmailPassword`, `signOut`, `getCurrentUser`, `sendPasswordReset`, `authStateChanges` |
| Firebase / external dependencies | `firebase_auth`, `google_sign_in` |
| Feature modules using it | Splash, authentication screens, onboarding screens, home dashboard, plans screens, gym session screen, progress screen, profile screens, settings screens, manual activity log |

### 2.2 FirestoreService

| Item | Details |
|---|---|
| File path evidence | `lib/services/firestore_service.dart` |
| Main responsibilities | User profile CRUD, onboarding persistence, session persistence, plan listing/tracking, XP/streak calculations, custom routine persistence, business partner lookup |
| Public methods | `createUserProfile`, `updateUserProfile`, `getUserProfile`, `saveOnboardingStep1`, `saveOnboardingStep2`, `saveOnboardingStep3`, `markOnboardingComplete`, `saveGymSession`, `getTodaysSessions`, `getRecentSessions`, `getTodaysCalories`, `getUserCalorieGoal`, `addXpToUser`, `calculateStreak`, `getSessionDates`, `saveManualActivity`, `getWeeklySessionStats`, `saveXpEvent`, `getXpEvents`, `getPlans`, `trackPlan`, `getTrackedPlan`, `markSessionComplete`, `checkAndAdvanceDay`, `saveCustomRoutine`, `updateCustomRoutine`, `getBusinessPartners` |
| Firebase / external dependencies | `cloud_firestore` |
| Feature modules using it | Splash, onboarding, home dashboard, plans hub, explore, plan match, plan detail, plan schedule, routine builder, gym session tracking, manual activity logging, progress analytics, profile, settings, health profile, find professional |

### 2.3 HTTP / OpenAI logic

| Item | Details |
|---|---|
| File path evidence | `lib/screens/coach/coach_screen.dart`, `lib/screens/plans/post_session_summary_screen.dart` |
| Main responsibilities | Sends prompts to OpenAI Chat Completions API for WiseCoach chat and post-session summary generation |
| Public service abstraction | Not present as a shared service; logic is embedded directly in screen classes |
| Firebase / external dependencies | `http`, `flutter_dotenv`, OpenAI REST API |
| Feature modules using it | WiseCoach chat, post-session summary |

### 2.4 Constants / config files

| Component | File path evidence | Main responsibility | Used by |
|---|---|---|---|
| App theme | `lib/core/app_theme.dart` | Shared visual theme constants and decorations | Nearly all screens |
| Route registry | `lib/core/router.dart` | Route names, `GoRouter`, redirect logic | App entry and all navigable screens |
| Firestore constants | `lib/core/constants.dart` | Collection names and app-wide numeric constants | `FirestoreService` |
| Firebase platform config | `lib/firebase_options.dart`, `firebase.json` | Firebase app configuration generated by FlutterFire | `lib/main.dart` |
| Environment config | `.env` declared in `pubspec.yaml`, loaded in `lib/main.dart` | Stores API keys such as `OPENAI_API_KEY` | WiseCoach chat, post-session summary |

### 2.5 Helper utilities

| Finding | File path evidence | Notes |
|---|---|---|
| Dedicated helper utility module | Not found | `lib/utils/` is empty in the current repository. |
| Dedicated reusable widget library | Not found | `lib/widgets/` exists as a folder but contains no runtime widget files in the current repository snapshot. |
| Dedicated provider/state module | Not found | `lib/providers/` is empty. |

## 3. Backend / Firebase Components Referenced in Code

| Backend component | Current status | File path evidence | App components depending on it |
|---|---|---|---|
| Firebase Core | Used in runtime code | `lib/main.dart`, `lib/firebase_options.dart`, `firebase.json` | App entry |
| Firebase Auth | Used in runtime code | `lib/services/auth_service.dart`, `lib/core/router.dart`, `lib/screens/plans/gym_session_screen.dart`, auth screens | Auth UI, routing, splash, onboarding, home, plans, session tracking, profile/settings |
| Cloud Firestore | Used in runtime code | `lib/services/firestore_service.dart`, `lib/screens/home/home_screen.dart`, `lib/screens/progress/progress_screen.dart` | Splash, onboarding, home, plans, session tracking, manual log, progress, coach professional discovery, profile/settings |
| Cloud Functions | Dependency only | `pubspec.yaml`; no runtime usage found in `lib/` | No current app component depends on runtime Cloud Functions code |
| Firebase Cloud Messaging | Dependency only | `pubspec.yaml`; no runtime usage found in `lib/` | No current app component depends on runtime FCM code |
| Firebase Storage | Config only | `lib/firebase_options.dart` includes `storageBucket`; no storage runtime code found | No current app component depends on runtime storage code |
| Firestore rules | Not found | No `firestore.rules` or equivalent file present in repository | None |

## 4. External Components Referenced in Code

| External component / package | Current usage or reference | File path evidence | Feature / module using it |
|---|---|---|---|
| Google Sign-In | Runtime usage via `AuthService` | `lib/services/auth_service.dart`, `pubspec.yaml` | Authentication |
| OpenAI / HTTP API | Runtime usage via direct screen-level `http.post` | `lib/screens/coach/coach_screen.dart`, `lib/screens/plans/post_session_summary_screen.dart`, `pubspec.yaml` | WiseCoach chat, post-session summary |
| HealthKit / Google Health Connect / health package | UI/reference only; no SDK integration | `lib/screens/onboarding/onboarding_step1_screen.dart`, `lib/screens/settings/settings_screen.dart` | Onboarding, settings |
| geolocator / GPS / maps | Not found in runtime code | Repository-wide search in `lib/` | None |
| `url_launcher` / mail client | Runtime usage | `lib/screens/coach/find_professional_screen.dart`, `pubspec.yaml` | Find Professional |
| `fl_chart` | Runtime usage | `lib/screens/progress/progress_screen.dart`, `pubspec.yaml` | Progress analytics |
| `lottie` | Dependency only | `pubspec.yaml`; no imports in `lib/` | None |
| `shared_preferences` | Dependency only | `pubspec.yaml`; no imports in `lib/` | None |
| `sensors_plus` / accelerometer | Not found | Repository-wide search in `lib/` and `pubspec.yaml` | None |
| `flutter_dotenv` | Runtime usage | `lib/main.dart`, `lib/screens/coach/coach_screen.dart`, `lib/screens/plans/post_session_summary_screen.dart`, `pubspec.yaml` | App entry, WiseCoach chat, post-session summary |
| `intl` | Runtime usage | `lib/screens/onboarding/onboarding_step1_screen.dart`, `pubspec.yaml` | Onboarding |

## 5. Component Interfaces and Dependencies

### 5.1 Core application relationships

- `WiseWorkoutApp` depends on `routerProvider`, `WW.theme`, `Firebase.initializeApp`, and `.env` loading.
- `routerProvider` depends on `GoRouter`, route constants, and all routed screen components.
- `routerProvider` currently depends directly on `FirebaseAuth.instance.currentUser` for auth redirection.
- `SplashScreen` depends on `AuthService` and `FirestoreService`.

### 5.2 Authentication relationships

- `LoginScreen` depends on `AuthService`.
- `RegisterScreen` depends on `AuthService`.
- `ForgotPasswordScreen` depends on `AuthService`.
- `AuthService` depends on `FirebaseAuth` and `GoogleSignIn`.

### 5.3 Onboarding relationships

- `OnboardingStep1Screen` depends on `AuthService` and `FirestoreService`.
- `OnboardingStep2Screen` depends on `AuthService` and `FirestoreService`.
- `OnboardingStep3Screen` depends on `AuthService` and `FirestoreService`.
- `OnboardingStep3Screen` depends on `FirestoreService.markOnboardingComplete`.

### 5.4 Home and dashboard relationships

- `HomeScreen` depends on `PlansScreen`, `CoachScreen`, `ClubScreen`, and `ProgressScreen`.
- The home dashboard logic inside `HomeScreen` depends on `AuthService` and `FirestoreService`.
- `HomeScreen` also depends directly on `FirebaseFirestore.instance.snapshots()` for live user document updates.
- `ManualActivityLogScreen` depends on `AuthService` and `FirestoreService`.

### 5.5 Plans and tracking relationships

- `PlansScreen` depends on `AuthService` and `FirestoreService`.
- `ExploreScreen` depends on `FirestoreService`.
- `PlanMatchScreen` depends on `AuthService` and `FirestoreService`.
- `PlanDetailScreen` depends on `AuthService` and `FirestoreService`.
- `PlanScheduleScreen` depends on `AuthService` and `FirestoreService`.
- `BuildRoutineScreen` depends on `AuthService` and `FirestoreService`.
- `GymSessionScreen` depends on `FirestoreService` and routing.
- `GymSessionScreen` also depends directly on `FirebaseAuth.instance.currentUser`.
- `GymSessionScreen` depends on `PostSessionSummaryScreen` through routing.

### 5.6 Coach and external service relationships

- `CoachScreen` depends on `http` and `flutter_dotenv`.
- `CoachScreen` currently calls OpenAI directly through HTTP.
- `FindProfessionalScreen` depends on `FirestoreService`.
- `FindProfessionalScreen` depends on `url_launcher` to open the device mail client.

### 5.7 Progress relationships

- `ProgressScreen` depends on `AuthService` and `FirestoreService`.
- `ProgressScreen` depends on `fl_chart` for chart rendering.
- `ActivityDetailScreen` depends on route-passed session data rather than a dedicated service call in the current screen entry path.

### 5.8 Profile and settings relationships

- `ProfileScreen` depends on `AuthService` and `FirestoreService`.
- `EditProfileScreen` depends on `AuthService` and `FirestoreService`.
- `SettingsScreen` depends on `AuthService` and `FirestoreService`.
- `HealthProfileScreen` depends on `AuthService` and `FirestoreService`.

### 5.9 Service-layer relationships

- `FirestoreService` depends on `Cloud Firestore`.
- `AuthService` depends on `Firebase Auth`.
- `AuthService` also depends on `Google Sign-In`.
- `FirestoreService` depends on `Collections` constants from `lib/core/constants.dart`.

## 6. Target UML Component Diagram Recommendation

This section recommends a clean UML component structure for the report diagram. It is intentionally grouped at component level rather than screen level.

### 6.1 Recommended UML component structure

#### Application container

- `WiseWorkout Mobile App`

#### Internal application components

- `App Routing Component`
- `Authentication Component`
- `Onboarding Component`
- `Home Dashboard Component`
- `Workout Plan Component`
- `Session Tracking Component`
- `WiseCoach Component`
- `Progress Analytics Component`
- `Social/Challenge Component`
- `Profile & Settings Component`

#### Internal service components

- `AuthService`
- `FirestoreService`
- `WiseCoach Gateway`
- `Notification Service`
- `Health Data Adapter`
- `Location Tracking Adapter`

#### External / backend components

- `Firebase Auth`
- `Cloud Firestore`
- `Cloud Functions`
- `Firebase Cloud Messaging`
- `Firebase Storage`
- `OpenAI LLM API`
- `Apple HealthKit / Google Health Connect`
- `Device GPS`
- `Mail Client`

#### Optional enterprise / ecosystem component

- `Admin Dashboard Component`

### 6.2 Suggested dependency flow for the diagram

- `WiseWorkout Mobile App` contains the UI components and `App Routing Component`.
- `Authentication Component` uses `AuthService`.
- `Onboarding Component` uses `AuthService`, `FirestoreService`, `Health Data Adapter`, and `Location Tracking Adapter`.
- `Home Dashboard Component` uses `AuthService` and `FirestoreService`.
- `Workout Plan Component` uses `AuthService` and `FirestoreService`.
- `Session Tracking Component` uses `AuthService`, `FirestoreService`, and `WiseCoach Gateway`.
- `WiseCoach Component` uses `WiseCoach Gateway`.
- `Progress Analytics Component` uses `FirestoreService`.
- `Social/Challenge Component` uses `FirestoreService`.
- `Profile & Settings Component` uses `AuthService`, `FirestoreService`, `Notification Service`, `Health Data Adapter`, and `Location Tracking Adapter`.
- `AuthService` connects to `Firebase Auth` and `Google Sign-In`.
- `FirestoreService` connects to `Cloud Firestore`.
- `WiseCoach Gateway` connects to `OpenAI LLM API`.
- `Notification Service` connects to `Firebase Cloud Messaging`.
- `Health Data Adapter` connects to `Apple HealthKit / Google Health Connect`.
- `Location Tracking Adapter` connects to `Device GPS`.
- `Find Professional` behaviour can be represented either inside `WiseCoach Component` or as a dependency from `WiseCoach Component` to `Mail Client`.
- `Admin Dashboard Component` can be shown as another client of `Cloud Firestore`, `Cloud Functions`, `Firebase Storage`, and `Firebase Auth` in the target architecture diagram.

### 6.3 Why this grouping fits the codebase

- The repository is screen-heavy, so grouping by feature domain is cleaner than showing every screen.
- `AuthService` and `FirestoreService` are the two clear service-layer components already implemented.
- OpenAI access is currently screen-level, but a UML component named `WiseCoach Gateway` is cleaner for the report and still consistent with the observed responsibility.
- Health, location, notifications, storage, Cloud Functions, and admin are better shown as architectural components than as current source-level modules.

## 7. Report-friendly guidance

### 7.1 Recommended components to include

- `WiseWorkout Mobile App`
- `App Routing Component`
- `Authentication Component`
- `Onboarding Component`
- `Home Dashboard Component`
- `Workout Plan Component`
- `Session Tracking Component`
- `WiseCoach Component`
- `Progress Analytics Component`
- `Social/Challenge Component`
- `Profile & Settings Component`
- `AuthService`
- `FirestoreService`
- `WiseCoach Gateway`
- `Notification Service`
- `Health Data Adapter`
- `Location Tracking Adapter`
- `Firebase Auth`
- `Cloud Firestore`
- `Cloud Functions`
- `Firebase Cloud Messaging`
- `Firebase Storage`
- `OpenAI LLM API`
- `Apple HealthKit / Google Health Connect`
- `Device GPS`
- `Mail Client`
- `Admin Dashboard Component`

### 7.2 Components to exclude from the diagram to avoid clutter

- Individual screens such as `LoginScreen`, `PlanDetailScreen`, `GymSessionScreen`, `ProgressScreen`
- Local helper classes such as `_SetData`, `_ExerciseData`, `_Badge`, `_LeaderEntry`
- Theme-only files such as `app_theme.dart`
- Constant-only files such as `constants.dart`
- Platform folders such as `android/` and `ios/`
- Testing files such as `test/widget_test.dart`
- Empty directories such as `lib/providers/`, `lib/models/`, `lib/utils/`, `lib/widgets/`

### 7.3 Short note for keeping the UML Component Diagram clean in draw.io

- Use one large container for `WiseWorkout Mobile App`.
- Group screens into feature components rather than drawing each screen.
- Show service components in a middle layer and backend/external systems in a bottom or right-side layer.
- Keep dependency arrows one-directional where possible: UI -> services -> backend/external systems.
- Use optional or lighter styling for target architecture components that are useful for the report but not strongly represented as current source modules.
