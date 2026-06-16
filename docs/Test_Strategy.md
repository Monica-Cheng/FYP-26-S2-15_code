# WiseWorkout Manual-First Test Strategy

**Generated:** 2026-06-12  
**Basis:** Derived from the repository implementation audit in `docs/Test_Case.md`  
**Scope:** Only features visible in the current codebase are included. No test outcomes are assumed.

## Test Type Legend

- `Manual`: Primary execution should be by human tester on device/simulator
- `Integration`: Best validated with Firebase-backed flows or seeded test data
- `Automated Candidate`: Good future candidate for Flutter widget/unit/integration testing

---

## 1. Authentication

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| AUTH-01 | Email/password login with valid credentials | Manual, Integration, Automated Candidate | Registered Firebase user exists | 1. Launch app. 2. Open Login screen. 3. Enter valid email and password. 4. Tap Log In. | User is authenticated and navigated into the app home flow. | To be tested | Pending | Good future Flutter integration test with Firebase Auth emulator. |
| AUTH-02 | Email/password login with invalid credentials | Manual, Integration, Automated Candidate | App is on Login screen | 1. Enter invalid email/password combination. 2. Tap Log In. | User remains on Login screen and friendly error message is shown. | To be tested | Pending | Maps Firebase auth errors in `login_screen.dart`. |
| AUTH-03 | Google sign-in entry flow | Manual, Integration | Google Sign-In configured for test environment | 1. Open Login or Register screen. 2. Tap Google sign-in. 3. Complete Google account selection. | User is authenticated and routed into onboarding or home depending on profile state. | To be tested | Pending | Requires platform and Firebase Google Sign-In setup. |
| AUTH-04 | Email/password registration | Manual, Integration, Automated Candidate | No existing account for test email | 1. Open Register screen. 2. Enter display name, email, password, confirm password. 3. Tap Sign Up. | Account is created and user is routed to onboarding step 1. | To be tested | Pending | Validation and navigation behavior are strong automation candidates. |
| AUTH-05 | Registration form validation | Manual, Automated Candidate | App is on Register screen | 1. Leave fields empty or enter mismatched passwords. 2. Attempt sign up. | Inline validation errors are shown and registration does not proceed. | To be tested | Pending | Pure UI/state validation, suitable for widget tests. |
| AUTH-06 | Forgot password email submission | Manual, Integration, Automated Candidate | Existing Firebase user email available | 1. Open Forgot Password screen. 2. Enter registered email. 3. Tap send reset email. | Success state is shown after Firebase reset email request succeeds. | To be tested | Pending | Can be emulator-backed for future automation. |
| AUTH-07 | Logout from settings | Manual, Integration, Automated Candidate | User is logged in | 1. Open Settings. 2. Tap Log Out. 3. Confirm. | User is signed out and redirected to Login screen. | To be tested | Pending | Can be tested with fake auth state in future. |

---

## 2. Onboarding

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| ONB-01 | Walkthrough to authentication flow | Manual, Automated Candidate | Fresh app launch while logged out | 1. Launch app. 2. Wait for splash. 3. Continue through walkthrough entry. | Logged-out user is routed to walkthrough and can continue into auth screens. | To be tested | Pending | Splash routing is suitable for automated navigation tests. |
| ONB-02 | Onboarding step 1 saves body profile | Manual, Integration, Automated Candidate | User is authenticated and not yet onboarded | 1. Complete Step 1 connection cards. 2. Fill display name, DOB, biological sex, height, weight. 3. Tap next. | Data is saved to Firestore user profile and app moves to onboarding step 2. | To be tested | Pending | Health connection cards are placeholder UI; body profile persistence is real. |
| ONB-03 | Onboarding step 1 health connection cards | Manual | User is on Onboarding Step 1 | 1. Tap Apple Health, Google Health Connect, and wearable connect cards. | Each card shows placeholder setup feedback and marks connection locally so user can proceed. | To be tested | Pending | Real HealthKit / Health Connect integration is not implemented. |
| ONB-04 | Onboarding step 2 goals survey progression | Manual, Integration, Automated Candidate | User is on Onboarding Step 2 | 1. Answer each survey question. 2. Continue through all steps. | Survey selections are saved and app navigates to onboarding step 3. | To be tested | Pending | Strong candidate for widget test flow coverage. |
| ONB-05 | Onboarding step 3 permission preference save | Manual, Integration, Automated Candidate | User is on Onboarding Step 3 | 1. Tap enable on notifications/location/motion cards or skip as needed. 2. Complete step. | Preference flags are saved to Firestore and onboarding finishes to Home. | To be tested | Pending | Code stores flags only; no real OS permission APIs are called. |
| ONB-06 | Onboarding completion routing | Manual, Integration, Automated Candidate | User has completed onboarding once | 1. Relaunch app while logged in. | Splash routes user directly to Home instead of onboarding. | To be tested | Pending | Depends on `onboardingComplete` profile flag. |

