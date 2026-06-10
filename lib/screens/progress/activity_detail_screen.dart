// lib/screens/progress/activity_detail_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  bool _exercisesExpanded = true;
  bool _wiseCoachExpanded = false;
  bool _deleteDialogOpen = false;

  Map<String, dynamic> get _session =>
      GoRouterState.of(context).extra as Map<String, dynamic>? ?? {};

  bool get _isGym => _session['type'] == 'gym';
  bool get _isManual => _session['isManuallyLogged'] == true;

  String get _title =>
      _session['sessionName'] as String? ??
      _session['activityName'] as String? ??
      'Activity';

  String _formatDate(dynamic ts) {
    DateTime date;
    if (ts is Timestamp) {
      date = ts.toDate();
    } else {
      return 'Unknown date';
    }
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDuration() {
    if (_isManual) {
      final mins = _session['durationMinutes'];
      return mins != null ? '$mins min' : '';
    }
    final secs = _session['durationSeconds'] as int?;
    if (secs == null) return '';
    final mins = secs ~/ 60;
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _formatVolume(int v) {
    if (v >= 1000) return '${v ~/ 1000},${(v % 1000).toString().padLeft(3, '0')}';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 12),
                      _buildStatsRow(),
                      const SizedBox(height: 12),
                      _buildWiseCoachCard(),
                      const SizedBox(height: 12),
                      ..._xpCardWidgets(),
                      if (_isGym) ...[
                        _buildExercisesSection(),
                        const SizedBox(height: 12),
                      ],
                      if (_isManual) ...[
                        _buildNotesSection(),
                        const SizedBox(height: 12),
                        _buildDeleteButton(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_deleteDialogOpen) _buildDeleteDialog(),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: WW.card,
          border: Border(bottom: BorderSide(color: WW.border, width: 0.5)),
          boxShadow: WW.shadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16, color: WW.primaryDark),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Share coming soon'),
                  behavior: SnackBarBehavior.floating,
                ),
              ),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.share_rounded, size: 18, color: WW.primaryDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header gradient card ───────────────────────────────────────────────────

  Widget _buildHeaderCard() {
    final duration = _formatDuration();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [WW.primaryDark, Color(0xFF4A4EA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: WW.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    _isGym
                        ? Icons.fitness_center_rounded
                        : Icons.directions_run_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(_session['date']),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha:0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (duration.isNotEmpty) ...[
                const Icon(Icons.timer_rounded, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (_isManual)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: WW.gold,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Manually logged',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stats row ──────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final List<({String label, String value})> stats;

    if (_isGym) {
      final sets = _session['totalSets'] as int? ?? 0;
      final volume =
          ((_session['totalVolume'] as num?)?.toDouble() ?? 0).round();
      final cals = _session['caloriesBurned'] as int? ?? 0;
      stats = [
        (label: 'Sets', value: '$sets'),
        (label: 'Volume', value: '${_formatVolume(volume)} kg'),
        (label: 'Calories', value: '$cals kcal'),
      ];
    } else if (_isManual) {
      final mins = _session['durationMinutes'] as int? ?? 0;
      final cals = _session['caloriesBurned'] as int? ?? 0;
      final intensity =
          _capitalize(_session['intensity'] as String? ?? 'moderate');
      stats = [
        (label: 'Duration', value: '$mins min'),
        (label: 'Calories', value: '$cals kcal'),
        (label: 'Intensity', value: intensity),
      ];
    } else {
      final dur = _formatDuration();
      final cals = _session['caloriesBurned'] as int? ?? 0;
      stats = [
        (label: 'Duration', value: dur.isEmpty ? '—' : dur),
        (label: 'Calories', value: '$cals kcal'),
        (label: 'Type', value: 'Cardio'),
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: WW.cardDecoration,
      child: Row(
        children: List.generate(stats.length, (i) {
          return Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: i < stats.length - 1
                    ? const Border(
                        right: BorderSide(
                            color: Color(0xFFE8EAF8), width: 0.5))
                    : null,
              ),
              child: Column(
                children: [
                  Text(
                    stats[i].value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stats[i].label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: WW.textSec,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── WiseCoach summary card (collapsible) ───────────────────────────────────

  Widget _buildWiseCoachCard() {
    final summary = _session['wiseCoachSummary'] as String?;
    final hasContent = summary != null && summary.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: WW.lavenderBg,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: WW.lavender, width: 3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _wiseCoachExpanded = !_wiseCoachExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
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
                const Expanded(
                  child: Text(
                    'WISECOACH SUMMARY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: WW.lavenderDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _wiseCoachExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: WW.lavenderDark, size: 20),
                ),
              ],
            ),
          ),
          if (_wiseCoachExpanded) ...[
            const SizedBox(height: 10),
            Text(
              hasContent
                  ? summary
                  : 'Complete more sessions to unlock AI insights.',
              style: TextStyle(
                fontSize: 13,
                color: hasContent ? WW.lavenderText : WW.textSec,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── XP card ────────────────────────────────────────────────────────────────

  List<Widget> _xpCardWidgets() {
    final xp = (_session['xpEarned'] as num?)?.toInt() ?? 0;
    if (xp <= 0) return [];
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: WW.tealBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, color: WW.teal, size: 22),
            const SizedBox(width: 10),
            const Text(
              'XP earned',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WW.teal),
            ),
            const Spacer(),
            Text(
              '+$xp XP',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: WW.teal,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  // ── Exercises section (gym only, collapsible) ──────────────────────────────

  Widget _buildExercisesSection() {
    final exercises = _session['exercises'] as List<dynamic>? ?? [];

    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
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
                  const Icon(Icons.fitness_center_rounded,
                      size: 18, color: WW.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Exercises (${exercises.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WW.primaryDark,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _exercisesExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: WW.textSec, size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (_exercisesExpanded) ...[
            Container(height: 0.5, color: const Color(0xFFE8EAF8)),
            if (exercises.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Text('No exercises recorded.',
                    style: TextStyle(fontSize: 13, color: WW.textSec)),
              )
            else
              ...List.generate(exercises.length, (ei) {
                final ex = exercises[ei] as Map<String, dynamic>;
                final sets = ex['sets'] as List<dynamic>? ?? [];
                final completedSets = sets.where((s) {
                  final m = s as Map<String, dynamic>;
                  return m['done'] == true || m['completed'] == true;
                }).toList();
                final muscle = ex['muscle'] as String? ??
                    ex['muscleGroup'] as String? ??
                    '';
                final exName = ex['name'] as String? ??
                    ex['exerciseName'] as String? ??
                    'Exercise';

                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: ei > 0
                          ? const BorderSide(
                              color: Color(0xFFE8EAF8), width: 0.5)
                          : BorderSide.none,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              exName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: WW.primaryDark,
                              ),
                            ),
                          ),
                          if (muscle.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: WW.elevated,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                muscle,
                                style: const TextStyle(
                                    fontSize: 11, color: WW.textSec),
                              ),
                            ),
                        ],
                      ),
                      if (completedSets.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Expanded(
                                flex: 1,
                                child: Text('Set',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: WW.textSec))),
                            Expanded(
                                flex: 2,
                                child: Text('kg',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: WW.textSec))),
                            Expanded(
                                flex: 2,
                                child: Text('Reps',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: WW.textSec))),
                          ],
                        ),
                        const SizedBox(height: 2),
                        ...List.generate(completedSets.length, (si) {
                          final s =
                              completedSets[si] as Map<String, dynamic>;
                          final weight =
                              s['weight'] ?? s['weightKg'] ?? s['w'] ?? 0;
                          final reps = s['reps'] ?? s['r'] ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                    color: Color(0xFFE8EAF8), width: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    flex: 1,
                                    child: Text('${si + 1}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: WW.textSec))),
                                Expanded(
                                    flex: 2,
                                    child: Text('$weight',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: WW.text))),
                                Expanded(
                                    flex: 2,
                                    child: Text('$reps',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: WW.text))),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  // ── Notes section (manual only) ────────────────────────────────────────────

  Widget _buildNotesSection() {
    final notes = _session['notes'] as String?;
    final hasNotes = notes != null && notes.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NOTES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.textSec,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasNotes ? notes : 'No notes added.',
            style: TextStyle(
              fontSize: 14,
              color: hasNotes ? WW.text : WW.textSec,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Delete button ──────────────────────────────────────────────────────────

  Widget _buildDeleteButton() {
    return GestureDetector(
      onTap: () => setState(() => _deleteDialogOpen = true),
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text(
            'Delete Activity',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDC2626),
            ),
          ),
        ),
      ),
    );
  }

  // ── Delete confirmation bottom sheet ──────────────────────────────────────

  Widget _buildDeleteDialog() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _deleteDialogOpen = false),
        child: Container(
          color: Colors.black.withValues(alpha:0.5),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: WW.card,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33141D3C),
                      blurRadius: 40,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: WW.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Delete activity?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: WW.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This will permanently remove this manually logged activity and its XP. This cannot be undone.',
                      style: TextStyle(
                          fontSize: 14, color: WW.textSec, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        setState(() => _deleteDialogOpen = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Delete coming soon'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text(
                            'Delete activity',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => setState(() => _deleteDialogOpen = false),
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: WW.elevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: WW.border, width: 1.5),
                        ),
                        child: const Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: WW.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
