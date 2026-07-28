# WiseWorkout — Project Context for Claude Code

## What this is
Final Year Project (FYP), team-based. This student owns the **nutrition
tracking + social sharing feature**, and has now also picked up the
**Business Portal / coach system** (reassigned from a teammate who
couldn't complete it in time). Relatively new to Git and Flutter tooling
— explain steps clearly, don't assume familiarity. Prefers things simple,
fast, and working over "technically more correct." Appreciates being told
directly when something was a mistake, without over-apologizing.

Team: repo owned by Monica-Cheng (project lead). Weekly team check-ins
Tuesdays 12pm. Submission deadline referenced as ~29 days out from
2026-07-20, so time is tight — favor shippable scope over gold-plating.

## Tech stack
- Flutter (Dart), SDK ^3.12.0
- Firebase (Firestore, Auth) — Firebase project: `WiseWorkout-FYP2615`
- OpenAI API (`gpt-4o-mini`, including vision) for AI food recognition
- `go_router` for navigation
- `camera` + `image_picker` — food photo capture
- `mobile_scanner` — barcode scanning
- `share_plus` — native OS share sheet
- Open Food Facts (free public API, no key) — barcode product lookup

## Architecture conventions (follow these exactly)
- **Design tokens**: all UI uses the `WW` class (`lib/core/app_theme.dart`).
  Never hardcode colors/styles.
- **Firestore collection names**: centralized in `lib/core/constants.dart`
  as `Collections.xxx`. Never hardcode a collection string elsewhere.
  (Note: `businessPartners` collection currently referenced as a raw
  string in firestore_service.dart, not yet added to Collections — worth
  fixing when touched.)
- **Routes**: centralized in `lib/core/router.dart` as `Routes.xxx`
  constants. Never use `Navigator.push` — always `context.push()` /
  `context.go()`. Pass data via go_router's `extra` param (see
  `startInDescribeMode` pattern on the nutrition route).
- **AI calls**: mirror `NutritionService`'s pattern — base64 vision or
  text call to `gpt-4o-mini`, strict JSON response, typed result class,
  key from `.env` via `flutter_dotenv`.
- **Firestore writes**: follow the `saveGymSession` / `saveNutritionLog`
  / `createFeedPost` pattern — subcollections under `users/{uid}/...` or
  top-level collections with denormalized display fields,
  `FieldValue.serverTimestamp()` for dates.
- **Index-based subtabs**: Club and Progress screens both use a simple
  `int _subtab` + `_subtabLabels` list pattern (not TabController) —
  follow this when adding new subtabs rather than introducing a new
  pattern.

## Current state — nutrition + social feature (fully built, PR open)

**Status: Pull Request open on GitHub** — branch `feature/nutrition-scan`,
pushed to `Monica-Cheng/FYP-26-S2-15_code`, commit `52c1211`, 19 files
changed. Awaiting team review/merge. This was built and tested in a
separate working folder first, then the 6 new files had to be manually
copied into a proper git clone before commit (see environment notes below
for why) — if starting a new session, check whether it's been merged to
`main` yet before assuming this is still "in progress."

**Scan / Describe / Barcode** — `lib/screens/nutrition/nutrition_scan_screen.dart`
- 3-tab mode toggle: Scan (live camera + AI vision), Barcode (live
  mobile_scanner + Open Food Facts, supports scanning multiple products
  in one session with a running list + summary), Describe (text + AI).
- AI scan auto-falls-back to Describe tab if the photo isn't recognized.
- Actions: **Log This Meal/All** (→ `users/{uid}/nutritionLogs`),
  **Post to Feed** (→ top-level `posts` collection), **Share** (native
  OS share via `NutritionShareCardWidget` + `share_plus`).

**Feed** — Club screen's 4th tab (`lib/screens/club/club_screen.dart`)
- Real Firestore-backed (`lib/widgets/feed_post_card.dart`) — posts, 🔥
  reactions (toggle, one per user), comments, all live/persisted.
- **Known scope gap:** app-wide, not friends-only — no real friend system
  exists yet. Marked in `getFeedPostsStream()` where to add a filter later.

**Quick Add** — Home `+` FAB (`lib/widgets/quick_add_sheet.dart`) — Scan
Food / Describe a Meal / Log Activity.

