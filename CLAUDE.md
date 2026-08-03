# WiseWorkout — Project Context for Claude Code

## What this is
Final Year Project (FYP), team-based. This student owns **nutrition
tracking + social sharing** end-to-end, and is now also building the
**Business Portal / coach-facing side** (an admin approval dashboard is
being built independently by another teammate — do NOT build any admin
UI, only the coach-facing parts: registration, coach dashboard, client
requests, viewing client history, building client plans).

Team: repo owned by Monica-Cheng (project lead). Team coordination note
from Monica: before starting work on a feature, flag it to the team
first to avoid file conflicts; push your own latest code before someone
else starts touching the same area. Weekly check-ins established
earlier; deadline pressure is real — favor shippable scope over
gold-plating, and flag scope tradeoffs honestly rather than silently
picking the heavier option.

## Tech stack
- Flutter (Dart), SDK ^3.12.0
- Firebase (Firestore, Auth) — project `WiseWorkout-FYP2615`
- OpenAI API (`gpt-4o-mini`, vision + text) for AI food recognition
- `go_router` for navigation
- `camera` + `image_picker` — photo capture (food, profile, share cards)
- `mobile_scanner` — barcode scanning
- `share_plus` — native OS share sheet
- Open Food Facts (free public API) — barcode product lookup
- `maplibre_gl` + `geolocator` — outdoor cardio GPS tracking (built by a
  teammate, not this student — see "Outdoor cardio" below)

## Architecture conventions
- **Design tokens**: `WW` class (`lib/core/app_theme.dart`). Never
  hardcode colors/styles.
- **Firestore collections**: `Collections.xxx` in `lib/core/constants.dart`.
- **Routes**: `Routes.xxx` in `lib/core/router.dart`. Never
  `Navigator.push` — use `context.push()`/`context.go()`, pass data via
  `extra`.
- **AI calls**: mirror `NutritionService`'s pattern (base64 vision/text
  → `gpt-4o-mini` → strict JSON → typed result class, key from `.env`).
- **Firestore writes**: `users/{uid}/...` subcollections or top-level
  collections with denormalized display fields, `FieldValue.serverTimestamp()`.
- **Request/accept flows** (friend requests, coach requests): follow the
  batch-write + notification pattern already established in
  `sendFriendRequest`/`acceptFriendRequest` — reuse that style.
- **Index-based subtabs**: Club/Progress screens use `int _subtab` +
  `_subtabLabels`. Recently changed to a bordered/pill visual style
  (not plain text) — match that when adding new subtabs.

## Current state — nutrition + social feature (PR #2 open, actively iterating)

**PR history**: PR #1 (original nutrition/barcode/feed build) was
reviewed and **merged** into `main`. PR #2 (`feature/nutrition-scan`,
same branch reused) is open now, covering everything since — Follow
system, workout feed posts, nutrition history, captions, delete post/
comment, share card system, profile photos, Business Portal. Push
regularly; this PR is being reviewed incrementally, not all at once.

