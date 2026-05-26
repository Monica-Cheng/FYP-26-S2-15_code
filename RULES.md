# RULES.md — WiseWorkout Coding Rules for All AI Agents

Before writing any code, read and follow these rules exactly.

## Step 1: Always Check Before Creating

- Run a mental check of existing files first
- Never create a file that already exists
- Never create files outside the lib/ folder unless explicitly told to

## Step 2: Never Touch These Files

- lib/firebase_options.dart
- lib/core/app_theme.dart
- lib/core/constants.dart
- lib/main.dart
- ios/ folder
- android/ folder
- pubspec.lock

## Step 3: Always Follow These Patterns

- Colors: always WW.primary, WW.card etc — never hardcode hex
- Navigation: always context.go(Routes.x) — never Navigator.push
- Firebase: always through lib/services/ — never directly in widgets
- State: always Riverpod providers — never setState for shared data
- Collection names: always Collections.x — never hardcode strings

## Step 4: When Adding a New Screen

1. Create file in correct lib/screens/subfolder/
2. Add route to Routes class in lib/core/router.dart
3. Add GoRoute entry in routerProvider in lib/core/router.dart
4. Import screen at top of router.dart

## Step 5: File Naming

- Files: snake_case → login_screen.dart
- Classes: PascalCase → LoginScreen
- Variables: camelCase → userId