**Home calorie ring** — redesigned single ring, two segments: light blue
(Cal Intake) + grey (Left). Formula: `left = dailyCalorieGoal -
caloriesBurned + caloriesEaten` (goal is a BURN target set in Settings,
confirmed via health_profile_screen.dart — eating adds to what's still
"left" to burn, working out subtracts). Segments sized proportionally to
each other (`intakeFraction`/`leftFraction` of their own sum), not capped
against the goal, so it never visually overflows. Gym/Cardio (yellow dot)
shown in the stat list only, not drawn into the ring.

**Services added**
- `lib/services/nutrition_service.dart` — AI photo/text estimation.
- `lib/services/barcode_service.dart` — Open Food Facts lookup (per-100g
  values, labeled honestly as such, not per-serving).
- `firestore_service.dart` additions: nutrition log CRUD, feed post CRUD,
  reactions, comments.

**Known design tradeoff:** feed post photos stored as small compressed
base64 PNGs directly in Firestore docs (not Firebase Storage) — avoided
adding another native dependency mid-project. Fine for FYP scope.

## Next up — scoped but not yet built

**1. Tap feed post → user profile + Follow (Instagram-style)**
No profile-viewing-other-users screen or follow system exists yet at all
— confirmed by searching the codebase. Plan: new
`lib/screens/profile/user_profile_screen.dart`, top-level `follows`
collection (`{followerUid}_{followingUid}` doc id), Follow/Unfollow
button, tap-through from `FeedPostCard`'s avatar/name. Explicitly NOT
filtering the main Feed by follows yet — separate follow-up task.

**2. Post a workout session to the Feed**
Only nutrition currently supports "Post to Feed". Plan: extend
`createFeedPost` with a `type: 'workout'` variant using the same data
`post_session_summary_screen.dart`'s existing `_captureAndShare()` /
`ShareCardWidget` already has available (sessionName, isCardio,
cardioActivity, elapsedSeconds, calories, totalSets, volume).
`FeedPostCard` needs to render workout-type posts differently (duration/
sets/volume instead of macros) but reactions/comments work identically
for both types.

**3. Food log history under Progress tab**
`lib/screens/progress/progress_screen.dart` has 4 subtabs (Charts,
Activities, XP History, Check-ins) — add a 5th: "Nutrition". Needs
`getNutritionLogsHistory(uid)` — same as `getTodaysNutritionLogs` but
without the "since midnight" filter, full history, descending order.

