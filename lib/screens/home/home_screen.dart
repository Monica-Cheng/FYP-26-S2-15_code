// lib/screens/home/home_screen.dart
// MainShell — 5-tab shell with IndexedStack + custom bottom nav.
// Tab 0 = Home (_HomeTab), tabs 1-4 = placeholder screens.
// FAB shown only on Home tab; tapping shows SnackBar.

import 'dart:math' as math;

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
    _HomeTab(key: _homeTabKey),
    const PlansScreen(),
    const CoachScreen(),
    const ClubScreen(),
    const ProgressScreen(),
  ];

  void _onTabTap(int index) => setState(() => _selectedIndex = index);

  void _onFabTap() {
    context.push(Routes.manualActivityLog)
        .then((_) => _homeTabKey.currentState?._loadCalorieData());
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
  const _HomeTab({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadHomeData();
    _loadCalorieData();
    _loadStreakData();
  }

  Future<void> _loadStreakData() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final results = await Future.wait<dynamic>([
        _firestoreService.calculateStreak(uid),
        _firestoreService.getSessionDates(uid, days: 30),
      ]);
      if (!mounted) return;
      setState(() {
        _streakDays = results[0] as int;
        _sessionDates = results[1] as Set<String>;
      });
    } catch (_) {}
  }

  Future<void> _loadCalorieData() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final results = await Future.wait<dynamic>([
        _firestoreService.getUserCalorieGoal(uid),
        _firestoreService.getTodaysCalories(uid),
      ]);
      if (!mounted) return;
      final calGoal = results[0] as Map<String, dynamic>;
      final todaysCal = results[1] as int;
      setState(() {
        _calorieGoalActive = calGoal['calorieGoalActive'] as bool? ?? false;
        _dailyCalorieGoal = calGoal['dailyCalorieGoal'] as int? ?? 500;
        _todaysCalories = todaysCal;
      });
    } catch (_) {}
  }

  Future<void> _loadHomeData() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoadingName = false);
      return;
    }
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      if (!mounted) return;
      setState(() {
        _displayName = profile?['displayName'] as String?;
        _isLoadingName = false;
      });
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
              child: _TodayPlanCard(),
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
            onTap: () => context.push(Routes.profile).then((_) => _loadCalorieData()),
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
  const _TodayPlanCard();

  @override
  Widget build(BuildContext context) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'DAY 1',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Chest, Shoulders & Triceps',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: const [
                _StatChip(icon: Icons.timer_outlined, label: '45 min'),
                SizedBox(width: 16),
                _StatChip(icon: Icons.fitness_center_rounded, label: '6 exercises'),
                SizedBox(width: 16),
                _StatChip(icon: Icons.local_fire_department_outlined, label: '~320 kcal'),
              ],
            ),
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: WW.elevated, indent: 16, endIndent: 16),
          const SizedBox(height: 10),

          // Exercise list
          _exerciseTile('Bench Press', '4 × 8–10 reps'),
          _exerciseTile('Incline Dumbbell Press', '3 × 10 reps'),
          _exerciseTile('Overhead Press', '3 × 8 reps'),
          _exerciseTile('Lateral Raises', '3 × 15 reps'),
          _exerciseTile('Tricep Pushdown', '3 × 12 reps'),
          _exerciseTile('Skull Crushers', '3 × 10 reps'),

          const SizedBox(height: 16),

          // Start Workout button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GestureDetector(
              onTap: () => context.go(Routes.gymSession),
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
