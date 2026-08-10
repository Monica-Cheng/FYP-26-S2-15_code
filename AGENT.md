# AGENT.md — WiseWorkout AI Coding Rules

# Read this entire file before writing any code.

# This file is the single source of truth for all AI agents (Claude Code, Codex, Gemini).

---

## Project Identity

- App name: WiseWorkout
- Platform: Flutter (iOS + Android)
- Language: Dart
- Bundle ID: com.wiseworkout.wise_workout
- Firebase Project: wiseworkout-fyp2615
- GitHub: https://github.com/Monica-Cheng/FYP-26-S2-15_code

## Scope of This Document

This document governs the Flutter app in `lib/` only. `admin/wiseworkout-admin/`
is a separate React + Firebase web app in the same repo, with its own
package.json, dependencies, and conventions — none of the rules below
(naming, folder structure, Firestore access pattern, etc.) apply to it.

## Tech Stack

- Flutter 3.44.0 + Dart 3.12.0
- State management: mixed in practice, not primarily Riverpod. Plain
  `StatefulWidget` + `setState()` is the dominant, default pattern across
  almost every screen (home, coach, gym session, progress, etc.) — 580+
  `setState()` call sites across 45 `StatefulWidget`s. `flutter_riverpod`
  is used for exactly two things: `lib/core/router.dart`'s
  `routerProvider` (the `GoRouter` instance) and
  `lib/providers/month_activity_provider.dart` (the month-activity/streak
  calendar feature) — there's only one `ConsumerWidget` in the whole app
  (`main.dart`'s `WiseWorkoutApp`). See "State Management Rules" below
  for what this means for new code.
- Navigation: go_router (holds with no exceptions — no direct
  screen-to-screen `Navigator.push` found anywhere in the app; see
  "Navigation Rules" below for the one accepted `Navigator.pop` pattern)
- Backend: Firebase (Auth, Firestore, Cloud Functions)
- Charts: fl_chart
- Animations: lottie

---

## Folder Structure — What Goes Where

lib/
├── core/
│ ├── app_theme.dart ← WW design tokens (colors, text styles, decorations)
│ ├── constants.dart ← the `Collections` class + a few app-wide constants
│ │ (not every Firestore collection name lives here — see "Firebase Rules")
│ └── router.dart ← routes, navigation, and the app's routerProvider
├── models/ ← currently EMPTY. Typed data/result classes exist, but live
│ inside the relevant service file instead (e.g. a service's own result
│ class is defined in that service file, not here) — treat this folder
│ as reserved/aspirational, not actually in use.
├── services/ ← Firebase calls only (auth_service, firestore_service)
├── providers/ ← Riverpod providers — currently one file
│ (month_activity_provider.dart); routerProvider itself lives in
│ core/router.dart, not here
├── utils/ ← small stateless helpers (image_encode.dart,
│ widget_capture.dart) — real, in active use, previously undocumented
├── widgets/
│ ├── common/ ← reusable widgets used across 2+ screens
│ └── (several feature-specific widgets also live directly under
│ widgets/, not under common/ — normal when a widget is specific to
│ one feature but was split out of its screen file for size/readability)
└── screens/ ← one subfolder per feature area, currently: auth/,
business/, cardio/, club/, coach/, home/, nutrition/, onboarding/,
plans/, profile/, progress/, settings/, plus splash_screen.dart at the
top level. This list grows as features are added — don't treat any
fixed list (including this one) as exhaustive.

---

## Naming Conventions

- Files: snake_case → `login_screen.dart`, `auth_service.dart`
- Classes: PascalCase → `LoginScreen`, `AuthService`
- Variables and functions: camelCase → `userId`, `getUserData()`
- Providers: camelCase ending in Provider → `authProvider`, `userProvider`
- Constants: camelCase → `Collections.users`, `AppConstants.appName`
- Private variables: underscore prefix → `_isLoading`, `_controller`

---

## The 10 Rules — Never Break These

1. **Prefer `WW.primary`, `WW.card` etc from `lib/core/app_theme.dart` over hardcoded colors** for standard app UI/chrome. Not absolute in practice — hardcoded `Color(0x...)` values exist in 40+ files. Some are a deliberate, separate visual system (e.g. `share_card_gradients.dart`'s custom gradient presets, intentionally distinct from the core app palette); others are plain unrouted duplication (e.g. the identical divider color hardcoded in both `club_screen.dart` and `friends_screen.dart` instead of becoming a token). Default to WW tokens for new UI; a genuine one-off custom color is fine, but don't duplicate the same hardcoded value across files — that should become a token instead.
2. **Firestore collection name strings must be centralized inside `lib/services/firestore_service.dart` — never hardcoded at a screen/widget call site.** This holds with zero exceptions found. Within firestore_service.dart itself, the real pattern is mixed: 17 shared/cross-feature collection names live in `Collections.x` (`lib/core/constants.dart`), while many feature-specific ones (`missedSessions`, `weightLogs`, `planProgress`, `reactions`, `comments`, `customRoutines`, etc.) are private `static const` fields defined directly in `FirestoreService`, or occasional inline literals. Both are fine as long as the string lives inside firestore_service.dart — the rule is "always `Collections.x`" only in the loose sense of "centralized," not literally.
3. **Never call Firestore or Firebase Auth directly from a widget — `lib/services/` is always the default, expected path.** Importing `cloud_firestore`/`firebase_auth` in a screen/widget purely for types (`Timestamp`, `QuerySnapshot`, `FirebaseAuthException`, etc.) used alongside data already fetched via the service layer is fine and common. An actual direct call (`.collection(...)`, `FirebaseAuth.instance.currentUser`, etc.) is not — any exception must be deliberate and documented at the call site, like `coach_screen.dart`'s message-history read/write (tightly coupled to session-specific `wasPersonalized`/`wiseCoachChatClearedAt` logic, intentionally built this way, not a bug to fix). One additional, currently *undocumented* direct-Auth call exists at `gym_session_screen.dart:1570` and `:1822` (`FirebaseAuth.instance.currentUser?.uid`, vs. `AuthService().getCurrentUser()?.uid` used correctly at 7 other sites in that same file) — this reads as an unintentional shortcut, not a sanctioned exception; flag for cleanup rather than treat as precedent.
4. **Never use `Navigator.push` for screen-to-screen navigation — always `context.go()`/`context.push()`.** Holds with zero exceptions (no `Navigator.push` anywhere in the app). `Navigator.pop(dialogContext, result)` to dismiss a locally-shown dialog/bottom sheet and return a value is a separate, accepted pattern used throughout the app (~20+ sites) — that's not screen navigation, so it doesn't violate this rule.
5. **`setState` is the default for UI state, including most screen-level state — not just narrow local toggles.** This is the actual dominant pattern (580+ `setState()` calls across 45 `StatefulWidget`s, vs. 1 `ConsumerWidget` and 4 `ref.watch`/`ref.read` calls total). Riverpod is used only where a couple of specific features need it (routing, the month-activity/streak calendar) — reach for a new provider when there's a specific reason it fits better, not as the default for new shared state.
6. **Never create a new file without checking if it already exists first**
7. **Never modify `app_theme.dart` colors unless explicitly told to**
8. **Never modify `main.dart` unless explicitly told to**
9. **Always add new routes to `router.dart` when creating a new screen** — except the 5 main tab screens (Home/Plans/Coach/Club/Progress), which are mounted directly in the app shell's `IndexedStack` (`home_screen.dart`) instead of getting their own `GoRoute`.
10. **Always use relative imports within lib/ — never absolute imports** (confirmed: zero absolute `package:wise_workout/...` imports anywhere in lib/)

---

## Firebase Rules

- Auth calls → `lib/services/auth_service.dart` is the expected, default
  path. One undocumented direct call currently exists
  (`gym_session_screen.dart`, see Rule 3 above) — not sanctioned, flagged
  for cleanup, not a pattern to repeat.
- Firestore reads/writes → `lib/services/firestore_service.dart` is the
  expected, default path. One deliberate, documented exception exists
  (`coach_screen.dart`'s WiseCoach message history). Any new direct
  Firestore call in a widget needs the same kind of explicit, documented
  justification — not a silent shortcut.
- Importing `firebase_auth`/`cloud_firestore` in a screen or widget
  purely for types (`Timestamp`, `QuerySnapshot`, `FirebaseAuthException`,
  etc.) is fine and common — it's making an actual direct call that's
  restricted, not the import itself.
- Firestore collection name strings must be centralized inside
  `firestore_service.dart` — either a `Collections.x` constant
  (`lib/core/constants.dart`, for names shared/relevant across features)
  or a private `static const` field local to `FirestoreService` (for
  feature-specific ones). Never hardcode a collection name string at a
  screen/widget call site.

---

## Navigation Rules

- Every screen must have a route defined in `lib/core/router.dart` —
  except the 5 main tab screens (Home/Plans/Coach/Club/Progress), which
  are mounted directly in the app shell's `IndexedStack` instead.
- Use `context.go(Routes.home)` to navigate and replace current screen
- Use `context.push(Routes.profile)` to navigate and keep back button
- Never hardcode route strings — always use `Routes.x` constants
- `Navigator.pop(dialogContext, result)` to dismiss a locally-shown
  dialog/bottom sheet and return a value is a separate, accepted
  pattern — it's not screen navigation, so it's not covered by (or in
  violation of) the rules above.

---

## State Management Rules

- In practice, `StatefulWidget` + `setState()` is the dominant pattern
  across the app — used for most screen-level state, not just narrowly
  local UI toggles. An earlier version of this document described
  Riverpod as the rule for all shared data; that was aspirational, not
  actual, and has been corrected here.
- Riverpod is used for a small number of specific things today: the
  app's routing (`routerProvider` in `lib/core/router.dart`) and the
  month-activity/streak calendar feature
  (`lib/providers/month_activity_provider.dart`). Widgets that consume
  it use `ConsumerWidget`/`ConsumerStatefulWidget` and
  `ref.watch()`/`ref.read()`, same mechanics as before.
- When adding new state, matching the surrounding screen's existing
  pattern (almost always `setState`) is the practical default. Reach for
  a new Riverpod provider when there's a specific reason it fits better
  (e.g. state genuinely needs to be shared live across multiple
  independent screens), not automatically.

---

## Design System — WW Colors (DO NOT CHANGE)

- Background: `WW.bg` = #F7F8FF
- Cards: `WW.card` = #FFFFFF
- Primary purple: `WW.primary` = #6C7EE8
- Dark purple: `WW.primaryDark` = #2D3A8C
- Lavender: `WW.lavender` = #9B84E8
- Teal: `WW.teal` = #4BB8CC
- Text primary: `WW.text` = #3D3D5C
- Text secondary: `WW.textSec` = #8A8A9E
- Border: `WW.border` = #C8C8D8
- Gold: `WW.gold` = #F59E0B

---

## How to Add a New Screen (Do This Every Time)

1. Create the file in the correct `lib/screens/subfolder/` directory
2. Name it `feature_screen.dart`
3. Add the route path constant to `Routes` class in `lib/core/router.dart`
4. Add the `GoRoute` entry in `routerProvider` in `lib/core/router.dart`
5. Import the screen at the top of `router.dart`
6. Never skip steps 3-5 or navigation will break

---

## How to Add a New Firebase Service Call (Do This Every Time)

1. Add the method to `lib/services/firestore_service.dart` or `auth_service.dart`
2. Call it from the widget — in practice this almost always means calling
   it directly from a `StatefulWidget`'s async method and updating state
   via `setState()` (the actual dominant pattern; see "State Management
   Rules" above), not routing it through a new Riverpod provider. Only
   reach for a provider if there's a specific reason one fits better.
3. Never call Firebase (Firestore/Auth) directly from a widget — always
   through the service method from step 1

---

## What This Project Is

WiseWorkout is a Flutter fitness app with 5 tabs: Home, Plans, Coach, Club, Progress.
It has Auth, Onboarding, Gym Session tracking, AI coaching (WiseCoach), GPS cardio,
gamification (XP, badges, streaks), social features (friends, challenges),
Business Partner profiles, and a React admin dashboard (a separate app —
see "Scope of This Document" above).

All 5 tabs, the Business Portal/coach system, and the admin dashboard are
live and under active, ongoing development — this is well past a
single-area prototype at this point. There's no single fixed "current
sprint focus" to name here anymore; check with the team/project owner
for what's actively in flight before starting new work.
