# WiseWorkout — Living Handoff Document
**Last updated:** 16 June 2026  
**App:** WiseWorkout (FYP-26-S2-15)  
**Developer:** Monica Cheng (solo)  
**Demo date:** 20 June 2026 (physical iPhone, assessor demo)  
**Final submission:** 15 August 2026  
**GitHub:** https://github.com/Monica-Cheng/FYP-26-S2-15_code  
**Local path:** /Users/monicacheng/Documents/FYP-26-S2-15_code  

---

## HOW TO USE THIS FILE
- This file lives in the project root alongside `AGENT.md` and `RULES.md`
- **Update it at the end of every coding session** — what you finished, what's in progress, what's next
- When starting a new Claude chat, attach this file AND the original `__PROJECT_HANDOFF_DOCUMENT.docx`
- This file tracks *changes* and *progress*; the docx has the full static context (stack, schema, architecture)

---

## QUICK CONTEXT (for new Claude sessions)

**What is this?** Flutter app (iOS + Android). AI-powered fitness tracker. Firebase backend. OpenAI for WiseCoach chat + post-session AI summaries.

**Stack in one line:** Flutter 3.44.0 + Firebase (Auth, Firestore) + OpenAI gpt-4o-mini + GoRouter + Riverpod (minimal)

**Key rules Claude must follow:**
- Never hardcode hex colors — always use `WW.primary`, `WW.surface` etc from `app_theme.dart`
- Never call Firebase directly in widgets — always go through `services/` (exception: missed_checkin_screen uses FirebaseFirestore directly for one write — acceptable)
- Navigation: `context.go()` for tabs, `context.push()` for gym session (needs back)
- Never use Riverpod except for `routerProvider` — all other state is `StatefulWidget`
- Never modify: `firebase_options.dart`, `app_theme.dart`, `constants.dart`
- `android/` and `ios/` folders: only modify if explicitly needed (e.g. HealthKit permissions)
- Always read `AGENT.md` and `RULES.md` at the start of every Claude Code prompt

**Run commands:**
```bash
flutter run -d emulator-5554        # Android (daily dev)
flutter run -d 00008140-000D04CC0E61801C  # Real iPhone (demo day)
```

---

## ⚠️ CRITICAL DEADLINES & ALERTS

| Alert | Date | Status |
|-------|------|--------|
| **Firestore rules EXPIRE** | 25 June 2026 | ❌ Must update in Firebase Console before this date |
| **Week 11 Assessor Demo** | 20 June 2026 | 🔴 4 days away — demo on physical iPhone |
| **Final Submission** | 15 August 2026 | 🟡 Ongoing |

---

## ASSESSOR REQUIREMENTS — STATUS

These are the 5 required features the assessor will check:

| # | Requirement | Status | Notes |
|---|-------------|--------|-------|
| 1 | Collect exercise data from phone sensors or wearables | 🔴 NOT DONE | Need Apple HealthKit (iOS) integration. Phone GPS for outdoor cardio also counts. Standalone cardio flow (indoor timer) is next priority. |
| 2 | Estimate exercise effects + provide analysis | 🟡 PARTIAL | Calories calculated via MET ✅. Heart rate not collected (no device). Weight chart not built yet ❌. AI summary exists ✅. |
| 3 | Supply fitness advice + schedule fitness plan | 🟡 PARTIAL | Plan Match ✅. Build Routine ✅. WiseCoach chat ✅. Weight loss goal tracking/chart missing ❌. |
| 4 | Remind user to exercise or take a break | 🟡 PARTIAL | Missed workout check-in screen ✅. Local notifications NOT built yet ❌. |
| 5 | Connect with social media + competitions | 🔴 NOT DONE | Club tab all hardcoded. Share button not built. Need share_plus on post-session summary. |

---

## CURRENT SPRINT STATUS — Sprint 5 (16 June 2026)

### ✅ Completed Today (16 June 2026) — MASSIVE SESSION

**Plans Tab — Full Rework:**
- Per-plan progress storage migrated from user doc to `users/{uid}/planProgress/{planId}` subcollection — fixes compress/completion state bleeding across plans
- Edit Routine pre-fill fixed — changes reflect immediately without restart (stream-based)
- Type cast crash fixed for custom plan sessions (`List<dynamic>` not subtype of `num?`)
- Custom plans no longer appear in Explore tab
- `fromExplore` flag injected when navigating from Explore — plan detail shows different layout
- "Save to My Plans" button added to Explore plan detail
- All Plans filters to only show saved plans + custom plans
- Start button on every non-rest day card in saved plan detail
- `overridePlanId` + `overrideDayIndex` on user doc — Start button loads correct plan/day
- Coach card ("Designed with Coach X") shows on plan detail when `designedBy` field exists in Firestore
- Discovery info (Best For, Experience Level, Plan Overview, Equipment, Goals) hidden for saved plans
- Health profile purple banner removed from all plan detail screens
- Custom plan hero shows "Custom Routine" chip only — no metadata chips, no WiseWorkout Certified
- Redundant Track buttons removed — top bar Track for saved plans, no duplicate bottom bar
- All Plans list refreshes immediately after returning from plan detail

