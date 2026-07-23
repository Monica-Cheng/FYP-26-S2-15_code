// lib/screens/progress/progress_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int _subtab = 0;
  int _timeFilter = 0;
  int _activityFilter = 0;

  List<String> get _chartLabels {
    if (_timeFilter == 0) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    } else if (_timeFilter == 1) {
      return ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'];
    } else {
      return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    }
  }

  int get _bucketCount {
    if (_timeFilter == 0) return 7;
    if (_timeFilter == 1) return 4;
    return 12;
  }

  List<Map<String, dynamic>> _sessions = [];
  bool _sessionsLoading = true;
  int _totalXp = 0;
  int _level = 1;
  List<Map<String, dynamic>> _xpEvents = [];
  bool _xpEventsLoading = true;

  List<double> _caloriesByDay = [0, 0, 0, 0, 0, 0, 0];
  List<double> _volumeByDay = [0, 0, 0, 0, 0, 0, 0];
  int _weekTotalCalories = 0;
  int _weekTotalVolume = 0;
  int _weekTotalSessions = 0;
  int _weekGymSessions = 0;
  bool _chartsLoading = true;
  bool _checkInsLoading = true;
  Stream<QuerySnapshot>? _checkInsStream;

  List<Map<String, dynamic>> _weightLogs = [];
  bool _weightLoading = true;
  double? _goalWeight;
  bool _weightExpanded = true;
  StreamSubscription<List<Map<String, dynamic>>>? _weightSub;
  StreamSubscription<DocumentSnapshot>? _userDocSub;

  static const List<String> _subtabLabels = ['Charts', 'Activities', 'XP History', 'Check-ins'];
  static const List<String> _timeLabels = ['This Week', 'This Month', 'This Year'];
  static const List<String> _actLabels = ['All', 'Gym', 'Cardio', 'Manual'];

  static const _kXpThresholds = [0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000];

  static String _levelName(int level) {
    const names = [
      '', 'Rookie', 'Beginner', 'Apprentice', 'Contender',
      'Challenger', 'Warrior', 'Iron Athlete', 'Steel Athlete',
      'Elite Athlete', 'Champion', 'Legend',
    ];
    if (level < 1 || level >= names.length) return 'Level $level';
    return names[level];
  }

  double _xpProgress() {
    if (_level >= _kXpThresholds.length) return 1.0;
    final start = _kXpThresholds[_level - 1];
    final end = _kXpThresholds[_level];
    return ((_totalXp - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadXpData();
    _loadXpEvents();
    _loadChartData();
    _loadCheckIns();
    _loadGoalWeight();
    _startUserDocStream();
    _startWeightStream();
  }

  @override
  void dispose() {
    _weightSub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }

  Future<void> _loadChartData() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _chartsLoading = false);
      return;
    }
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      DateTime startDate;
      DateTime endDate;
      int bucketCount;
      String bucketUnit;

      if (_timeFilter == 0) {
        // This Week — Mon to Sun, 7 day buckets
        startDate =
            today.subtract(Duration(days: today.weekday - 1));
        endDate = startDate.add(const Duration(days: 7));
        bucketCount = 7;
        bucketUnit = 'day';
      } else if (_timeFilter == 1) {
        // This Month — 1st to end, 4 week buckets
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 1);
        bucketCount = 4;
        bucketUnit = 'week';
      } else {
        // This Year — Jan to Dec, 12 month buckets
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year + 1, 1, 1);
        bucketCount = 12;
        bucketUnit = 'month';
      }

      final stats = await FirestoreService().getSessionStats(
        uid,
        startDate: startDate,
        endDate: endDate,
        bucketCount: bucketCount,
        bucketUnit: bucketUnit,
      );

      if (!mounted) return;
      setState(() {
        _caloriesByDay =
            List<double>.from(stats['caloriesByDay'] as List);
        _volumeByDay =
            List<double>.from(stats['volumeByDay'] as List);
        _weekTotalCalories = stats['totalCalories'] as int;
        _weekTotalVolume = stats['totalVolume'] as int;
        _weekTotalSessions = stats['totalSessions'] as int;
        _weekGymSessions = stats['gymSessions'] as int;
        _chartsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _chartsLoading = false);
    }
  }

  void _loadCheckIns() {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _checkInsLoading = false);
      return;
    }
    setState(() {
      _checkInsStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('missedSessions')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots();
      _checkInsLoading = false;
    });
  }

  Future<void> _loadXpData() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await FirestoreService().getUserProfile(uid);
      if (!mounted) return;
      setState(() {
        _totalXp = (profile?['totalXp'] as num?)?.toInt() ?? 0;
        _level = (profile?['level'] as num?)?.toInt() ?? 1;
      });
    } catch (_) {}
  }

  Future<void> _loadXpEvents() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _xpEventsLoading = false);
      return;
    }
    try {
      final result = await FirestoreService().getXpEvents(uid);
      if (!mounted) return;
      setState(() {
        _xpEvents = result;
        _xpEventsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _xpEventsLoading = false);
    }
  }

  Future<void> _loadSessions() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _sessionsLoading = false);
      return;
    }
    try {
      final result = await FirestoreService().getRecentSessions(uid, limit: 20);
      if (!mounted) return;
      setState(() {
        _sessions = result;
        _sessionsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _loadGoalWeight() async {
    try {
      final uid = AuthService().getCurrentUser()?.uid;
      if (uid == null) return;
      final profile = await FirestoreService().getUserProfile(uid);
      if (!mounted) return;
      final raw = profile?['goalWeight'];
      setState(() {
        _goalWeight = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '');
      });
    } catch (_) {}
  }

  void _startUserDocStream() {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;
      final raw = data['goalWeight'];
      final newGoal = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '');
      if (newGoal != _goalWeight) {
        setState(() => _goalWeight = newGoal);
      }
    });
  }

  void _startWeightStream() {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _weightLoading = false);
      return;
    }
    _weightSub = FirestoreService()
        .getWeightLogsStream(uid)
        .listen((logs) {
      if (mounted) {
        setState(() {
          _weightLogs = logs;
          _weightLoading = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _weightLoading = false);
    });
  }

  Future<void> _logWeight(double weightKg) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    await FirestoreService().saveWeightEntry(uid, weightKg);
  }

  void _showLogWeightSheet() {
    final controller = TextEditingController();
    if (_weightLogs.isNotEmpty) {
      final last = _weightLogs.last['weightKg'];
      if (last is num) {
        controller.text = last.toStringAsFixed(1);
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log Weight',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Today · ${DateTime.now().toString().substring(0, 10)}',
              style: const TextStyle(fontSize: 12, color: WW.textSec),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: WW.text,
                    ),
                    decoration: const InputDecoration(
                      hintText: '70.0',
                      hintStyle: TextStyle(
                          color: WW.border,
                          fontSize: 32,
                          fontWeight: FontWeight.w800),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const Text(
                  'kg',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                final val = double.tryParse(controller.text);
                if (val == null || val <= 0 || val > 300) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please enter a valid weight'),
                    behavior: SnackBarBehavior.floating,
                  ));
                  return;
                }
                Navigator.of(ctx).pop();
                await _logWeight(val);
              },
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Center(
                  child: Text(
                    'Save Weight',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredSessions {
    if (_activityFilter == 0) return _sessions;
    if (_activityFilter == 3) {
      return _sessions.where((s) => s['isManuallyLogged'] == true).toList();
    }
    final type = _activityFilter == 1 ? 'gym' : 'cardio';
    return _sessions.where((s) => s['type'] == type).toList();
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'Recently';
    final date = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    final mins = seconds ~/ 60;
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String _buildManualSubtitle(Map<String, dynamic> session) {
    final date = _formatDate(session['date'] as Timestamp?);
    final mins = session['durationMinutes'];
    final cals = session['caloriesBurned'];
    final parts = [date];
    if (mins != null) parts.add('$mins min');
    if (cals != null) parts.add('$cals kcal');
    return parts.join(' · ');
  }

  String _formatVolume(double? v) {
    if (v == null || v == 0) return '';
    final n = v.round();
    if (n >= 1000) {
      return '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')} kg';
    }
    return '$n kg';
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WW.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            _buildSubtabs(),
            Expanded(
              child: IndexedStack(
                index: _subtab,
                children: [
                  _buildChartsTab(),
                  _buildActivitiesTab(),
                  _buildXpTab(),
                  _buildCheckInsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Progress',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
              ),
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: WW.primary,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'M',
                style: TextStyle(
                  fontSize: 14,
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

  // ── Subtabs ───────────────────────────────────────────────────────────────

  Widget _buildSubtabs() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: List.generate(_subtabLabels.length, (i) {
            final active = i == _subtab;
            return Padding(
              padding: EdgeInsets.only(right: i < _subtabLabels.length - 1 ? 8 : 0),
              child: GestureDetector(
                onTap: () => setState(() => _subtab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: active ? WW.primary : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      _subtabLabels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : WW.textSec,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHARTS TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChartsTab() {
    if (_chartsLoading) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildWiseCoachCard(),
          const SizedBox(height: 12),
          _buildTimeFilter(),
          const SizedBox(height: 12),
          _buildCaloriesChart(),
          const SizedBox(height: 12),
          _buildGymChart(),
          const SizedBox(height: 12),
          _buildStatCardsRow(),
          const SizedBox(height: 12),
          _buildWeightSection(),
        ],
      ),
    );
  }

  Widget _buildWiseCoachCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WW.lavenderBg,
        borderRadius: BorderRadius.circular(14),
        border: const Border(
          left: BorderSide(color: WW.lavender, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: WW.lavender,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WiseCoach Insight',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WW.lavenderDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildInsightText(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: WW.lavenderText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildInsightText() {
    final period = _timeFilter == 0
        ? 'this week'
        : _timeFilter == 1
            ? 'this month'
            : 'this year';
    if (_weekTotalSessions == 0) {
      return 'No sessions logged $period yet. Start a workout to see your insights here.';
    }
    final calStr = _weekTotalCalories > 0
        ? ' and burned $_weekTotalCalories kcal'
        : '';
    final volStr = _weekTotalVolume > 0
        ? ' with $_weekTotalVolume kg total volume'
        : '';
    final gymStr = _weekGymSessions > 0
        ? '$_weekGymSessions gym session${_weekGymSessions == 1 ? '' : 's'}'
        : '';
    final cardioCount =
        _weekTotalSessions - _weekGymSessions;
    final cardioStr = cardioCount > 0
        ? '$cardioCount cardio session${cardioCount == 1 ? '' : 's'}'
        : '';
    final sessionStr = [gymStr, cardioStr]
        .where((s) => s.isNotEmpty)
        .join(' and ');
    return 'You completed $sessionStr $period$calStr$volStr. Keep it up!';
  }

  Widget _buildTimeFilter() {
    return Row(
      children: List.generate(_timeLabels.length, (i) {
        final active = i == _timeFilter;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _timeLabels.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _timeFilter = i;
                  _chartsLoading = true;
                });
                _loadChartData();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 36,
                decoration: BoxDecoration(
                  color: active ? WW.primary : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _timeLabels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : WW.textSec,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCaloriesChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_outlined,
                  color: WW.teal, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Calories Burned',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WW.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                barGroups: List.generate(_bucketCount, (i) {
                  final val = i < _caloriesByDay.length
                      ? _caloriesByDay[i]
                      : 0.0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: val > 0 ? val : 30,
                        color: val > 0 ? WW.primary : WW.border,
                        width: 26,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        final labels = _chartLabels;
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => WW.primaryDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final val = (group.x < _caloriesByDay.length
                              ? _caloriesByDay[group.x]
                              : 0.0)
                          .round();
                      if (val == 0) return null;
                      return BarTooltipItem(
                        '$val kcal',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: $_weekTotalCalories kcal  ·  Avg: ${_weekTotalSessions > 0 ? (_weekTotalCalories / _weekTotalSessions).round() : 0} kcal/session',
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

  Widget _buildGymChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center_rounded,
                  color: WW.primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Gym Training',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WW.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                barGroups: List.generate(_bucketCount, (i) {
                  final val = i < _volumeByDay.length
                      ? _volumeByDay[i]
                      : 0.0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: val > 0 ? val : 80,
                        color: val > 0 ? WW.lavender : WW.border,
                        width: 26,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        final labels = _chartLabels;
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => WW.primaryDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final val = (group.x < _volumeByDay.length
                              ? _volumeByDay[group.x]
                              : 0.0)
                          .round();
                      if (val == 0) return null;
                      return BarTooltipItem(
                        '$val kg',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: $_weekTotalVolume kg  ·  $_weekTotalSessions sessions',
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

  Widget _buildStatCardsRow() {
    final periodLabel = _timeFilter == 0
        ? 'This Week'
        : _timeFilter == 1
            ? 'This Month'
            : 'This Year';
    final items = [
      ('$_weekTotalSessions', 'sessions\n$periodLabel'),
      ('$_weekGymSessions', 'gym\nsessions'),
    ];
    return Row(
      children: List.generate(items.length, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < items.length - 1 ? 10 : 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    items[i].$1,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: WW.textSec,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildWeightSection() {
    double? startWeight;
    double? currentWeight;
    double? change;

    if (_weightLogs.isNotEmpty) {
      final first = _weightLogs.first['weightKg'];
      final last = _weightLogs.last['weightKg'];
      startWeight = first is num ? first.toDouble() : null;
      currentWeight = last is num ? last.toDouble() : null;
      if (startWeight != null && currentWeight != null) {
        change = currentWeight - startWeight;
      }
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < _weightLogs.length; i++) {
      final w = _weightLogs[i]['weightKg'];
      if (w is num) {
        spots.add(FlSpot(i.toDouble(), w.toDouble()));
      }
    }

    double minY = 40;
    double maxY = 120;
    if (spots.isNotEmpty) {
      final weights = spots.map((s) => s.y).toList();
      minY = (weights.reduce((a, b) => a < b ? a : b) - 3).clamp(30, 200);
      maxY = (weights.reduce((a, b) => a > b ? a : b) + 3).clamp(50, 250);
      if (_goalWeight != null) {
        minY = minY.clamp(0, _goalWeight! - 2);
        maxY = maxY < _goalWeight! + 2 ? _goalWeight! + 2 : maxY;
      }
    }

    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _weightExpanded = !_weightExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: WW.tealBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.monitor_weight_outlined,
                      color: WW.teal,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Track Weight',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showLogWeightSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: WW.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '+ Log',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _weightExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: WW.textSec,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_weightExpanded) ...[
            const Divider(height: 1, color: WW.elevated),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _weightLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: WW.primary))
                  : _weightLogs.isEmpty
                      ? Column(
                          children: [
                            const Icon(Icons.monitor_weight_outlined,
                                size: 36, color: WW.border),
                            const SizedBox(height: 8),
                            const Text(
                              'No weight logged yet',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: WW.textSec,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Tap "+ Log" to record your first weight',
                              style: TextStyle(
                                  fontSize: 12, color: WW.textSec),
                            ),
                            if (_goalWeight != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: WW.tealBg,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.flag_rounded,
                                        color: WW.teal, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Goal: ${_goalWeight!.toStringAsFixed(1)} kg',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: WW.teal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 160,
                              child: LineChart(
                                LineChartData(
                                  minY: minY,
                                  maxY: maxY,
                                  gridData:
                                      const FlGridData(show: false),
                                  borderData:
                                      FlBorderData(show: false),
                                  titlesData: const FlTitlesData(
                                    leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                            showTitles: false)),
                                    rightTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                            showTitles: false)),
                                    topTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                            showTitles: false)),
                                    bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                            showTitles: false)),
                                  ),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: spots.length == 1
                                          ? [spots[0], FlSpot(spots[0].x + 0.001, spots[0].y)]
                                          : spots,
                                      isCurved: true,
                                      color: WW.primary,
                                      barWidth: 2.5,
                                      dotData: FlDotData(
                                        show: true,
                                        getDotPainter: (spot, percent,
                                            bar, index) {
                                          return FlDotCirclePainter(
                                            radius: 4,
                                            color: WW.primary,
                                            strokeWidth: 2,
                                            strokeColor: Colors.white,
                                          );
                                        },
                                      ),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: WW.primary
                                            .withOpacity(0.08),
                                      ),
                                    ),
                                    if (_goalWeight != null)
                                      LineChartBarData(
                                        spots: spots.isEmpty
                                            ? [
                                                FlSpot(0, _goalWeight!),
                                                FlSpot(1, _goalWeight!),
                                              ]
                                            : spots.length == 1
                                                ? [
                                                    FlSpot(0, _goalWeight!),
                                                    FlSpot(1, _goalWeight!),
                                                  ]
                                                : [
                                                    FlSpot(0, _goalWeight!),
                                                    FlSpot(
                                                        (spots.length - 1)
                                                            .toDouble(),
                                                        _goalWeight!),
                                                  ],
                                        isCurved: false,
                                        color: WW.teal,
                                        barWidth: 1.5,
                                        dashArray: [6, 4],
                                        dotData: const FlDotData(
                                            show: false),
                                        belowBarData:
                                            BarAreaData(show: false),
                                      ),
                                  ],
                                  lineTouchData: LineTouchData(
                                    touchTooltipData:
                                        LineTouchTooltipData(
                                      getTooltipColor: (_) =>
                                          WW.primaryDark,
                                      getTooltipItems: (touchedSpots) {
                                        return touchedSpots.map((spot) {
                                          if (spot.barIndex == 1) {
                                            return LineTooltipItem(
                                              'Goal: ${_goalWeight!.toStringAsFixed(1)} kg',
                                              const TextStyle(
                                                color: WW.teal,
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            );
                                          }
                                          final idx = spot.x.toInt();
                                          final date =
                                              idx < _weightLogs.length
                                                  ? _weightLogs[idx]
                                                          ['date']
                                                      as String? ??
                                                      ''
                                                  : '';
                                          return LineTooltipItem(
                                            '${spot.y.toStringAsFixed(1)} kg\n$date',
                                            const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        }).toList();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (currentWeight != null)
                                  Text(
                                    '${currentWeight.toStringAsFixed(1)} kg',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: WW.text,
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                if (change != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: change <= 0
                                          ? WW.tealBg
                                          : const Color(0xFFFEF3C7),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: change <= 0
                                            ? WW.teal
                                            : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                if (_goalWeight != null)
                                  Row(
                                    children: [
                                      const Icon(Icons.flag_rounded,
                                          color: WW.teal, size: 13),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Goal: ${_goalWeight!.toStringAsFixed(1)} kg',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: WW.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Recent entries',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: WW.textSec,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._weightLogs.reversed.take(5).map((log) {
                              final w = log['weightKg'];
                              final d = log['date'] as String? ?? '';
                              final wStr = w is num
                                  ? '${w.toStringAsFixed(1)} kg'
                                  : '--';
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Text(
                                      d,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: WW.textSec,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      wStr,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: WW.text,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 4),
                          ],
                        ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVITIES TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildActivitiesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActivityFilter(),
        Expanded(child: _buildActivitiesList()),
      ],
    );
  }

  Widget _buildActivitiesList() {
    if (_sessionsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: WW.primary),
      );
    }

    final sessions = _filteredSessions;

    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fitness_center_rounded, size: 48, color: WW.textSec),
            SizedBox(height: 12),
            Text(
              'No sessions yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Complete a workout to see your activity here',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WW.textSec,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = sessions[i];
        final isManual = s['isManuallyLogged'] == true;

        if (isManual) {
          return _ActivityCard(
            title: s['activityName'] as String? ?? 'Manual Activity',
            subtitle: _buildManualSubtitle(s),
            xpLabel: 'Manual',
            isCardio: false,
            isManual: true,
            onTap: () => context.push(Routes.activityDetail, extra: s),
          );
        }

        final isCardio = s['type'] == 'cardio';
        final ts = s['date'] as Timestamp?;
        final duration = _formatDuration(s['durationSeconds'] as int?);
        final sets = s['totalSets'] as int? ?? 0;
        final volume = _formatVolume((s['totalVolume'] as num?)?.toDouble());
        final xp = (s['xpEarned'] as num?)?.toInt() ?? 0;

        final parts = <String>[_formatDate(ts)];
        if (duration.isNotEmpty) parts.add(duration);
        if (!isCardio && sets > 0) parts.add('$sets sets');
        if (!isCardio && volume.isNotEmpty) parts.add(volume);
        final subtitle = parts.join(' · ');

        return _ActivityCard(
          title: s['sessionName'] as String? ?? 'Workout',
          subtitle: subtitle,
          xpLabel: '+$xp XP',
          isCardio: isCardio,
          onTap: () => context.push(Routes.activityDetail, extra: s),
        );
      },
    );
  }

  Widget _buildActivityFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: List.generate(_actLabels.length, (i) {
          final active = i == _activityFilter;
          return Padding(
            padding: EdgeInsets.only(right: i < _actLabels.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() => _activityFilter = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: active ? WW.primary : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    _actLabels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : WW.textSec,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // XP HISTORY TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildXpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLevelCard(),
          const SizedBox(height: 16),
          const Text(
            'XP HISTORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.textSec,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (_xpEventsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(color: WW.primary),
              ),
            )
          else if (_xpEvents.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.star_rounded, size: 40, color: WW.textSec),
                    SizedBox(height: 10),
                    Text(
                      'No XP history yet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Complete a workout to earn XP',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: WW.textSec,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              decoration: WW.cardDecoration,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: List.generate(_xpEvents.length, (i) {
                  return _XpRow(
                    event: _xpEvents[i],
                    isLast: i == _xpEvents.length - 1,
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLevelCard() {
    final progress = _xpProgress();
    final isMaxLevel = _level >= _kXpThresholds.length;
    final nextLevelXp = isMaxLevel ? 0 : _kXpThresholds[_level];
    final xpToNext = isMaxLevel ? 0 : nextLevelXp - _totalXp;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Lv.$_level',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: WW.primaryDark,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _levelName(_level),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: WW.border,
              valueColor: const AlwaysStoppedAnimation<Color>(WW.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isMaxLevel
                ? '$_totalXp XP · Max Level'
                : '$_totalXp XP · $xpToNext XP to Level ${_level + 1}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WW.textSec,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHECK-INS TAB
  // ══════════════════════════════════════════════════════════════════════════

  static const Map<String, Map<String, dynamic>> _reasonData = {
    'busy': {
      'label': 'Too busy',
      'sub': 'Not enough time',
      'icon': Icons.access_time_rounded,
      'color': Color(0xFF6C7EE8),
    },
    'sick': {
      'label': 'Not feeling well',
      'sub': 'Unwell or fatigued',
      'icon': Icons.thermostat_rounded,
      'color': Color(0xFFEF4444),
    },
    'injured': {
      'label': 'Injured',
      'sub': 'Needed to adapt',
      'icon': Icons.shield_outlined,
      'color': Color(0xFFF59E0B),
    },
    'rest': {
      'label': 'Needed rest',
      'sub': 'Body needed recovery',
      'icon': Icons.nightlight_round,
      'color': Color(0xFF4BB8CC),
    },
    'skip': {
      'label': 'Just skipped',
      'sub': 'No particular reason',
      'icon': Icons.skip_next_rounded,
      'color': Color(0xFF8A8A9E),
    },
  };

  Widget _buildCheckInsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _checkInsStream,
      builder: (context, snapshot) {
        if (_checkInsLoading ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: WW.primary));
        }
        final checkIns = snapshot.data?.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return {'id': doc.id, ...data};
            }).toList() ??
            [];
        if (checkIns.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: WW.elevated,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 32,
                    color: WW.textSec,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No missed sessions logged',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your check-in history will appear here.',
                  style: TextStyle(fontSize: 13, color: WW.textSec),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          itemCount: checkIns.length,
          itemBuilder: (context, index) {
            final item = checkIns[index];
            return _buildCheckInCard(item);
          },
        );
      },
    );
  }

  Widget _buildCheckInCard(Map<String, dynamic> item) {
    final reason = item['reason'] as String? ?? 'skip';
    final date = item['date'] as String? ?? '';
    final dayIndex = (item['dayIndex'] as num?)?.toInt() ?? 1;
    final planId = item['planId'] as String? ?? '';
    final rd = _reasonData[reason] ?? _reasonData['skip']!;
    final iconColor = rd['color'] as Color;
    final icon = rd['icon'] as IconData;
    final label = rd['label'] as String;
    final sub = rd['sub'] as String;

    String displayDate = date;
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        final dt = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        displayDate =
            '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
      }
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WW.border, width: 0.5),
        boxShadow: WW.shadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      displayDate,
                      style: const TextStyle(
                        fontSize: 11,
                        color: WW.textSec,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WW.textSec,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: WW.elevated,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Day $dayIndex',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: WW.textSec,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () async {
                      await context.push(
                        Routes.missedCheckin,
                        extra: {
                          'planId': planId,
                          'planName': '',
                          'missedDayIndex': dayIndex,
                          'existingDate': date,
                        },
                      );
                    },
                    child: const Text(
                      'Change reason',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Activity card ─────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String xpLabel;
  final bool isCardio;
  final bool isManual;
  final VoidCallback? onTap;

  const _ActivityCard({
    required this.title,
    required this.subtitle,
    required this.xpLabel,
    required this.isCardio,
    this.isManual = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color barColor;
    final Color iconColor;
    final IconData iconData;

    if (isManual) {
      barColor = WW.lavender;
      iconColor = WW.lavender;
      iconData = Icons.edit_note_rounded;
    } else if (isCardio) {
      barColor = WW.teal;
      iconColor = WW.teal;
      iconData = Icons.directions_run_rounded;
    } else {
      barColor = WW.primary;
      iconColor = WW.primary;
      iconData = Icons.fitness_center_rounded;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left color bar
            Container(width: 4, color: barColor),

            // Icon
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 14, 4, 14),
              child: Icon(iconData, color: iconColor, size: 22),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: WW.textSec,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Badge: XP for gym/cardio, "Manual" label for manual logs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isManual ? WW.lavenderBg : WW.tealBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  xpLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isManual ? WW.lavenderText : WW.teal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ── XP row ────────────────────────────────────────────────────────────────────

class _XpRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isLast;

  const _XpRow({required this.event, required this.isLast});

  String _formatTs(dynamic ts) {
    if (ts is! Timestamp) return 'Recently';
    final date = ts.toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final reason = event['reason'] as String? ?? 'XP earned';
    final amount = (event['amount'] as num?)?.toInt() ?? 0;
    final dateLabel = _formatTs(event['date']);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
              ),
      ),
      child: Row(
        children: [
          // Star circle
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: WW.tealBg,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.star_rounded, color: WW.teal, size: 18),
            ),
          ),
          const SizedBox(width: 10),

          // Reason + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
          ),

          // XP amount
          Text(
            '+$amount XP',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: WW.primary,
            ),
          ),
        ],
      ),
    );
  }
}