---

## 3. Home Dashboard

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| HOME-01 | Authenticated user lands on home shell | Manual, Integration, Automated Candidate | User is authenticated and onboarded | 1. Launch app. | App opens main 5-tab shell with Home tab selected. | To be tested | Pending | Good future integration test candidate. |
| HOME-02 | Home dashboard loads user profile summary | Manual, Integration | User profile exists in Firestore | 1. Open Home tab. 2. Observe greeting and dashboard cards. | Greeting, display name, streak, calorie goal state, and week session indicators load from Firestore. | To be tested | Pending | Requires seeded Firestore data. |
| HOME-03 | Today’s tracked session preview | Manual, Integration | User has a tracked plan with sessions | 1. Open Home tab. | Today’s session card reflects current tracked plan day or rest day state. | To be tested | Pending | Depends on `trackedPlanId`, `currentDayIndex`, and plan data. |
| HOME-04 | Bottom navigation between 5 tabs | Manual, Automated Candidate | User is logged in | 1. Tap Home, Plans, Coach, Club, Progress tabs in sequence. | Each tab switches correctly and preserves shell navigation behavior. | To be tested | Pending | Strong widget/integration candidate. |
| HOME-05 | Manual activity log entry point from FAB | Manual, Automated Candidate | User is on Home tab | 1. Tap floating action button. | Manual Activity Log screen opens. | To be tested | Pending | Straightforward navigation test candidate. |

---

## 4. Plan Management

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| PLAN-01 | Plans hub loads plan list | Manual, Integration | Firestore `plans` collection exists or fallback path available | 1. Open Plans tab. | Plans hub loads, showing tracked plan section and available plans. | To be tested | Pending | Supports Firestore or fallback plans. |
| PLAN-02 | Track a plan from Plan Detail | Manual, Integration | User is logged in and a plan can be opened from list/explore | 1. Open a plan detail screen. 2. Tap Track Plan. 3. Confirm. | Selected plan becomes tracked and user profile is updated. | To be tested | Pending | Good integration test with seeded plan data. |
| PLAN-03 | Untrack current plan | Manual, Integration | User currently has tracked plan | 1. Open tracked plan detail or plan schedule. 2. Choose untrack/stop tracking. 3. Confirm. | Tracked plan fields are cleared from user profile. | To be tested | Pending | Should also affect Home/Plans state on reload. |
| PLAN-04 | Explore screen filters and search | Manual, Automated Candidate | Explore screen accessible | 1. Open Explore. 2. Search by plan name/goal/coach. 3. Apply level/goal/sport filters. | Visible plan list updates according to entered search and selected filters. | To be tested | Pending | Good widget test candidate with fake plan list. |
| PLAN-05 | Plan Match recommendation flow | Manual, Integration, Automated Candidate | Firestore has plans with match fields or test data available | 1. Open Plan Match. 2. Select goal, sport, level, equipment, days. 3. Generate result. | Best matching plan is shown and preferences are saved to user profile. | To be tested | Pending | Matching algorithm is a strong future unit test candidate. |
| PLAN-06 | Track matched plan from Plan Match result | Manual, Integration | Plan Match result is displayed | 1. Tap Track on matched plan result. | Plan becomes tracked and user returns to home flow. | To be tested | Pending | Depends on `trackPlan()` path. |
| PLAN-07 | Custom routine creation | Manual, Integration | User is logged in | 1. Open Build Routine. 2. Add exercises and sets. 3. Name routine. 4. Save. | Routine is saved to Firestore as user custom routine and plan entry. | To be tested | Pending | Strong integration candidate. |
| PLAN-08 | Custom routine editing | Manual, Integration | Existing custom plan is available | 1. Open custom routine in edit mode. 2. Modify exercises/sets/name. 3. Save. | Existing custom plan document is updated. | To be tested | Pending | Tests `updateCustomRoutine()`. |
| PLAN-09 | Plan schedule break mode | Manual, Integration | User has tracked plan | 1. Open Plan Schedule. 2. Start break mode. 3. Confirm. | Break fields are saved and schedule reflects break state. | To be tested | Pending | Good database-backed scenario. |
| PLAN-10 | Plan schedule compress session mode | Manual, Integration | User has tracked plan with exercises | 1. Open Plan Schedule. 2. Compress a day’s session. | Selected day index is stored in `compressedDays` and compressed state is shown. | To be tested | Pending | Affects gym session loading behavior later. |
| PLAN-11 | Start Cardio CTA placeholder behavior | Manual | Plans tab open | 1. Tap Start Cardio. | Placeholder feedback is shown indicating cardio tracking is coming soon. | To be tested | Pending | Included because feature is partially implemented in visible UI. |

