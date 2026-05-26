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

## Tech Stack

- Flutter 3.44.0 + Dart 3.12.0
- State management: flutter_riverpod
- Navigation: go_router
- Backend: Firebase (Auth, Firestore, Cloud Functions)
- Charts: fl_chart
- Animations: lottie

---

## Folder Structure — What Goes Where

lib/
├── core/
│ ├── app_theme.dart ← ALL colors, text styles, decorations
│ ├── constants.dart ← ALL Firestore collection names, app constants
│ └── router.dart ← ALL routes and navigation
├── models/ ← Dart data classes only (no logic)
├── services/ ← Firebase calls only (auth_service, firestore_service)
├── providers/ ← Riverpod providers only
├── widgets/
│ └── common/ ← Reusable widgets used across 2+ screens
└── screens/
├── auth/ ← login, register
├── onboarding/ ← steps 1, 2, 3
├── home/ ← home tab
├── plans/ ← plans tab
├── coach/ ← coach tab
├── club/ ← club tab
└── progress/ ← progress tab

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

1. **Never hardcode colors.** Always use `WW.primary`, `WW.card` etc from `lib/core/app_theme.dart`
2. **Never hardcode Firestore collection names.** Always use `Collections.users` etc from `lib/core/constants.dart`
3. **Never call Firestore or Firebase Auth directly from a widget.** Always go through `lib/services/`
4. **Never use Navigator.push or Navigator.pop.** Always use `context.go()` or `context.push()` with routes from `lib/core/router.dart`
5. **Never use setState for shared data.** Use Riverpod providers in `lib/providers/`. setState is only allowed for purely local UI state like a toggle or animation
6. **Never create a new file without checking if it already exists first**
7. **Never modify `app_theme.dart` colors unless explicitly told to**
8. **Never modify `main.dart` unless explicitly told to**
9. **Always add new routes to `router.dart` when creating a new screen**
10. **Always use relative imports within lib/ — never absolute imports**

---

## Firebase Rules

- Auth calls → `lib/services/auth_service.dart` only
- Firestore reads/writes → `lib/services/firestore_service.dart` only
- Never import firebase_auth or cloud_firestore directly in a screen or widget file
- All Firestore collection names must use `Collections.x` constants

---

## Navigation Rules

- Every screen must have a route defined in `lib/core/router.dart`
- Use `context.go(Routes.home)` to navigate and replace current screen
- Use `context.push(Routes.profile)` to navigate and keep back button
- Never hardcode route strings — always use `Routes.x` constants

---

## State Management Rules

- Every piece of shared data needs a Riverpod provider in `lib/providers/`
- Widgets that read data use `ConsumerWidget` and `ref.watch()`
- Widgets that call actions use `ref.read(provider.notifier)`
- Local UI state only (e.g. password visibility toggle) can use `StatefulWidget`

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
2. Create or update a Riverpod provider in `lib/providers/`
3. Call the provider from the widget using `ref.watch()` or `ref.read()`
4. Never call Firebase directly from a widget

---

## What This Project Is

WiseWorkout is a Flutter fitness app with 5 tabs: Home, Plans, Coach, Club, Progress.
It has Auth, Onboarding, Gym Session tracking, AI coaching (WiseCoach), GPS cardio,
gamification (XP, badges, streaks), social features (friends, challenges),
Business Partner profiles, and a React admin dashboard.

Current sprint focus: Auth + Onboarding + Home + Plans + Gym Session (prototype demo).
