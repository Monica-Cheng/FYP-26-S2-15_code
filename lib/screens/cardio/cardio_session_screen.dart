// lib/screens/cardio/cardio_session_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────

class CardioSessionScreen extends StatefulWidget {
  const CardioSessionScreen({super.key});

  @override
  State<CardioSessionScreen> createState() => _CardioSessionScreenState();
}

class _CardioSessionScreenState extends State<CardioSessionScreen> {
  String _activity = 'Run';
  int _plannedMinutes = 30;
  bool _fromPlan = false;
  int _goalMinutes = 0;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _timer;
  double _weightKg = 70.0;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = AuthService().getCurrentUser()?.uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      setState(() {
        _activity = extra?['activity'] as String? ?? 'Run';
        _plannedMinutes = extra?['plannedMinutes'] as int? ?? 30;
        _fromPlan = extra?['fromPlan'] as bool? ?? false;
        _goalMinutes = extra?['goalMinutes'] as int? ??
            extra?['plannedMinutes'] as int? ?? 0;
      });
      _loadUserWeight();
      _startTimer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadUserWeight() async {
    if (_uid == null) return;
    final profile = await FirestoreService().getUserProfile(_uid!);
    if (!mounted) return;
    final raw = profile?['weight'];
    if (raw is num) {
      setState(() => _weightKg = raw.toDouble());
    } else if (raw is String) {
      final parsed = double.tryParse(
          raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (parsed != null) setState(() => _weightKg = parsed);
    }
  }

  double get _calories {
    final met = _activity == 'Run'
        ? 9.0
        : _activity == 'Walk'
            ? 3.5
            : 6.0;
    return met * _weightKg * (_elapsedSeconds / 3600);
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _isRunning = true;
    _isPaused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_goalMinutes > 0 && _elapsedSeconds >= _goalMinutes * 60) {
        _timer?.cancel();
        _finishSession();
      }
    });
  }

  void _togglePause() {
    setState(() {
      if (_isPaused) {
        _isPaused = false;
        _startTimer();
      } else {
        _isPaused = true;
        _timer?.cancel();
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _finishSession() async {
    _timer?.cancel();
    final uid = _uid;
    if (uid != null) {
      try {
        await FirestoreService().saveCardioSession(
          uid: uid,
          activity: _activity,
          durationSeconds: _elapsedSeconds,
          caloriesBurned: _calories.round(),
          mode: 'indoor',
        );
      } catch (_) {}
    }
    if (!mounted) return;
    context.pushReplacement(Routes.postSessionSummary, extra: {
      'planId': null,
      'sessionName': '$_activity · Indoor',
      'elapsedSeconds': _elapsedSeconds,
      'date': DateTime.now(),
      'exercises': <dynamic>[],
      'isCardio': true,
      'cardioActivity': _activity,
      'cardioCalories': _calories.round(),
      'goalMinutes': _goalMinutes,
    });
  }

  void _showAbandonDialog() {
    _timer?.cancel();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'End session?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: WW.text,
          ),
        ),
        content: const Text(
          'Your progress will not be saved.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Resume timer if session was running
              if (!_isPaused) _startTimer();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WW.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.pop();
            },
            child: const Text(
              'End',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  IconData get _activityIcon {
    switch (_activity) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  Color get _activityColor {
    switch (_activity) {
      case 'Walk':
        return const Color(0xFF22C55E);
      case 'Cycle':
        return WW.lavender;
      default:
        return WW.teal;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final progressValue = _goalMinutes > 0
        ? (_elapsedSeconds / (_goalMinutes * 60)).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: WW.primaryDark,
      body: Column(
        children: [
          // ── Top section ───────────────────────────────────────────────────
          Container(
            color: WW.primaryDark,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Header row
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _showAbandonDialog,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.chevron_left_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_activityIcon,
                                  color: _activityColor, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                _activity,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Big elapsed time
                    Text(
                      _fmtTime(_elapsedSeconds),
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _goalMinutes > 0
                          ? 'of $_goalMinutes min goal'
                          : 'Open run',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.15),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(WW.teal),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Stats row ─────────────────────────────────────────────────────
          Container(
            color: WW.card,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                          color: WW.teal, size: 18),
                      const SizedBox(height: 4),
                      Text(
                        '${_calories.round()} kcal',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                        ),
                      ),
                      const Text(
                        'Calories',
                        style: TextStyle(fontSize: 11, color: WW.textSec),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: WW.border),
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.timer_outlined,
                          color: WW.primary, size: 18),
                      const SizedBox(height: 4),
                      Text(
                        _fmtTime(_elapsedSeconds),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                        ),
                      ),
                      const Text(
                        'Time',
                        style: TextStyle(fontSize: 11, color: WW.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Middle — big calories + goal status ──────────────────────────
          Expanded(
            child: Container(
              color: WW.bg,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_calories.round()}',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w800,
                        color: WW.text,
                        letterSpacing: -2,
                      ),
                    ),
                    const Text(
                      'kcal burned',
                      style: TextStyle(
                        fontSize: 14,
                        color: WW.textSec,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: WW.elevated,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _goalMinutes > 0
                            ? _elapsedSeconds >= _goalMinutes * 60
                                ? 'Goal reached! Keep going 🏆'
                                : '${_goalMinutes - (_elapsedSeconds ~/ 60)} min remaining'
                            : 'Open run — finish when ready',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WW.textSec,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom controls ───────────────────────────────────────────────
          Container(
            color: WW.card,
            padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Finish button
                GestureDetector(
                  onTap: _finishSession,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: WW.elevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_rounded,
                            color: WW.textSec, size: 22),
                        SizedBox(height: 4),
                        Text(
                          'Finish',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WW.textSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Pause/Resume button
                GestureDetector(
                  onTap: _togglePause,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _isPaused ? WW.teal : WW.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: WW.primary.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),

                // +5 min / Set goal button
                GestureDetector(
                  onTap: () => setState(() {
                    _goalMinutes =
                        (_goalMinutes > 0 ? _goalMinutes : 30) + 5;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: WW.elevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: WW.primary, size: 22),
                        const SizedBox(height: 4),
                        Text(
                          _goalMinutes > 0 ? '+5 min' : 'Set goal',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WW.primary,
                          ),
                        ),
                      ],
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