---

## 5. Gym Session Tracking

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| GYM-01 | Load tracked gym session | Manual, Integration | User has a tracked gym plan and current day is not rest day | 1. Open today’s workout from Home or schedule flow. | Gym Session screen loads current session exercises and session name. | To be tested | Pending | Reads tracked plan and current day from Firestore. |
| GYM-02 | Rest day handling | Manual, Integration | User’s current tracked day is marked `isRestDay` | 1. Open today’s workout. | App displays rest-day state instead of active workout logging flow. | To be tested | Pending | Important branch to validate manually. |
| GYM-03 | Set completion and rest timer behavior | Manual, Automated Candidate | Gym session loaded | 1. Mark sets done. 2. Observe rest timer. 3. Pause/resume as needed. | Completed sets update UI correctly and rest timer behavior follows selected rest time. | To be tested | Pending | Timers are a future widget/integration candidate. |
| GYM-04 | Save completed gym session | Manual, Integration | Gym session loaded with at least one completed set | 1. Complete some sets. 2. Finish workout. | Session is saved to Firestore with cleaned exercises, totals, calories, and XP earned. | To be tested | Pending | Core end-to-end integration case. |
| GYM-05 | XP update after gym session | Manual, Integration | Existing profile with known XP value | 1. Finish and save gym session. 2. Check progress/profile data. | User total XP, weekly XP, level, and XP history update accordingly. | To be tested | Pending | Validates `addXpToUser()` and `saveXpEvent()`. |
| GYM-06 | Tracked plan day completion progression | Manual, Integration | User has tracked plan with multiple sessions | 1. Complete today’s gym session. 2. Reopen app on following day or re-enter flow after progression condition. | `lastCompletedDate` is saved and tracked day advances according to implementation. | To be tested | Pending | Requires date-sensitive validation. |
| GYM-07 | Compressed session excludes accessory exercises | Manual, Integration | Current tracked day exists in `compressedDays` | 1. Open gym session for compressed day. | Exercise list excludes accessory-tagged exercises. | To be tested | Pending | Important partial feature interaction test. |
| GYM-08 | Post-session summary screen generation | Manual, Integration | Gym session saved successfully and summary screen opens | 1. Complete a gym session. 2. Observe post-session summary page. | Summary page shows workout stats and begins generating WiseCoach summary. | To be tested | Pending | OpenAI dependency affects completion of summary text. |

---

