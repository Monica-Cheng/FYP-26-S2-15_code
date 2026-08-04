// lib/screens/home/home_screen.dart
// MainShell — 5-tab shell with IndexedStack + custom bottom nav.
// Tab 0 = Home (_HomeTab), tabs 1-4 = placeholder screens.
// FAB shown only on Home tab; tapping shows SnackBar.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../providers/month_activity_provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/common/month_calendar.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../widgets/session_resume_prompt.dart';
import '../business/coach_dashboard_screen.dart';
import '../plans/plans_screen.dart';
import '../coach/coach_screen.dart';
import '../club/club_screen.dart';
import '../progress/progress_screen.dart';

// ── Main shell ─────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _clubInitialSubtab = 0;
  final _homeTabKey = GlobalKey<_HomeTabState>();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  static const List<_TabItem> _tabItems = [
    _TabItem(label: 'Home', icon: Icons.home_rounded),
    _TabItem(label: 'Plans', icon: Icons.fitness_center_rounded),
    _TabItem(label: 'Coach', icon: Icons.auto_awesome_rounded),
    _TabItem(label: 'Club', icon: Icons.people_rounded),
    _TabItem(label: 'Progress', icon: Icons.bar_chart_rounded),
  ];

  // Not one of the 5 real bottom-nav destinations above (no icon points
  // here, matching the earlier decision to keep the business-coach system
  // out of the shared bottom nav) — only ever reached by _checkCoachLanding()
  // setting _selectedIndex here directly, right after this shell first
  // mounts. Tapping any of the 5 real nav items below always overrides it
  // via _onTabTap, same as switching between any other two tabs.
  static const int _kCoachDashboardIndex = 5;

  List<Widget> get _tabs => [
        _HomeTab(
          key: _homeTabKey,
          onGoToPlans: () => _onTabTap(1),
          onGoToClubFriends: _goToClubFriends,
        ),
        const PlansScreen(),
        const CoachScreen(),
        ClubScreen(initialSubtab: _clubInitialSubtab),
        const ProgressScreen(),
        const CoachDashboardScreen(embedded: true),
      ];

  @override
  void initState() {
    super.initState();
    _checkCoachLanding();
  }

  // Decides the post-login landing tab based on role — this is the single
  // choke point for "coach account feels different immediately after
  // logging in": this shell (Routes.home) is only ever freshly mounted at
  // the start of a session (explicit login, post-onboarding for a brand
  // new account, or splash_screen.dart's silent auto-resume for an
  // already-authenticated user reopening the app) — go_router's default
  // (non-custom-keyed) behavior for this route disposes and recreates
  // HomeScreen on each fresh navigation to it rather than reusing a
  // buried instance, so initState() reliably re-runs each time, not just
  // once per app install. Runs exactly once per mount (initState, not
  // build), so switching tabs afterwards — including tapping Home to
  // reach normal Home content — is never fought or overridden by this
  // check firing again.
  //
  // Deliberately does NOT touch router.dart's pendingCoachRegistration
  // flag/redirect — that one fires (if at all) BEFORE Routes.home is ever
  // reached, redirecting straight to coachRegister instead, so this
  // check simply never runs that cycle. The two mechanisms operate at
  // different layers and can't double-fire against each other.
  Future<void> _checkCoachLanding() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      if (!mounted) return;
      final role = (profile?['role'] as String?) ?? 'user';
      // Approved vs pending both land here — CoachDashboardScreen itself
      // branches on isApproved to show the right state, same as the
      // standalone routed version.
      if (role == 'coach') {
        setState(() => _selectedIndex = _kCoachDashboardIndex);
      }
    } catch (_) {
      // Fails soft — worst case a coach lands on normal Home same as
      // before this feature existed, not a broken shell.
    }
  }

  void _onTabTap(int index) => setState(() => _selectedIndex = index);

  // Switches to the Club tab with its Friends subtab selected — used when
  // tapping a friend-request notification in the bell's bottom sheet.
  void _goToClubFriends() {
    setState(() {
      _selectedIndex = 3;
      _clubInitialSubtab = ClubScreen.kFriendsSubtabIndex;
    });
  }

  void _onFabTap() {
    showQuickAddSheet(context, [
      QuickAddOption(
        icon: Icons.camera_alt_rounded,
        iconColor: WW.lavender,
        iconBg: WW.lavenderBg,
        title: 'Scan Food',
        subtitle: 'Snap a photo for instant calories',
        onTap: () => context
            .push(Routes.nutritionScan)
            .then((_) => _homeTabKey.currentState?._loadUserData()),
      ),
      QuickAddOption(
        icon: Icons.edit_note_rounded,
        iconColor: WW.teal,
        iconBg: WW.tealBg,
        title: 'Describe a Meal',
        subtitle: 'Type what you ate instead',
        onTap: () => context
            .push(Routes.nutritionScan, extra: 'describe')
            .then((_) => _homeTabKey.currentState?._loadUserData()),
      ),
      QuickAddOption(
        icon: Icons.fitness_center_rounded,
        iconColor: WW.gold,
        iconBg: WW.gold.withValues(alpha: 0.14),
        title: 'Log Activity',
        subtitle: 'Manually add a workout or exercise',
        onTap: () => context
            .push(Routes.manualActivityLog)
            .then((_) => _homeTabKey.currentState?._loadUserData()),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _onFabTap,
              backgroundColor: WW.primary,
              shape: const CircleBorder(),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            )
          : null,
      bottomNavigationBar: _BottomNav(
        selectedIndex: _selectedIndex,
        items: _tabItems,
        onTap: _onTabTap,
      ),
    );
  }
}

// ── Bottom nav ────────────────────────────────────────────────────────────────

