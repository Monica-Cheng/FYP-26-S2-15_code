// lib/screens/plans/post_session_summary_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';

// ── Module-level helpers ───────────────────────────────────────────────────────

String _fmtDuration(int secs) {
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  if (m == 0) return '< 1m';
  return '${m}m';
}

String _fmtVolume(double vol) {
  final rounded = vol.round();
  if (rounded >= 1000) {
    final thousands = rounded ~/ 1000;
    final remainder = rounded % 1000;
    return '$thousands,${remainder.toString().padLeft(3, '0')}';
  }
  return '$rounded';
}

String _fmtDate(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class PostSessionSummaryScreen extends StatefulWidget {
  const PostSessionSummaryScreen({super.key});

  @override
  State<PostSessionSummaryScreen> createState() =>
      _PostSessionSummaryScreenState();
}

class _PostSessionSummaryScreenState extends State<PostSessionSummaryScreen>
    with SingleTickerProviderStateMixin {
  bool _exercisesExpanded = false;
  late AnimationController _entranceCtrl;
  late Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _checkScale = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _parseExercises(dynamic raw) {
    if (raw is! List) return _defaultExercises();
    final list = raw.where((e) => e is Map).cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return list.isEmpty ? _defaultExercises() : list;
  }

  static List<Map<String, dynamic>> _defaultExercises() => [
        {
          'name': 'Bench Press',
          'muscle': 'Chest',
          'sets': [
            {'kg': '82.5', 'reps': '8', 'done': true},
            {'kg': '82.5', 'reps': '8', 'done': true},
            {'kg': '80', 'reps': '8', 'done': true},
            {'kg': '77.5', 'reps': '8', 'done': true},
          ]
        },
        {
          'name': 'Overhead Press',
          'muscle': 'Shoulders',
          'sets': [
            {'kg': '52.5', 'reps': '10', 'done': true},
            {'kg': '52.5', 'reps': '10', 'done': true},
            {'kg': '50', 'reps': '10', 'done': true},
          ]
        },
        {
          'name': 'Tricep Pushdown',
          'muscle': 'Triceps',
          'sets': [
            {'kg': '30', 'reps': '12', 'done': true},
            {'kg': '30', 'reps': '12', 'done': true},
            {'kg': '27.5', 'reps': '12', 'done': true},
          ]
        },
        {
          'name': 'Lateral Raise',
          'muscle': 'Shoulders',
          'sets': [
            {'kg': '12', 'reps': '15', 'done': true},
            {'kg': '12', 'reps': '15', 'done': true},
            {'kg': '12', 'reps': '15', 'done': true},
          ]
        },
        {
          'name': 'Cable Fly',
          'muscle': 'Chest',
          'sets': [
            {'kg': '20', 'reps': '12', 'done': true},
            {'kg': '20', 'reps': '12', 'done': true},
            {'kg': '17.5', 'reps': '12', 'done': true},
          ]
        },
      ];

  ({int totalSets, double volume}) _calcStats(
      List<Map<String, dynamic>> exercises) {
    int totalSets = 0;
    double volume = 0;
    for (final e in exercises) {
      final sets = e['sets'];
      if (sets is! List) continue;
      for (final s in sets) {
        final m = s is Map ? s : <String, dynamic>{};
        if (m['done'] == true) {
          totalSets++;
          final kg = double.tryParse(m['kg']?.toString() ?? '') ?? 0;
          final reps = int.tryParse(m['reps']?.toString() ?? '') ?? 0;
          volume += kg * reps;
        }
      }
    }
    return (totalSets: totalSets, volume: volume);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final sessionName = extra?['sessionName'] as String? ?? 'Push A';
    final elapsedSeconds = extra?['elapsedSeconds'] as int? ?? 41 * 60;
    final date = extra?['date'] is DateTime
        ? extra!['date'] as DateTime
        : DateTime.now();
    final exercises = _parseExercises(extra?['exercises']);
    final stats = _calcStats(exercises);
    final xp = stats.totalSets * 15;
    final caloriesBurned = stats.totalSets * 8;

    return Scaffold(
      backgroundColor: WW.bg,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(sessionName, date),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatsRow(elapsedSeconds, stats, caloriesBurned),
                        const SizedBox(height: 16),
                        _buildMusclesCard(),
                        const SizedBox(height: 16),
                        _buildPbCard(),
                        const SizedBox(height: 16),
                        _buildWiseCoachCard(),
                        const SizedBox(height: 16),
                        _buildXpCard(xp),
                        const SizedBox(height: 16),
                        _buildBadgesCard(),
                        const SizedBox(height: 16),
                        _buildExercisesCard(exercises),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildActionBar(context),
        ],
      ),
    );
  }

  // ── Section 1 — Celebration header ───────────────────────────────────────

  Widget _buildHeader(String sessionName, DateTime date) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.of(context).padding.top + 28,
            24,
            32,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [WW.primaryDark, Color(0xFF4a4ea8)],
            ),
          ),
          child: Column(
            children: [
              ScaleTransition(
                scale: _checkScale,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Session Complete!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sessionName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _fmtDate(date),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        const _ConfettiBurst(),
      ],
    );
  }

  // ── Section 2 — Stats row ─────────────────────────────────────────────────

  Widget _buildStatsRow(
    int secs,
    ({int totalSets, double volume}) stats,
    int calories,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Duration',
                value: _fmtDuration(secs),
                icon: Icons.timer_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Total Sets',
                value: '${stats.totalSets}',
                icon: Icons.fitness_center_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Volume',
                value: '${_fmtVolume(stats.volume)} kg',
                icon: Icons.bar_chart_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Calories',
                value: '~$calories kcal',
                icon: Icons.local_fire_department_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Section 3 — Muscles worked ────────────────────────────────────────────

  Widget _buildMusclesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Muscles Worked',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 14),
          const _MusclesDiagram(),
        ],
      ),
    );
  }

  // ── Section 4 — Personal Bests ────────────────────────────────────────────

  Widget _buildPbCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Personal Bests 🏆',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          SizedBox(height: 12),
          _PbRow(
            exercise: 'Bench Press',
            value: '82.5 kg × 8',
            prev: '80 kg × 8',
          ),
        ],
      ),
    );
  }

  // ── Section 5 — WiseCoach ─────────────────────────────────────────────────

  Widget _buildWiseCoachCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WW.lavenderBg,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: WW.lavender, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: WW.lavender, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'WiseCoach Insight',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WW.lavenderDark,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Great session! Your bench press volume is up 8% from last week. Consider adding a 5th set next session to keep progressing.',
                  style: TextStyle(
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

  // ── Section 6 — XP banner ─────────────────────────────────────────────────

  Widget _buildXpCard(int xp) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: WW.tealBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WW.teal.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: WW.teal, size: 20),
              const SizedBox(width: 6),
              Text(
                '+$xp XP earned!',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: WW.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.72,
              minHeight: 7,
              backgroundColor: WW.teal.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(WW.teal),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Level 4 — 720 / 1000 XP to next level',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: WW.teal,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 7 — Badges ────────────────────────────────────────────────────

  Widget _buildBadgesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Badges Earned',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: WW.chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text('💪', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Iron Session',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Completed every set',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WW.textSec,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section 8 — Exercises (collapsible) ───────────────────────────────────

  static const Set<String> _pbExercises = {'Bench Press', 'Overhead Press'};

  Widget _buildExercisesCard(List<Map<String, dynamic>> exercises) {
    return Container(
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _exercisesExpanded = !_exercisesExpanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  const Text(
                    'Exercises',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${exercises.length} exercises',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WW.textSec,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _exercisesExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: WW.textSec,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_exercisesExpanded) ...[
            Container(height: 0.5, color: WW.elevated),
            ...exercises.map((e) {
              final name = e['name']?.toString() ?? '';
              final muscle = e['muscle']?.toString() ?? '';
              final sets = e['sets'];
              final setList = sets is List ? sets : [];
              final doneSets = setList.where((s) {
                return s is Map && s['done'] == true;
              }).toList();
              final isPb = _pbExercises.contains(name);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: WW.text,
                            ),
                          ),
                        ),
                        if (isPb)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: WW.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'PB 🏆',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: WW.gold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      muscle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: WW.textSec,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...doneSets.map((s) {
                      final m = s is Map ? s : <String, dynamic>{};
                      final kg = m['kg']?.toString() ?? '';
                      final reps = m['reps']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: WW.teal,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              kg.isNotEmpty && reps.isNotEmpty
                                  ? '$kg kg × $reps'
                                  : '—',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: WW.textSec,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Section 9 — Action bar ────────────────────────────────────────────────

  Widget _buildActionBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: WW.elevated, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Share coming soon'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: WW.primary, width: 1.5),
                ),
                child: const Center(
                  child: Text(
                    'Share',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => context.go(Routes.home),
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
                    'Done',
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
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: WW.cardDecoration,
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: WW.chipBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: WW.primary, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: WW.text,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: WW.textSec,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── PB row ────────────────────────────────────────────────────────────────────

class _PbRow extends StatelessWidget {
  final String exercise;
  final String value;
  final String prev;

  const _PbRow({
    required this.exercise,
    required this.value,
    required this.prev,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: WW.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Text('🏆', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exercise,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: WW.gold,
                ),
              ),
            ],
          ),
        ),
        Text(
          'prev: $prev',
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

// ── Confetti burst ────────────────────────────────────────────────────────────

class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  static const int _count = 18;
  static final List<Color> _palette = [
    WW.primary,
    WW.teal,
    WW.lavender,
    WW.gold,
    Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cx = w / 2;
        return IgnorePointer(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return SizedBox(
                width: w,
                height: 200,
                child: Stack(
                  children: List.generate(_count, (i) {
                    final phase = i / _count;
                    final angle = (phase * 2 * math.pi) - math.pi / 2;
                    final progress = _ctrl.value;
                    final t = ((progress - phase * 0.3).clamp(0.0, 1.0));
                    if (t <= 0) return const SizedBox.shrink();
                    final radius = t * 120.0;
                    final x = cx + math.cos(angle) * radius;
                    final y = 60 + math.sin(angle) * radius * 0.6 + t * t * 60;
                    final opacity = (1.0 - t * t).clamp(0.0, 1.0);
                    final color = _palette[i % _palette.length];
                    return Positioned(
                      left: x - 4,
                      top: y - 4,
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.rotate(
                          angle: t * angle * 3,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Muscles diagram ───────────────────────────────────────────────────────────

class _MusclesDiagram extends StatelessWidget {
  const _MusclesDiagram();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 190,
          height: 160,
          child: CustomPaint(painter: _MusclesPainter()),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: WW.primary, label: 'Primary'),
            const SizedBox(width: 16),
            _LegendDot(color: WW.lavender, label: 'Secondary'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: WW.textSec,
          ),
        ),
      ],
    );
  }
}

class _MusclesPainter extends CustomPainter {
  const _MusclesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = WW.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Head
    canvas.drawOval(
      Rect.fromLTWH(75, 2, 40, 36),
      outline,
    );

    // Torso
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(58, 42, 74, 76),
        const Radius.circular(8),
      ),
      outline,
    );

    // Left shoulder / arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 44, 28, 72),
        const Radius.circular(10),
      ),
      outline,
    );

    // Right shoulder / arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(134, 44, 28, 72),
        const Radius.circular(10),
      ),
      outline,
    );

    // Left leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 122, 28, 36),
        const Radius.circular(8),
      ),
      outline,
    );

    // Right leg
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(102, 122, 28, 36),
        const Radius.circular(8),
      ),
      outline,
    );

    // Highlights — chest (primary)
    final chestPaint = Paint()
      ..color = WW.primary.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(62, 48, 66, 30),
        const Radius.circular(6),
      ),
      chestPaint,
    );

    // Highlights — shoulders (primary, lighter)
    final shoulderPaint = Paint()
      ..color = WW.primary.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    // Left shoulder
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(30, 44, 28, 18),
        const Radius.circular(5),
      ),
      shoulderPaint,
    );
    // Right shoulder
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(132, 44, 28, 18),
        const Radius.circular(5),
      ),
      shoulderPaint,
    );

    // Highlights — triceps (secondary)
    final tricepPaint = Paint()
      ..color = WW.lavender.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    // Left tricep
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 64, 18, 34),
        const Radius.circular(5),
      ),
      tricepPaint,
    );
    // Right tricep
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(144, 64, 18, 34),
        const Radius.circular(5),
      ),
      tricepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