## 6. Manual Activity Logging

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| MAN-01 | Open Manual Activity Log from home FAB | Manual, Automated Candidate | User is on Home tab | 1. Tap FAB. | Manual Activity Log screen opens. | To be tested | Pending | Navigation candidate for widget test. |
| MAN-02 | Select activity and save manual log | Manual, Integration | User is logged in | 1. Select an activity. 2. Set intensity and duration. 3. Optionally enter distance/notes. 4. Save. | Manual activity session is written to Firestore under user sessions. | To be tested | Pending | Core integration path. |
| MAN-03 | Duration validation | Manual, Automated Candidate | Manual Activity Log open | 1. Try to save with no duration or zero duration. | Save does not proceed and duration validation is shown. | To be tested | Pending | Good widget test candidate. |
| MAN-04 | Estimated calorie calculation display | Manual, Automated Candidate | Manual Activity Log open | 1. Select activity. 2. Change intensity and duration. | Estimated calories update according to input. | To be tested | Pending | Strong pure-logic test candidate. |
| MAN-05 | Manual activity appears in Progress activities list | Manual, Integration | A manual activity has been saved | 1. Save manual activity. 2. Open Progress > Activities. | Manual activity appears in recent activity list with manual-specific subtitle. | To be tested | Pending | Good end-to-end verification case. |

---

## 7. WiseCoach AI

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| AI-01 | WiseCoach screen initial state | Manual, Automated Candidate | User is logged in | 1. Open Coach tab. | Initial coach greeting and quick reply options are shown. | To be tested | Pending | Easy widget test candidate. |
| AI-02 | Send chat message to WiseCoach | Manual, Integration | Valid `OPENAI_API_KEY` available in `.env` | 1. Open Coach. 2. Enter question. 3. Send. | User message appears, typing/loading state occurs, and AI response is displayed on success. | To be tested | Pending | External API dependency. |
| AI-03 | WiseCoach error handling on API failure | Manual | OpenAI API unavailable or invalid key in test environment | 1. Send a message while API is unavailable. | Friendly fallback error message appears in chat. | To be tested | Pending | Important resilience test. |
| AI-04 | Quick reply prompt sends correctly | Manual, Automated Candidate | Coach screen open | 1. Tap a quick reply chip. | Prompt is inserted/sent and WiseCoach response flow starts. | To be tested | Pending | Good future widget test. |
| AI-05 | Post-session WiseCoach summary generation | Manual, Integration | Completed gym session reaches summary screen and OpenAI key is valid | 1. Finish gym session. 2. Wait for summary generation. | AI-generated short summary appears on post-session summary screen. | To be tested | Pending | External API dependency. |

---

## 8. Progress Tracking

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| PROG-01 | Progress screen loads charts | Manual, Integration | User has session history in Firestore | 1. Open Progress tab. | Weekly calories, volume, and summary statistics load correctly. | To be tested | Pending | Requires seeded session data. |
| PROG-02 | Progress activities list loads recent sessions | Manual, Integration | User has gym and/or manual sessions | 1. Open Progress > Activities. | Most recent sessions are listed from Firestore. | To be tested | Pending | `getRecentSessions()` driven. |
| PROG-03 | Activity type filter in Progress | Manual, Automated Candidate | Mixed session history exists | 1. Open Activities subtab. 2. Switch filters between All, Gym, Cardio, Manual. | Activity list updates to match selected filter. | To be tested | Pending | Good widget test candidate with fake data. |
| PROG-04 | XP history list loads | Manual, Integration | User has XP events | 1. Open Progress > XP History. | XP events display in descending recent-first order. | To be tested | Pending | Tests Firestore xpEvents read path. |
| PROG-05 | Activity detail for gym session | Manual, Integration | At least one gym session exists | 1. Open a gym activity from Progress. | Detail page shows title, date, stats, exercise breakdown, and XP-related sections. | To be tested | Pending | Good manual verification of mapped session data. |
| PROG-06 | Activity detail for manual session | Manual, Integration | At least one manual session exists | 1. Open a manual activity from Progress. | Detail page shows manual activity data, notes section, and manual-specific fields. | To be tested | Pending | Delete action is placeholder-only. |
| PROG-07 | Home streak reflects session history | Manual, Integration | User has consecutive-day session data | 1. Open Home after seeded session history exists. | Streak count matches current streak calculation rules. | To be tested | Pending | Good future unit test target around `calculateStreak()`. |

---

