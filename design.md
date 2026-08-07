# WiseWorkout — Visual Design Reference

This document captures WiseWorkout's **actual** visual design system as implemented
in its Flutter app, so a separate project (marketing website, admin dashboard) can be
redesigned to visually match it — same colors, same typography feel, same component
patterns — without needing to read the Flutter codebase.

Source of truth: `lib/core/app_theme.dart` (the `WW` design-token class), plus real
usage observed across `lib/screens/home/home_screen.dart`,
`lib/screens/plans/plan_schedule_screen.dart`, `lib/screens/profile/profile_screen.dart`,
`lib/screens/coach/coach_screen.dart`, and `lib/screens/club/club_screen.dart`.

This is a **reference document**, not a design-system implementation. No CSS or code
is generated here — a human or a future Claude Code session should read this and
translate it manually into the target project's own stack.

---

## 1. Color palette

All tokenized colors live in the `WW` class at `lib/core/app_theme.dart`. Values below
are exact hex, annotated with how they're actually used across the app (not just what
they're named).

### Backgrounds

| Token | Hex | Usage |
|---|---|---|
| `WW.bg` | `#F7F8FF` | App/screen background (`scaffoldBackgroundColor`) — a very pale blue-lavender, never pure white. Used behind every screen. |
| `WW.card` | `#FFFFFF` | Card surfaces, sheets, dialogs, top bars — pure white sitting on top of `WW.bg` for contrast/elevation. |
| `WW.elevated` | `#EEF0FB` | A step "between" bg and card — used for secondary/inset surfaces inside a card (e.g. stat tiles in `profile_screen.dart`'s `_buildStatsRow()`, info chips, progress-bar track backgrounds, icon-button backgrounds like the back-button circle). Reads as a subtle recessed panel, not a card of its own. |

### Primary / accent

| Token | Hex | Usage |
|---|---|---|
| `WW.primary` | `#6C7EE8` | The single dominant accent color of the whole app. Main CTA buttons (Start Session, Send in chat), selected chip/tab/toggle states, active bottom-nav icon, progress bar fill, links ("See all friends →", "Find Professional"), focus/selection borders, the FAB. |
| `WW.primaryDark` | `#2D3A8C` | Headings and high-emphasis titles specifically — screen titles ("Profile", plan name in the schedule top bar), "Today's Plan" section header, the greeting name on Home. Also the base color for `WW.shadow` (a tinted shadow, not plain black). Reads as "primary, but for typography, not fills." |
| `WW.lavender` | `#9B84E8` | Secondary accent, used to visually separate a distinct feature from the main primary-purple flow — the WiseCoach avatar/chat-bubble icon color, the "Compressed" session state and Compress button outline in Plan Schedule, one Quick-Add icon color. Signals "AI / a related-but-different action" against the primary blue-purple. |
| `WW.lavenderBg` | `#F0EEFE` | Tint background paired with `WW.lavender` (e.g. the "⚡ Compressed" chip background, Quick Add icon circle background). |
| `WW.lavenderDark` | `#7B5CB8` | Darker lavender variant — declared in tokens, seen for reference; not observed in the 5 sampled screens (may be used elsewhere in the app for lavender-on-light-background text needing more contrast, mirroring how `primaryDark` relates to `primary`). |
| `WW.lavenderText` | `#5B3F9E` | Same pattern as above — the "text-safe" darker lavender, tokenized but not hit in this sample. |
| `WW.teal` | `#4BB8CC` | Tertiary accent, consistently meaning "success / completed / positive stat" — the "Completed" schedule-day status badge, the streak stat icon+number on Profile, "Workout Time" stat icon. |
| `WW.tealBg` | `#E0F4F8` | Tint background paired with teal (e.g. the "Completed" status badge background in Plan Schedule). |

### Neutral text

| Token | Hex | Usage |
|---|---|---|
| `WW.text` | `#3D3D5C` | Primary body/label text color — a dark blue-grey, never true black. Default color for `bodyMed`, `titleMed`, row names, exercise names, message bubble text. |
| `WW.textSec` | `#8A8A9E` | Secondary/muted text — timestamps, captions, subtitles, placeholder hints, unselected nav labels, "this week" micro-labels. The app's single "de-emphasized" color, used very consistently instead of varying opacity. |

### Borders & chips

| Token | Hex | Usage |
|---|---|---|
| `WW.border` | `#C8C8D8` | Hairline borders on cards (`WW.cardDecoration`), dividers between list rows, unselected chip/tab outlines, input field borders. |
| `WW.chipBg` | `#E6EAFE` | Light purple chip/pill background — selected-adjacent badges ("TODAY" status pill), avatar circle backgrounds, active icon backgrounds. Distinct from `WW.elevated` in that it carries a purple tint (ties back to `WW.primary`) rather than being neutral. |

### Accent (secondary palette)

| Token | Hex | Usage |
|---|---|---|
| `WW.gold` | `#F59E0B` | Streak flame icon, XP-related highlights, one Quick Add icon color, unread-notification dot border accent. Warm accent used sparingly against the cool purple/teal palette — draws the eye to gamification/urgency. |
| `WW.lightBlue` | `#7EC8E3` | Tokenized but not observed in the 5 sampled screens — likely used elsewhere (e.g. cardio/GPS-related UI, per the teammate's outdoor cardio feature) as a sky-blue accent. |
| `WW.lightYellow` | `#F5D76E` | Tokenized but not observed in the sampled screens — likely a secondary gold/highlight variant. |

### Semantic colors — NOT tokenized (hardcoded hex literals in Dart)

These are **not** in the `WW` class but are used repeatedly and consistently enough to
be de facto semantic colors. A website/admin redesign should treat these as real
palette entries even though the Flutter app itself doesn't formalize them:

| Literal hex | Meaning | Where seen |
|---|---|---|
| `#EF4444` | Destructive red | "Stop Tracking This Plan" text button, "Stop Tracking"/destructive dialog action text, unread-notification red dot, removed-exercise strikethrough text and icon in the Compress sheet |
| `#FEE2E2` | Destructive red, light tint | Background for the "Accessory" removal chip in the Compress sheet |
| `#DCFCE7` | Success green, light tint | "Saves approximately X minutes" banner background in the Compress sheet |
| `#22C55E` | Success green | Checkmark icon + text in the same "Saves ~X minutes" banner and the "KEEPING" exercise list checkmarks |
| `#F59E0B` (also `WW.gold`, but used raw) | Warning amber | Missed-session banner icon/border/button (`_buildMissedBanner()` in `home_screen.dart`) |
| `#FEF3C7` | Warning amber, light tint | Missed-session banner background |
| `#92400E` / `#B45309` | Warning amber, dark text variants | Missed-session banner title/subtitle text (need enough contrast on the light amber background, so darker than the base amber) |
| `#10B981` / `#059669` | "Online" status green | WiseCoach top bar's green status dot + "Online" text |
| `#E8EAF8` | Divider grey (a slightly purple-tinted grey, close to but distinct from `WW.border`) | Bottom-nav top border, top-bar bottom border, leaderboard row divider |

See **Section 6** for why these matter as a non-goal to silently "fix."

---

## 2. Typography

**Font family**: `'SF Pro Display'`, set once in `WW.theme` (`ThemeData(fontFamily: 'SF Pro Display', ...)`). This is an Apple system font — a website redesign should pick the closest equivalent available on the web (e.g. `-apple-system`/`BlinkMacSystemFont` fallback stack, or a similar geometric-humanist sans like Inter/General Sans if SF Pro isn't licensable for web use) rather than trying to load SF Pro Display itself.

**Named text styles** (all defined in `WW`, all default to `WW.text` color unless noted):

| Style | Size | Weight | Color | Notes |
|---|---|---|---|---|
| `titleLarge` | 20px | w800 (extra-bold) | `WW.text` | `letterSpacing: -0.3` — tight tracking on the largest heading style. Used for prominent screen-level headings. |
| `titleMed` | 17px | w700 (bold) | `WW.text` | Sub-heading weight — dialog titles, sheet titles. |
| `bodyMed` | 15px | w400 (regular) | `WW.text` | Default body copy weight. |
| `labelMed` | 13px | w500 (medium) | `WW.textSec` | Muted, small — form labels, secondary descriptors. |
| `caption` | 11px | w600 (semibold) | `WW.textSec` | Smallest defined style — but bumped to semibold rather than regular, so tiny text still reads with intent rather than looking like a footnote. |
| `rowName` | 14px | w600 (semibold) | `WW.text` | List-row primary label (leaderboard/friends rows). |
| `rowSecondary` | 12px | w500 (medium) | `WW.textSec` | List-row secondary label (e.g. "Level 5" under a name). |
| `rowStat` | 15px | w700 (bold) | *(unset — caller supplies via `.copyWith(color:)`)* | The stat value at the end of a row (e.g. "1,240 XP"). Colorless by design since callers vary it (e.g. highlighting the current user's own row differently). |

**Informal hierarchy observed beyond the named styles** (i.e. real inline `TextStyle`s
repeated often enough to be a pattern, even though not promoted to a named `WW` style):

- **Screen-title / greeting-name tier**: 18–22px, w600–w800, color `WW.primaryDark` — e.g. Home's greeting name (22px/w800), Profile's "Profile" top-bar title (18px/w600), Plan Schedule's plan-name top-bar title (16px/w700). This tier consistently uses `primaryDark`, not plain `WW.text` — headings get the purple treatment, body text does not.
- **Section-header tier**: ~16–18px, w700–w800, `WW.primaryDark` or `WW.text` — "Today's Plan", "Badges", "Friends" section labels.
- **Card-title tier**: 15px, w800, `WW.primaryDark` — e.g. the plan name inside the progress card.
- **Small all-caps eyebrow tier**: 10px, w700, `WW.textSec`, `letterSpacing: 0.5` — "KEEPING"/"REMOVING" labels in the Compress sheet, "THIS WEEK · FRIENDS" section eyebrow in the leaderboard. A distinct micro-pattern: uppercase + wide tracking + tiny size, used to label a group of content without competing with real headings.
- **Badge/status pill text**: 9–11px, w600–w700, color matched to its pill's tint (e.g. teal text on teal-tinted background for "Completed"). Never plain grey on a colored pill.
- **Numeric/stat display**: 20px, w700, `WW.text` (unqualified numbers) or `WW.primaryDark` (level number "Lv.5") — bigger and bolder than body text specifically for at-a-glance numbers (stat tiles, XP level).

**What reads as heading vs. body vs. caption in this app:**
- Heading = bold-to-extrabold (w600–w800) + `WW.primaryDark` (not `WW.text`) at 16px+.
- Body = regular-to-medium (w400–w600) + `WW.text` at 12–15px.
- Caption/label = medium-to-semibold (w500–w700, i.e. *never* thin/regular even at tiny sizes) + `WW.textSec` at 9–13px.

The consistent rule: **weight increases as size decreases** for secondary text (a
9px caption is still semibold+), so nothing ever looks accidentally faint — de-emphasis
comes entirely from color (`WW.textSec`) and size, never from lighter font weight.

---

## 3. Spacing & shape language

**Border radius** (observed values, largest-surface to smallest):

| Radius | Used for |
|---|---|
| 20px | Bottom-sheet top corners (`BorderRadius.vertical(top: Radius.circular(20))`) — every modal sheet in the app uses this exact value. Also large pills like the mode-toggle "WiseCoach/My Clients" active-tab background at 10px is smaller — see below; 20px is reserved for sheets and some fully-round chips (week-selector pills, chat bubbles' rounded end). |
| 16px | Standard card radius — `WW.cardDecoration`'s `borderRadius: BorderRadius.circular(16)`, AlertDialog shapes, message bubble outer corners. This is the single most common "card" radius in the app. |
| 12–14px | Secondary card-like containers that don't use `WW.cardDecoration` directly — break-mode card, progress card, badge-image squircle corners scale with tile size (`size * 0.28`, e.g. ~16px at the 56px tile size used in the badge grid). |
| 10px | Buttons (`ElevatedButton`/`OutlinedButton` `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10–13))`), icon-button squares (back button, settings button — 34×34px containers at 10px radius), mode-toggle segments. |
| 8–9px | Small chips/tags (info chip, exercise tag chip), small action buttons (accept/decline 34×34 squares at 9px). |
| Circle (`BoxShape.circle` / `999px`) | Avatars, FAB, notification icon badges, week-selector pills (`circular(20)` on a 36px-tall pill — effectively a stadium/pill shape), chat message bubbles' rounded side. |

**Common padding/spacing patterns:**
- Card internal padding: `EdgeInsets.all(14)` or `EdgeInsets.all(16)` are the two most common — 14px for denser cards (progress card), 16px for primary content cards (profile card, break-mode card).
- Screen-edge horizontal padding: consistently **16px** or **20px** depending on screen (Plan Schedule/Profile use 16px; Home uses 20px) — no single universal value, but always in that 16–20px range, never edge-to-edge without padding except for full-bleed list dividers.
- Inter-element vertical spacing: built almost entirely from `SizedBox(height: N)` in a tight scale of **4, 6, 8, 10, 12, 14, 16** — small gaps (4–6px) between a label and its value directly below it, medium gaps (8–12px) between distinct pieces of content in the same card, larger gaps (14–16px+) between separate cards/sections.
- List-row height: 56px is a recurring fixed row height for compact rows (friend row in Profile).
- Icon-badge circle sizes: 36px (notification icon), 40px (friend-row avatar, coach-dashboard-link icon), 28–36px (chat avatar / send button), 56–72px (profile badge tile: 56px in-grid, 72px in the detail sheet), 80px (profile header avatar).

**Shadow style** (`WW.shadow`):
```dart
BoxShadow(
  color: Color(0xFF2D3A8C).withOpacity(0.06),  // WW.primaryDark at 6% opacity
  blurRadius: 8,
  offset: Offset(0, 2),
)
```
A single, soft, barely-there shadow — tinted with the brand's dark purple rather than
plain black, low opacity (6%), small vertical offset (2px), moderate blur (8px). Applied
uniformly via `WW.cardDecoration` to nearly every card in the app — there is no
multi-elevation shadow system (no "level 1 vs level 2" shadow depths), just this one
shadow, present or absent.

---

## 4. Component patterns

### Buttons

**Primary (filled) button** — solid `WW.primary` background, white text, no border,
`elevation: 0` (flat, relies on `WW.shadow` or a custom colored shadow instead of
Material's default elevation), radius 10–13px:
```dart
ElevatedButton.styleFrom(
  backgroundColor: WW.primary,
  foregroundColor: Colors.white,
  minimumSize: const Size(double.infinity, 48),
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
)
```
Seen in: "Start [N] Day Break" (`plan_schedule_screen.dart`), and hand-rolled equivalents
using `GestureDetector` + `Container` instead of `ElevatedButton` for custom shadow
control, e.g. the "Start Session" button which adds its own tinted glow shadow:
```dart
BoxShadow(color: WW.primary.withValues(alpha: 0.3), blurRadius: 8, offset: Offset(0, 3))
```
This "colored glow shadow matching the button's own fill color" is a deliberate accent
on the single most important CTA per screen (Start Session), not used on every button.

**Outlined (secondary) button** — transparent background, `WW.primary` border + text,
same radius family as primary:
```dart
OutlinedButton.styleFrom(
  side: const BorderSide(color: WW.primary, width: 1.5),
  foregroundColor: WW.primary,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
)
```
Seen in: "Restart from Day 1", "End Break Early". Always paired 1:1 with a primary
button nearby as the less-emphasized alternative action, never used alone as a screen's
only CTA.

**Destructive action** — no filled/outlined destructive button pattern exists; destructive
actions are rendered as plain text (no container, no border) in `#EF4444`, w600–w700:
```dart
Text('Stop Tracking This Plan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFEF4444)))
```
This is consistent — destructive intent is communicated by color+weight only, always
lower visual weight (plain text, not a button surface) than the primary/outlined
button styles above, positioned last/lowest on the screen. In dialogs, the destructive
confirm action is a plain `TextButton` with `#EF4444` text, same shape as the dialog's
Cancel button, not a filled red button.

**Icon-button squares** — a very common small utility pattern, 34×34px, `WW.elevated`
background, `borderRadius: 10`, centered icon in `WW.textSec` or `WW.text`:
```dart
Container(
  width: 34, height: 34,
  decoration: BoxDecoration(color: WW.elevated, borderRadius: BorderRadius.circular(10)),
  child: Center(child: Icon(..., color: WW.textSec)),
)
```
Used for back buttons and settings buttons across nearly every screen's top bar.

### Chips / segmented controls

**Selected vs. unselected chip pattern** (seen in week selector, break-day-count picker,
mode toggle, subtab pills):
- Selected: solid `WW.primary` fill, white text, no border (or border matches fill).
- Unselected: transparent or `WW.elevated` fill, `WW.textSec` text, `WW.border` outline (1–1.5px) when it's a pill-with-border variant, or no border when it's a plain elevated segment.
- Radius is always fully-rounded/pill (20px on a ~32–36px-tall element) for standalone chip rows; slightly less rounded (10px) for two-segment toggles like WiseCoach/My Clients.

Example (week selector):
```dart
decoration: BoxDecoration(
  color: active ? WW.primary : Colors.transparent,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: active ? WW.primary : WW.border, width: 1.5),
)
```

**Status/info chips** (non-interactive, e.g. "3 days/wk", "Intermediate" tags on the
progress card) — small, `WW.elevated` background, `WW.textSec` text, 8px radius, no
border. A visually quieter cousin of the selected/unselected toggle chip, used purely
to display metadata rather than to select between options.

### Cards

`WW.cardDecoration` is the canonical card style, reused directly wherever possible
rather than re-declared:
```dart
BoxDecoration(
  color: WW.card,               // #FFFFFF
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: WW.border, width: 0.5),
  boxShadow: WW.shadow,
)
```
Hairline border (0.5px) + soft tinted shadow + white fill + 16px radius = the app's one
consistent "elevated surface" language. Some cards deviate deliberately for visual
distinction — e.g. schedule day cards add a 4px colored left "strip" (`Container(width: 4, color: _stripColor)`) whose color encodes status (teal=completed, primary/lavender=today, light grey=rest, border-grey=upcoming) — a status-by-color-strip pattern worth replicating for any "list of dated/stateful items" UI on the website/admin side.

### Dialogs

Every `AlertDialog` in the app shares one shape:
```dart
AlertDialog(
  backgroundColor: WW.card,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  title: Text(..., style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: WW.text)),
  content: Text(..., style: TextStyle(fontSize: 14, color: WW.textSec)),
  actions: [
    TextButton(child: Text('Cancel', style: TextStyle(color: WW.textSec))),
    TextButton(child: Text(<confirm label>, style: TextStyle(color: WW.primary /* or #EF4444 if destructive */, fontWeight: FontWeight.w700))),
  ],
)
```
Two plain `TextButton`s (never filled buttons inside a dialog), Cancel always muted/
`textSec`, confirm always bold + colored (primary normally, red for a destructive
confirm like "Stop Tracking"/"Restart").

### Bottom sheets / modals

Every `showModalBottomSheet` shares:
```dart
showModalBottomSheet(
  backgroundColor: WW.card,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
  isScrollControlled: true,
)
```
Content convention inside the sheet: a small centered drag-handle bar first
(`36×4px` (notifications/calendar sheets) or `32×4px` (compress sheet), `WW.border`
fill, `circular(2)`), then a title row (17px/w800/`WW.primaryDark`, often with a close
`X` icon on the right for sheets that aren't dismiss-by-swipe-only), then content.

### Icon badges (streaks, rest-days, achievement tiles)

Two recurring circular/squircle badge patterns:

1. **Small circular icon badge** (~36–40px) — solid brand-color fill (`WW.primary` for
   notification-type icons, `WW.elevated` for neutral avatar-style badges), white or
   colored icon centered, sometimes with a small dot/status overlay positioned at the
   top-right corner via `Stack`/`Positioned` (unread dot, streak indicator). E.g.
   `_NotificationIcon` in `home_screen.dart`.
2. **Squircle achievement/badge tile** (56–72px) — `borderRadius: size * 0.28` (a
   proportional squircle, not a fixed radius), tinted background (`WW.chipBg` when
   earned), image or icon centered. **Locked state** = same shape, `_kLockedBg`
   (`#F2F2F7`, an off-white not in the `WW` token set) background + `WW.border` outline
   + the icon/image desaturated to greyscale and dropped to 35% opacity + a small
   translucent-black circular lock-icon overlay centered on top. This
   earned-vs-locked treatment (full color vs. desaturated+dimmed+locked) is the app's
   one formalized "achievement/gamification" visual pattern — worth replicating
   exactly if the website ever needs to show badges/achievements marketing-side.

The small rest-day badge in Plan Schedule (18×18px, `WW.chipBg` bg, `WW.border`-colored
moon icon) is the same "small circular/squircle badge" idea scaled down for an inline
context rather than a grid tile.

### Banners / disclaimers

Two distinct banner styles observed, both full-width, not card-elevated (no shadow, no
independent card):

1. **Warning/alert banner** (missed-session banner) — light amber tint background
   (`#FEF3C7`), amber border (`#F59E0B` @ 40% alpha), amber icon, dark-amber text
   (`#92400E`/`#B45309`), 14px radius, includes an inline action button in solid
   amber. This is the app's only "you should act on this" banner style.
2. **Informational/persistent banner** (WiseCoach context banner, disclaimer strip) —
   no border, no radius (edge-to-edge or near-edge-to-edge), tinted flat background
   (`WW.lavender` @ 12% alpha for the context banner; plain `WW.card` for the
   always-visible medical disclaimer strip above the chat input), small `textSec`-toned
   text (10.5–11.5px). Purely informational, never actionable, sits statically above/
   below primary content rather than being dismissible.

### Chat bubbles (WiseCoach)

- Assistant/"coach" bubble: `WW.card` background + `WW.border` hairline, left-aligned,
  paired with a 28px circular lavender avatar (custom 4-point sparkle icon, not a
  Material icon) to its left.
- User bubble: solid `WW.primary` fill, white text, right-aligned, no avatar.
- Both share the same asymmetric corner treatment — 16px on three corners, 4px on the
  corner nearest the "tail" side (bottom-left for coach, bottom-right for user) — the
  classic chat-bubble "pointer" effect done via `BorderRadius.only(...)` rather than an
  actual pointer/tail shape.
- Timestamp: 10px `WW.textSec`, below the bubble, indented to align under the bubble
  (not under the avatar) for coach messages.

### Input fields

Chat text input (`coach_screen.dart`'s message box) — the representative text-input
pattern in this app:
```dart
Container(
  height: 40,
  decoration: BoxDecoration(
    color: WW.bg,                              // NOT WW.card — sits one tone darker
    borderRadius: BorderRadius.circular(20),    // fully pill-shaped
    border: Border.all(color: WW.border, width: 1.5),
  ),
  child: TextField(decoration: InputDecoration(border: InputBorder.none, ...)),
)
```
Pill-shaped (20px radius on a 40px-tall field), sits on `WW.bg` (not white) so it
recesses slightly against its `WW.card` toolbar container, `1.5px` `WW.border` outline
— no focus-color change observed (no visible "border turns primary-purple on focus"
behavior in this file).

### Empty states / illustrations

**Confirmed: no illustration assets exist anywhere in this Flutter app** (verified via
a project-wide asset search — no SVGs, no illustration image files; `pubspec.yaml`'s
`assets:` section only declares `.env`). Every empty state in the sampled screens is
plain centered text in `WW.textSec`, e.g. `"No friends yet — add some!"`,
`"Add friends to see the leaderboard"`, `"No notifications yet"` — no icon, no
illustration, no custom empty-state widget. **Do not invent or assume an illustration
system exists** when redesigning the website/admin — if the new project wants
illustrations, that's a net-new decision, not something to "match" from this app.

---

## 5. Tone & personality

WiseWorkout reads as **clean and minimal-color-per-screen**, with one dominant accent
(`WW.primary`, a mid-saturation blue-purple) doing almost all of the "this is
interactive/important" signaling, rather than many competing accent colors. Most of
any given screen is neutral — white cards, pale lavender-white background, dark-grey-
purple text — and color is spent deliberately: purple for the primary action and
brand identity, teal for "good/complete," amber/gold for "streak/urgency/warning,"
red reserved strictly for destructive/negative actions. Nothing in the sampled screens
uses more than 2–3 colors at once outside of these consistent semantic roles.

Shapes are soft and rounded throughout (nothing has a hard 0px corner), shadows are
extremely subtle (a 6%-opacity tinted glow, not a drop shadow), and borders are
hairline-thin (0.5px is the most common card border weight) — the overall effect is
closer to "quiet, friendly, slightly playful fitness app" than "clinical dashboard."
Small emoji are used unironically inline in copy in a few places (☕ for break mode, ⚡
for compressed sessions, 💪/🌟 in snackbar confirmations) — a deliberate warmth choice,
not an oversight. Weight (not color-lightening) is the primary tool for establishing
text hierarchy, which gives even the smallest captions a slightly more confident,
"designed" feel than a typical grey-and-faded caption treatment.

---

## 6. Explicit non-goals / things NOT to copy

These are known inconsistencies in the current app — a redesign should treat them as
bugs to *improve on*, not as intentional design language to replicate:

1. **Hardcoded hex literals instead of tokens.** `#EF4444` (red), `#F59E0B` (amber, also
   duplicated as `WW.gold`), `#22C55E`/`#DCFCE7` (green), `#10B981`/`#059669` (online-
   status green), and `#E8EAF8` (a near-duplicate of `WW.border`) are all used as raw
   `Color(0x...)` literals directly in screen files instead of being defined once in
   `WW`. AGENT.md's own rule #1 ("never hardcode colors") is violated by the very
   codebase it governs. **Recommendation for the new project: formalize these as real
   named tokens** (e.g. `danger`, `warning`, `success`, `divider`) — don't replicate the
   inconsistency of leaving them as scattered literals.
2. **No formal destructive/success/warning button variants** — as noted in Section 4,
   destructive actions are just colored text, not a button component. This works in a
   small mobile app but is thin for a marketing site or admin dashboard, which will
   likely need real button variants (e.g. a filled or outlined red button for delete
   actions in an admin table) — treat the *color* (`#EF4444`) as canon, not the
   "always just plain text, never a button" *pattern*.
3. **No dark mode.** Every value in this document is a light-theme value; there's no
   evidence of a dark palette anywhere in `WW` or `ThemeData`.
4. **No focus/hover states observed** (unsurprising for a touch-first mobile app) — a
   website redesign will need to design its own hover/focus treatment for buttons,
   links, and inputs; nothing here should be assumed to define that.
5. **`WW.lightBlue` and `WW.lightYellow`** are declared tokens with no observed usage in
   the sampled screens — don't assume they carry specific established meaning; treat
   them as available-but-unproven accent colors, not load-bearing brand colors.
6. **No illustration/empty-state visual system** — see Section 4's Empty States note.
   Don't retroactively invent one and call it "matching the app."
