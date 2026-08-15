# WiseWorkout

WiseWorkout is a Flutter fitness app that combines gym and cardio session
tracking, nutrition logging, and AI-assisted coaching in a single platform,
with a companion admin dashboard and marketing website.

## Features

- **Workout plans** — build custom gym routines or follow structured plans,
  with support for combined gym + cardio sessions.
- **Session tracking** — guided gym sessions with set/rep logging, and
  outdoor/indoor cardio tracking (GPS route capture, distance, pace,
  elevation gain).
- **Nutrition tracking** — log meals via AI photo recognition, barcode
  scanning, or text description, with a running history of past logs.
- **WiseCoach (AI)** — AI-driven coaching features layered on top of a
  user's workout and nutrition data.
- **Progress analytics** — charts and summaries of training volume,
  streaks, and nutrition over time.
- **Social & challenges** — friends, a follow system, a shared activity
  feed, and challenges with leaderboards.
- **Gamification** — XP and level progression, streaks, and session-based
  rewards to encourage consistency.
- **Business Portal** — a coach-facing side of the app: coach registration,
  a coach dashboard, client requests, and coach-built client plans.
- **Premium tiers** — subscription-gated features across plans, progress,
  and social areas of the app.

## Tech stack

- **Flutter / Dart** (SDK `^3.12.0`) — cross-platform mobile app
- **Firebase**
  - Firestore — primary data store
  - Authentication — user accounts (including Google Sign-In)
  - Cloud Functions — server-side logic
  - Cloud Storage — file uploads (e.g. coach credential documents)
- **`health`** package — HealthKit (iOS) / Health Connect (Android)
  integration for device health data
- **`go_router`** — navigation
- **`flutter_riverpod`** — state management
- **`maplibre_gl` + `geolocator`** — outdoor cardio map rendering and GPS
- **OpenAI API** (`gpt-4o-mini`) — AI food recognition and coaching features
- **React / Next.js** — admin dashboard and marketing website (see below)

## Repository structure

```
lib/                    Flutter app source (screens, services, models, etc.)
admin/wiseworkout-admin/  Admin dashboard (React) for approvals and moderation
website/                Marketing website (Next.js)
functions/              Firebase Cloud Functions (Node.js)
docs/                   Project documentation (architecture, test cases, etc.)
android/, ios/           Platform-specific Flutter project files
```

## Setup & running

Prerequisites: Flutter SDK `^3.12.0` (stable channel), and a configured
Firebase project.

1. Install dependencies:
   ```
   flutter pub get
   ```
2. This project depends on Firebase config files that are not checked into
   version control:
   - `.env` — contains `OPENAI_API_KEY`
   - `lib/firebase_options.dart` — generated via `flutterfire configure`
   - `android/app/google-services.json` — from the Firebase console
   - iOS equivalent (`GoogleService-Info.plist`) if building for iOS

   These must be obtained separately and are not included in this
   submission.
3. Run the app on a connected device or emulator:
   ```
   flutter run
   ```

The admin dashboard (`admin/wiseworkout-admin/`) and website (`website/`)
are separate Node.js/Next.js projects; each has its own `package.json` and
is run independently with `npm install` and `npm run dev` from within its
own directory.
