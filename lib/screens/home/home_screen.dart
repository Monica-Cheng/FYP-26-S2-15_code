// lib/screens/home/home_screen.dart
// MainShell — 5-tab shell with IndexedStack + custom bottom nav.
// Tab 0 = Home (_HomeTab), tabs 1-4 = placeholder screens.
// FAB shown only on Home tab; tapping shows SnackBar.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
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
  final _homeTabKey = GlobalKey<_HomeTabState>();

  static const List<_TabItem> _tabItems = [
    _TabItem(label: 'Home', icon: Icons.home_rounded),
    _TabItem(label: 'Plans', icon: Icons.fitness_center_rounded),
    _TabItem(label: 'Coach', icon: Icons.auto_awesome_rounded),
    _TabItem(label: 'Club', icon: Icons.people_rounded),
    _TabItem(label: 'Progress', icon: Icons.bar_chart_rounded),
  ];

  late final List<Widget> _tabs = [
    _HomeTab(key: _homeTabKey, onGoToPlans: () => _onTabTap(1)),
    const PlansScreen(),
    const CoachScreen(),
    const ClubScreen(),
    const ProgressScreen(),
  ];

  void _onTabTap(int index) => setState(() => _selectedIndex = index);

  void _onFabTap() {
    context.push(Routes.manualActivityLog)
        .then((_) => _homeTabKey.currentState?._loadUserData());
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
  const _HomeTab({super.key, this.onGoToPlans});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  String? _displayName;
  bool _isLoadingName = true;
  int _todaysCalories = 0;
  int _dailyCalorieGoal = 500;
  bool _calorieGoalActive = false;
  int _streakDays = 0;
  Set<String> _sessionDates = {};
  String _trackedPlanName = '';
  String _trackedPlanId = '';
  int _currentDayIndex = 1;
  Map<String, dynamic>? _todaySession;
  bool _todayIsRestDay = false;
  bool _todayCompleted = false;
  bool _isSessionCompressed = false;
  StreamSubscription<DocumentSnapshot>? _userStreamSub;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _startUserStream();
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
        final newDayIndex =
            (doc.data()?['currentDayIndex'] as num?)?.toInt() ?? 1;
        final lastCompletedDate =
            doc.data()?['lastCompletedDate'] as String?;
        final today = DateTime.now().toString().substring(0, 10);
        final shouldReload =
            (newPlanId != _trackedPlanId || newDayIndex != _currentDayIndex) &&
                newPlanId.isNotEmpty;

        final rawCompressedDays = doc.data()?['compressedDays'];
        bool newIsCompressed = false;
        if (rawCompressedDays is List) {
          final compressedSet =
              rawCompressedDays.map((d) => (d as num).toInt()).toSet();
          newIsCompressed = compressedSet.contains(newDayIndex);
        }

        setState(() {
          _trackedPlanName =
              doc.data()?['trackedPlanName'] as String? ?? '';
          _trackedPlanId = newPlanId;
          _currentDayIndex = newDayIndex;
          _displayName =
              doc.data()?['displayName'] as String? ?? _displayName;
          _todayCompleted = lastCompletedDate == today;
          _isSessionCompressed = newIsCompressed;
        });

        if (shouldReload) _loadTodaySession(uid, newDayIndex);
      }
    });
  }

  Future<void> _loadTodaySession(String uid, int currentDayIndex) async {
    try {
      final plan = await _firestoreService.getTrackedPlan(uid);
      if (plan == null || !mounted) return;
      final sessions = (plan['sessions'] as List<dynamic>?) ?? [];
      if (sessions.isEmpty) return;
      final effectiveDayIndex =
          await _firestoreService.checkAndAdvanceDay(uid, sessions.length);
      final sessionIdx = (effectiveDayIndex - 1) % sessions.length;
      final session = sessions[sessionIdx] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _currentDayIndex = effectiveDayIndex;
        _todaySession = session;
        _todayIsRestDay = session['isRestDay'] == true;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _userStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoadingName = false);
      return;
    }
    try {
      final results = await Future.wait<dynamic>([
        _firestoreService.getUserProfile(uid),
        _firestoreService.getUserCalorieGoal(uid),
        _firestoreService.getTodaysCalories(uid),
        _firestoreService.calculateStreak(uid),
        _firestoreService.getSessionDates(uid, days: 30),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>?;
      final calGoal = results[1] as Map<String, dynamic>;
      final todaysCal = results[2] as int;
      final streak = results[3] as int;
      final sessionDates = results[4] as Set<String>;
      final dayIndex =
          (profile?['currentDayIndex'] as num?)?.toInt() ?? 1;
      final trackedPlanId =
          profile?['trackedPlanId'] as String? ?? '';
      final lastCompletedDate =
          profile?['lastCompletedDate'] as String?;
      final today = DateTime.now().toString().substring(0, 10);

      final rawCompressedDays = profile?['compressedDays'];
      bool sessionCompressed = false;
      if (rawCompressedDays is List) {
        final compressedSet =
            rawCompressedDays.map((d) => (d as num).toInt()).toSet();
        sessionCompressed = compressedSet.contains(dayIndex);
      }

      setState(() {
        _displayName = profile?['displayName'] as String?;
        _isLoadingName = false;
        _calorieGoalActive = calGoal['calorieGoalActive'] as bool? ?? false;
        _dailyCalorieGoal = calGoal['dailyCalorieGoal'] as int? ?? 500;
        _todaysCalories = todaysCal;
        _streakDays = streak;
        _sessionDates = sessionDates;
        _currentDayIndex = dayIndex;
        _todayCompleted = lastCompletedDate == today;
        _isSessionCompressed = sessionCompressed;
      });

      if (trackedPlanId.isNotEmpty) {
        _loadTodaySession(uid, dayIndex);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingName = false);
    }
  }

  Future<void> _handleLogout() async {
    await _authService.signOut();
    if (mounted) context.go(Routes.login);
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
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _CalorieRingCard(
                calories: _todaysCalories,
                goal: _dailyCalorieGoal,
                goalActive: _calorieGoalActive,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
                todaySession: _todaySession,
                todayIsRestDay: _todayIsRestDay,
                currentDayIndex: _currentDayIndex,
                todayCompleted: _todayCompleted,
                isCompressed: _isSessionCompressed,
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
              ],
            ),
          ),
          // Bell icon
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: WW.textSec, size: 24),
            onPressed: () {},
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
          const SizedBox(width: 8),
          // Settings / logout gear
          GestureDetector(
            onTap: _handleLogout,
            child: const Icon(Icons.logout_rounded, color: WW.textSec, size: 22),
          ),
        ],
      ),
    );
  }
}