**Build Routine Screen:**
- "+ Add Cardio" button now opens bottom sheet with Run/Walk/Cycle picker + CupertinoPicker duration (1-120 min)
- Cardio blocks added with `isCardio: true`, `cardioActivity`, `cardioMinutes` fields
- Cardio exercise cards show activity icon + duration only — no SET/KG/REPS columns, no rest timer
- Three-dot menu now uses Flutter Overlay system — floats above ListView, no content push
- Day tab cap removed — unlimited days (was capped at 7)
- 5 cardio machine exercises added to exercise library under Cardio filter: Treadmill Run, Stationary Bike, Rowing Machine, Elliptical, Stair Climber

**Plan Schedule Screen:**
- "Restart from Day 1" button added — shows confirmation dialog, resets `planProgress/{planId}`, jumps to Week 1
- Week grouping already existed (horizontal pill selector) — verified working

**Missed Workout Check-in:**
- New screen: `lib/screens/home/missed_checkin_screen.dart`
- New route: `/missed-checkin` in router.dart
- Home screen detects missed session on load — shows amber banner "Missed yesterday's session"
- Banner only shows once per missed day (checked via `missedSessions/{date}` doc existence)
- 5 reason cards: Too busy, Not feeling well, Injured, Needed rest, Just skipped
- Logs to `users/{uid}/missedSessions/{date}` in Firestore
- "Change reason" link on each card in Check-ins tab

**Progress Tab:**
- New "Check-ins" 4th sub-tab showing missed session log
- Cards show: reason icon+color, label, formatted date, Day N chip, "Change reason" link
- Tab row scrolls horizontally — no overflow

### 🔨 Next Priority (must do before demo — June 20)

1. **Standalone cardio flow** — S-20 (setup) → S-22 (indoor timer) → S-23 (post-cardio summary). Satisfies Requirement 1. Wireframes exist at S-20, S-21, S-22, S-22b, S-23 HTML files. Indoor timer first, GPS outdoor is placeholder.

2. **Weight logging + chart** in Progress tab — user logs daily weight, line chart shows progression toward goal weight. Satisfies Requirements 2 and 3.

3. **Share button** on post-session summary screen — uses `share_plus` package. Shares text summary to any platform via native share sheet. Satisfies Requirement 5.

4. **Apple HealthKit integration** — reads heart rate, steps, calories from Apple Health on iOS. Requires modifying `ios/Runner/Info.plist` and `ios/Runner/Runner.entitlements`. Uses `health` Flutter package. Satisfies Requirement 1 properly.

5. **Local notifications** for workout reminders — uses `flutter_local_notifications`. User sets preferred time in Settings → daily notification fires. Satisfies Requirement 4.

6. **Demo flow test** on physical iPhone (Device ID: `00008140-000D04CC0E61801C`)

### ❌ Not Started (deferred post-demo)

- GPS outdoor cardio (needs geolocator, flutter_map, OpenStreetMap)
- Mixed gym+cardio session summary (cardio blocks within gym session)
- Apple Watch / Garmin / Samsung direct wearable connection
- Push notifications via Firebase Cloud Functions (server-side)
- Personal bests detection
- Badge award system
- Club tab real data (currently all hardcoded)
- Month/Year charts (only weekly works)
- Weekly XP reset (needs Cloud Function)
- Missed workout check-in actions: actually navigate to compress/break mode (currently just snackbar advice)
- Edit button hidden for non-custom plans (Explore/Generated plans still show Edit)
- "Designed with" coach card on Explore plan list cards (only shows on detail, not list)
- Plan Match — no origin field, no save-without-track flow
- Restart Plan button (exists in Plan Schedule for tracked plan ✅)
- Run plan week structure display
- Admin dashboard (separate React project)

---

## FIRESTORE SCHEMA (current)

