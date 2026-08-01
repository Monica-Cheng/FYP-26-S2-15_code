# Admin Challenge Document Schema — `challenges` and `challengeCategories` Collections

This is the exact Firestore document shape the WiseWorkout Flutter app expects
when reading from the top-level `challenges` and `challengeCategories`
collections (Club → Challenges tab, the challenge detail screen, and the
challenge leaderboard screen). It is meant for whoever builds
challenge-creation into the admin (React) dashboard.

Every field below was confirmed directly against either:

- the Flutter app's own write code (`createChallenge()`, `joinChallenge()`,
  `getChallengeCategories()`, `computeChallengeProgress()` — all in
  `lib/services/firestore_service.dart`), or
- the live Firestore security rules (`firestore.rules`), or
- real documents currently live in production Firestore
  (`challengeCategories`).

Nothing here is guessed or carried over from stale design discussion.

---

## 1. `challengeCategories/{categoryId}` — entirely admin-managed

The app **only ever reads** this collection (`getChallengeCategories()`) — no
app code writes to it, and the security rules explicitly deny all client
writes (`allow write: if false`). Categories are seeded/managed directly via
the admin dashboard or Firebase Console.

| Field        | Type     | Example      | Notes                                                                                                                                 |
| ------------ | -------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `name`       | `string` | `"Distance"` | Shown as the category label in the challenge-creation picker.                                                                         |
| `unit`       | `string` | `"km"`       | Free-text unit label, shown throughout the app (badge, progress text, leaderboard). Real values in use: `"km"`, `"cal"`, `"min"`.     |
| `metricType` | `string` | `"distance"` | **Must be exactly one of three values** — this is not free text, it's a hard-coded switch in `computeChallengeProgress()`. See below. |
| `minGoal`    | `number` | `1`          | Lower bound enforced by the app's goal-value input when a user creates their own challenge in this category.                          |
| `maxGoal`    | `number` | `500`        | Upper bound, same enforcement.                                                                                                        |

### The 3 valid `metricType` values — exact, case-sensitive

`computeChallengeProgress()` switches on this string literally — any other
value silently falls through to 0 progress for every participant, with no
error surfaced anywhere.

- **`"distance"`** — progress summed from real session data: `distanceMeters` for a `cardio`-type session, summed across `cardioBlocks[].distanceMeters` for a `combined`-type session. `unit: "km"` divides the raw meters total by 1000 before display; any other unit value is shown as raw meters.
- **`"calories"`** — progress summed from `caloriesBurned` across every qualifying session, regardless of type. No unit conversion — whatever `unit` says is just a label.
- **`"duration"`** — progress summed from `durationSeconds` across every qualifying session, regardless of type. `unit: "min"` divides by 60, `unit: "hr"` divides by 3600; any other unit value is shown as raw seconds.

---

## 2. `challenges/{challengeId}` — admin-created docs are `isGlobal: true`

