# 15.3 Application Architecture Inventory

Repository scope only. This inventory is based strictly on implemented code in this repository and does not assume features beyond what is present.

## 1. Frontend applications

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Flutter mobile app | Implemented | `lib/main.dart`, `lib/core/router.dart`, `android/`, `ios/` | The repository is a Flutter application with Android and iOS platform folders, a Flutter entry point, and app routing/screens under `lib/`. |
| React/admin dashboard or web dashboard | Not found | Repository-wide structure from `rg --files`; no `package.json`, `src/`, `web/`, `next.config.*`, or React app files | No separate React, Next.js, Vite, or admin web codebase is present. |
| Main app entry file | Implemented | `lib/main.dart` | Initializes dotenv, Firebase, Riverpod `ProviderScope`, and `MaterialApp.router`. |
| Main routing file | Implemented | `lib/core/router.dart` | Central `go_router` route table for auth, onboarding, home, plans, profile, coach, progress, and settings flows. |
| Main feature folders | Implemented | `lib/screens/`, `lib/services/`, `lib/core/` | Architecture is primarily screen-driven, with Firebase/auth logic in service classes. |

## 2. Flutter application structure

### 2.1 Screens / pages

| Area | Status | File path evidence | Short explanation |
|---|---|---|---|
| Splash / app entry flow | Implemented | `lib/screens/splash_screen.dart` | Checks auth state and onboarding completion before routing. |
| Authentication screens | Implemented | `lib/screens/auth/login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart` | Email/password login, Google sign-in, registration, and password reset UI are present. |
| Onboarding screens | Implemented | `lib/screens/onboarding/onboarding_walkthrough_screen.dart`, `onboarding_step1_screen.dart`, `onboarding_step2_screen.dart`, `onboarding_step3_screen.dart` | Multi-step onboarding collects body profile, goals, and permission preferences. |
| Main shell / dashboard | Implemented | `lib/screens/home/home_screen.dart` | Contains the main 5-tab application shell. |
| Plans screens | Implemented | `lib/screens/plans/plans_screen.dart`, `explore_screen.dart`, `plan_detail_screen.dart`, `plan_match_screen.dart`, `plan_schedule_screen.dart`, `build_routine_screen.dart`, `gym_session_screen.dart`, `post_session_summary_screen.dart` | Plans, routine building, workout tracking, and session summary screens are implemented. |
| Coach screens | Implemented | `lib/screens/coach/coach_screen.dart`, `find_professional_screen.dart` | Includes AI chat and a professional discovery screen. |
| Club / community screen | Partially Implemented | `lib/screens/club/club_screen.dart` | UI exists, but data is hardcoded in the screen rather than loaded from backend. |
| Progress screens | Implemented | `lib/screens/progress/progress_screen.dart`, `activity_detail_screen.dart` | Shows charts, activities, and XP history. |
| Profile / settings screens | Implemented | `lib/screens/profile/profile_screen.dart`, `edit_profile_screen.dart`, `lib/screens/settings/settings_screen.dart`, `health_profile_screen.dart` | User profile editing and health/profile settings exist. |

### 2.2 Main tabs / navigation structure

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| 5-tab shell | Implemented | `lib/screens/home/home_screen.dart` | Uses `IndexedStack` and custom bottom navigation with tabs: Home, Plans, Coach, Club, Progress. |
| Declarative app routing | Implemented | `lib/core/router.dart` | Uses `go_router` for navigation and route guarding. |
| Auth/onboarding gating | Implemented | `lib/screens/splash_screen.dart`, `lib/core/router.dart` | Splash checks current user and `onboardingComplete`; router blocks private routes when logged out. |

### 2.3 State management

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Riverpod at app root | Implemented | `lib/main.dart`, `lib/core/router.dart` | App is wrapped in `ProviderScope`; router is exposed via a Riverpod `Provider<GoRouter>`. |
| Riverpod feature/state providers | Not found | `lib/providers/` is empty | No actual feature providers, `StateNotifier`, `Notifier`, or stream providers are implemented in the repository. |
| Local widget state via `setState` | Implemented | Many screens under `lib/screens/**` | Most screen state is handled imperatively with `StatefulWidget` + `setState`. |
| Provider package | Not found | Repository-wide search | `provider` package usage is not present. |
| Bloc/Cubit | Not found | Repository-wide search | No Bloc/Cubit implementation is present. |