## 9. Profile and Settings

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| PROF-01 | Profile screen loads user identity and XP | Manual, Integration | Logged-in user profile exists | 1. Open Profile screen. | Display name, hometown/bio if present, level, and total XP are shown. | To be tested | Pending | Reads user profile from Firestore. |
| PROF-02 | Edit profile save | Manual, Integration, Automated Candidate | User is logged in | 1. Open Edit Profile. 2. Change name/username/hometown/bio. 3. Save. | Updated values persist and screen closes after successful save. | To be tested | Pending | Good integration/widget candidate. |
| PROF-03 | Edit profile validation for empty display name | Manual, Automated Candidate | Edit Profile screen open | 1. Clear display name. 2. Attempt save. | Save is blocked and validation error appears. | To be tested | Pending | Pure UI validation candidate. |
| PROF-04 | Settings notification toggles persist | Manual, Integration | Logged-in user and Settings screen accessible | 1. Open Settings. 2. Toggle push/workout/streak/WiseCoach switches. 3. Reopen Settings. | Selected values persist from Firestore. | To be tested | Pending | No actual push delivery; only preference persistence. |
| PROF-05 | Health profile body metrics save | Manual, Integration | Health Profile screen accessible | 1. Edit display name, DOB, height, weight, biological sex. 2. Save. | Updated body metrics are saved and success feedback appears. | To be tested | Pending | Real persistence path exists. |
| PROF-06 | Health profile calorie goal save | Manual, Integration | Health Profile screen accessible | 1. Edit calorie goal values. 2. Save. | Calorie goal fields persist to user profile. | To be tested | Pending | Important for home calorie ring behavior. |
| PROF-07 | Placeholder settings actions | Manual | Settings/Profile screens accessible | 1. Tap change email, devices, units, photo upload, or similar placeholder actions. | Placeholder feedback is shown and app does not crash. | To be tested | Pending | Included because these are partially implemented UI actions. |

---

## 10. Club / Social Features

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| CLUB-01 | Club screen loads subtabs | Manual, Automated Candidate | User is logged in | 1. Open Club tab. 2. Switch between Leaderboard, Challenges, Friends. | All three subtabs render correctly. | To be tested | Pending | Data is mostly hardcoded but UI is present. |
| CLUB-02 | Leaderboard display | Manual | Club screen open | 1. View Leaderboard tab. | Hardcoded leaderboard entries display without runtime issues. | To be tested | Pending | Presentation-only partial feature. |
| CLUB-03 | Challenges display | Manual | Club screen open | 1. Open Challenges subtab. | Active/discover challenge cards display correctly. | To be tested | Pending | Hardcoded UI content. |
| CLUB-04 | Friends display | Manual | Club screen open | 1. Open Friends subtab. | Hardcoded friend list displays correctly. | To be tested | Pending | Presentation-only partial feature. |
| CLUB-05 | Placeholder social actions | Manual | Club screen open | 1. Tap Add Friend, Create Challenge, Join Challenge, Search. | Placeholder feedback is shown and app remains stable. | To be tested | Pending | Important partial-implementation validation. |

---

## 11. Business Partner / Find Professional

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| BP-01 | Find Professional screen opens from Coach | Manual, Automated Candidate | User is logged in | 1. Open Coach tab. 2. Tap Find Professional. | Find Professional screen opens. | To be tested | Pending | Straightforward navigation candidate. |
| BP-02 | Load approved visible business partners | Manual, Integration | Firestore contains `businessPartners` documents with `isApproved` and `isVisible` true | 1. Open Find Professional. | Only approved and visible business partners are listed. | To be tested | Pending | Core Firestore query validation. |
| BP-03 | Filter professionals by type | Manual, Automated Candidate | Professional list contains multiple types | 1. Switch filter chips such as Trainer, Running Coach, Physiotherapist, Nutritionist. | List updates to match selected filter. | To be tested | Pending | Good future widget test candidate. |
| BP-04 | Empty state when no professionals available | Manual, Integration | Firestore has no matching `businessPartners` data | 1. Open Find Professional. | Empty-state message is shown. | To be tested | Pending | Useful emulator-seeded scenario. |
| BP-05 | Contact professional via email action | Manual | Professional entry with email exists and device supports mailto handling | 1. Tap contact action for a professional. | Email client opens, or fallback snackbar shows email if launching is unavailable. | To be tested | Pending | Depends on `url_launcher` and device setup. |