| Field             | Type            | Example                                   | Notes                                                                                                                                                                                                                                                                                                                    |
| ----------------- | --------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `name`            | `string`        | `"Summer 100km Challenge"`                |                                                                                                                                                                                                                                                                                                                          |
| `categoryId`      | `string`        | `"distance"`                              | **Must be the real document ID of a `challengeCategories` doc.** The app never validates this reference at read time — an invalid `categoryId` just means the app can never look up category metadata for this challenge if it ever needs to (nothing currently does at read time, but don't rely on that staying true). |
| `metricType`      | `string`        | `"distance"`                              | **Denormalized copy of the referenced category's own `metricType`** — see "why duplicated" below. Must match exactly.                                                                                                                                                                                                    |
| `unit`            | `string`        | `"km"`                                    | **Denormalized copy of the referenced category's own `unit`.** Must match exactly.                                                                                                                                                                                                                                       |
| `goalValue`       | `number`        | `100`                                     | The target value, in `unit`. Should fall within the referenced category's `minGoal`–`maxGoal`, though nothing in the app enforces this for an admin-created doc (client-side challenge creation enforces it in the UI; a direct admin write bypasses that UI entirely).                                                  |
| `startDate`       | `Timestamp`     | `2026-08-01T00:00:00Z`                    |                                                                                                                                                                                                                                                                                                                          |
| `endDate`         | `Timestamp`     | `2026-08-31T23:59:59Z`                    | Progress is computed over `[startDate, endDate)` — a session exactly at `endDate` is excluded (`isLessThan`, not `isLessThanOrEqualTo`, in `computeChallengeProgress()`).                                                                                                                                                |
| `isGlobal`        | `bool`          | `true`                                    | **Must be `true` for every admin-created challenge.** See the dedicated warning below — this is the single most important field on this whole document.                                                                                                                                                                  |
| `createdBy`       | `string`        | `"admin"` or any placeholder              | The app never reads this field to gate behavior for a global challenge (only used client-side to decide who sees the "Invite Friends" button, which never renders on a global challenge in the first place — see `challenge_detail_screen.dart`). Any string works; it does not need to be a real Firebase Auth uid.     |
| `participantUids` | `array<string>` | `[]`                                      | **Must start empty.** See the dedicated warning below.                                                                                                                                                                                                                                                                   |
| `invitedUids`     | `array<string>` | `[]`                                      | **Always empty for a global challenge** — the invite system only exists for private, user-created challenges. Never used by any admin-facing flow.                                                                                                                                                                       |
| `createdAt`       | `Timestamp`     | `FieldValue.serverTimestamp()` equivalent | Not read/sorted on anywhere in the current app, but include it for consistency with app-written docs.                                                                                                                                                                                                                    |

### Why `metricType`/`unit` are duplicated onto the challenge doc instead of just referencing the category

`computeChallengeProgress()` runs once per visible challenge card, every time
the Challenges tab or a challenge detail screen renders (the app's "on-demand
computation" architecture, not a cached/precomputed value). If it had to
resolve `categoryId → challengeCategories/{categoryId}` first to find out
what metric to sum and what unit to display in, that would be a second
Firestore read for every single challenge shown, every time. Denormalizing
`metricType`/`unit` directly onto the challenge doc means the app can compute
and render progress from the challenge doc alone — one read, not two.

---

## 3. ⚠️ What NOT to do

This section exists for the same reason as `ADMIN_PLAN_SCHEMA.md`'s callout
about the deleted malformed `"5K Running Plan"` — each of these is a
plausible-looking mistake that produces a document that _exists_ but behaves
wrong in a way that's easy to miss during a quick admin-dashboard review.

- **Do NOT set `isGlobal: false` on an admin-created challenge.** The Discover
  tab's query (`getDiscoverableChallengesStream()`) only ever fetches docs
  where `isGlobal == true`. A `false` value makes the challenge **completely
  undiscoverable** — no user will ever see it in the app, anywhere, with no
  error and no indication it exists. It will just silently sit in Firestore,
  unreachable.
- **Do NOT reference a `categoryId` that doesn't exist in `challengeCategories`.**
  Nothing in the app validates this at write time (there is no server-side
  validation on this collection at all — Firestore rules only check `isGlobal`/
  `createdBy` on client writes, and admin writes via the service account
  bypass rules entirely). The challenge will still display using its own
  denormalized `metricType`/`unit` fields (since those are read directly off
  the challenge doc, not resolved through `categoryId`), but the reference
  itself becomes a dangling pointer to nothing — a future feature that reads
  category metadata by looking it up via `categoryId` would silently fail for
  this challenge.
- **Do NOT let `metricType`/`unit` mismatch the referenced category.** E.g.
  `categoryId: "distance"` (whose real category doc has `metricType: "distance"`,
  `unit: "km"`) paired with `metricType: "calories"`, `unit: "cal"` on the
  challenge doc itself. Since the app reads `metricType`/`unit` **from the
  challenge doc, not the category**, this produces a challenge that's
  filed under "Distance" conceptually but actually sums calories and labels
  everything in `cal` — confusing and wrong, with nothing to catch it.
- **Do NOT pre-populate `participantUids`.** It's tempting to seed a global
  challenge with a starting participant list to make it look active, but this
  is actively harmful: a uid in `participantUids` with no real matching
  session data means `computeChallengeProgress()` will correctly compute
  their progress as `0` forever (there are no real sessions to sum), while
  the app's UI treats them as a genuine participant who joined and just
  hasn't done anything yet. Worse, on the leaderboard, they'd show up
  permanently stuck at the bottom with no way to ever "really" join later —
  `joinChallenge()`'s `arrayUnion` is a no-op if the uid is already present.
  **Always create global challenges with `participantUids: []`** — real users
  join themselves via the app's own "Join" button (`joinChallenge()`), which
  is the only thing that should ever add a uid to this array for a global
  challenge.

---

## 4. `progressCache` and `progressNotifications` — never write to these directly

Both are subcollections nested under each individual challenge doc
(`challenges/{challengeId}/progressCache/{uid}` and
`challenges/{challengeId}/progressNotifications/{...}`). They are **entirely
app-managed** — `progressCache` is written automatically by
`computeChallengeProgress()` (client-side) and the
`checkChallengeProgressOnSessionCreate` Cloud Function (server-side) as a
denormalized cache of each participant's real, session-data-backed progress,
specifically so the leaderboard can read a small cached number per
participant instead of re-querying everyone's private session history.
`progressNotifications` is a purely internal once-per-day dedup marker for
the "your friend made progress" notification feature.

**The admin dashboard should never write to either subcollection.** Doing so
would either get silently overwritten the next time a real user's progress
is computed, or — worse, for `progressCache` — display a fabricated progress
number with no real session data behind it. The only document the admin
dashboard should ever create is the top-level `challenges/{challengeId}` doc
itself; everything under it is computed by the app.

---

## 5. Complete, valid example documents

### Example `challengeCategories` document — real, currently live in production

This is the actual `challengeCategories/distance` document, seeded earlier
this session and confirmed via a direct Firestore read — not invented:

```json
{
  "name": "Distance",
  "unit": "km",
  "metricType": "distance",
  "minGoal": 1,
  "maxGoal": 500
}
```

(The other two real categories currently live, same shape: `challengeCategories/calories` — `{"name": "Calories", "unit": "cal", "metricType": "calories", "minGoal": 100, "maxGoal": 50000}` — and `challengeCategories/duration` — `{"name": "Duration", "unit": "min", "metricType": "duration", "minGoal": 10, "maxGoal": 3000}`.)

### Example `challenges` document — illustrative, matching the real schema

No admin-created (`isGlobal: true`) challenge exists in production yet — every
real challenge doc currently live was created from within the app by a test
user, and is therefore `isGlobal: false`. The example below is constructed
from the exact field names/types confirmed in `createChallenge()` and the
live security rules, referencing the real `distance` category above, but the
document itself does not exist in Firestore — it's a template, not a copy of
a live doc:

```json
{
  "name": "Summer 100km Challenge",
  "categoryId": "distance",
  "metricType": "distance",
  "unit": "km",
  "goalValue": 100,
  "startDate": "2026-08-01T00:00:00Z",
  "endDate": "2026-08-31T23:59:59Z",
  "isGlobal": true,
  "createdBy": "admin",
  "participantUids": [],
  "invitedUids": [],
  "createdAt": "2026-08-01T00:00:00Z"
}
```

(`startDate`/`endDate`/`createdAt` should be written as real Firestore
`Timestamp` values, not ISO strings — shown as strings here only because
that's how they serialize to JSON for this document.)

---

## 6. Security rules — why the admin dashboard can set `isGlobal: true` when the app never can

The live Firestore rule for creating a `challenges` document is:

```
allow create: if request.auth != null &&
  request.resource.data.isGlobal == false &&
  request.resource.data.createdBy == request.auth.uid;
```

This is enforced against every write that goes through the **Flutter app's**
client SDK, which is always subject to Firestore Security Rules — this is
exactly why `createChallenge()` hardcodes `isGlobal: false` and why a regular
user can never create a public challenge from within the app, no matter what.

The admin (React) dashboard, by contrast, is expected to use a **Firebase
Admin SDK connection backed by a service account** (the same kind of
privileged, rules-bypassing connection used to seed `challengeCategories`
earlier this session) — not the constrained client SDK. Firestore Security
Rules **do not apply to Admin SDK writes at all**, by design. This is the
_only_ legitimate path capable of setting `isGlobal: true` — there is no rule
that grants this to any client-authenticated user, and there shouldn't be
one added. If the admin dashboard is ever built using the same
rules-constrained client SDK/auth flow the Flutter app uses (rather than a
proper Admin SDK backend), it will hit this exact rule and be unable to
create global challenges at all.

One thing worth your attention — it flagged a real architectural point: the admin dashboard needs to use its own service-account/Admin SDK backend, not the same client-side Flutter auth flow, in order to legitimately set isGlobal: true (since the security rules correctly block any regular authenticated client from doing that). This is worth confirming with your teammates building the React dashboard — if they're planning to just call Firestore directly from the browser with a signed-in user's normal auth token, they'll hit the same rule wall you did, and will need either a proper backend service account or a Cloud Function endpoint instead.