// ── Week calendar strip ───────────────────────────────────────────────────────

class _WeekCalendar extends StatelessWidget {
  final Set<String> sessionDates;
  final int streakDays;

  const _WeekCalendar({required this.sessionDates, required this.streakDays});

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
            // Header row: "This Week" label + streak pill
            Row(
              children: [
                const Text(
                  'This Week',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const Spacer(),
                if (streakDays > 0)
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
            const SizedBox(height: 12),
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
  final int goal;
  final bool goalActive;

  const _CalorieRingCard({
    required this.calories,
    required this.goal,
    required this.goalActive,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (goal - calories).clamp(0, goal);
    final progress = (goal > 0 ? calories / goal : 0.0).clamp(0.0, 1.0);

    return Container(
      decoration: WW.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: goalActive ? _buildGoalMode(calories, goal, remaining, progress) : _buildSimpleMode(),
    );
  }

  Widget _buildSimpleMode() {
    return Row(
      children: [
        const Icon(Icons.local_fire_department_rounded, color: WW.teal, size: 24),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            "Today's Energy",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WW.textSec,
            ),
          ),
        ),
        Text(
          '$calories kcal',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
          ),
        ),
      ],
    );
  }

  Widget _buildGoalMode(int calories, int goal, int remaining, double progress) {
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
                painter: _CalorieRingPainter(progress),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$calories',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Text(
                    'kcal',
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
              _statRow(WW.primary, 'Gym', '$calories kcal'),
              const SizedBox(height: 6),
              _statRow(WW.teal, 'Cardio', '0 kcal'),
              const SizedBox(height: 6),
              _statRow(WW.textSec, 'Left', '$remaining kcal'),
            ],
          ),
        ),
      ],
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
  final double progress; // 0.0–1.0

  const _CalorieRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 7.0;
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -math.pi / 2; // top of circle

    // Background track
    final trackPaint = Paint()
      ..color = WW.chipBg
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..color = WW.primary
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CalorieRingPainter old) => old.progress != progress;
}

// ── Today's Plan card ─────────────────────────────────────────────────────────

class _TodayPlanCard extends StatelessWidget {
  final String trackedPlanName;
  final VoidCallback? onGoToPlans;
  final Map<String, dynamic>? todaySession;
  final bool todayIsRestDay;
  final int currentDayIndex;
  final bool todayCompleted;
  final bool isCompressed;

  const _TodayPlanCard({
    required this.trackedPlanName,
    this.onGoToPlans,
    this.todaySession,
    this.todayIsRestDay = false,
    this.currentDayIndex = 1,
    this.todayCompleted = false,
    this.isCompressed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (trackedPlanName.isEmpty) return _buildEmptyState(context);
    if (todayIsRestDay) return _buildRestDayCard();
    return _buildPlanCard(context);
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
            trackedPlanName,
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
            onTap: onGoToPlans,
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
        todaySession?['name'] as String? ?? '';
    final estimatedMinutes =
        (todaySession?['estimatedMinutes'] as num?)?.toInt() ?? 45;
    final allExercises =
        (todaySession?['exercises'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
            [];
    // FIX 3: filter to Primary-only when session is compressed.
    final exercises = isCompressed
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
                    'DAY $currentDayIndex',
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
                        trackedPlanName,
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
                      if (isCompressed) ...[
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

          // Exercise list — show first 5, "+N more" if needed
          ...exercises.take(5).map((e) {
            final name = e['name'] as String? ?? 'Exercise';
            final sets = (e['sets'] as num?)?.toInt() ?? 3;
            final reps = (e['reps'] as num?)?.toInt() ?? 10;
            return _exerciseTile(name, '$sets × $reps reps');
          }),
          if (exercises.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '+ ${exercises.length - 5} more',
                style: const TextStyle(fontSize: 12, color: WW.textSec),
              ),
            ),

          const SizedBox(height: 16),

          // Start Workout / Completed today
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: todayCompleted
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
                    onTap: () => context.push(Routes.gymSession),
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

  Widget _exerciseTile(String name, String sets) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Container(
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
