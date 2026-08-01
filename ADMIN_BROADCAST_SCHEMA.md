# Admin Broadcast Document Schema — `adminBroadcasts` Collection

This is the exact Firestore document shape the `sendAdminBroadcast` Cloud
Function (`functions/index.js`) expects when reading from the top-level
`adminBroadcasts` collection, and what it produces as a side effect — a real
notification fanned out into every user's `users/{uid}/notifications`
subcollection. It is meant for whoever builds broadcast-sending into the
admin (React) dashboard.

Every field below was confirmed directly against:
- `sendAdminBroadcast`'s own trigger/handler code (`functions/index.js`),
- the existing notification document conventions it reuses
  (`sendFriendRequest()`/`_writeChallengeInviteNotifications()` in
  `lib/services/firestore_service.dart`), and
- `home_screen.dart`'s `_notificationText()`, which renders the resulting
  notification in the app.

Nothing here is guessed.

---

## 1. `adminBroadcasts/{broadcastId}` fields

| Field | Type | Example | Notes |
|---|---|---|---|
| `message` | `string` | `"New feature: Challenges are live! Check the Club tab."` | The exact text shown to every recipient — see §3, this is rendered *verbatim*, not wrapped in a constructed sentence. |
| `audience` | `string` | `"all"` | **Only `"all"` is implemented today.** See §2 — this field is intentionally an open string (not hardcoded to a single literal check) so future values can be added, but writing anything other than `"all"` right now does nothing. |
| `createdAt` | `Timestamp` | `FieldValue.serverTimestamp()` equivalent | Set once, at document creation, by the admin dashboard. |
| `processed` | `bool` | `false` | **Must start `false`.** Set to `true` by the Cloud Function itself once the fan-out fully completes — this is the idempotency guard (see §4). Never set this to `true` from the admin dashboard; doing so would make the Cloud Function skip the broadcast entirely, believing it was already sent. |

The document itself only needs these four fields — nothing else is read.

---

## 2. `audience: "all"` is the only supported value today

`sendAdminBroadcast` checks `audience` with a strict equality check, not a
pattern or partial match. Any value other than the literal string `"all"`
causes the function to **log a clear error and exit without sending
anything** — it does not fall back to "all" and does not silently no-op
without explanation. This is deliberate: a future unsupported value (e.g. an
admin dashboard update that starts writing `"premium"` before the Cloud
Function actually knows how to handle it) fails loudly in the function logs
rather than either quietly doing nothing (confusing — "why didn't my
broadcast send?") or, worse, silently falling back to sending to everyone
when a narrower audience was intended.

**Adding a new audience value (e.g. `"premium"`, `"level:5"`) requires
updating `sendAdminBroadcast`'s own matching logic in `functions/index.js` —
the admin dashboard cannot unlock new segmentation just by writing a new
string into this field.** The schema is deliberately left open (a plain
string, not a hardcoded single-value type) so that future work is additive —
add a new `if (broadcast.audience === "premium") { ... }` branch alongside
the existing `"all"` handling — rather than a breaking schema change.

---

## 3. The notification document this produces

For every user, `sendAdminBroadcast` writes exactly this shape into
`users/{uid}/notifications/{auto-id}` — reusing the same base conventions
(`type`, `read`, `createdAt`) every other notification type in this app
already uses:

```json
{
  "type": "admin_broadcast",
  "message": "New feature: Challenges are live! Check the Club tab.",
  "fromDisplayName": "WiseWorkout",
  "read": false,
  "createdAt": "<serverTimestamp>"
}
```

This is different from every other notification type in one specific way:
`home_screen.dart`'s `_notificationText()` normally *constructs* a sentence
from `fromDisplayName` (e.g. `"$fromName sent you a friend request"`). For
`admin_broadcast`, the `message` field **is** the display text, shown
verbatim:
```dart
case 'admin_broadcast':
  return n['message'] as String? ?? 'New notification from WiseWorkout';
```
Whatever you write into `adminBroadcasts/{broadcastId}.message` is exactly
what every user sees in their notifications list — write it as the complete,
final sentence, not a fragment.

---

## 4. Idempotency — what `processed` actually protects against, and what it doesn't

`processed` guards against **the same document triggering the function
twice** — Cloud Functions has an at-least-once delivery guarantee, meaning a
single `onDocumentCreate` event can, rarely, fire more than once for the same
document. Without this flag, a re-trigger on an already-fully-sent broadcast
would re-run the entire fan-out and notify every user a second time. The
function checks `processed === true` first and exits immediately if so.

**What this does NOT protect against**: a crash partway through a large
fan-out (e.g. the function dies after successfully committing batch 2 of 4).
`processed` is only set `true` once *every* chunked batch has committed — if
an earlier batch already committed before a crash, and the function later
retries the same (still `processed: false`) document from the top, users in
that already-succeeded batch would receive a duplicate notification. This is
a known, accepted limitation for a broadcast feature at this project's
current scale, not a full exactly-once guarantee — a true fix would need
per-user idempotency tracking (e.g. a `sentTo` subcollection checked before
each write), which is disproportionate to what's needed today and explicitly
out of scope for this pass.

---

## 5. ⚠️ What NOT to do

- **Do not set `processed: true` when creating the document.** The Cloud
  Function checks this *first*, before doing anything else — a broadcast
  created with `processed: true` is silently skipped entirely, and no
  notification is ever sent, with no error (this genuinely looks identical
  to "it worked and there was nothing to do," which is why it's worth
  calling out explicitly rather than just relying on the field description
  above).
- **Do not write directly into users' `notifications` subcollections
  yourself, even for a broadcast.** Let `sendAdminBroadcast` do it. Writing
  the fan-out yourself from the dashboard bypasses the chunking, the
  idempotency guard, and the single source of truth for what an
  `admin_broadcast` notification doc looks like — any drift here means a
  future dashboard update could silently start writing a differently-shaped
  notification that `_notificationText()` doesn't know how to render.
- **Do not expect an `audience` value other than `"all"` to do anything
  useful right now** (see §2) — it will fail loudly in the Cloud Function
  logs, not partially work.

---

## 6. Complete, valid example

```json
{
  "message": "New feature: Challenges are live! Check the Club tab.",
  "audience": "all",
  "createdAt": "<serverTimestamp>",
  "processed": false
}
```

This is exactly what the admin dashboard should write. Everything else
(fan-out, per-user notification docs, marking `processed: true`) is handled
automatically by `sendAdminBroadcast` the moment this document is created.