**Scan / Describe / Barcode** — `lib/screens/nutrition/nutrition_scan_screen.dart`
- 3-tab toggle: Scan (camera + AI vision, now with an "Is this right? /
  No, let me fix it" confirm-or-correct step after AI results), Barcode
  (multi-product session), Describe (text + AI).
- **Share/Post to Feed for nutrition posts uses the RAW scanned/picked
  photo directly** — explicitly NOT the branded gradient card. This was
  built with the card wrapper first, then reverted per direct
  instruction: "just photo like before." `NutritionShareCardWidget`
  still exists in the codebase but is unused in this flow — don't
  delete it, it may be wanted again.
- Photos are now also saved onto `nutritionLogs` docs (`imageBase64`)
  and shown in `nutrition_log_detail_screen.dart` under Progress →
  Nutrition tab, which is tappable (mirrors `_ActivityCard`'s pattern).

**Feed** — Club's Feed tab, real Firestore (`posts` collection,
`lib/widgets/feed_post_card.dart`). Reactions/comments live and
persisted; delete own post/comment supported (uid-owner check).
**Known scope gap, still true:** app-wide, not friends-only (real
friends now exist via a teammate's system — see below — but the feed
query hasn't been scoped to it).

**Workout share cards — multi-card system, still being debugged**
`post_session_summary_screen.dart`'s Share/Post to Feed now opens a
swipeable picker (`lib/widgets/share_card_picker.dart`) between 3 card
types, all rendered at 1080x1920 (Story ratio):
1. **Map/route card** (`lib/widgets/route_map_share_card.dart`) — uses
   `mapSnapshotBase64` if present, else falls back to a `CustomPainter`
   route line on a gradient. Only offered when route data exists
   (`isAvailable()` check).
2. **Photo-background card** — user-picked photo as background.
3. **Colored-background card** — now has a 4-5 gradient preset picker
   (`lib/core/share_card_gradients.dart`).
All 3 are meant to show a **route line overlay** (`lib/widgets/route_overlay.dart`)
on top of whatever background, when route data exists — this is NOT a
4th separate card, it's a shared overlay layer across all 3.

**Bug history on this system (useful if debugging resurfaces):**
- Posted cards initially showed cropped/blank because `FeedPostCard`
  forced a 4:3 `AspectRatio` on what are 9:16 images — fixed.
- A regression briefly made posting fail entirely with
  `[cloud_firestore/invalid-argument]` — traced to a malformed field
  (NaN/nested-array-family bug) introduced alongside route-data work —
  fixed; if this error class reappears, check for NaN/Infinity in
  calculated fields (e.g. pace = time/distance with distance=0) or
  nested arrays (route points must be `List<Map<String,double>>`, never
  `List<List<double>>`) first.
- Map/photo cards intermittently rendered blank (white space) while the
  color card worked — root cause was suspected to be an async
  image-decode race against `RenderRepaintBoundary.toImage()` capture
  timing (capturing before the background image finished loading).
- **As of the last exchange in this session, the route line overlay
  itself still was NOT confirmed visible on any card** — under active
  debugging. Suspects, in order of likelihood based on where the trail
  was left: (a) route data reaching the widget but the overlay not
  actually present in all 3 build methods, or (b) a contrast problem
  (white route line against light/white backgrounds — several bug
  screenshots showed the route area as blank white, which is also
  consistent with an invisible-but-present white-on-white line, not
  only a missing-image explanation). **Check this first in the next
  session** rather than assuming either the posting-fix or earlier
  attempts resolved it.

**Quick Add** — Home `+` FAB (`lib/widgets/quick_add_sheet.dart`) — Scan
Food / Describe a Meal / Log Activity.

**Home calorie section** — always visible now (previously hidden
entirely when calorie tracking was toggled off in Settings — fixed per
direct feedback). With tracking on: existing ring (gold=eaten,
grey=left, `left = dailyCalorieGoal - caloriesBurned + caloriesEaten`,
since the goal is a BURN target, not an eating target — confirmed via
Settings copy). With tracking off: plain "X kcal eaten today" number,
no ring/goal math. Daily protein/carbs/fat totals also shown in both
states, informational only, no goals attached.

**Profile photos** — new `photoBase64` field on `users/{uid}`. Current
user can upload their own (profile screen, tappable avatar →
ImagePicker). Shown on the user's own profile and their own feed posts
(denormalized `authorPhotoBase64` onto posts at creation). **Explicitly
NOT yet propagated everywhere** — leaderboard rows, friend rows, comment
avatars, and other users' feed-post headers still show initials-only;
this was a deliberate scope decision to avoid a large ripple change, not
an oversight.

**User profile screen (viewing others)** — `lib/screens/profile/
user_profile_screen.dart`. Now a "game profile": Follow/Unfollow,
follower/following counts, a level+XP card (mirrors Progress tab's
`_buildLevelCard()` styling/logic, including `_levelName()` and XP
thresholds — factored out to `lib/core/xp_levels.dart`), a
streak/sessions/lifetime-volume stat box (now styled to match the level
card, per feedback that it looked inconsistent at first), and the
user's own feed posts below.

**Small-screen responsiveness** — actively being audited/fixed against
an emulator specifically named **"Small_Phone"** (not just the default
Pixel profile most testing has used) — two confirmed overflow bugs (cardio
setup screen, nutrition AI-confirm section) were fixed; a broader pass
across recently-added screens (share card picker, profile stat boxes,
nutrition detail) was also requested. **Use the Small_Phone emulator
profile for future UI verification, not just the default one** — this
is how these bugs were actually caught.

## Business Portal / coach system — scope finalized, build starting

**Admin approval is being built by a separate teammate — do not build
any admin UI or bootstrap-to-admin flow.** This student's scope is only
the coach-facing side, 4 parts (not 5 — admin dropped from this
student's list):
1. `role` field on users + real "Register as Professional" registration
   form → `businessPartners/{uid}` (must write `isApproved: false`,
   `isVisible: false` to match the existing `getBusinessPartners()` read
   query and whatever the teammate's admin dashboard expects to read —
   check field-name compatibility with their work before building, since
   both sides depend on this same collection shape).
2. Coach dashboard + client request/accept (`coachRequests`,
   `coachClients` collections, batch-write pattern like the friend
   system).
3. Coach views a client's full nutrition + workout history.
4. Coach builds a brand-new custom plan per client (`assignedToUid`
   field on plans; client's own Plans screen shows a "From your coach"
   section).
Before building, check whether any teammate has already touched
`role`, `login_screen.dart`'s "Register as Professional" text, or
created any coach-registration screen, given how much has landed via
merges recently.

## What teammates built (read-only context, not this student's code —
## useful for knowing what exists so nothing gets duplicated)

- **Friends system** (`lib/screens/club/friends_screen.dart`) — real
  mutual-acceptance friends: search by username, send/accept/decline
  requests, notifications collection, a friends-scoped weekly
  leaderboard (`getFriendsLeaderboardStream`, hand-rolled combine-latest
  over chunked `whereIn` queries since neither `rxdart` nor `async` is a
  dependency). Club's old "Friends" tab was removed and replaced by a
  full-page screen opened from a top-bar icon; Club's subtabs are now
  just Leaderboard/Challenges/Feed.
- **Outdoor cardio GPS tracking** (`lib/screens/cardio/
  outdoor_cardio_screen.dart`, ~2,500 lines) — live map (`maplibre_gl`),
  Strava-style Start/Pause/hold-to-Finish, GPS accuracy filtering, speed-
  implausibility rejection, point smoothing, elevation gain, background-
  location permission with disclosure. Produces `route` (downsampled to
  ~400 points, `List<Map<String,double>>`, flattened across pause
  boundaries — no gap-rendering support), `mapSnapshotBase64` (pre-
  rendered route thumbnail), `distanceMeters`, `elevationGainMeters`,
  optional `photoBase64`. Saved via `saveCardioSession()` for standalone
  sessions, or into `cardioBlocks[]` per-block for plan-linked combined
  sessions (**the map share card only supports pure-cardio-type
  sessions** — combined gym+cardio sessions' per-block route data isn't
  merged into one shareable card, a deliberate scope line, not a bug).
  Has a teammate's own temporary debug print at ~line 2137 tagged
  "TEMPORARY DEBUG" — not this student's to remove.
- **Session-resume system** (`lib/widgets/session_resume_prompt.dart`)
  and related changes across `gym_session_screen.dart`,
  `plan_detail_screen.dart`, `plan_schedule_screen.dart`,
  `plans_screen.dart`.

## Local dev environment — hard-won setup notes (still applies)

- **`.env`** (gitignored): `OPENAI_API_KEY=...`.
- **`lib/firebase_options.dart`** (gitignored): via `flutterfire configure`.
- **`android/app/google-services.json`** (gitignored, a THIRD Firebase
  secret file, separate from the above two): download from Firebase
  Console → Project Settings → General → Your apps → Android app.
- **Android build — Gradle/Kotlin JVM target fix**, in
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
  Use `compilerOptions { jvmTarget.set(...) }`, NOT deprecated
  `kotlinOptions { jvmTarget = "..." }` (hard compile error on this
  toolchain).
- **`flutter_timezone`** must stay `^5.1.0`+ (not `^1.0.8` — old v1
  Android embedding API, won't compile). API returns `TimezoneInfo`, use
  `.identifier` for the IANA string.
- **`lib/services/notification_service.dart` is real, in-use code** —
  called from `settings_screen.dart`. Do not delete as "dead code"
  without checking actual call sites.
- **Android emulators**: default Pixel profile for general testing,
  **`Small_Phone` profile specifically for responsiveness checks** (see
  above — this is how real overflow bugs were caught, general testing
  alone missed them).

## Git / repo workflow — hard-won lessons, follow this order every time

- **Working folder**: `WiseWorkout-git` (a real `git clone`), NOT
  `FYP-26-S2-15_code-main` (never a real repo, retired) or any
  re-extracted zip folder (e.g. a stray `...main02` — these lack
  `.env`/`firebase_options.dart`/`google-services.json` and have no git
  history; if one appears again, abandon it, don't try to fix it).
- **Always commit local work BEFORE pulling**, every time, no
  exceptions — `git pull`/`git merge` will abort with "local changes
  would be overwritten" if you try to pull with uncommitted changes,
  which is git protecting you, not a bug. Correct order:
  ```
  git add .
  git commit -m "..."
  git fetch origin
  git merge origin/main
  git push
  ```
- **When `git merge` needs a commit message**, it may open **Vim** in
  the terminal (looks like a stuck/frozen screen with `~` lines) — this
  trips up almost everyone the first time. Fix: press `Esc`, type
  `:wq`, press Enter. The default merge message is already fine, no
  need to type anything else.
- **Real merge conflicts happen regularly** on this project (multiple
  teammates actively pushing to the same files: `constants.dart`,
  `club_screen.dart`, `progress_screen.dart`, `firestore_service.dart`
  especially, since everyone adds Firestore methods/constants there).
  When resolving: read both sides carefully, usually "accept both" is
  correct for additive changes (new constants, new methods) but NOT for
  structural changes (e.g. `_subtabLabels` list length must match the
  `IndexedStack` children count exactly — verify downstream usage, don't
  just blindly keep both versions of a list). For large/tangled
  conflicts spanning hundreds of lines, it's safer to select-all-replace
  the whole conflicted section with a hand-verified merged version than
  to trust auto-merge buttons, which have duplicated/corrupted content
  at least once this session.
- **Don't delete files reported as "unused"** without verifying actual
  call sites yourself — a stale "dead code" report led to deleting
  `notification_service.dart`, which was genuinely in use and had to be
  restored.

## Still to verify / open threads
- **Route overlay visibility bug** — see share-card bug history above,
  not confirmed fixed as of the last exchange. Check this first.
- Firestore security rules for `posts`/`reactions`/`comments`,
  `follows`, `coachRequests`/`coachClients`, `businessPartners` writes —
  managed in Firebase Console, not version controlled, unknown current
  state.
- Business Portal Parts 1-4 — scoped, prompt sent, not yet confirmed
  built/tested as of this update.
- Home page UI/UX redesign (top bar simplification, card hierarchy) —
  discussed early on, still not started, likely lower priority now given
  everything else in flight.

## Working style
- Prefers fastest working path over "more correct" when they conflict —
  flag tradeoffs honestly, don't silently pick the heavier option.
- Escalating trust in Claude Code over the session — increasingly sends
  "continue until finished" instructions for multi-part features rather
  than requiring a check-in after every single part; still wants
  `flutter analyze` run and confirmed clean at each checkpoint though.
- When something is reported as "still not working" after a claimed
  fix, don't re-guess — force actual debugPrint evidence and real
  values before claiming resolution again. This pattern (photo-not-
  showing, ring-color-not-showing, route-not-showing) has recurred
  several times; evidence-first debugging prompts have been the
  reliable way to actually close these out.
- New to Git — the commit-before-pull discipline above prevents most
  of the friction that's come up.