class _TabItem {
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final List<_TabItem> items;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.selectedIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: Color(0xFFE8EAF8), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(items.length, (i) {
            final active = i == selectedIndex;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      items[i].icon,
                      size: 24,
                      color: active ? WW.primary : WW.textSec,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: active ? WW.primary : WW.textSec,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Home tab ──────────────────────────────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  final VoidCallback? onGoToPlans;
  final VoidCallback? onGoToClubFriends;
  const _HomeTab({super.key, this.onGoToPlans, this.onGoToClubFriends});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  String? _displayName;
  bool _isLoadingName = true;
  // Covers the whole "profile group" (display name, calorie goal settings,
  // tracked plan id/name) — see _loadProfileGroup(). One flag for the
  // group, not per-field, since all of it comes from one users/{uid} read.
  bool _profileError = false;
  int _todaysCalories = 0;
  int _caloriesEaten = 0;
  int _dailyCalorieGoal = 500;
  bool _calorieGoalActive = false;
  int _proteinG = 0;
  int _carbsG = 0;
  int _fatG = 0;
  bool _isLoadingCalorieRing = true;
  bool _calorieRingError = false;
  int _streakDays = 0;
  bool _isLoadingStreak = true;
  bool _streakError = false;
  Set<String> _sessionDates = {};
  bool _isLoadingCalendar = true;
  bool _calendarError = false;
  String _trackedPlanName = '';
  String _trackedPlanId = '';
  int _currentDayIndex = 1;
  Map<String, dynamic>? _todaySession;
  bool _todayIsRestDay = false;
  bool _todayCompleted = false;
  bool _isSessionCompressed = false;
  StreamSubscription<DocumentSnapshot>? _userStreamSub;
  StreamSubscription<Map<String, dynamic>?>? _progressStreamSub;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationsSub;
  int _unreadNotificationCount = 0;
  bool _showMissedBanner = false;
  String _missedSessionDate = '';
  String _missedPlanId = '';
  String _missedPlanName = '';
  int _missedDayIndex = 1;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _startUserStream();
    _startNotificationsStream();
  }

  void _startNotificationsStream() {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    _notificationsSub =
        _firestoreService.getNotificationsStream(uid).listen((notifications) {
      if (!mounted) return;
      final unread = notifications.where((n) => n['read'] != true).length;
      setState(() => _unreadNotificationCount = unread);
    });
  }

  void _startUserStream() {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    _userStreamSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        final newPlanId =
            doc.data()?['trackedPlanId'] as String? ?? '';
        final planChanged = newPlanId != _trackedPlanId;
        setState(() {
          _trackedPlanName =
              doc.data()?['trackedPlanName'] as String? ?? '';
          _trackedPlanId = newPlanId;
          _displayName =
              doc.data()?['displayName'] as String? ?? _displayName;
        });
        if (planChanged && newPlanId.isNotEmpty) {
          _startProgressStream(uid, newPlanId);
          _loadTodaySession(uid, _currentDayIndex);
        }
      }
    });
  }

  void _startProgressStream(String uid, String planId) {
    _progressStreamSub?.cancel();
    _progressStreamSub = _firestoreService
        .getPlanProgressStream(uid, planId)
        .listen((progress) {
      if (progress == null || !mounted) return;
      final newDayIndex =
          (progress['currentDayIndex'] as num?)?.toInt() ?? 1;
      // Matches plan_detail_screen.dart/plan_schedule_screen.dart's
      // _isDayCompleted()/_statusOf() convention — the lifetime
      // completedDayIndices ledger, not the old lastCompletedDate == today
      // comparison, which this screen used to use on its own. That field
      // only ever remembered the single most recently completed day and
      // could disagree with the other two screens; completedDayIndices is
      // the one authoritative signal now shared by all three.
      final rawCompletedDayIndices = progress['completedDayIndices'];
      final completedDayIndices = rawCompletedDayIndices is List
          ? rawCompletedDayIndices.map((d) => (d as num).toInt()).toSet()
          : <int>{};
      final rawCompressedDays = progress['compressedDays'];
      bool newIsCompressed = false;
      if (rawCompressedDays is List) {
        final compressedSet =
            rawCompressedDays.map((d) => (d as num).toInt()).toSet();
        newIsCompressed = compressedSet.contains(newDayIndex);
      }
      final dayChanged = newDayIndex != _currentDayIndex;
      setState(() {
        _currentDayIndex = newDayIndex;
        _todayCompleted = completedDayIndices.contains(newDayIndex);
        _isSessionCompressed = newIsCompressed;
      });
      if (dayChanged && _trackedPlanId.isNotEmpty) {
        _loadTodaySession(uid, newDayIndex);
      }
    });
  }

  Future<void> _loadTodaySession(String uid, int currentDayIndex) async {
    try {
      final plan = await _firestoreService.getTrackedPlan(uid);
      if (plan == null || !mounted) return;
      final planId = plan['id'] as String? ?? '';
      if (planId.isEmpty) return;
      final sessions = (plan['sessions'] as List<dynamic>?) ?? [];
      if (sessions.isEmpty) return;
      final effectiveDayIndex = await _firestoreService
          .checkAndAdvanceDay(uid, sessions.length, planId);
      final sessionIdx = (effectiveDayIndex - 1) % sessions.length;
      final session = sessions[sessionIdx] as Map<String, dynamic>;
      final isRestDay = session['isRestDay'] == true;
      if (!mounted) return;
      setState(() {
        _currentDayIndex = effectiveDayIndex;
        _todaySession = session;
        _todayIsRestDay = isRestDay;
      });
      // This is the one place today's rest-day status is already known
      // live — record it so calculateStreak() can later treat a scheduled
      // rest day as not breaking the streak. Safe to call every time this
      // method runs (initial load, plan-progress stream day-changes, plan
      // switches) — recordDailyActivityLog() writes to a doc keyed by
      // today's date with merge:true, so repeat calls the same day are a
      // no-op in effect, not a duplicate-write concern.
      await _firestoreService.recordDailyActivityLog(uid, isRestDay: isRestDay);
    } catch (_) {}
  }

  // Wired to _TodayPlanCard's Start Workout button (see its onStartWorkout
  // prop) instead of that card navigating straight to Routes.gymSession
  // itself — routes through the shared discovery-and-prompt step first, so
  // an already-abandoned in-progress session for today's plan/day offers
  // Resume/Start Over instead of silently being orphaned by a brand-new
  // one. _todayCompleted already gates whether this button is even shown
  // at all (see _TodayPlanCard's own build()), so no separate completed
  // check is needed here — by the time this can fire, today genuinely
  // isn't completed yet.
  Future<void> _handleStartWorkoutTap() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null || _trackedPlanId.isEmpty) return;
    await startOrResumeTrackedSession(
      context: context,
      uid: uid,
      planId: _trackedPlanId,
      dayIndex: _currentDayIndex,
      startFresh: () async => context.push(Routes.gymSession),
    );
  }

  Future<void> _checkMissedSession(String uid) async {
    try {
      final yesterday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toString()
          .substring(0, 10);
      final today = DateTime.now().toString().substring(0, 10);

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data();
      final trackedPlanId = userData?['trackedPlanId'] as String?;
      final trackedPlanName =
          userData?['trackedPlanName'] as String? ?? '';
      if (trackedPlanId == null || trackedPlanId.isEmpty) return;

      final progressDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('planProgress')
          .doc(trackedPlanId)
          .get();
      final progress = progressDoc.data();
      if (progress == null) return;

      final lastCompletedDate =
          progress['lastCompletedDate'] as String? ?? '';
      final currentDayIndex =
          (progress['currentDayIndex'] as num?)?.toInt() ?? 1;
      final breakModeActive =
          progress['breakModeActive'] as bool? ?? false;
      final trackedPlanStartedAt =
          progress['trackedPlanStartedAt'] as Timestamp?;

      if (breakModeActive) return;

      // Grace period: don't flag a plan that hasn't been tracked for a
      // full 24h yet — e.g. the user tracked a different plan earlier
      // today, untracked it, and just switched onto this one, which may
      // carry stale/empty history of its own. trackPlan() stamps this
      // fresh on every track/switch (see firestore_service.dart), so it
      // always reflects the current tracking stint, not the plan's
      // lifetime history. A missing value (plan tracked before this field
      // existed) doesn't block the check — treated as long since past the
      // grace period. Break time is excluded from this window: entering
      // and leaving a break in plan_schedule_screen.dart shifts this
      // timestamp forward by the break's duration, so it measures real
      // tracked time, not wall-clock time since first tracked.
      if (trackedPlanStartedAt != null &&
          DateTime.now().difference(trackedPlanStartedAt.toDate()) <
              const Duration(hours: 24)) {
        return;
      }

      if (lastCompletedDate == yesterday || lastCompletedDate == today) return;

      final missedDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('missedSessions')
          .doc(yesterday)
          .get();
      if (missedDoc.exists) return;

      if (!mounted) return;
      setState(() {
        _missedSessionDate = yesterday;
        _missedPlanId = trackedPlanId;
        _missedPlanName = trackedPlanName;
        _missedDayIndex = currentDayIndex;
        _showMissedBanner = true;
      });
    } catch (_) {}
  }

  // Break-mode auto-expiry detection, duplicated from
  // plan_schedule_screen.dart's _init() rather than sharing a helper (per
  // this session's scope: keep this minimal, single-consumer wiring, no
  // new shared abstraction) — this is the second and only other place a
  // break's expiry is discovered. plan_schedule_screen.dart's own check
  // only runs if the user reopens that specific screen; this one runs
  // here instead on every _loadUserData() call (app cold-start, and every
  // Quick Add/Profile-return reload), so an expired break gets resumed
  // even if the user never revisits Plan Schedule.
  //
  // Safe to run alongside plan_schedule_screen.dart's own check rather
  // than needing to prevent both from ever firing together: whichever
  // check reads breakModeActive == true first does the write and reminder
  // reschedule; the other reads it as already false (once the first
  // write lands) and no-ops via the guard below. In the rare case both
  // read the stale (still-active) state before either writes, both
  // compute the same shift from the same source fields and both call
  // scheduleDailyWorkoutReminder(), which itself cancels-then-reschedules
  // — so the end state is still exactly one correctly-resumed reminder,
  // not a duplicate or a double-shifted timestamp.
  Future<void> _checkBreakAutoExpiry(
    String uid,
    String planId,
    Map<String, dynamic>? profile,
  ) async {
    try {
      final progress = await _firestoreService.getPlanProgress(uid, planId);
      final breakActive = progress?['breakModeActive'] as bool? ?? false;
      if (!breakActive) return;

      final breakEndDate = progress?['breakEndDate'] as String?;
      final today = DateTime.now().toString().substring(0, 10);
      if (breakEndDate == null || breakEndDate.compareTo(today) >= 0) return;

      final breakStartDate = progress?['breakStartDate'] as String?;
      final startedAt = progress?['trackedPlanStartedAt'] as Timestamp?;
      Timestamp? shifted;
      if (startedAt != null && breakStartDate != null) {
        try {
          final start = DateTime.parse(breakStartDate);
          final through = DateTime.parse(breakEndDate);
          final days = through.difference(start).inDays;
          if (days > 0) {
            shifted =
                Timestamp.fromDate(startedAt.toDate().add(Duration(days: days)));
          }
        } catch (_) {}
      }

      final updates = <String, dynamic>{
        'breakModeActive': false,
        'breakEndDate': null,
        'breakStartDate': null,
        'breakDays': null,
      };
      if (shifted != null) updates['trackedPlanStartedAt'] = shifted;
      await _firestoreService.updatePlanProgress(uid, planId, updates);

      final workoutRemindersOn =
          profile?['workoutReminders'] as bool? ?? true;
      if (!workoutRemindersOn) return;
      final hour = (profile?['reminderHour'] as num?)?.toInt() ?? 7;
      final minute = (profile?['reminderMinute'] as num?)?.toInt() ?? 0;
      await NotificationService()
          .scheduleDailyWorkoutReminder(TimeOfDay(hour: hour, minute: minute));
    } catch (_) {}
  }

  Widget _buildMissedBanner() {
    if (!_showMissedBanner) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Missed yesterday\'s session',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _missedPlanName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _showMissedBanner = false);
              context.push(Routes.missedCheckin, extra: {
                'planId': _missedPlanId,
                'planName': _missedPlanName,
                'missedDayIndex': _missedDayIndex,
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Log reason',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _userStreamSub?.cancel();
    _progressStreamSub?.cancel();
    _notificationsSub?.cancel();
    super.dispose();
  }

  // Dispatches the 4 independent load groups below concurrently (each
  // manages its own try/catch/setState/loading+error flags, so a failure
  // in one never blanks the others — see prior investigation this session
  // for why the old single-Future.wait version cascaded). Still `await`s
  // all 4 so external callers (e.g. Quick Add's `.then((_) =>
  // _loadUserData())`) see the same "fully refreshed" completion signal as
  // before; total load time is unchanged since all 4 fire together, not
  // sequentially.
  Future<void> _loadUserData() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() {
        _isLoadingName = false;
        _isLoadingCalorieRing = false;
        _isLoadingStreak = false;
        _isLoadingCalendar = false;
      });
      return;
    }
    await Future.wait([
      _loadProfileGroup(uid),
      _loadCalorieRingGroup(uid),
      _loadStreakGroup(uid),
      _loadWeekCalendarGroup(uid),
    ]);
  }

  // Profile group: one users/{uid} read feeds display name, tracked plan
  // id/name, and the calorie goal settings — calorieGoalActive/
  // dailyCalorieGoal used to come from a SEPARATE getUserCalorieGoal(uid)
  // read of this exact same doc; now read once here instead (same field
  // names/defaults getUserCalorieGoal used internally). Also owns
  // starting the plan-progress stream/today's-session load/missed-session
  // check, since all three are gated on trackedPlanId, which lives here —
  // previously they only ran after the old shared 7-future bundle
  // succeeded as a whole.
  Future<void> _loadProfileGroup(String uid) async {
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      if (!mounted) return;
      final trackedPlanId = profile?['trackedPlanId'] as String? ?? '';

      setState(() {
        _displayName = profile?['displayName'] as String?;
        _isLoadingName = false;
        _profileError = false;
        _calorieGoalActive = profile?['calorieGoalActive'] as bool? ?? false;
        _dailyCalorieGoal =
            (profile?['dailyCalorieGoal'] as num?)?.toInt() ?? 500;
        _trackedPlanId = trackedPlanId;
        _trackedPlanName = profile?['trackedPlanName'] as String? ?? '';
      });

      if (trackedPlanId.isNotEmpty) {
        _startProgressStream(uid, trackedPlanId);
        // Progress stream will trigger _loadTodaySession via dayChanged logic,
        // but call it immediately so the home screen isn't blank while streaming.
        _loadTodaySession(uid, _currentDayIndex);
        _checkMissedSession(uid);
        _checkBreakAutoExpiry(uid, trackedPlanId, profile);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingName = false;
          _profileError = true;
        });
      }
    }
  }

  // Calorie ring group: getTodaysCalories(uid) + a single
  // getTodaysNutritionLogs(uid) read, with caloriesEaten/protein/carbs/fat
  // all derived locally from that one log list — getTodaysNutritionCalories
  // and getTodaysNutritionMacros used to each independently re-run that
  // same query. Field-level fallback logic (num? -> toInt() ?? 0) mirrors
  // exactly what those two service methods did internally.
  Future<void> _loadCalorieRingGroup(String uid) async {
    try {
      final results = await Future.wait<dynamic>([
        _firestoreService.getTodaysCalories(uid),
        _firestoreService.getTodaysNutritionLogs(uid),
      ]);
      if (!mounted) return;
      final todaysCal = results[0] as int;
      final logs = results[1] as List<Map<String, dynamic>>;

      int caloriesEaten = 0;
      int proteinG = 0;
      int carbsG = 0;
      int fatG = 0;
      for (final log in logs) {
        caloriesEaten += (log['calories'] as num?)?.toInt() ?? 0;
        proteinG += (log['proteinG'] as num?)?.toInt() ?? 0;
        carbsG += (log['carbsG'] as num?)?.toInt() ?? 0;
        fatG += (log['fatG'] as num?)?.toInt() ?? 0;
      }

      setState(() {
        _todaysCalories = todaysCal;
        _caloriesEaten = caloriesEaten;
        _proteinG = proteinG;
        _carbsG = carbsG;
        _fatG = fatG;
        _isLoadingCalorieRing = false;
        _calorieRingError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingCalorieRing = false;
          _calorieRingError = true;
        });
      }
    }
  }

  // Streak group: calculateStreak(uid) alone.
  Future<void> _loadStreakGroup(String uid) async {
    try {
      final streak = await _firestoreService.calculateStreak(uid);
      if (!mounted) return;
      setState(() {
        _streakDays = streak;
        _isLoadingStreak = false;
        _streakError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingStreak = false;
          _streakError = true;
        });
      }
    }
  }

  // Week calendar group: getSessionDates(uid, days: 30) alone.
  Future<void> _loadWeekCalendarGroup(String uid) async {
    try {
      final sessionDates =
          await _firestoreService.getSessionDates(uid, days: 30);
      if (!mounted) return;
      setState(() {
        _sessionDates = sessionDates;
        _isLoadingCalendar = false;
        _calendarError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingCalendar = false;
          _calendarError = true;
        });
      }
    }
  }

  void _showNotificationsSheet() {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        // Tracks challenge_invite notificationIds with an in-flight
        // accept/decline call, so the buttons can disable/spinner the
        // instant they're tapped (before the Firestore round-trip
        // resolves) and rapid repeated taps can't fire multiple calls.
        // Declared here (once, when the sheet is first built) rather than
        // inside StatefulBuilder's own builder callback, so it survives
        // the setSheetState rebuilds below instead of resetting each time.
        final processingIds = <String>{};

        Future<void> respond(
          BuildContext sheetContext,
          StateSetter setSheetState,
          Map<String, dynamic> n,
          String notificationId, {
          required bool accept,
        }) async {
          if (processingIds.contains(notificationId)) return;
          final challengeId = n['challengeId'] as String?;
          if (challengeId == null) return;
          setSheetState(() => processingIds.add(notificationId));
          try {
            await _firestoreService.respondToChallengeInvite(
              uid,
              challengeId,
              notificationId,
              accept: accept,
            );
            if (sheetContext.mounted) {
              final challengeName =
                  n['challengeName'] as String? ?? 'the challenge';
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(
                  content: Text(accept ? 'Joined $challengeName!' : 'Declined'),
                  backgroundColor: WW.primaryDark,
                  behavior: SnackBarBehavior.floating,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (_) {
            if (sheetContext.mounted) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(
                  content: Text('Something went wrong. Please try again.'),
                  backgroundColor: WW.primaryDark,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10))),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } finally {
            if (sheetContext.mounted) {
              setSheetState(() => processingIds.remove(notificationId));
            }
          }
        }

        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          // A nested Scaffold gives this sheet its own local
          // ScaffoldMessenger. Without it, showing a SnackBar via the
          // underlying screen's ScaffoldMessenger still "works" in that it
          // gets queued, but that Scaffold sits BELOW this modal bottom
          // sheet's route in the Navigator's overlay z-order — so the
          // SnackBar is rendered behind the sheet and only becomes visible
          // (or has already finished its timer) once the sheet is
          // dismissed, which is exactly the "delayed/after the sheet
          // closes" symptom. Transparent background so it doesn't cover
          // the outer showModalBottomSheet's own WW.card/rounded-corner
          // styling.
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    decoration: BoxDecoration(
                      color: WW.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _firestoreService.getNotificationsStream(uid),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: WW.primary),
                        );
                      }
                      final notifications = snapshot.data ?? [];
                      if (notifications.isEmpty) {
                        return const Center(
                          child: Text(
                            'No notifications yet',
                            style: TextStyle(fontSize: 13, color: WW.textSec),
                          ),
                        );
                      }
                      // StatefulBuilder gives this list its own local
                      // setState (setSheetState) scoped to the sheet's
                      // subtree — setState on _HomeTabState itself would
                      // NOT rebuild this content, since showModalBottomSheet
                      // inserts its builder's result into the Navigator's
                      // overlay rather than into _HomeTabState's own
                      // build() tree.
                      return StatefulBuilder(
                        builder: (context, setSheetState) {
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                            itemCount: notifications.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final n = notifications[i];
                              final read = n['read'] == true;
                              final notificationId =
                                  n['notificationId'] as String?;
                              final type = n['type'] as String? ?? '';
                              final isChallengeInvite =
                                  type == 'challenge_invite';
                              final inviteStatus =
                                  n['status'] as String? ?? 'pending';
                              final isProcessing = notificationId != null &&
                                  processingIds.contains(notificationId);
                              return InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: notificationId == null
                                    ? null
                                    : () {
                                        _firestoreService.markNotificationRead(
                                            uid, notificationId);
                                        if (n['type'] == 'friend_request') {
                                          Navigator.pop(ctx);
                                          widget.onGoToClubFriends?.call();
                                        }
                                      },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: read ? WW.card : WW.elevated,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: WW.border, width: 0.5),
                                    boxShadow: WW.shadow,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _NotificationIcon(
                                        icon: _notificationIcon(type),
                                        showUnreadDot: !read,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _notificationText(n),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: read
                                                    ? FontWeight.w500
                                                    : FontWeight.w700,
                                                color: WW.text,
                                                height: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _relativeTime(n['createdAt']),
                                              style: WW.caption,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Only challenge_invite gets extra
                                      // trailing content — every other type
                                      // keeps the plain icon+text+time card
                                      // above.
                                      if (isChallengeInvite &&
                                          notificationId != null) ...[
                                        const SizedBox(width: 10),
                                        if (inviteStatus == 'pending')
                                          _ChallengeInviteActions(
                                            isProcessing: isProcessing,
                                            onDecline: () => respond(
                                              context,
                                              setSheetState,
                                              n,
                                              notificationId,
                                              accept: false,
                                            ),
                                            onAccept: () => respond(
                                              context,
                                              setSheetState,
                                              n,
                                              notificationId,
                                              accept: true,
                                            ),
                                          )
                                        else
                                          _ChallengeInviteStatusPill(
                                            status: inviteStatus,
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Opens the full-month calendar in a bottom sheet — triggered by tapping
  // the week strip's header (see _WeekCalendar's onHeaderTap). Same
  // showModalBottomSheet + StatefulBuilder shape as
  // _showNotificationsSheet() above (local sheet-scoped state via
  // setSheetState, not this State's own setState, since the sheet's
  // content lives in the Navigator's overlay, not this widget's own
  // build() tree) — here it tracks which month is currently displayed so
  // prev/next taps rebuild just the sheet, not the whole Home tab.
  //
  // MonthCalendar itself is a plain StatelessWidget with no Firestore/
  // provider access of its own (see its doc comment) — this Consumer is
  // what actually watches monthActivityProvider and threads the result
  // down as props. Consumer works here without _HomeTabState itself being
  // a ConsumerState, since main.dart already wraps the whole app in a
  // ProviderScope.
  void _openMonthCalendarModal() {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    final now = DateTime.now();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        DateTime displayedMonth = DateTime(now.year, now.month, 1);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 14),
                        decoration: BoxDecoration(
                          color: WW.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
                      child: Text(
                        'Activity Calendar',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: WW.primaryDark,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        child: Consumer(
                          builder: (context, ref, _) {
                            final asyncData = ref.watch(
                              monthActivityProvider(
                                MonthKey(
                                  uid: uid,
                                  year: displayedMonth.year,
                                  month: displayedMonth.month,
                                ),
                              ),
                            );
                            return asyncData.when(
                              data: (data) => MonthCalendar(
                                month: displayedMonth,
                                dayStates: data.dayStates,
                                streakDates: data.streakDates,
                                onMonthChanged: (newMonth) => setSheetState(
                                    () => displayedMonth = newMonth),
                              ),
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: CircularProgressIndicator(
                                      color: WW.primary),
                                ),
                              ),
                              error: (_, _) => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Text(
                                    "Couldn't load calendar",
                                    style: TextStyle(
                                        fontSize: 13, color: WW.textSec),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // One glyph per notification type actually produced anywhere in this
  // app (kept in sync with _notificationText()'s own switch below — same
  // types, same order) so a card never falls back to a generic/missing
  // icon. Deliberately all WW.primary (see _NotificationIcon), matching
  // this app's 2-color-minimalist system from the Feed redesign — the
  // glyph itself is what distinguishes types, not a rainbow of accent
  // colors per type.
  IconData _notificationIcon(String type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add_rounded;
      case 'friend_accepted':
        return Icons.how_to_reg_rounded;
      case 'coach_request_accepted':
        // Same badge glyph used for the coach system elsewhere
        // (coach_register_screen.dart, profile_screen.dart's Coach
        // Dashboard link) rather than inventing a new one for this.
        return Icons.badge_rounded;
      case 'challenge_invite':
        return Icons.emoji_events_rounded;
      case 'challenge_friend_progress':
        return Icons.trending_up_rounded;
      case 'admin_broadcast':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  // Same Today/Yesterday/"X days ago" shape as progress_screen.dart's own
  // _formatTs() (its _XpRow widget) — ported rather than imported, since
  // that one is a private method on a different file's class, but the
  // exact same pattern so relative timestamps read consistently
  // app-wide instead of introducing a second, differently-worded style.
  String _relativeTime(dynamic ts) {
    if (ts is! Timestamp) return 'Recently';
    final date = ts.toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  String _notificationText(Map<String, dynamic> n) {
    final type = n['type'] as String? ?? '';
    final fromName = n['fromDisplayName'] as String? ?? 'Someone';
    final challengeName = n['challengeName'] as String? ?? 'a challenge';
    switch (type) {
      case 'friend_request':
        return '$fromName sent you a friend request';
      case 'friend_accepted':
        return '$fromName accepted your friend request';
      case 'coach_request_accepted':
        // fromName here is coachDisplayName, written by
        // acceptCoachRequest() in firestore_service.dart — same
        // fromDisplayName field every other case already reads, just
        // populated with the coach's own name for this type.
        return 'Coach $fromName accepted your request';
      case 'challenge_invite':
        return '$fromName invited you to challenge $challengeName';
      case 'challenge_friend_progress':
        return '$fromName made progress on challenge $challengeName';
      case 'admin_broadcast':
        // Unlike every other type, the admin's own message IS the display
        // text — there's no sentence to construct from fromDisplayName here.
        return n['message'] as String? ?? 'New notification from WiseWorkout';
      default:
        return 'New notification';
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildTopBar()),
          SliverToBoxAdapter(
            child: _WeekCalendar(
              sessionDates: _sessionDates,
              streakDays: _streakDays,
              streakError: !_isLoadingStreak && _streakError,
              calendarError: !_isLoadingCalendar && _calendarError,
              onHeaderTap: _openMonthCalendarModal,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _CalorieRingCard(
                calories: _todaysCalories,
                caloriesEaten: _caloriesEaten,
                goal: _dailyCalorieGoal,
                goalActive: _calorieGoalActive,
                proteinG: _proteinG,
                carbsG: _carbsG,
                fatG: _fatG,
                hasError: !_isLoadingCalorieRing && _calorieRingError,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildMissedBanner(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                "Today's Plan",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _TodayPlanCard(
                trackedPlanName: _trackedPlanName,
                onGoToPlans: widget.onGoToPlans,
                onStartWorkout: _handleStartWorkoutTap,
                todaySession: _todaySession,
                todayIsRestDay: _todayIsRestDay,
                currentDayIndex: _currentDayIndex,
                todayCompleted: _todayCompleted,
                isCompressed: _isSessionCompressed,
                hasError: _profileError,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final name = _isLoadingName ? '' : (_displayName ?? '');
    final initials = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
                const SizedBox(height: 2),
                _isLoadingName
                    ? const SizedBox(
                        height: 24,
                        width: 120,
                        child: LinearProgressIndicator(
                          color: WW.primary,
                          backgroundColor: WW.elevated,
                        ),
                      )
                    : Text(
                        name.isNotEmpty ? name : 'Athlete',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: WW.primaryDark,
                          letterSpacing: -0.4,
                        ),
                      ),
                if (!_isLoadingName && _profileError) ...[
                  const SizedBox(height: 2),
                  const _SectionErrorHint(),
                ],
              ],
            ),
          ),
          // Bell icon
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined, color: WW.textSec, size: 24),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showNotificationsSheet,
          ),
          const SizedBox(width: 4),
          // Avatar → Profile screen
          GestureDetector(
            onTap: () => context.push(Routes.profile).then((_) => _loadUserData()),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: WW.chipBg,
                shape: BoxShape.circle,
                border: Border.all(color: WW.primary, width: 1.5),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: WW.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Challenge invite row actions ────────────────────────────────────────────
// Inline accept/decline for a pending challenge_invite notification row —
// same 2-icon-button interaction as friends_screen.dart's
// _buildRequestRow(), sized up slightly with an outlined decline button so
// it reads as clearly secondary against the solid-filled accept button.
// isProcessing swaps both buttons for a single small spinner rather than
// disabling them individually, so there's no ambiguity about whether a tap
// registered while its Firestore call is still in flight.
class _ChallengeInviteActions extends StatelessWidget {
  final bool isProcessing;
  final VoidCallback onDecline;
  final VoidCallback onAccept;
  const _ChallengeInviteActions({
    required this.isProcessing,
    required this.onDecline,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    if (isProcessing) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Padding(
          padding: EdgeInsets.all(9),
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: WW.primary,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onDecline,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: WW.card,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: WW.border, width: 1.2),
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 17,
              color: WW.textSec,
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onAccept,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: WW.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// Muted inline label replacing the action buttons once a challenge_invite
// has been responded to. Driven entirely by the notification doc's own
// `status` field (read via getNotificationsStream, not local widget
// state), so it renders correctly even after the sheet is closed and
// reopened, or rebuilt for any other reason.
class _ChallengeInviteStatusPill extends StatelessWidget {
  final String status;
  const _ChallengeInviteStatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status == 'accepted' ? 'Accepted' : 'Declined';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // WW.chipBg instead of the old WW.elevated — the notification
      // card itself now uses WW.card/WW.elevated as its own background
      // (see _showNotificationsSheet's itemBuilder), so this pill needs
      // a background that still reads as a distinct pill against either.
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: WW.textSec,
        ),
      ),
    );
  }
}

// Circular icon badge for the leading element of each notification card
// — same visual weight/size as FeedPostCard's own initials-circle avatar
// (radius 18), but a type-specific icon glyph instead of initials, since
// not every notification type has a meaningful single "sender" to show
// initials for (admin_broadcast has none at all). Single WW.primary
// treatment for every type, matching this app's 2-color-minimalist
// system — the glyph is what differs per type, not the color.
class _NotificationIcon extends StatelessWidget {
  final IconData icon;
  final bool showUnreadDot;

  const _NotificationIcon({required this.icon, required this.showUnreadDot});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: WW.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          if (showUnreadDot)
            Positioned(
              top: -1,
              right: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: WW.gold,
                  shape: BoxShape.circle,
                  border: Border.all(color: WW.card, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared section error hint ─────────────────────────────────────────────────
// Minimal, muted "this section's data may be stale" inline hint — an icon +
// tiny caption in WW.textSec, matching this file's existing caption-style
// hints (e.g. _CalorieRingCard's "Turn on calorie tracking..." line) rather
// than a loud banner. Shown only when a specific load group's own error flag
// is true; the section itself still falls back to its last-known/default
// values underneath, this just makes that fallback visible instead of silent.
class _SectionErrorHint extends StatelessWidget {
  final String message;
  const _SectionErrorHint({this.message = "Couldn't refresh"});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.info_outline_rounded, size: 12, color: WW.textSec),
        const SizedBox(width: 4),
        Text(
          message,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: WW.textSec,
          ),
        ),
      ],
    );
  }
}

// ── Week calendar strip ───────────────────────────────────────────────────────

class _WeekCalendar extends StatelessWidget {
  final Set<String> sessionDates;
  final int streakDays;
  final bool streakError;
  final bool calendarError;
  final VoidCallback? onHeaderTap;

  const _WeekCalendar({
    required this.sessionDates,
    required this.streakDays,
    this.streakError = false,
    this.calendarError = false,
    this.onHeaderTap,
  });

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final weekday = today.weekday; // 1=Mon … 7=Sun
    final monday = today.subtract(Duration(days: weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: WW.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: "This Week" label + streak pill — tappable as a
            // whole (not just the label) to open the full month-calendar
            // modal, matching the larger-tap-target convention already
            // used elsewhere in this file (e.g. the avatar/name area).
            GestureDetector(
              onTap: onHeaderTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
              children: [
                const Text(
                  'This Week',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                if (onHeaderTap != null)
                  const Icon(Icons.chevron_right_rounded,
                      color: WW.textSec, size: 16),
                const Spacer(),
                if (streakError)
                  const _SectionErrorHint(message: 'Streak unavailable')
                else if (streakDays > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: WW.tealBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            color: WW.teal, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          '$streakDays day streak',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: WW.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              ),
            ),
            const SizedBox(height: 12),
            if (calendarError) ...[
              const _SectionErrorHint(message: "Couldn't load activity"),
              const SizedBox(height: 8),
            ],
            // Day cells
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: days.map((day) {
                final isToday = day.year == today.year &&
                    day.month == today.month &&
                    day.day == today.day;
                final hasSession = sessionDates.contains(_dateKey(day));
                return _DayCell(day: day, isToday: isToday, isCompleted: hasSession);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool isCompleted;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isCompleted,
  });

  static const List<String> _weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Border? border;

    if (isCompleted) {
      bgColor = WW.teal;
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = WW.chipBg;
      textColor = WW.primary;
      border = Border.all(color: WW.primary, width: 1.5);
    } else {
      bgColor = Colors.transparent;
      textColor = WW.textSec;
      border = Border.all(color: WW.border, width: 1);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _weekLabels[day.weekday - 1],
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isToday ? WW.primary : WW.textSec,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: border,
          ),
          child: Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Calorie ring card ─────────────────────────────────────────────────────────

class _CalorieRingCard extends StatelessWidget {
  final int calories;
  final int caloriesEaten;
  final int goal;
  final bool goalActive;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final bool hasError;

  const _CalorieRingCard({
    required this.calories,
    required this.caloriesEaten,
    required this.goal,
    required this.goalActive,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    // Not clamped — legitimately grows past the goal if burned > eaten.
    // e.g. goal=700, burned=238, eaten=350 -> left = 700-238+350 = 812.
    final left = goal - calories + caloriesEaten;
    final total = caloriesEaten + calories + left;
    final intakeFraction = total > 0 ? caloriesEaten / total : 0.0;
    final burnedFraction = total > 0 ? calories / total : 0.0;
    final leftFraction = total > 0 ? left / total : 0.0;

    return Container(
      decoration: WW.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasError) ...[
            const _SectionErrorHint(),
            const SizedBox(height: 8),
          ],
          goalActive
              ? _buildGoalMode(caloriesEaten, calories, goal, left,
                  intakeFraction, burnedFraction, leftFraction)
              : _buildSimpleMode(),
          const SizedBox(height: 12),
          Container(height: 0.5, color: WW.border),
          const SizedBox(height: 12),
          _buildMacrosRow(),
        ],
      ),
    );
  }

  // Always visible regardless of goalActive — the whole card is now shown
  // unconditionally (see home_screen.dart's build(), which no longer
  // gates this widget out). When calorie tracking hasn't been turned on,
  // there's no goal to build a ring/"left" figure against, so this shows
  // just the plain eaten-today number instead, with a pointer to Settings
  // rather than pretending a goal exists.
  Widget _buildSimpleMode() {
    return Row(
      children: [
        const Icon(Icons.local_fire_department_rounded, color: WW.teal, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Today's Energy",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WW.textSec,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$caloriesEaten kcal eaten today',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Turn on calorie tracking in Settings to set a goal',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Informational only — no goal denominator exists for macros specifically
  // (per direct instruction), so this is plain totals, no rings/percentages.
  Widget _buildMacrosRow() {
    return Row(
      children: [
        Expanded(child: _macroChip('${proteinG}g', 'Protein')),
        Expanded(child: _macroChip('${carbsG}g', 'Carbs')),
        Expanded(child: _macroChip('${fatG}g', 'Fat')),
      ],
    );
  }

  Widget _macroChip(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: WW.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: WW.textSec,
          ),
        ),
      ],
    );
  }

  Widget _buildGoalMode(
      int caloriesEaten,
      int caloriesBurned,
      int goal,
      int left,
      double intakeFraction,
      double burnedFraction,
      double leftFraction) {
    // Display-only clamp — intakeFraction/burnedFraction/leftFraction above
    // are computed from the raw, unclamped `left` in build() and passed to
    // _CalorieRingPainter completely untouched; only the TEXT shown here
    // floors at 0. Goal is a burn target (see Settings' "Daily burn
    // target" copy), so a negative `left` just means today's burn goal
    // was exceeded — that's surfaced as its own "+X over goal" chip below
    // instead of a confusing negative number in the two text spots that
    // used to show the raw value.
    final displayLeft = left < 0 ? 0 : left;
    final isOverGoal = left < 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Ring
        SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(104, 104),
                painter: _CalorieRingPainter(
                  intakeFraction: intakeFraction,
                  burnedFraction: burnedFraction,
                  leftFraction: leftFraction,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$displayLeft',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Text(
                    'kcal left',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: WW.textSec,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Info column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Today's energy",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Goal $goal kcal',
                style: const TextStyle(fontSize: 12, color: WW.textSec),
              ),
              const SizedBox(height: 10),
              _statRow(WW.lightBlue, 'Cal Intake', '$caloriesEaten kcal'),
              const SizedBox(height: 6),
              _statRow(WW.lightYellow, 'Gym or Cardio', '$caloriesBurned kcal'),
              const SizedBox(height: 6),
              _statRow(WW.border, 'Left', '$displayLeft kcal'),
              if (isOverGoal) ...[
                const SizedBox(height: 8),
                _overGoalChip(-left),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Same small-pill shape as _WeekCalendar's streak badge (Container,
  // horizontal:10/vertical:4 padding, circular(20) radius, a light-tint
  // background + matching bold icon/text color) — reused here rather than
  // inventing new chip styling, per instruction. Shown only when the raw
  // (unclamped) `left` above is negative, i.e. the burn goal was exceeded;
  // reframes that as a positive achievement instead of the negative number
  // it replaces in the two text spots above.
  Widget _overGoalChip(int surplus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: WW.tealBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: WW.teal, size: 13),
          const SizedBox(width: 4),
          Text(
            '+$surplus over goal',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: WW.teal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(Color dotColor, String label, String value) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: WW.textSec),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WW.text),
        ),
      ],
    );
  }
}

class _CalorieRingPainter extends CustomPainter {
  // Single ring, three adjacent arcs that always sum to exactly the full
  // circle (intakeFraction + burnedFraction + leftFraction == 1.0) — no
  // capping/overflow logic needed since all three are derived from the
  // same total.
  final double intakeFraction;
  final double burnedFraction;
  final double leftFraction;

  const _CalorieRingPainter({
    required this.intakeFraction,
    required this.burnedFraction,
    required this.leftFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 8.0;
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -math.pi / 2; // top of circle
    final rect = Rect.fromCircle(center: center, radius: radius);

    void drawSegment(Color color, double startFraction, double sweepFraction) {
      if (sweepFraction <= 0) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
        rect,
        startAngle + 2 * math.pi * startFraction,
        2 * math.pi * sweepFraction,
        false,
        paint,
      );
    }

    drawSegment(WW.lightBlue, 0, intakeFraction);
    drawSegment(WW.lightYellow, intakeFraction, burnedFraction);
    drawSegment(WW.border, intakeFraction + burnedFraction, leftFraction);
  }

  @override
  bool shouldRepaint(_CalorieRingPainter old) =>
      old.intakeFraction != intakeFraction ||
      old.burnedFraction != burnedFraction ||
      old.leftFraction != leftFraction;
}

// ── Today's Plan card ─────────────────────────────────────────────────────────

class _TodayPlanCard extends StatefulWidget {
  final String trackedPlanName;
  final VoidCallback? onGoToPlans;
  // Fires the shared discovery-and-prompt step (see
  // widgets/session_resume_prompt.dart) instead of navigating to
  // Routes.gymSession directly — see _buildPlanCard's Start Workout button.
  final VoidCallback? onStartWorkout;
  final Map<String, dynamic>? todaySession;
  final bool todayIsRestDay;
  final int currentDayIndex;
  final bool todayCompleted;
  final bool isCompressed;
  final bool hasError;

  const _TodayPlanCard({
    required this.trackedPlanName,
    this.onGoToPlans,
    this.onStartWorkout,
    this.todaySession,
    this.todayIsRestDay = false,
    this.currentDayIndex = 1,
    this.todayCompleted = false,
    this.isCompressed = false,
    this.hasError = false,
  });

  @override
  State<_TodayPlanCard> createState() => _TodayPlanCardState();
}

// Stateful only for the exercise-list expand/collapse toggle below (purely
// local UI state) — everything else this card renders comes from the
// widget's own constructor params.
class _TodayPlanCardState extends State<_TodayPlanCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final Widget content = widget.trackedPlanName.isEmpty
        ? _buildEmptyState(context)
        : widget.todayIsRestDay
            ? _buildRestDayCard()
            : _buildPlanCard(context);
    if (!widget.hasError) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6, left: 4),
          child: _SectionErrorHint(),
        ),
        content,
      ],
    );
  }

  Widget _buildRestDayCard() {
    return Container(
      decoration: WW.cardDecoration,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          const Text('💤', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text(
            'Rest Day',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.trackedPlanName,
            style: const TextStyle(fontSize: 13, color: WW.textSec),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Recovery and rest are key to reaching your goals.',
            style: TextStyle(
              fontSize: 13,
              color: WW.textSec,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      decoration: WW.cardDecoration,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Column(
        children: [
          const Icon(Icons.fitness_center_rounded, size: 40, color: WW.textSec),
          const SizedBox(height: 12),
          const Text(
            'No plan tracked yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Go to Plans tab to choose a plan',
            style: TextStyle(fontSize: 13, color: WW.textSec),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: widget.onGoToPlans,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Browse Plans',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context) {
    final sessionName =
        widget.todaySession?['name'] as String? ?? '';
    final estimatedMinutes =
        (widget.todaySession?['estimatedMinutes'] as num?)?.toInt() ?? 45;
    final allExercises =
        (widget.todaySession?['exercises'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
            [];
    // FIX 3: filter to Primary-only when session is compressed.
    final exercises = widget.isCompressed
        ? allExercises.where((e) => e['tag'] == 'Primary').toList()
        : allExercises;
    final estimatedCals = (estimatedMinutes * 6.5).round();

    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dark header strip
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: WW.primaryDark,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'DAY ${widget.currentDayIndex}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.trackedPlanName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sessionName.isNotEmpty)
                        Text(
                          sessionName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (widget.isCompressed) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: WW.lavenderBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '⚡ Compressed session',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: WW.lavender,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                _StatChip(
                    icon: Icons.timer_outlined,
                    label: '${estimatedMinutes}min'),
                const SizedBox(width: 16),
                _StatChip(
                    icon: Icons.fitness_center_rounded,
                    label: '${exercises.length} exercises'),
                const SizedBox(width: 16),
                _StatChip(
                    icon: Icons.local_fire_department_outlined,
                    label: '~${estimatedCals}kcal'),
              ],
            ),
          ),

          const SizedBox(height: 14),
          const Divider(
              height: 1, color: WW.elevated, indent: 16, endIndent: 16),
          const SizedBox(height: 10),

          // Exercise list — show first 5 by default, expandable to the
          // full list in place (see _expanded) rather than navigating
          // anywhere else.
          ...(_expanded ? exercises : exercises.take(5).toList())
              .map((e) => _buildExerciseRow(e)),
          if (exercises.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  _expanded ? 'Show less' : 'See all (${exercises.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WW.primary,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Start Workout / Completed today
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: widget.todayCompleted
                ? Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: WW.tealBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: WW.teal.withValues(alpha: 0.35), width: 1),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: WW.teal, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Completed today!',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: WW.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: widget.onStartWorkout,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: WW.primary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: WW.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'Start Workout',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // Branches on isCardio (build_routine_screen.dart's _addCardioBlock()
  // writes 'isCardio': true, 'cardioActivity': <Run/Walk/Cycle>,
  // 'cardioMinutes': <int> for these entries — see that method) rather
  // than computing setsCount/reps from the fake single-entry 'sets' array
  // and absent top-level 'reps' field it also seeds purely so older
  // sets-based renderers wouldn't crash on a cardio block.
  Widget _buildExerciseRow(Map<String, dynamic> e) {
    if (e['isCardio'] == true) {
      final activity = e['cardioActivity'] as String? ?? 'Cardio';
      final minutes = (e['cardioMinutes'] as num?)?.toInt();
      final duration = minutes != null && minutes > 0 ? '$minutes min' : '';
      return _exerciseTile(activity, duration, icon: _cardioIcon(activity));
    }
    final name = e['name'] as String? ?? 'Exercise';
    final setsCount =
        FirestoreService.parseExerciseSets(e['sets'], 3).length;
    final reps = (e['reps'] as num?)?.toInt();
    final label = reps != null && reps > 0
        ? '$setsCount × $reps reps'
        : '$setsCount sets';
    return _exerciseTile(name, label);
  }

  // Same Run/Walk/Cycle icon mapping already used by cardio_setup_screen.dart's
  // _kActivities and activity_detail_screen.dart's _headerIcon — reused
  // here (duplicated, not imported, since those are private to their own
  // files) rather than inventing a new mapping. Run/unrecognized falls
  // back to the running icon, matching both of those files' own default.
  IconData _cardioIcon(String activity) {
    switch (activity) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  Widget _exerciseTile(String name, String sets, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          icon != null
              ? Icon(icon, size: 14, color: WW.primary)
              : Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: WW.primary,
                    shape: BoxShape.circle,
                  ),
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: WW.text,
              ),
            ),
          ),
          Text(
            sets,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WW.textSec,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: WW.textSec),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: WW.textSec,
          ),
        ),
      ],
    );
  }
}