---

## 12. Database and Integration

| Test ID | Feature | Test Type | Preconditions | Test Steps | Expected Result | Actual Result | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| DB-01 | User profile document creation/merge on onboarding | Integration, Automated Candidate | Authenticated new user available | 1. Complete onboarding Step 1-3. 2. Inspect resulting Firestore user document. | Profile fields are merged correctly and onboarding flag is stored. | To be tested | Pending | Best executed with Firebase emulator or isolated test project. |
| DB-02 | Plan tracking updates user profile fields | Integration, Automated Candidate | User and trackable plan exist | 1. Track a plan. 2. Inspect user document. | `trackedPlanId`, `trackedPlanName`, `trackingStartDate`, and `currentDayIndex` are updated. | To be tested | Pending | Strong backend integration case. |
| DB-03 | Gym session save writes expected session shape | Integration, Automated Candidate | User has active gym session and can finish workout | 1. Save completed gym session. 2. Inspect `users/{uid}/sessions`. | Gym session document contains expected fields and cleaned exercise structure. | To be tested | Pending | Good candidate for repository/service test harness later. |
| DB-04 | Manual activity save writes expected session shape | Integration, Automated Candidate | User logged in and manual activity saved | 1. Save manual activity. 2. Inspect `users/{uid}/sessions`. | Manual session document contains expected manual activity fields. | To be tested | Pending | Strong integration test candidate. |
| DB-05 | XP event append after gym session save | Integration, Automated Candidate | User has known XP baseline | 1. Save gym session. 2. Inspect `users/{uid}/xpEvents` and profile XP fields. | XP event record is added and profile XP values are updated consistently. | To be tested | Pending | Good future service/integration test. |
| DB-06 | Custom routine save writes both private and discoverable entries | Integration | User logged in | 1. Save new custom routine. 2. Inspect `users/{uid}/customRoutines` and `plans`. | Routine is stored in both locations as implemented. | To be tested | Pending | Important implementation-specific behavior. |
| DB-07 | Business partner query returns only approved visible documents | Integration, Automated Candidate | Seed visible and non-visible partner documents | 1. Open Find Professional or query through app flow. | Only documents meeting query conditions are returned. | To be tested | Pending | Strong emulator-backed integration scenario. |
| DB-08 | OpenAI integration from Coach screen | Integration | Valid API key available in `.env` | 1. Send message in Coach. | Request succeeds and response is rendered in app. | To be tested | Pending | External API dependency; not suitable for deterministic offline automation without mocking. |
| DB-09 | OpenAI integration from post-session summary | Integration | Valid API key available and gym session completed | 1. Complete workout. 2. Wait for summary generation. | Summary request succeeds and text is shown. | To be tested | Pending | External API dependency. |
| DB-10 | Placeholder-only integrations do not falsely invoke native services | Manual | Onboarding step 1 and step 3 accessible | 1. Use health connect cards and permission priming cards. | App stores local/profile flags or shows placeholder messages without requiring real HealthKit, Health Connect, GPS, or notification integrations. | To be tested | Pending | Important because these integrations are only partial in current repo. |

---

## Automation Priorities

The strongest future automated Flutter test candidates from this document are:

1. `AUTH-01`, `AUTH-02`, `AUTH-04`, `AUTH-05`, `AUTH-06`, `AUTH-07`
2. `ONB-01` to `ONB-06`
3. `HOME-01`, `HOME-04`, `HOME-05`
4. `PLAN-04`, `PLAN-05`, `PLAN-07`, `PLAN-08`
5. `GYM-03`, `GYM-04`, `GYM-05`
6. `MAN-03`, `MAN-04`
7. `AI-01`, `AI-04`
8. `PROG-03`, `PROG-07`
9. `PROF-02`, `PROF-03`, `PROF-04`
10. `CLUB-01`
11. `BP-01`, `BP-03`
12. `DB-01` to `DB-07`

These are the best candidates because they are either:

- deterministic UI/state flows,
- Firebase-backed flows that can be emulator-seeded,
- or pure/local business logic that can be unit tested.