### 2.4 Models / entities

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Dedicated domain model files | Not found | `lib/models/` is empty | There are no standalone model/entity classes in `lib/models/`. |
| Screen-local helper/data classes | Implemented | `lib/screens/onboarding/onboarding_step2_screen.dart`, `lib/screens/plans/gym_session_screen.dart`, `lib/screens/profile/profile_screen.dart`, `lib/screens/club/club_screen.dart` | Several screens define private UI/data helper classes such as `_CardOption`, `_SetData`, `_ExerciseData`, `_Badge`, `_LeaderEntry`. |
| Firestore document handling via maps | Implemented | `lib/services/firestore_service.dart`, multiple screens in `lib/screens/plans/` and `lib/screens/progress/` | Backend entities are mostly passed around as `Map<String, dynamic>` instead of typed models. |

### 2.5 Services / repositories

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Authentication service | Implemented | `lib/services/auth_service.dart` | Wraps Firebase Auth and Google Sign-In operations. |
| Firestore data service | Implemented | `lib/services/firestore_service.dart` | Centralizes user profile, plans, sessions, XP history, routines, and business partner reads/writes. |
| Repository layer separate from services | Not found | `lib/services/` only | No extra repository abstraction exists beyond the service classes. |

### 2.6 Local storage / cache / offline handling

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| SharedPreferences dependency declared | Planned reference only | `pubspec.yaml` | `shared_preferences` is listed as a dependency. |
| SharedPreferences runtime usage | Not found | Repository-wide search in `lib/` | No `SharedPreferences` import or call is present. |
| Explicit cache/offline sync layer | Not found | Repository-wide structure and search | No offline queue, cache repository, Hive/Sqflite store, or conflict handling is implemented. |

## 3. Implemented feature modules

| Module | Status | File path evidence | Short explanation |
|---|---|---|---|
| Authentication / login / register / logout | Implemented | `lib/screens/auth/login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`, `lib/services/auth_service.dart`, `lib/screens/settings/settings_screen.dart` | Email/password auth, Google sign-in, password reset, and logout are implemented. |
| Onboarding / body profile / goals survey | Implemented | `lib/screens/onboarding/onboarding_step1_screen.dart`, `onboarding_step2_screen.dart`, `onboarding_step3_screen.dart`, `lib/services/firestore_service.dart` | Three onboarding steps save profile, survey, and permission fields into Firestore. |
| Home dashboard | Implemented | `lib/screens/home/home_screen.dart`, `lib/services/firestore_service.dart` | Home shows greeting, calorie goal, streak, calendar, tracked plan state, and today’s session data. |
| Plans / plan catalog / plan match / tracked plan | Implemented | `lib/screens/plans/plans_screen.dart`, `explore_screen.dart`, `plan_match_screen.dart`, `plan_detail_screen.dart`, `plan_schedule_screen.dart`, `lib/services/firestore_service.dart` | Plans can be listed, matched, tracked, scheduled, and untracked. Explore mixes Firestore plans with hardcoded catalog extras. |
| Gym session tracking | Implemented | `lib/screens/plans/gym_session_screen.dart`, `lib/services/firestore_service.dart`, `lib/screens/plans/post_session_summary_screen.dart` | Active gym session flow tracks sets/rest/timer, saves session data, awards XP, and routes to a summary screen. |
| Cardio session tracking | Partially Implemented | `lib/screens/home/manual_activity_log_screen.dart`, `lib/screens/plans/plans_screen.dart`, `lib/services/firestore_service.dart` | Manual activity logging exists, but dedicated live cardio tracking is not implemented; the Plans CTA says “Cardio tracking coming soon”. |
| WiseCoach AI / chat / post-session summary | Implemented | `lib/screens/coach/coach_screen.dart`, `lib/screens/plans/post_session_summary_screen.dart` | Direct OpenAI chat completions are used for the coach chat and generated post-session summaries. |
| Progress charts / activity log / XP history | Implemented | `lib/screens/progress/progress_screen.dart`, `activity_detail_screen.dart`, `lib/services/firestore_service.dart` | Weekly stats, recent sessions, activity details, and XP history are loaded from Firestore and displayed. |
| Club / friends / challenges / leaderboard | Partially Implemented | `lib/screens/club/club_screen.dart`, `lib/screens/profile/profile_screen.dart` | Community UI exists, but leaderboard/challenges/friends data is hardcoded and action buttons often show “coming soon”. |
| Business Partner flow | Partially Implemented | `lib/screens/coach/find_professional_screen.dart`, `lib/services/firestore_service.dart` | Users can browse approved `businessPartners` records and contact via email, but no partner-side onboarding/admin flow is present. |
| Admin dashboard | Not found | Repository-wide structure | No separate admin UI or admin application is present. |
| Notifications | Partially Implemented | `lib/screens/onboarding/onboarding_step3_screen.dart`, `lib/screens/settings/settings_screen.dart`, `lib/services/firestore_service.dart` | The app stores notification preference flags, but no push notification delivery or FCM handling is implemented. |
| Health data integration | Partially Implemented | `lib/screens/onboarding/onboarding_step1_screen.dart`, `lib/screens/settings/settings_screen.dart`, `lib/services/firestore_service.dart` | Health connection UI and stored flags exist, but no HealthKit/Health Connect SDK integration is implemented. |
| GPS / geolocation | Partially Implemented | `lib/screens/onboarding/onboarding_step3_screen.dart`, `lib/services/firestore_service.dart` | Location permission preference is stored, but there is no geolocation SDK usage or route tracking implementation. |

