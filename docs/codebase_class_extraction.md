# WiseWorkout Codebase Class Extraction

**Generated:** 2026-06-12  
**Project:** WiseWorkout (FYP-26-S2-15)  
**Scanned directory:** `lib/`  
**Total files scanned:** 34 Dart files

---

## Table of Contents

1. [lib/core/app_theme.dart](#libcoreapp_themedart)
2. [lib/core/constants.dart](#libcoreconstantsdart)
3. [lib/core/router.dart](#libcorerouterdart)
4. [lib/firebase_options.dart](#libfirebase_optionsdart)
5. [lib/main.dart](#libmaindart)
6. [lib/services/auth_service.dart](#libservicesauth_servicedart)
7. [lib/services/firestore_service.dart](#libservicesfirestore_servicedart)
8. [lib/screens/splash_screen.dart](#libscreenssplash_screendart)
9. [lib/screens/auth/login_screen.dart](#libscreensauthlogin_screendart)
10. [lib/screens/auth/register_screen.dart](#libscreensauthregister_screendart)
11. [lib/screens/auth/forgot_password_screen.dart](#libscreensauthforgot_password_screendart)
12. [lib/screens/home/home_screen.dart](#libscreenshomehome_screendart)
13. [lib/screens/home/manual_activity_log_screen.dart](#libscreenshomemanual_activity_log_screendart)
14. [lib/screens/onboarding/onboarding_walkthrough_screen.dart](#libscreensonboardingonboarding_walkthrough_screendart)
15. [lib/screens/onboarding/onboarding_step1_screen.dart](#libscreensonboardingonboarding_step1_screendart)
16. [lib/screens/onboarding/onboarding_step2_screen.dart](#libscreensonboardingonboarding_step2_screendart)
17. [lib/screens/onboarding/onboarding_step3_screen.dart](#libscreensonboardingonboarding_step3_screendart)
18. [lib/screens/plans/plans_screen.dart](#libscreensplansplans_screendart)
19. [lib/screens/plans/plan_detail_screen.dart](#libscreensplansplan_detail_screendart)
20. [lib/screens/plans/plan_match_screen.dart](#libscreensplansplan_match_screendart)
21. [lib/screens/plans/plan_schedule_screen.dart](#libscreensplansplan_schedule_screendart)
22. [lib/screens/plans/gym_session_screen.dart](#libscreensplansgym_session_screendart)
23. [lib/screens/plans/explore_screen.dart](#libscreensplansexplore_screendart)
24. [lib/screens/plans/build_routine_screen.dart](#libscreensplansbuild_routine_screendart)
25. [lib/screens/plans/post_session_summary_screen.dart](#libscreensplanspost_session_summary_screendart)
26. [lib/screens/progress/progress_screen.dart](#libscreensprogressprogress_screendart)
27. [lib/screens/progress/activity_detail_screen.dart](#libscreensprogressactivity_detail_screendart)
28. [lib/screens/club/club_screen.dart](#libscreensclubclub_screendart)
29. [lib/screens/coach/coach_screen.dart](#libscreenscoachcoach_screendart)
30. [lib/screens/coach/find_professional_screen.dart](#libscreenscoachfind_professional_screendart)
31. [lib/screens/profile/profile_screen.dart](#libscreensprofileprofile_screendart)
32. [lib/screens/profile/edit_profile_screen.dart](#libscreensprofileedit_profile_screendart)
33. [lib/screens/settings/settings_screen.dart](#libscreenssettingssettings_screendart)
34. [lib/screens/settings/health_profile_screen.dart](#libscreenssettingshealth_profile_screendart)
35. [Summary: Enums](#summary-enums)
36. [Summary: Firebase Collections](#summary-firebase-collections)
37. [Key Observations](#key-observations)

---

## lib/core/app_theme.dart

### Class: `WW`

| Item | Detail |
|------|--------|
| **Declaration** | `class WW` |
| **Purpose** | Single source of truth for all colors, text styles, BoxDecorations, ThemeData |
| **Constructor** | `WW._()` — private, prevents instantiation |
| **Riverpod** | No |

**Fields (all `static const`):**

| Field | Type | Value / Notes |
|-------|------|---------------|
| `bg` | `Color` | `0xFFF5F5F9` — app background |
| `card` | `Color` | `Colors.white` |
| `elevated` | `Color` | `0xFFF2F2F7` |
| `border` | `Color` | `0xFFE2E4F0` |
| `primary` | `Color` | `0xFF5356C8` — main brand indigo |
| `primaryDark` | `Color` | `0xFF3B3E9E` |
| `teal` | `Color` | `0xFF2BBFA4` |
| `tealBg` | `Color` | `0xFFE6F8F5` |
| `lavender` | `Color` | `0xFF9B8FE0` |
| `lavenderBg` | `Color` | `0xFFF0EEFF` |
| `lavenderDark` | `Color` | `0xFF6B5FC4` |
| `lavenderText` | `Color` | `0xFF5A4F9E` |
| `gold` | `Color` | `0xFFF59E0B` |
| `chipBg` | `Color` | `0xFFEEEEFC` |
| `text` | `Color` | `0xFF1A1A2E` |
| `textSec` | `Color` | `0xFF7B7E9A` |
| `shadow` | `List<BoxShadow>` | Subtle card shadow |
| `cardDecoration` | `BoxDecoration` | White card with rounded corners and shadow |
| `theme` | `ThemeData` | App-wide MaterialApp theme |

**No methods** (all members are static const data).

**Relationships:** Used by every single screen and widget in the codebase.

---

## lib/core/constants.dart

### Class: `Collections`

| Item | Detail |
|------|--------|
| **Declaration** | `class Collections` |
| **Constructor** | `Collections._()` — private |
| **Riverpod** | No |

**Fields (all `static const String`):**

| Field | Value |
|-------|-------|
| `users` | `'users'` |
| `plans` | `'plans'` |
| `exercises` | `'exercises'` |
| `sessions` | `'sessions'` |
| `xpEvents` | `'xpEvents'` |
| `challenges` | `'challenges'` |

---

### Class: `AppConstants`

| Item | Detail |
|------|--------|
| **Declaration** | `class AppConstants` |
| **Constructor** | `AppConstants._()` — private |
| **Riverpod** | No |

**Fields (all `static const`):**

| Field | Type | Value |
|-------|------|-------|
| `appName` | `String` | `'WiseWorkout'` |
| `freeMessageLimit` | `int` | `10` |
| `freeRoutineLimit` | `int` | `3` |
| `freeChallengeLimit` | `int` | `1` |

---

## lib/core/router.dart

### Class: `Routes`

| Item | Detail |
|------|--------|
| **Declaration** | `class Routes` |
| **Constructor** | `Routes._()` — private |
| **Riverpod** | No |

**Fields (all `static const String` — route path constants):**

| Field | Value |
|-------|-------|
| `splash` | `'/splash'` |
| `walkthrough` | `'/walkthrough'` |
| `login` | `'/login'` |
| `forgotPassword` | `'/forgot-password'` |
| `register` | `'/register'` |
| `onboarding` | `'/onboarding'` |
| `onboardingStep1` | `'/onboarding-step1'` |
| `onboardingStep2` | `'/onboarding-step2'` |
| `onboardingStep3` | `'/onboarding-step3'` |
| `home` | `'/home'` |
| `plans` | `'/plans'` |
| `coach` | `'/coach'` |
| `club` | `'/club'` |
| `progress` | `'/progress'` |
| `gymSession` | `'/gym-session'` |
| `postSessionSummary` | `'/post-session-summary'` |
| `profile` | `'/profile'` |
| `settings` | `'/settings'` |
| `healthProfile` | `'/health-profile'` |
| `editProfile` | `'/edit-profile'` |
| `manualActivityLog` | `'/manual-activity-log'` |
| `planDetail` | `'/plan-detail'` |
| `activityDetail` | `'/activity-detail'` |
| `findProfessional` | `'/find-professional'` |
| `planMatch` | `'/plan-match'` |
| `planSchedule` | `'/plan-schedule'` |
| `explore` | `'/explore'` |
| `buildRoutine` | `'/build-routine'` |
| `editRoutine` | `'/edit-routine'` |

---

### Provider: `routerProvider`

| Item | Detail |
|------|--------|
| **Declaration** | `final routerProvider = Provider<GoRouter>((ref) { ... })` |
| **Riverpod** | YES — `Provider<GoRouter>` |
| **Purpose** | Creates and provides the `GoRouter` instance with auth redirect logic |
| **Auth redirect logic** | Allows public routes (splash, walkthrough, login, register, forgot-password) freely; redirects unauthenticated users to `/login` for all other routes |

---

## lib/firebase_options.dart

### Class: `DefaultFirebaseOptions`

| Item | Detail |
|------|--------|
| **Declaration** | `class DefaultFirebaseOptions` |
| **Constructor** | Private (utility class) |
| **Riverpod** | No |
| **Firebase project** | `wiseworkout-fyp2615` |

**Methods:**

| Method | Return Type | Notes |
|--------|-------------|-------|
| `static currentPlatform` | `FirebaseOptions` (getter) | Platform-specific options dispatcher |

**Static Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `android` | `FirebaseOptions` | Android configuration |
| `ios` | `FirebaseOptions` | iOS configuration |
| `web` | `FirebaseOptions` | Web configuration |

---

## lib/main.dart

### Class: `WiseWorkoutApp`

| Item | Detail |
|------|--------|
| **Declaration** | `class WiseWorkoutApp extends ConsumerWidget` |
| **Riverpod** | YES — **the only `ConsumerWidget` in the codebase** |
| **Purpose** | Root application widget; watches `routerProvider` and builds `MaterialApp.router` |

**Methods:**

| Method | Return Type | Notes |
|--------|-------------|-------|
| `build(BuildContext context, WidgetRef ref)` | `Widget` | Watches `routerProvider` |

**Top-level function:**

| Function | Notes |
|----------|-------|
| `main()` | Initializes Firebase, loads `.env` via `flutter_dotenv`, runs `ProviderScope(child: WiseWorkoutApp())` |

---

## lib/services/auth_service.dart

### Class: `AuthService`

| Item | Detail |
|------|--------|
| **Declaration** | `class AuthService` |
| **Constructor** | Default (no-arg) |
| **Riverpod** | No — plain Dart service class |
| **Pattern** | Service class; instantiated inline wherever needed |

**Fields:**

| Field | Type | Modifier |
|-------|------|----------|
| `_auth` | `FirebaseAuth` | `final` (private) — `FirebaseAuth.instance` |
| `_googleSignIn` | `GoogleSignIn` | `final` (private) — `GoogleSignIn()` |

**Methods:**

| Method | Return Type | Notes |
|--------|-------------|-------|
| `signInWithEmailPassword(email, password)` | `Future<UserCredential>` | Email/password sign-in |
| `signInWithGoogle()` | `Future<UserCredential?>` | Google OAuth sign-in |
| `registerWithEmailPassword(email, password)` | `Future<UserCredential>` | Email registration |
| `signOut()` | `Future<void>` | Signs out from both Firebase and Google |
| `getCurrentUser()` | `User?` | Returns `_auth.currentUser` |
| `sendPasswordReset(email)` | `Future<void>` | Sends Firebase password reset email |
| `authStateChanges` | `Stream<User?>` (getter) | Returns `_auth.authStateChanges()` |

---

## lib/services/firestore_service.dart

### Class: `FirestoreService`

| Item | Detail |
|------|--------|
| **Declaration** | `class FirestoreService` |
| **Constructor** | Default (no-arg) |
| **Riverpod** | No — plain Dart service class |
| **Pattern** | Service class; instantiated inline wherever needed |
| **fromJson/toJson** | No — all data handled as `Map<String, dynamic>` |

**Fields:**

| Field | Type | Modifier |
|-------|------|----------|
| `_db` | `FirebaseFirestore` | `final` (private) — `FirebaseFirestore.instance` |

**Methods — User Profile:**

| Method | Return Type | Firestore Operation |
|--------|-------------|---------------------|
| `createUserProfile(uid, data)` | `Future<void>` | `users/{uid}` set merge:true |
| `updateUserProfile(uid, data)` | `Future<void>` | `users/{uid}` update |
| `getUserProfile(uid)` | `Future<Map<String,dynamic>?>` | `users/{uid}` get |

**Methods — Onboarding:**

| Method | Return Type | Firestore Operation |
|--------|-------------|---------------------|
| `saveOnboardingStep1(uid, data)` | `Future<void>` | `users/{uid}` set merge:true |
| `saveOnboardingStep2(uid, data)` | `Future<void>` | `users/{uid}` set merge:true |
| `saveOnboardingStep3(uid, data)` | `Future<void>` | `users/{uid}` set merge:true |
| `markOnboardingComplete(uid)` | `Future<void>` | `users/{uid}` set `{onboardingComplete: true}` merge:true |

**Methods — Sessions:**

| Method | Return Type | Firestore Operation |
|--------|-------------|---------------------|
| `saveGymSession(uid, sessionData)` | `Future<void>` | `users/{uid}/sessions` add |
| `getTodaysSessions(uid)` | `Future<List<Map<String,dynamic>>>` | `users/{uid}/sessions` query (today) |
| `getRecentSessions(uid, {limit})` | `Future<List<Map<String,dynamic>>>` | `users/{uid}/sessions` query ordered by date desc |
| `getTodaysCalories(uid)` | `Future<int>` | Aggregates `caloriesBurned` from today's sessions |

**Methods — XP / Level:**

| Method | Return Type | Firestore Operation |
|--------|-------------|---------------------|
| `getUserCalorieGoal(uid)` | `Future<int>` | Reads `dailyCalorieGoal` from `users/{uid}` |
| `addXpToUser(uid, xpEarned)` | `Future<void>` | Updates `totalXp`, `level` in `users/{uid}` |
| `_calculateLevel(totalXp)` | `static int` | XP threshold lookup |
| `saveXpEvent(uid, eventData)` | `Future<void>` | `users/{uid}/xpEvents` add |
| `getXpEvents(uid, {limit})` | `Future<List<Map<String,dynamic>>>` | `users/{uid}/xpEvents` query ordered by date desc |

**Methods — Streak / Stats:**

| Method | Return Type | Firestore Operation |
|--------|-------------|---------------------|
| `calculateStreak(uid)` | `Future<int>` | Reads session dates to count consecutive days |
| `getSessionDates(uid, days)` | `Future<List<DateTime>>` | `users/{uid}/sessions` last N days |
| `saveManualActivity(uid, ...)` | `Future<void>` | `users/{uid}/sessions` add with `isManuallyLogged: true` |
| `getWeeklySessionStats(uid)` | `Future<Map<String,dynamic>>` | Aggregates calorie/volume stats for current week |

**Methods — Plans:**

| Method | Return Type | Firestore Operation |
|--------|-------------|---------------------|
| `getPlans()` | `Future<List<Map<String,dynamic>>>` | `plans` collection get |
| `trackPlan(uid, planId, planName)` | `Future<void>` | Updates `users/{uid}` with `trackedPlanId`, `trackedPlanName`, `currentDayIndex: 0` |
| `getTrackedPlan(uid)` | `Future<Map<String,dynamic>?>` | Reads tracked plan data from `users/{uid}` |
| `markSessionComplete(uid, totalSessions)` | `Future<void>` | Increments `currentDayIndex` in `users/{uid}` |
| `checkAndAdvanceDay(uid, totalSessions)` | `Future<void>` | Advances day if today's session is marked done |
| `saveCustomRoutine(uid, routineName, sessions, daysPerWeek)` | `Future<void>` | Writes to `users/{uid}/customRoutines` AND `plans` collection |
| `updateCustomRoutine({planId, routineName, sessions, daysPerWeek})` | `Future<void>` | Updates existing plan in `plans` collection |

**Methods — Business Partners:**

| Method | Return Type | Firestore Operation |
|--------|-------------|---------------------|
| `getBusinessPartners()` | `Future<List<Map<String,dynamic>>>` | `businessPartners` collection get (hardcoded collection name string — NOT in `Collections` class) |

---

## lib/screens/splash_screen.dart

### Class: `SplashScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class SplashScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Animated splash screen; checks auth state and routes to walkthrough, onboarding, or home |

---

### Class: `_SplashScreenState`

| Item | Detail |
|------|--------|
| **Declaration** | `class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin` |

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_logoCtrl` | `AnimationController` | Logo fade/scale animation |
| `_spinCtrl` | `AnimationController` | Arc spinner animation |
| `_logoFade` | `Animation<double>` | |
| `_logoScale` | `Animation<double>` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_checkAuthAndNavigate()` | Reads `FirebaseAuth.instance.currentUser`; checks `onboardingComplete` in `users/{uid}`; navigates to `Routes.walkthrough`, `Routes.onboardingStep1`, or `Routes.home` |

---

### Class: `_ArcSpinner`

| Item | Detail |
|------|--------|
| **Declaration** | `class _ArcSpinner extends StatelessWidget` |
| **Purpose** | Loading spinner wrapper using `_ArcSpinnerPainter` |

---

### Class: `_ArcSpinnerPainter`

| Item | Detail |
|------|--------|
| **Declaration** | `class _ArcSpinnerPainter extends CustomPainter` |
| **Purpose** | Draws an animated rotating arc |

---

### Class: `_LogoPainter`

| Item | Detail |
|------|--------|
| **Declaration** | `class _LogoPainter extends CustomPainter` |
| **Purpose** | Draws the WiseWorkout logo using canvas primitives |

---

## lib/screens/auth/login_screen.dart

### Class: `LoginScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class LoginScreen extends StatefulWidget` |
| **Riverpod** | No |

---

### Class: `_LoginScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_emailCtrl` | `TextEditingController` | |
| `_passwordCtrl` | `TextEditingController` | |
| `_authService` | `AuthService` | Instantiated inline |
| `_isLoading` | `bool` | |
| `_errorMessage` | `String?` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_handleEmailSignIn()` | Calls `AuthService.signInWithEmailPassword`; on success navigates to `Routes.home` |
| `_handleGoogleSignIn()` | Calls `AuthService.signInWithGoogle`; creates/updates user profile in Firestore; navigates based on `onboardingComplete` flag |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_InputField` | `StatelessWidget` | Reusable styled text input |
| `_Banner` | `StatelessWidget` | Error message banner |
| `_GoogleLogo` | `StatelessWidget` | Google logo widget using `_GoogleLogoPainter` |
| `_GoogleLogoPainter` | `CustomPainter` | Draws the Google 'G' logo via canvas |

---

## lib/screens/auth/register_screen.dart

### Class: `RegisterScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class RegisterScreen extends StatefulWidget` |
| **Riverpod** | No |

---

### Class: `_RegisterScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_nameCtrl` | `TextEditingController` | |
| `_emailCtrl` | `TextEditingController` | |
| `_passwordCtrl` | `TextEditingController` | |
| `_authService` | `AuthService` | |
| `_firestoreService` | `FirestoreService` | |
| `_isLoading` | `bool` | |
| `_error` | `String?` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_handleRegister()` | Calls `AuthService.registerWithEmailPassword`; calls `FirestoreService.createUserProfile`; navigates to `Routes.onboardingStep1` |
| `_handleGoogleSignIn()` | Calls `AuthService.signInWithGoogle`; creates user profile; navigates based on `onboardingComplete` |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_RegisterField` | `StatelessWidget` | Styled text input field |
| `_ErrorBanner` | `StatelessWidget` | Error message display |
| `_GoogleLogo` | `StatelessWidget` | Google logo |
| `_GoogleLogoPainter` | `CustomPainter` | Draws Google 'G' logo |

---

## lib/screens/auth/forgot_password_screen.dart

### Class: `ForgotPasswordScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class ForgotPasswordScreen extends StatefulWidget` |
| **Riverpod** | No |

---

### Class: `_ForgotPasswordScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_emailCtrl` | `TextEditingController` | |
| `_authService` | `AuthService` | |
| `_isLoading` | `bool` | |
| `_sent` | `bool` | |
| `_error` | `String?` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_handleSend()` | Calls `AuthService.sendPasswordReset(email)` |

---

## lib/screens/home/home_screen.dart

### Class: `HomeScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class HomeScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Root shell with bottom navigation via `IndexedStack` |

---

### Class: `_HomeScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_currentIndex` | `int` | Active tab index (0–4) |

**Tabs (IndexedStack):** `_HomeTab`, `ExploreScreen` (embedded), `PlansScreen` (embedded), `ClubScreen` (embedded), `ProgressScreen` (embedded)

---

### Class: `_TabItem`

| Item | Detail |
|------|--------|
| **Declaration** | `class _TabItem extends StatelessWidget` |
| **Purpose** | Single bottom nav tab item |

---

### Class: `_BottomNav`

| Item | Detail |
|------|--------|
| **Declaration** | `class _BottomNav extends StatelessWidget` |
| **Purpose** | Custom bottom navigation bar |

---

### Class: `_HomeTab`

| Item | Detail |
|------|--------|
| **Declaration** | `class _HomeTab extends StatefulWidget` |
| **Purpose** | The Home tab content (dashboard view) |

---

### Class: `_HomeTabState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_userProfile` | `Map<String,dynamic>?` | Loaded from Firestore |
| `_subscription` | `StreamSubscription<DocumentSnapshot>` | Real-time listener on `users/{uid}` |
| `_todaysCalories` | `int` | |
| `_calorieGoal` | `int` | |
| `_streak` | `int` | |
| `_trackedPlan` | `Map<String,dynamic>?` | |

**Note:** Directly uses `FirebaseFirestore.instance.collection('users')` for the real-time stream (not via `FirestoreService`).

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_WeekCalendar` | `StatelessWidget` | 7-day calendar strip with streak indicators |
| `_DayCell` | `StatelessWidget` | Single day cell in the week calendar |
| `_CalorieRingCard` | `StatelessWidget` | Calorie ring display card |
| `_CalorieRingPainter` | `CustomPainter` | Draws circular calorie progress ring |
| `_TodayPlanCard` | `StatelessWidget` | Today's plan/session card |
| `_StatChip` | `StatelessWidget` | Small stat display chip |

---

## lib/screens/home/manual_activity_log_screen.dart

### Class: `ManualActivityLogScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class ManualActivityLogScreen extends StatefulWidget` |
| **Riverpod** | No |

---

### Class: `_ManualActivityLogScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_selectedCategory` | `String` | Activity category |
| `_selectedActivity` | `_Activity?` | Selected activity from library |
| `_durationCtrl` | `TextEditingController` | Duration in minutes |
| `_notesCtrl` | `TextEditingController` | Notes |
| `_intensity` | `String` | 'light', 'moderate', 'vigorous' |
| `_isSaving` | `bool` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_calculateCalories()` | Uses MET values map to estimate calories burned |
| `_save()` | Calls `FirestoreService.saveManualActivity()`; calls `FirestoreService.addXpToUser()`; navigates back |

---

### Internal data classes (private to file):

| Class | Fields | Notes |
|-------|--------|-------|
| `_Activity` | `name: String, met: double` | Exercise/activity with MET value for calorie estimation |
| `_Category` | `name: String, icon: IconData, color: Color, activities: List<_Activity>` | Activity category |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_SectionLabel` | `StatelessWidget` | Section header label |
| `_FieldLabel` | `StatelessWidget` | Form field label |
| `_Divider` | `StatelessWidget` | Visual divider |
| `_ActivityRow` | `StatelessWidget` | Single activity row in picker |

---

## lib/screens/onboarding/onboarding_walkthrough_screen.dart

### Class: `OnboardingWalkthroughScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class OnboardingWalkthroughScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | 3-card walkthrough with swipe support; no Firestore interaction |

---

### Class: `_OnboardingWalkthroughScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_currentIndex` | `int` | Current card index |

---

### Internal data class (private to file):

| Class | Fields |
|-------|--------|
| `_CardData` | `title: String, body: String, illustrationBg: Color, illustration: Widget` |

---

### Private widgets and painters in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_IllustrationPane` | `StatelessWidget` | Illustration card area |
| `_TextBlock` | `StatelessWidget` | Title + body text |
| `_PrimaryButton` | `StatelessWidget` | Filled primary button |
| `_OutlineButton` | `StatelessWidget` | Outline border button |
| `_CoachIllustration` | `StatelessWidget` | Coach screen illustration |
| `_CalendarIllustration` | `StatelessWidget` | Calendar screen illustration |
| `_PodiumIllustration` | `StatelessWidget` | Podium/leaderboard illustration |
| `_CoachPainter` | `CustomPainter` | Draws coach chat UI illustration |
| `_CalendarPainter` | `CustomPainter` | Draws calendar illustration |
| `_PodiumPainter` | `CustomPainter` | Draws podium/leaderboard illustration |

---

## lib/screens/onboarding/onboarding_step1_screen.dart

### Class: `OnboardingStep1Screen`

| Item | Detail |
|------|--------|
| **Declaration** | `class OnboardingStep1Screen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Step 1: health/wearable connection (sub-step 0) + body profile form (sub-step 1) |

---

### Class: `_OnboardingStep1ScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_authService` | `AuthService` | |
| `_firestoreService` | `FirestoreService` | |
| `_displayNameController` | `TextEditingController` | |
| `_heightController` | `TextEditingController` | |
| `_weightController` | `TextEditingController` | |
| `_subStep` | `int` | 0 = health, 1 = body |
| `_displayName` | `String` | |
| `_dob` | `DateTime?` | |
| `_biologicalSex` | `String` | |
| `_heightCm` | `double?` | |
| `_weightKg` | `double?` | |
| `_heightUnit` | `String` | `'cm'` or `'ft'` |
| `_weightUnit` | `String` | `'kg'` or `'lbs'` |
| `_isLoading` | `bool` | |
| `_connected` | `Map<String,bool>` | Keys: `apple`, `google`, `wearable` |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_handleNext()` | Validates, converts units, calls `FirestoreService.saveOnboardingStep1()`, navigates to `Routes.onboardingStep2` |
| `_handleConnect(key)` | Marks a health source connected |
| `_pickDate()` | Shows native date picker |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_ProgressHeader` | `StatelessWidget` | Step 1 of 3 progress indicator |
| `_FieldLabel` | `StatelessWidget` | Form field label |
| `_HealthCard` | `StatelessWidget` | Health source connection card |
| `_SegmentedChips` | `StatelessWidget` | Segmented chip selector (e.g. biological sex) |
| `_PlainTextField` | `StatelessWidget` | Styled text input |
| `_UnitTextField` | `StatelessWidget` | Text input with inline unit toggle (cm/ft, kg/lbs) |
| `_AppleHealthIcon` | `StatelessWidget` | Apple Health icon |
| `_GoogleHealthIcon` | `StatelessWidget` | Google Health icon |
| `_WearableIcon` | `StatelessWidget` | Wearable device icon |

---

## lib/screens/onboarding/onboarding_step2_screen.dart

### Class: `OnboardingStep2Screen`

| Item | Detail |
|------|--------|
| **Declaration** | `class OnboardingStep2Screen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Goals survey — 6 questions shown one at a time |

---

### Class: `_OnboardingStep2ScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_authService` | `AuthService` | |
| `_firestoreService` | `FirestoreService` | |
| `_questionIndex` | `int` | 0–5 |
| `_primaryGoal` | `String?` | Options: `lose_weight`, `build_muscle`, `improve_endurance`, `general_fitness` |
| `_sportPreference` | `String?` | Options: `gym`, `running`, `both` |
| `_experienceLevel` | `String?` | Options: `beginner`, `intermediate`, `advanced` |
| `_equipment` | `List<String>` | Multi-select: `bodyweight`, `gym_weights`, `outdoor`, `both` |
| `_daysPerWeek` | `int?` | 2–6 |
| `_sessionLength` | `String?` | `'30'`, `'45'`, `'60'`, `'75'` |
| `_isLoading` | `bool` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_save()` | Calls `FirestoreService.saveOnboardingStep2()`, navigates to `Routes.onboardingStep3` |

---

### Internal data classes (private to file):

| Class | Fields |
|-------|--------|
| `_CardOption` | `id, title, desc, iconBg, iconColor, iconData` |
| `_ChipOption` | `id, label` |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_SurveyPage` | `StatelessWidget` | Survey page wrapper with title, subtitle, sticky footer |
| `_SingleSelectCards` | `StatelessWidget` | Single-select card list (goal/sport/experience questions) |
| `_MultiSelectChips` | `StatelessWidget` | Multi-select chip grid (equipment question) |
| `_DaysPicker` | `StatelessWidget` | Days-per-week pill selector (2–6) |

---

## lib/screens/onboarding/onboarding_step3_screen.dart

### Class: `OnboardingStep3Screen`

| Item | Detail |
|------|--------|
| **Declaration** | `class OnboardingStep3Screen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Permission priming — 3 cards (notifications, location, motion) |

---

### Class: `_OnboardingStep3ScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_authService` | `AuthService` | |
| `_firestoreService` | `FirestoreService` | |
| `_cardIndex` | `int` | 0–2 |
| `_tapped` | `bool` | Whether CTA button has been tapped |
| `_permissions` | `Map<String,bool>` | Keys: `notifications`, `location`, `motion` |
| `_isLoading` | `bool` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_handleEnable()` | Calls `FirestoreService.saveOnboardingStep3()` fire-and-forget |
| `_finishOnboarding()` | Calls `FirestoreService.markOnboardingComplete()`, navigates to `Routes.home` |

---

### Internal data class (private to file):

| Class | Fields |
|-------|--------|
| `_CardData` | `id, accentColor, iconBg, iconData, hasBadge, headline, body, benefits, ctaLabel, note` |

---

### Private widget in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_PulsingRipple` | `StatefulWidget` | Animated pulsing ripple ring around permission icon |
| `_PulsingRippleState` | `State with SingleTickerProviderStateMixin` | Animation controller |

---

## lib/screens/plans/plans_screen.dart

### Class: `PlansScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class PlansScreen extends StatefulWidget` |
| **Riverpod** | No |

---

### Class: `_PlansScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_trackedPlan` | `Map<String,dynamic>?` | Loaded from `FirestoreService.getTrackedPlan()` |
| `_customRoutines` | `List<Map<String,dynamic>>` | From Firestore `users/{uid}/customRoutines` |
| `_isLoading` | `bool` | |
| `_uid` | `String?` | Current user UID |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadData()` | Loads tracked plan and custom routines |
| `_untrackPlan()` | Clears tracking fields in `users/{uid}` |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_TrainCard` | `StatelessWidget` | Action card for starting gym session or matching a plan |
| `_PlanCard` | `StatelessWidget` | Tracked plan display card with edit/untrack options |
| `_Tag` | `StatelessWidget` | Small label chip |

---

## lib/screens/plans/plan_detail_screen.dart

### Class: `PlanDetailScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class PlanDetailScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Data source** | Plan data passed via `GoRouter` `extra` as `Map<String,dynamic>` |

---

### Class: `_PlanDetailScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_isTracking` | `bool` | Whether user is tracking this plan |
| `_isLoading` | `bool` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_trackPlan()` | Calls `FirestoreService.trackPlan()` |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_HeroChip` | `StatelessWidget` | Chip in the plan hero header |
| `_SectionCard` | `StatelessWidget` | Plan info section card |
| `_DayCard` | `StatefulWidget` | Collapsible day card showing exercises |
| `_DayCardState` | State | Expanded/collapsed state |
| `_EquipmentChip` | `StatelessWidget` | Equipment tag chip |

---

## lib/screens/plans/plan_match_screen.dart

### Class: `PlanMatchScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class PlanMatchScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Rule-based plan recommendation engine |

---

### Class: `_PlanMatchScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_goal` | `String` | Selected goal |
| `_sport` | `String` | Selected sport |
| `_level` | `String` | Selected experience level |
| `_equipment` | `String` | Selected equipment |
| `_daysPerWeek` | `int` | Selected days |
| `_allPlans` | `List<Map<String,dynamic>>` | Loaded from Firestore |
| `_matchedPlan` | `Map<String,dynamic>?` | Best matching plan |
| `_isLoading` | `bool` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadPlans()` | Calls `FirestoreService.getPlans()` |
| `_runMatchAlgorithm()` | Scores plans by goal/sport/level/daysPerWeek; saves preferences to `users/{uid}` with fields: `planMatchGoal`, `planMatchSport`, `planMatchLevel`, `planMatchEquipment`, `planMatchDays` |

---

### Internal data classes (private to file):

| Class | Fields |
|-------|--------|
| `_GoalOption` | `id: String, label: String, icon: IconData, color: Color` |
| `_LevelOption` | `id: String, label: String, description: String` |

---

### Private widget in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_PreviewDayCard` | `StatefulWidget` | Expandable preview of a plan day |
| `_PreviewDayCardState` | State | Expanded/collapsed toggle |

---

## lib/screens/plans/plan_schedule_screen.dart

### Class: `PlanScheduleScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class PlanScheduleScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Full plan schedule view with compress mode and break mode |

---

### Class: `_PlanScheduleScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_plan` | `Map<String,dynamic>?` | Full plan data from Firestore |
| `_userProfile` | `Map<String,dynamic>?` | From `FirestoreService.getUserProfile()` |
| `_isLoading` | `bool` | |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadData()` | Loads plan and user profile |
| `_startBreak()` | Sets `breakModeActive: true`, `breakStartDate`, `breakEndDate` in `users/{uid}` |
| `_endBreak()` | Clears break mode fields in `users/{uid}` |
| `_compressDay(dayIndex)` | Adds day index to `compressedDays` list in `users/{uid}` |

**User profile fields consumed:**

- `currentDayIndex` — which day the user is on
- `compressedDays` — list of day indices that are compressed (Primary exercises only)
- `breakModeActive` — whether user is on a break
- `breakStartDate`, `breakEndDate`, `breakDays` — break tracking

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_InfoChip` | `StatelessWidget` | Plan info tag |
| `_ScheduleDayCard` | `StatelessWidget` | Individual day row in schedule |
| `_StatusBadge` | `StatelessWidget` | Status label (completed, current, upcoming) |
| `_CompressSheet` | `StatelessWidget` | Bottom sheet for session compression confirmation |

---

## lib/screens/plans/gym_session_screen.dart

### Class: `GymSessionScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class GymSessionScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Live gym session tracker; loads plan session from Firestore; saves results on finish |

---

### Class: `_GymSessionState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_exercises` | `List<Map<String,dynamic>>` | Loaded from Firestore plan session |
| `_elapsedSeconds` | `int` | Session timer |
| `_restTimer` | `int` | Rest countdown |
| `_isLoading` | `bool` | |
| `_sessionName` | `String` | |
| `_planId` | `String?` | |
| `_dayIndex` | `int` | |
| `_totalSessions` | `int` | Total sessions in plan |
| `_isCompressed` | `bool` | Whether this day is in compressed mode |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadSession()` | Reads plan from `plans/{planId}`, respects `compressedDays`; filters to Primary exercises only if compressed |
| `_finishSession()` | Calls `FirestoreService.saveGymSession()`, `addXpToUser()`, `saveXpEvent()`, `markSessionComplete()`; navigates to `Routes.postSessionSummary` |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_TopBarButton` | `StatelessWidget` | Top bar icon button |
| `_RestButton` | `StatelessWidget` | Rest timer trigger button |
| `_SetRow` | `StatefulWidget` | Single set row with done toggle |
| `_SetRowState` | State | Done/undone state |
| `_RestTimerPicker` | `StatefulWidget` | Rest timer bottom sheet |
| `_RestTimerPickerState` | State | Timer countdown logic |

---

### Enum: `_SetType`

| Item | Detail |
|------|--------|
| **Declaration** | `enum _SetType` |
| **Values** | `warmup`, `normal`, `dropSet` |
| **Purpose** | Set type classification in gym session |

---

## lib/screens/plans/explore_screen.dart

### Class: `ExploreScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class ExploreScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Browse and filter plan catalog; merges Firestore plans with hardcoded catalog |

---

### Class: `_ExploreScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_allPlans` | `List<Map<String,dynamic>>` | Merged Firestore + hardcoded plans (deduped by name) |
| `_filteredPlans` | `List<Map<String,dynamic>>` | After applying filter chips |
| `_isLoading` | `bool` | |
| `_selectedLevel` | `String?` | Filter |
| `_selectedGoal` | `String?` | Filter |
| `_selectedSport` | `String?` | Filter |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadPlans()` | Calls `FirestoreService.getPlans()` and merges with hardcoded catalog |
| `_applyFilters()` | Filters `_allPlans` by selected level/goal/sport |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_FeaturedCard` | `StatelessWidget` | Large featured plan card |
| `_FeaturedChip` | `StatelessWidget` | Chip on featured card |
| `_PlanCard` | `StatelessWidget` | Standard plan card in list |
| `_Chip` | `StatelessWidget` | Small plan attribute chip |
| `_FilterSheet` | `StatefulWidget` | Bottom sheet with filter controls |
| `_FilterSheetState` | State | Filter state management |
| `_FilterChipData` | (data class) | `label: String, isSelected: bool` |

---

## lib/screens/plans/build_routine_screen.dart

### Class: `BuildRoutineScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class BuildRoutineScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Build or edit a custom workout routine day by day |
| **Route** | Used for both `Routes.buildRoutine` and `Routes.editRoutine` |

---

### Class: `_BuildRoutineScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_routineName` | `String` | Routine name |
| `_activeDay` | `int` | Currently selected day tab index |
| `_days` | `List<Map<String,dynamic>>` | List of day objects, each with `id`, `label`, `exercises` |
| `_hasChanges` | `bool` | Dirty flag |
| `_isSaving` | `bool` | |
| `_existingPlanId` | `String?` | Non-null when in edit mode |
| `_idCounter` | `int` | Auto-incrementing unique ID generator |
| `_controllers` | `Map<String, TextEditingController>` | Keyed by `'${setId}_kg'` and `'${setId}_reps'` |

**Key methods:**

| Method | Return Type | Notes |
|--------|-------------|-------|
| `_initFromExtra()` | `void` | Reads GoRouter `extra` to populate edit mode |
| `_newDay(label)` | `Map<String,dynamic>` | Factory for a new day map |
| `_newExercise(name, muscle)` | `Map<String,dynamic>` | Factory for a new exercise map |
| `_newSet({type})` | `Map<String,dynamic>` | Factory for a new set map |
| `_saveRoutine()` | `Future<void>` | Calls `FirestoreService.saveCustomRoutine()` or `updateCustomRoutine()` |

**Computed getters:**

| Getter | Notes |
|--------|-------|
| `_isEditMode` | `true` when `_existingPlanId != null` |
| `_canSave` | `true` when at least one day has exercises |
| `_currentExercises` | Exercises for the active day |

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_ExerciseCard` | `StatefulWidget` | Expandable exercise card with set table |
| `_ExerciseCardState` | State | Menu open/close and note visibility |
| `_ExerciseSearchSheet` | `StatefulWidget` | Bottom sheet: searchable exercise library |
| `_ExerciseSearchSheetState` | State | Search query and muscle filter state |

**Module-level constants:**

| Constant | Type | Notes |
|----------|------|-------|
| `_kMuscleFilters` | `const List<String>` | `['All', 'Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Glutes']` |
| `_kExerciseLibrary` | `const List<Map<String,String>>` | 37 exercises with `name` and `muscle` keys |
| `_kSetTypes` | `const List<String>` | `['W', 'N', 'D']` — Warmup, Normal, Drop Set |
| `_kRestValues` | `final List<int>` | Off + 5s increments up to 5 min |

---

## lib/screens/plans/post_session_summary_screen.dart

### Class: `PostSessionSummaryScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class PostSessionSummaryScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Post-workout summary with OpenAI WiseCoach insight, stats, muscles worked, XP, badges |
| **External API** | OpenAI `gpt-4o-mini` via HTTP POST for WiseCoach summary |

---

### Class: `_PostSessionSummaryScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_exercisesExpanded` | `bool` | |
| `_entranceCtrl` | `AnimationController` | Check mark entrance animation |
| `_checkScale` | `Animation<double>` | |
| `_wiseCoachSummary` | `String` | Generated by OpenAI |
| `_summaryLoading` | `bool` | |

**Key methods:**

| Method | Return Type | Notes |
|--------|-------------|-------|
| `_generateWiseCoachSummary()` | `Future<void>` | POST to OpenAI `v1/chat/completions` with session data; uses `OPENAI_API_KEY` from `.env` |
| `_parseExercises(raw)` | `static List<Map<String,dynamic>>` | Parses exercise data from `GoRouter` extra |
| `_getMusclesWorked(exercises)` | `static List<String>` | Returns muscles sorted by frequency |
| `_calcStats(exercises)` | `({int totalSets, double volume})` | Computes totalSets and total volume (kg × reps) |

**Data source:** All data passed via `GoRouter` `extra` as `Map<String,dynamic>` with keys: `sessionName`, `elapsedSeconds`, `date`, `exercises`

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_WiseCoachTypingDots` | `StatefulWidget` | Animated typing dots while AI generates |
| `_WiseCoachTypingDotsState` | `State with SingleTickerProviderStateMixin` | |
| `_StatCard` | `StatelessWidget` | Individual stat card (duration, sets, volume, calories) |
| `_PbRow` | `StatelessWidget` | Personal best row (exercise + new value + previous) |
| `_ConfettiBurst` | `StatefulWidget` | Animated confetti particle burst |
| `_ConfettiBurstState` | `State with SingleTickerProviderStateMixin` | |
| `_LegendDot` | `StatelessWidget` | Color legend dot with label |

---

## lib/screens/progress/progress_screen.dart

### Class: `ProgressScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class ProgressScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Progress dashboard with Charts / Activities / XP History subtabs |

---

### Class: `_ProgressScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_subtab` | `int` | 0=Charts, 1=Activities, 2=XP History |
| `_timeFilter` | `int` | 0=Week, 1=Month, 2=Year |
| `_activityFilter` | `int` | 0=All, 1=Gym, 2=Cardio, 3=Manual |
| `_sessions` | `List<Map<String,dynamic>>` | From `FirestoreService.getRecentSessions()` |
| `_sessionsLoading` | `bool` | |
| `_totalXp` | `int` | From user profile |
| `_level` | `int` | From user profile |
| `_xpEvents` | `List<Map<String,dynamic>>` | From `FirestoreService.getXpEvents()` |
| `_xpEventsLoading` | `bool` | |
| `_caloriesByDay` | `List<double>` | 7-element weekly calorie data |
| `_volumeByDay` | `List<double>` | 7-element weekly volume data |
| `_weekTotalCalories` | `int` | |
| `_weekTotalVolume` | `int` | |
| `_weekTotalSessions` | `int` | |
| `_weekGymSessions` | `int` | |
| `_chartsLoading` | `bool` | |

**XP Level system (static constants):**

| Constant | Value |
|----------|-------|
| `_kXpThresholds` | `[0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000]` |
| Level names | Rookie, Beginner, Apprentice, Contender, Challenger, Warrior, Iron Athlete, Steel Athlete, Elite Athlete, Champion, Legend |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadChartData()` | Calls `FirestoreService.getWeeklySessionStats()` |
| `_loadXpData()` | Calls `FirestoreService.getUserProfile()` |
| `_loadXpEvents()` | Calls `FirestoreService.getXpEvents()` |
| `_loadSessions()` | Calls `FirestoreService.getRecentSessions()` |

**Uses:** `fl_chart` package for `BarChart` (calories and gym volume charts)

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_ActivityCard` | `StatelessWidget` | Activity list row card |
| `_XpRow` | `StatelessWidget` | XP history event row |

---

## lib/screens/progress/activity_detail_screen.dart

### Class: `ActivityDetailScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class ActivityDetailScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Data source** | Session map passed via `GoRouter` `extra` |

---

### Class: `_ActivityDetailScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_exercisesExpanded` | `bool` | Initially `true` |
| `_wiseCoachExpanded` | `bool` | |
| `_deleteDialogOpen` | `bool` | |

**Computed getters:**

| Getter | Notes |
|--------|-------|
| `_session` | `GoRouterState.of(context).extra` as `Map<String,dynamic>` |
| `_isGym` | `session['type'] == 'gym'` |
| `_isManual` | `session['isManuallyLogged'] == true` |
| `_title` | `sessionName` or `activityName` |

**Sections rendered:** Header gradient card, stats row, WiseCoach summary (collapsible), XP card, Exercises (gym only, collapsible), Notes (manual only), Delete button (manual only)

---

## lib/screens/club/club_screen.dart

### Class: `ClubScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class ClubScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Community tab with Leaderboard / Challenges / Friends subtabs |
| **Data** | All data is hardcoded (no Firestore interaction) |

---

### Class: `_ClubScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_subtab` | `int` | 0=Leaderboard, 1=Challenges, 2=Friends |
| `_searchQuery` | `String` | Friends search query |

---

### Internal data classes (private to file — hardcoded display data):

| Class | Fields |
|-------|--------|
| `_LeaderEntry` | `rank, initial, color, name, level, xp, isMe` |
| `_Challenge` | `name, detail, gradStart, gradEnd, pct, pctColor` |
| `_DiscoverCard` | `name, participants, xp, gradStart, gradEnd` |
| `_Friend` | `initial, color, name, username, level, weeklyXp` |
| `_MiniEntry` | `initial, color, name, pct` |

---

## lib/screens/coach/coach_screen.dart

### Class: `CoachScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class CoachScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | AI chat interface with OpenAI-backed WiseCoach |
| **External API** | OpenAI `gpt-4o-mini` via HTTP POST |

---

### Class: `_CoachScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_messages` | `List<Map<String,dynamic>>` | Chat display messages with `role`, `text`, `time` |
| `_chatHistory` | `List<Map<String,String>>` | OpenAI message history with `role`, `content` |
| `_inputController` | `TextEditingController` | |
| `_scrollController` | `ScrollController` | |
| `_isTyping` | `bool` | Typing indicator state |

**Key methods:**

| Method | Return Type | Notes |
|--------|-------------|-------|
| `_sendToOpenAI(messages)` | `Future<String>` | POST to OpenAI `v1/chat/completions` with system prompt; uses `OPENAI_API_KEY` from `.env` |
| `_send([override])` | `Future<void>` | Sends user message, adds to history, gets reply |
| `_addCoachMessage(text)` | `void` | Adds coach message to `_messages` |

**System prompt:** Instructs model as "WiseCoach" — supportive fitness coach, max 3 sentences, no markdown, no medical advice.

---

### Private widgets in file:

| Class | Declaration | Purpose |
|-------|-------------|---------|
| `_MessageBubble` | `StatelessWidget` | Chat bubble for coach and user messages |
| `_TypingIndicator` | `StatefulWidget` | Animated typing dots indicator |
| `_TypingIndicatorState` | `State with SingleTickerProviderStateMixin` | |
| `_SparkleIcon` | `StatelessWidget` | Custom sparkle icon using `_SparklePainter` |
| `_SparklePainter` | `CustomPainter` | Draws 4-point star sparkle |

---

## lib/screens/coach/find_professional_screen.dart

### Class: `FindProfessionalScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class FindProfessionalScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Browse verified fitness professionals from Firestore `businessPartners` collection |

---

### Class: `_FindProfessionalScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_professionals` | `List<Map<String,dynamic>>` | Loaded from `FirestoreService.getBusinessPartners()` |
| `_isLoading` | `bool` | |
| `_filterIndex` | `int` | Index into `_kFilters` |

**Filter types:** `['All', 'Trainer', 'Running Coach', 'Physiotherapist', 'Nutritionist']`

**Key methods:**

| Method | Notes |
|--------|-------|
| `_load()` | Calls `FirestoreService.getBusinessPartners()` |
| `_contact(name, email)` | Launches `mailto:` URL |

**Firestore data fields consumed from `businessPartners` documents:** `name`, `displayName`, `type`, `bio`, `email`, `certifications`

---

## lib/screens/profile/profile_screen.dart

### Class: `ProfileScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class ProfileScreen extends StatefulWidget` |
| **Riverpod** | No |

---

### Class: `_ProfileScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_auth` | `AuthService` | |
| `_firestore` | `FirestoreService` | |
| `_displayName` | `String?` | From Firestore profile |
| `_hometown` | `String?` | From Firestore profile |
| `_bio` | `String?` | From Firestore profile |
| `_isLoading` | `bool` | |
| `_totalXp` | `int` | |
| `_level` | `int` | |

**Same XP threshold/level system as `ProgressScreen`**

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadProfile()` | Calls `FirestoreService.getUserProfile()` |

---

### Internal data classes (private to file — hardcoded display data):

| Class | Fields |
|-------|--------|
| `_Badge` | `icon, bgColor, label, locked` |
| `_Friend` | `initial, color, name, username, level, xp` |

---

## lib/screens/profile/edit_profile_screen.dart

### Class: `EditProfileScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class EditProfileScreen extends StatefulWidget` |
| **Riverpod** | No |

---

### Class: `_EditProfileScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_auth` | `AuthService` | |
| `_firestore` | `FirestoreService` | |
| `_saveState` | `String` | `'idle'` / `'loading'` / `'saved'` |
| `_errorMessage` | `String?` | |
| `_isLoadingProfile` | `bool` | |
| `_origName`, `_origUsername`, `_origHometown`, `_origBio` | `String` | Original values for dirty check |
| `_nameCtrl`, `_usernameCtrl`, `_hometownCtrl`, `_bioCtrl` | `TextEditingController` | |

**Computed getters:**

| Getter | Notes |
|--------|-------|
| `_isDirty` | Compares controllers to original values |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadProfile()` | Calls `FirestoreService.getUserProfile()` |
| `_save()` | Calls `FirestoreService.updateUserProfile()` with `displayName`, `username`, `hometown`, `bio`; pops on success |

---

## lib/screens/settings/settings_screen.dart

### Class: `SettingsScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class SettingsScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | App settings with account, preferences, notifications, community, support, danger zone |

---

### Class: `_SettingsScreenState`

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_auth` | `AuthService` | |
| `_firestore` | `FirestoreService` | |
| `_pushNotif` | `bool` | |
| `_workoutReminders` | `bool` | |
| `_streakAlerts` | `bool` | |
| `_wiseCoachMessages` | `bool` | |
| `_prefsLoading` | `bool` | |
| `_userEmail` | `String?` | From `AuthService.getCurrentUser()?.email` |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadPrefs()` | Calls `FirestoreService.getUserProfile()` |
| `_savePrefs()` | Calls `FirestoreService.updateUserProfile()` with notification prefs |
| `_handleLogOut()` | Shows confirmation dialog; calls `AuthService.signOut()`; navigates to `Routes.login` |

**Notification preference fields saved to Firestore:** `notificationsEnabled`, `workoutReminders`, `streakAlerts`, `wiseCoachMessages`

---

## lib/screens/settings/health_profile_screen.dart

### Class: `HealthProfileScreen`

| Item | Detail |
|------|--------|
| **Declaration** | `class HealthProfileScreen extends StatefulWidget` |
| **Riverpod** | No |
| **Purpose** | Health profile with body metrics, injuries, calorie goals, fitness preferences |

---

### Class: `_HealthProfileScreenState`

**Sections:** A = Body Metrics, B = Injuries & Conditions, C = Calorie Goal Tracking, D = Fitness Preferences

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `_auth` | `AuthService` | |
| `_firestore` | `FirestoreService` | |
| `_isLoading` | `bool` | |
| `_editingBody` | `bool` | Section A edit mode |
| `_isSavingBody` | `bool` | |
| `_showBodySuccess` | `bool` | Success banner visibility |
| `_vName`, `_vDob`, `_vHeight`, `_vWeight`, `_vSex` | `String` | View-mode display values |
| `_nameCtrl`, `_heightCtrl`, `_weightCtrl` | `TextEditingController` | Edit mode controllers |
| `_biologicalSex` | `String` | |
| `_heightUnit`, `_weightUnit` | `String` | `'cm'`/`'ft'`, `'kg'`/`'lb'` |
| `_dobDate` | `DateTime?` | |
| `_calorieGoalActive` | `bool` | |
| `_isSavingCalorie` | `bool` | |
| `_showCalorieSuccess` | `bool` | |
| `_dailyCalCtrl`, `_weeklyCalCtrl`, `_monthlyCalCtrl`, `_goalWeightCtrl` | `TextEditingController` | |
| `_goalDate` | `DateTime?` | |
| `_prefGoal`, `_prefSport`, `_prefExperience`, `_prefDays` | `String` | From onboarding survey |

**Key methods:**

| Method | Notes |
|--------|-------|
| `_loadProfile()` | Calls `FirestoreService.getUserProfile()` |
| `_saveBodyMetrics()` | Calls `FirestoreService.updateUserProfile()` with `displayName`, `dob`, `heightCm`, `weightKg`, `biologicalSex` |
| `_saveCalorieGoals()` | Calls `FirestoreService.updateUserProfile()` with calorie goal fields |
| `_onCalorieToggle(val)` | Updates `calorieGoalActive` in Firestore |
| `_toggleHeightUnit(unit)` | Converts height value between cm and ft in controller |
| `_toggleWeightUnit(unit)` | Converts weight value between kg and lb in controller |
| `_autoCalcFromDaily()` | Auto-calculates weekly (×7) and monthly (×28) from daily calorie |

---

## Summary: Enums

| Enum | Values | File | Notes |
|------|--------|------|-------|
| `_SetType` | `warmup`, `normal`, `dropSet` | `gym_session_screen.dart` | Private to file; used for set classification in live session |

---

## Summary: Firebase Collections

### Defined in `Collections` class (`lib/core/constants.dart`):

| Constant | Firestore Collection |
|----------|---------------------|
| `Collections.users` | `users` |
| `Collections.plans` | `plans` |
| `Collections.exercises` | `exercises` |
| `Collections.sessions` | `sessions` |
| `Collections.xpEvents` | `xpEvents` |
| `Collections.challenges` | `challenges` |

### Hardcoded strings (NOT using `Collections` class):

| Location | Hardcoded String | Notes |
|----------|------------------|-------|
| `FirestoreService.saveCustomRoutine()` | `'customRoutines'` | Subcollection under `users/{uid}` |
| `FirestoreService.getBusinessPartners()` | `'businessPartners'` | Top-level collection |
| `_HomeTabState` | `'users'` | Direct `FirebaseFirestore.instance.collection('users')` for real-time stream |

### Subcollections (accessed via paths):

| Subcollection | Path Pattern |
|---------------|--------------|
| User sessions | `users/{uid}/sessions` |
| User XP events | `users/{uid}/xpEvents` |
| User custom routines | `users/{uid}/customRoutines` |

---

## Key Observations

### Riverpod Providers

| Provider | Type | File | Notes |
|----------|------|------|-------|
| `routerProvider` | `Provider<GoRouter>` | `lib/core/router.dart` | The only Riverpod provider in the codebase |
| `WiseWorkoutApp` | `ConsumerWidget` | `lib/main.dart` | The only ConsumerWidget; watches `routerProvider` |

No `StateNotifier`, `StateProvider`, `FutureProvider`, or `StreamProvider` is used anywhere. All screens are `StatefulWidget`.

---

### Firestore Model Classes

There are **no Dart model classes** with `fromJson` / `toJson` / `fromFirestore` / `toFirestore` methods. All Firestore data is handled entirely as `Map<String, dynamic>` throughout the codebase.

---

### Widget Classes

All screen-level classes follow the `StatefulWidget` pattern exclusively (except `WiseWorkoutApp` which is a `ConsumerWidget`). No screen uses `ConsumerStatefulWidget`.

**Private helper widgets** (prefixed with `_`) are defined inline within the same file as the screen they belong to. They are never shared across files.

**Custom Painters in codebase:**

| Painter | File | Purpose |
|---------|------|---------|
| `_GoogleLogoPainter` | `login_screen.dart`, `register_screen.dart` | Google 'G' logo |
| `_LogoPainter` | `splash_screen.dart` | WiseWorkout logo |
| `_ArcSpinnerPainter` | `splash_screen.dart` | Loading arc spinner |
| `_CalorieRingPainter` | `home_screen.dart` | Calorie progress ring |
| `_CoachPainter` | `onboarding_walkthrough_screen.dart` | Coach chat illustration |
| `_CalendarPainter` | `onboarding_walkthrough_screen.dart` | Calendar illustration |
| `_PodiumPainter` | `onboarding_walkthrough_screen.dart` | Leaderboard/podium illustration |
| `_SparklePainter` | `coach_screen.dart` | Sparkle icon for WiseCoach avatar |

---

### Service / Repository Classes

| Class | File | Pattern | Riverpod |
|-------|------|---------|----------|
| `AuthService` | `lib/services/auth_service.dart` | Plain Dart service; instantiated inline | No |
| `FirestoreService` | `lib/services/firestore_service.dart` | Plain Dart service; instantiated inline | No |

Both services are instantiated with `AuthService()` and `FirestoreService()` directly wherever needed — there is no dependency injection or Riverpod provider wrapping them.

---

### OpenAI Integration

OpenAI's `gpt-4o-mini` model is called from two screens:

| Screen | Purpose | Key |
|--------|---------|-----|
| `CoachScreen` | Live AI chat (WiseCoach) | `OPENAI_API_KEY` from `.env` |
| `PostSessionSummaryScreen` | Post-session workout summary generation | `OPENAI_API_KEY` from `.env` |

Both use `http` package with a direct POST to `https://api.openai.com/v1/chat/completions`.

---

### Navigation Pattern

- Navigation is exclusively via `context.go(Routes.xxx)` or `context.push(Routes.xxx)` using `go_router`.
- `Navigator.push` is never used for screen-to-screen navigation.
- The `GoRouter` instance is provided via `routerProvider`.
- Data is passed between screens via `GoRouter`'s `extra` parameter as `Map<String, dynamic>`.
- Route path strings are never hardcoded — all use `Routes.*` constants.

---

### Architectural Patterns

| Pattern | Details |
|---------|---------|
| **Single source of truth for colors** | `WW` class in `app_theme.dart` |
| **Single source of truth for routes** | `Routes` class in `router.dart` |
| **Single source of truth for Firestore collection names** | `Collections` class in `constants.dart` (with 2 exceptions: `customRoutines` subcollection and `businessPartners` top-level collection) |
| **State management** | `StatefulWidget` + `setState` throughout; Riverpod only for router |
| **Bottom navigation** | `IndexedStack` inside `HomeScreen` for zero-rebuild tab switching |
| **Inline services** | Services instantiated fresh per widget — no singleton or injection |
| **No serialization** | All Firestore data as raw `Map<String, dynamic>` — no model classes |