**4. Business Portal / coach system — large, multi-part, in progress**
This is what Monica called the "Business Portal" — reassigned to this
student. Currently almost nothing exists: a `businessPartners` Firestore
collection + `getBusinessPartners()` read method exist (used by
`find_professional_screen.dart` to list already-approved coaches to
regular users), but "Register as Professional" on `login_screen.dart` is
literally just static unclickable text — no registration flow, no coach
dashboard, no admin approval, no plan-assignment, nothing coach-facing.
Decisions made: **full in-app approval flow** (not manual Firebase
Console approval), and coaches **build brand-new custom plans per
client** (not just assigning existing plans). Scoped into 5 parts, meant
to be built and tested one at a time, NOT all in one pass:
  1. `role` field on users (user/coach/admin) + make "Register as
     Professional" actually navigate somewhere + a real registration
     form writing to `businessPartners/{uid}` with `isApproved: false`
  2. Admin approval screen (**no way to become admin exists yet** — flag
     this, don't invent a bootstrap flow; someone manually sets
     `role: 'admin'` on a test account via Firebase Console for now)
  3. Coach dashboard + client request/accept flow (`coachRequests`,
     `coachClients` collections)
  4. Coach views a specific client's full nutrition + workout history
     (reuses #3 above from the "next up" list)
  5. Coach builds a custom plan for one client (reuse
     `build_routine_screen.dart`'s builder, add `assignedToUid`; client's
     own Plans screen shows a "From your coach" section for these)
Given the tight timeline, this may need to span several sessions —
check in after each part rather than attempting all 5 at once.

## Local dev environment — hard-won setup notes

**This machine (Windows, VS Code) had a long, painful first-time setup.**
Known fixes, don't rediscover from scratch:

- **Git, Flutter SDK, Android SDK, Firebase CLI** — all had to be
  installed manually (Git wasn't present at all; Flutter installed to
  `C:\flutter`; Android SDK via Android Studio's SDK Manager, including
  Command-line Tools which isn't installed by default).
- **`.env`** (gitignored) — `OPENAI_API_KEY=...`, get from teammate who
  built WiseCoach chat.
- **`lib/firebase_options.dart`** (gitignored) — generate via
  `flutterfire configure` for project `WiseWorkout-FYP2615` (needs
  `firebase login`, Node.js, `npm install -g firebase-tools`,
  `dart pub global activate flutterfire_cli`, and
  `C:\Users\<user>\AppData\Local\Pub\Cache\bin` on PATH).
- **Android build — Gradle/Kotlin JVM target fighting.** Root cause: a
  very new Android/Kotlin/AGP toolchain vs. several plugins declaring
  older/inconsistent Java or Kotlin targets. **Working fix**, in
  `android/build.gradle.kts` (root-level):
  ```kotlin
  subprojects {
      afterEvaluate {
          extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
              compileSdkVersion(36)
              compileOptions {
                  sourceCompatibility = JavaVersion.VERSION_17
                  targetCompatibility = JavaVersion.VERSION_17
              }
          }
          tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
              compilerOptions {
                  jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
              }
          }
      }
  }
  ```
  MUST use `compilerOptions { jvmTarget.set(...) }`, NOT the deprecated
  `kotlinOptions { jvmTarget = "..." }` — the latter is a hard compile
  *error* (not just a warning) on this toolchain.
- **`flutter_timezone` upgraded `^1.0.8` → `^5.1.0`** — old version used
  removed v1 Android embedding APIs, wouldn't compile at all. API also
  changed: `getLocalTimezone()` now returns `TimezoneInfo`, use
  `.identifier` for the IANA string (see notification_service.dart ~line
  24).
- **`lib/services/notification_service.dart` is real, in-use code** —
  called from `settings_screen.dart` (notification permissions, workout
  reminders). Was mistakenly deleted once as "dead code" from a stale
  report and had to be restored — check actual call sites before ever
  deleting anything as "unused."
- **Android emulator**: `Pixel_10_Pro`, launch via
  `flutter emulators --launch Pixel_10_Pro` then
  `flutter run -d emulator-5554`. iOS not possible from this Windows
  machine (needs a Mac) — not attempted.

## Git / repo situation — RESOLVED, but know the history

- **The original working folder (`FYP-26-S2-15_code-main`) was NEVER a
  real git repo** — it was extracted from a downloaded zip, not
  `git clone`d. All the nutrition/barcode/feed work above was built and
  tested there, but `git` commands didn't work in it at all.
- **Fixed by**: a fresh, proper `git clone
  https://github.com/Monica-Cheng/FYP-26-S2-15_code.git` into a new
  folder, `WiseWorkout-git` (sibling folder, same Documents directory).
  This is now **the correct, real working folder going forward** — stop
  using `FYP-26-S2-15_code-main` for git operations.
- Branch `feature/nutrition-scan` created there, all 19 changed/new files
  manually copied over from the tested working folder, committed, and
  pushed successfully. Collaborator push access confirmed working (no
  permission errors).
- `WiseWorkout-git` does NOT yet have `.env` or `firebase_options.dart`
  set up (fresh clone, these are gitignored) — needed again before the
  app can actually *run* from this folder, even though committing/
  pushing doesn't require them.
- **When starting fresh work**: use `WiseWorkout-git` as the base. If
  `FYP-26-S2-15_code-main` still exists on disk, treat it as retired —
  don't build new features there again, to avoid repeating the
  "built somewhere ungitted" problem.

## Still to verify
- Confirm Firestore security rules exist for `posts` (+ `reactions`/
  `comments` subcollections) — managed in Firebase Console, not in this
  repo, so unknown from a fresh clone whether it's done.
- Whether the `feature/nutrition-scan` PR has been reviewed/merged yet.
- Home page UI/UX redesign — separate, not-yet-started task (top bar
  simplification, card hierarchy, empty states, etc. — discussed but not
  built).

## Working style
- Prefers visual references (screenshots) as design input.
- Wants the fastest working path over the "more correct" one when they
  conflict — flag tradeoffs honestly rather than silently picking heavier.
- New to Git — walk through steps explicitly, one command at a time when
  things go wrong; avoid multi-command blocks when debugging live issues.
- For big/ambiguous feature asks (Feed scope, coach system approval
  flow), ask 1-2 scoping questions before writing a large implementation
  plan — this has worked well so far, keep doing it.
- Appreciates direct acknowledgment of mistakes without over-apologizing
  — state what was wrong, fix it, move on.