## 4. Firebase / backend integration

### 4.1 Firebase Auth usage

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Firebase initialization | Implemented | `lib/main.dart`, `lib/firebase_options.dart`, `firebase.json` | App initializes Firebase using generated platform options. |
| Email/password auth | Implemented | `lib/services/auth_service.dart` | Uses `FirebaseAuth.signInWithEmailAndPassword` and `createUserWithEmailAndPassword`. |
| Google Sign-In | Implemented | `lib/services/auth_service.dart` | Uses `google_sign_in` plus Firebase credential sign-in. |
| Auth state checks in routing | Implemented | `lib/core/router.dart`, `lib/screens/splash_screen.dart` | Current user is checked to gate navigation. |

### 4.2 Firestore collections used or referenced

| Collection / path | Status | File path evidence | Short explanation |
|---|---|---|---|
| `users` | Implemented | `lib/core/constants.dart`, `lib/services/firestore_service.dart` | Main user profile document store. |
| `plans` | Implemented | `lib/core/constants.dart`, `lib/services/firestore_service.dart` | Plan catalog and custom routine plan documents are read/written here. |
| `users/{uid}/sessions` | Implemented | `lib/services/firestore_service.dart` | Gym sessions and manual activities are stored here. |
| `users/{uid}/xpEvents` | Implemented | `lib/services/firestore_service.dart` | XP history is appended and queried here. |
| `users/{uid}/customRoutines` | Implemented | `lib/services/firestore_service.dart` | Private custom routine copies are stored here. |
| `businessPartners` | Implemented | `lib/services/firestore_service.dart`, `lib/screens/coach/find_professional_screen.dart` | Approved and visible business partner profiles are queried for the coach discovery flow. |
| `exercises` | Planned reference only | `lib/core/constants.dart` | Declared as a constant but not queried in current code. |
| `challenges` | Planned reference only | `lib/core/constants.dart` | Declared as a constant but not queried in current code. |

### 4.3 Cloud Functions

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| `cloud_functions` dependency declared | Planned reference only | `pubspec.yaml` | Package is declared. |
| Callable/HTTP Cloud Functions usage | Not found | Repository-wide search in `lib/` | No `FirebaseFunctions`, `HttpsCallable`, or functions source directory is present. |

### 4.4 Firebase Storage

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Storage bucket configured | Planned reference only | `lib/firebase_options.dart` | Firebase options include a storage bucket. |
| Storage runtime usage | Not found | Repository-wide search in `lib/` | No `firebase_storage` package or storage API usage is present. |

### 4.5 Firebase Cloud Messaging

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| `firebase_messaging` dependency declared | Planned reference only | `pubspec.yaml` | Package is declared. |
| Messaging runtime usage | Not found | Repository-wide search in `lib/` | No `FirebaseMessaging` import, token handling, permission request, or message listener is implemented. |

### 4.6 Firestore security rules

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Firestore security rules file | Not found | Repository-wide structure; `firebase.json` only contains FlutterFire config | No `firestore.rules` or equivalent rules file is present in the repository. |