```
users/{uid}
  displayName, email, trackedPlanId, trackedPlanName
  overridePlanId, overrideDayIndex  ← temporary, cleared after use
  savedPlanIds: []  ← array of saved Explore plan IDs
  
users/{uid}/planProgress/{planId}
  currentDayIndex, lastCompletedDate, lastCompletedDayIndex
  compressedDays: [], breakModeActive, breakStartDate, breakEndDate
  breakDays, trackingStartDate, overrideDayIndex

users/{uid}/customRoutines/{id}
  name, sessions, isCustom, createdAt

users/{uid}/missedSessions/{date}  ← date = yyyy-MM-dd of missed day
  reason, planId, dayIndex, date, timestamp

plans/{planId}
  name, level, type, daysPerWeek, durationWeeks, description
  isCustom, createdBy, sessions: []
  designedBy: { name, title, credential, quote }  ← optional, Explore plans only

sessions/{sessionId}  ← completed workout sessions
  planId, dayIndex, exercises, totalVolume, calories, duration
  wiseCoachSummary, timestamp
```

---

## KNOWN BUGS (open)

| # | File | Symptom | Decision |
|---|------|---------|----------|
| 3 | `plan_schedule_screen.dart` | Empty day cards when plan has no sessions array | Fix later |
| 4 | `progress_screen.dart` | Month/Year filter shows same weekly data | Fix later |
| 5 | `gym_session_screen.dart` | Cardio blocks in gym session show SET/KG/REPS (isCardio not handled in session screen) | Fix after cardio flow built |
| 6 | Various | `withOpacity()` deprecated warnings | Ignore |
| 8 | `home_screen.dart` | Weight stored as "30kg" string → defaults to 70kg for MET | Fix later |

---

## DEMO FLOW (Week 11 — 20 June 2026)
Must demo on **physical iPhone via USB**. Device ID: `00008140-000D04CC0E61801C`

Suggested order:
1. Register → full onboarding → home
2. Plans → Explore → browse → save a plan → view saved plan detail with Start buttons
3. Plans → Plan Match → get AI recommendation → Track Plan
4. Plans → Build → create custom routine with gym + cardio exercises
5. Home → Start Workout → log sets → finish → AI summary → Share
6. Plans → Plan Schedule → Compress → Break Mode → Restart
7. Home → missed session banner → log reason → Progress → Check-ins tab
8. Coach tab → WiseCoach chat → Find a Professional
9. Progress tab → Charts → Activities → XP History → Check-ins
10. Profile → Edit Profile → Settings → Health Profile

---

## SESSION LOG

### Session — 16 June 2026 (LONG SESSION)
- **What we did:** Massive plans tab rework, build routine improvements, missed workout check-in system, progress tab check-ins log. See "Completed Today" above for full list.
- **Files touched:** `firestore_service.dart`, `explore_screen.dart`, `plans_screen.dart`, `plan_detail_screen.dart`, `gym_session_screen.dart`, `home_screen.dart`, `plan_schedule_screen.dart`, `build_routine_screen.dart`, `progress_screen.dart`, `router.dart`
- **New files created:** `lib/screens/home/missed_checkin_screen.dart`
- **What's next:** Standalone cardio flow (S-20 → S-22 → S-23), weight logging chart, share button, HealthKit
- **Blockers:** Firestore rules expire June 25 — must update before then

### Session — 15 June 2026
- **What we did:** Read handoff doc, set up this living HANDOFF.md file.
- **Files touched:** None (context session)
- **What's next:** Edit Routine pre-fill fix

---

## CLAUDE CODE PROMPT TEMPLATE
Always use this structure when sending to Claude Code:

```
Read AGENT.md and RULES.md first. Then read these files:
- lib/core/app_theme.dart
- lib/core/router.dart
- lib/services/firestore_service.dart
- [other relevant files]

Task: [clear task description]

Requirements:
- [requirement 1]
- [requirement 2]

Rules:
- Use WW colors only — never hardcode hex
- Do NOT use Riverpod
- Do NOT create any new files except [file name if needed]
- Only modify: [exact list of files]
- Do not modify any other files
```

## CARDIO FLOW — WIREFRAME REFERENCE
HTML wireframes exist for the cardio flow:
- `S-20-Cardio-Setup.html` — activity picker (Run/Walk/Cycle), Indoor/Outdoor toggle, optional goal, countdown
- `S-21-Live-Outdoor-GPS-Cardio.html` — live GPS map, pace, distance (PLACEHOLDER for now)
- `S-22-Indoor-Cardio-Logging.html` — indoor timer, MET-based calories, optional HR zones
- `S-22b-Post-Indoor-Save.html` — save confirmation with duration + calories
- `S-23-Post-Cardio-Summary.html` — full post-cardio summary with stats, optional route map, WiseCoach AI

**Decision:** Build indoor flow first (S-20 → S-22 → S-23). Outdoor GPS is placeholder showing "GPS coming soon" with basic timer fallback.