## 5. External integrations

| Integration | Status | File path evidence | Short explanation |
|---|---|---|---|
| OpenAI / LLM API | Implemented | `lib/screens/coach/coach_screen.dart`, `lib/screens/plans/post_session_summary_screen.dart`, `pubspec.yaml` | Uses direct `http.post` to OpenAI Chat Completions with API key from `.env`. |
| Apple HealthKit / Google Health Connect | Partially Implemented | `lib/screens/onboarding/onboarding_step1_screen.dart`, `lib/screens/settings/settings_screen.dart`, `lib/services/firestore_service.dart` | Connection cards and flags exist, but actual SDK integration is not implemented. |
| Geolocator / GPS / maps | Not found | Repository-wide search in `lib/` | No `geolocator`, maps SDK, or route capture logic is present. |
| Google Sign-In | Implemented | `lib/services/auth_service.dart`, `pubspec.yaml` | Used for Firebase authentication. |
| URL launcher | Implemented | `lib/screens/coach/find_professional_screen.dart`, `pubspec.yaml` | Used to open `mailto:` links for contacting professionals. |
| HTTP client | Implemented | `lib/screens/coach/coach_screen.dart`, `lib/screens/plans/post_session_summary_screen.dart`, `pubspec.yaml` | Used for OpenAI API requests. |
| Charts | Implemented | `lib/screens/progress/progress_screen.dart`, `pubspec.yaml` | `fl_chart` is used for progress visualisation. |
| Intl date formatting | Implemented | `lib/screens/onboarding/onboarding_step1_screen.dart`, `pubspec.yaml` | Used in onboarding UI. |
| Lottie | Planned reference only | `pubspec.yaml` | Declared as a dependency, but no runtime usage was found in `lib/`. |

## 6. Summary of architecture actually implemented

### Architectural style observed

| Finding | Status | File path evidence | Short explanation |
|---|---|---|---|
| Screen-centric Flutter architecture | Implemented | `lib/screens/**`, `lib/services/**` | Most logic lives directly inside `StatefulWidget` screens, with Firebase access delegated to service classes. |
| Thin application/state layer | Partially Implemented | `lib/main.dart`, `lib/core/router.dart`, empty `lib/providers/` | Riverpod is introduced but only lightly used for router wiring; there is no substantial provider-based application layer yet. |
| Data layer centered on FirestoreService | Implemented | `lib/services/firestore_service.dart` | FirestoreService functions as the main repository/service boundary. |
| Typed domain layer | Not found | Empty `lib/models/` | The codebase currently relies on maps and local helper classes instead of central typed entities. |

## 7. Proposed simple application architecture diagram structure

Use the following layer structure for Section 15.3.

### Presentation Layer

- Flutter app UI
- `lib/main.dart`
- `lib/core/router.dart`
- Screen modules under `lib/screens/auth`, `onboarding`, `home`, `plans`, `coach`, `club`, `progress`, `profile`, `settings`

### Application / State Layer

- Riverpod app root and router provider
- Screen-local `StatefulWidget` state via `setState`
- Auth/onboarding navigation decisions in splash/router

### Feature Modules

- Authentication
- Onboarding
- Home dashboard
- Plans and tracked plan flow
- Gym session tracking
- Manual activity logging
- WiseCoach AI chat
- Post-session AI summary
- Progress / XP history
- Club/community UI
- Profile and settings
- Business partner discovery

### Service / Repository Layer

- `AuthService`
- `FirestoreService`

### Backend Integration Layer

- Firebase Core initialization
- Firebase Auth
- Cloud Firestore
- Firestore subcollections:
  - `users`
  - `plans`
  - `users/{uid}/sessions`
  - `users/{uid}/xpEvents`
  - `users/{uid}/customRoutines`
  - `businessPartners`

### External Services

- OpenAI Chat Completions API
- Google Sign-In
- Mail client via `url_launcher`

### Important caveats to reflect in the diagram caption

- No React/admin dashboard was found in this repository.
- No Cloud Functions, Firebase Storage, FCM delivery, HealthKit/Health Connect SDK, or geolocation SDK integration is currently implemented in runtime code.
- Community features exist mainly as UI prototypes/hardcoded views.
- The current architecture is closer to a screen-driven Flutter client with Firebase services than a strongly layered MVVM/Clean Architecture codebase.
