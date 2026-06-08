// lib/screens/plans/gym_session_screen.dart
// Active gym session tracker.
// Full-screen experience: no bottom nav bar.
// Timer counts up while not paused. Rest timer counts down after each done set.
// Five exercises displayed one at a time via progress dots.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/firestore_service.dart';

// ── Data models ────────────────────────────────────────────────────────────────

enum _SetType { warmup, normal, dropSet }

class _SetData {
  String prev;
  _SetType type;
  bool done;
  String kg;
  String reps;

  _SetData({
    required this.prev,
    this.type = _SetType.normal,
    this.done = false,
    this.kg = '',
    this.reps = '',
  });
}

class _ExerciseData {
  final String name;
  final String muscle;
  String note;
  int restTime; // seconds; 0 = Off
  final List<_SetData> sets;

  _ExerciseData({
    required this.name,
    required this.muscle,
    this.note = '',
    this.restTime = 90,
    required this.sets,
  });
}

// ── Column header style (module-level const) ──────────────────────────────────

const TextStyle _kColHeader = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  color: WW.textSec,
  letterSpacing: 0.4,
);

// ── Rest timer options (label, seconds) ──────────────────────────────────────

const List<(String, int)> _kRestOptions = [
  ('Off', 0),
  ('5s', 5),
  ('10s', 10),
  ('15s', 15),
  ('20s', 20),
  ('30s', 30),
  ('45s', 45),
  ('1m', 60),
  ('1m 30s', 90),
  ('2m', 120),
  ('2m 30s', 150),
  ('3m', 180),
  ('4m', 240),
  ('5m', 300),
];

String _fmtRestTime(int secs) {
  if (secs == 0) return 'Off';
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  final s = secs % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class GymSessionScreen extends StatefulWidget {
  const GymSessionScreen({super.key});

  @override
  State<GymSessionScreen> createState() => _GymSessionState();
}

class _GymSessionState extends State<GymSessionScreen> {
  int _exIdx = 0;
  int _elapsed = 0;
  bool _paused = false;
  bool _showRest = false;
  int _restSecs = 90;
  bool _isSaving = false;

  Timer? _elapsedTimer;
  Timer? _restTimer;

  // Note controllers keyed by exercise index — persists text across exercise switches.
  final Map<int, TextEditingController> _noteControllers = {};

  late final List<_ExerciseData> _exercises;

  @override
  void initState() {
    super.initState();
    _exercises = [
      _ExerciseData(
        name: 'Bench Press',
        muscle: 'Chest',
        sets: List.generate(4, (i) => _SetData(
          prev: '80kg×8',
          type: i == 0 ? _SetType.warmup : _SetType.normal,
        )),
      ),
      _ExerciseData(
        name: 'Overhead Press',
        muscle: 'Shoulders',
        sets: List.generate(3, (_) => _SetData(prev: '50kg×10')),
      ),
      _ExerciseData(
        name: 'Tricep Pushdown',
        muscle: 'Triceps',
        sets: [
          _SetData(prev: '25kg×12'),
          _SetData(prev: '25kg×12'),
          _SetData(prev: '25kg×12', type: _SetType.dropSet),
        ],
      ),
      _ExerciseData(
        name: 'Lateral Raise',
        muscle: 'Shoulders',
        sets: List.generate(3, (_) => _SetData(prev: '10kg×15')),
      ),
      _ExerciseData(
        name: 'Cable Fly',
        muscle: 'Chest',
        sets: List.generate(3, (_) => _SetData(prev: '15kg×12')),
      ),
    ];
    _startElapsedTimer();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _restTimer?.cancel();
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _noteController(int idx) {
    return _noteControllers.putIfAbsent(
      idx,
      () => TextEditingController(text: _exercises[idx].note),
    );
  }

  // ── Timers ──────────────────────────────────────────────────────────────────

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_paused && mounted) setState(() => _elapsed++);
    });
  }

  void _startRestTimer() {
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_restSecs <= 1) {
          _showRest = false;
          _restSecs = 90;
          _restTimer?.cancel();
        } else {
          _restSecs--;
        }
      });
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _togglePause() => setState(() => _paused = !_paused);

  void _cycleType(int si) {
    final set = _exercises[_exIdx].sets[si];
    if (set.done) return;
    setState(() {
      set.type = _SetType.values[(set.type.index + 1) % _SetType.values.length];
    });
  }

  void _markSetDone(int si, String kg, String reps) {
    final set = _exercises[_exIdx].sets[si];
    if (!set.done) {
      if (kg.trim().isEmpty || reps.trim().isEmpty) return;
      final restTime = _exercises[_exIdx].restTime;
      setState(() {
        set.kg = kg;
        set.reps = reps;
        set.done = true;
        if (restTime > 0) {
          _showRest = true;
          _restSecs = restTime;
        }
      });
      if (restTime > 0) _startRestTimer();
    } else {
      setState(() => set.done = false);
    }
  }

  void _addSet() {
    final ex = _exercises[_exIdx];
    final last = ex.sets.isNotEmpty ? ex.sets.last : null;
    setState(() {
      ex.sets.add(_SetData(prev: last?.prev ?? '—'));
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    setState(() {
      _showRest = false;
      _restSecs = 90;
    });
  }

  Future<void> _saveAndNavigate() async {
    if (!mounted) return;
    setState(() => _isSaving = true);

    final sessionData = {
      'sessionName': 'Push A',
      'elapsedSeconds': _elapsed,
      'exercises': _exercises
          .map((e) => {
                'name': e.name,
                'muscle': e.muscle,
                'sets': e.sets
                    .map((s) => {
                          'kg': s.kg,
                          'reps': s.reps,
                          'done': s.done,
                        })
                    .toList(),
              })
          .toList(),
    };

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      print('Saving session for uid: $uid');
      print('Session data: $sessionData');
      if (uid != null) {
        await FirestoreService().saveGymSession(uid, sessionData);
      } else {
        print('saveGymSession skipped: no authenticated user');
      }
    } catch (e) {
      print('saveGymSession error: $e');
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    context.go(Routes.postSessionSummary, extra: sessionData);
  }

  void _showFinishDialog() {
    final incomplete = _exercises
        .expand((e) => e.sets)
        .where((s) => !s.done)
        .length;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: WW.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'End session?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                incomplete > 0
                    ? '$incomplete sets remaining. Your completed sets will still be logged.'
                    : 'All sets complete. Great work!',
                style: const TextStyle(
                  fontSize: 13,
                  color: WW.textSec,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: WW.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Keep Going',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: WW.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _saveAndNavigate();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      child: const Text(
                        'End Session',
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
            ],
          ),
        ),
      ),
    );
  }

  void _showRestTimerPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RestTimerPicker(
        currentSecs: _exercises[_exIdx].restTime,
        onSet: (secs) => setState(() => _exercises[_exIdx].restTime = secs),
      ),
    );
  }

  String _fmtElapsed() {
    final h = _elapsed ~/ 3600;
    final m = (_elapsed % 3600) ~/ 60;
    final s = _elapsed % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: WW.bg,
          body: Column(
            children: [
              // Top bar extends to status bar edge.
              Container(
                color: WW.primaryDark,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top),
                    _buildTopBar(),
                    if (_showRest) _buildRestBar(),
                  ],
                ),
              ),
              _buildProgressDots(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      _buildExerciseCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildNavFooter(),
        ),
        if (_isSaving)
          const ColoredBox(
            color: Color(0x66000000),
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16))),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: WW.primary),
                      SizedBox(height: 14),
                      Text(
                        'Saving session…',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WW.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Section 1 — Top bar ───────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          // Elapsed timer
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _paused ? WW.textSec : WW.teal,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _fmtElapsed(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          // Session name
          const Text(
            'Push A',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          // Controls
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TopBarButton(
                  icon: _paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  onTap: _togglePause,
                ),
                const SizedBox(width: 8),
                _TopBarButton(
                  icon: Icons.arrow_forward_rounded,
                  onTap: _showFinishDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2 — Rest timer bar ────────────────────────────────────────────

  Widget _buildRestBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REST',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white60,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '0:${_restSecs.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          _RestButton(
            label: '+30s',
            onTap: () => setState(() => _restSecs += 30),
          ),
          const SizedBox(width: 6),
          _RestButton(label: 'Skip', onTap: _skipRest),
        ],
      ),
    );
  }

  // ── Section 3 — Progress dots ─────────────────────────────────────────────

  Widget _buildProgressDots() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: List.generate(_exercises.length, (i) {
          final allDone = _exercises[i].sets.every((s) => s.done);
          final Color dotColor;
          if (allDone) {
            dotColor = WW.teal;
          } else if (i == _exIdx) {
            dotColor = WW.primary;
          } else {
            dotColor = WW.border;
          }
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _exIdx = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 4,
                margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                decoration: BoxDecoration(
                  color: dotColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Section 4 — Exercise card ─────────────────────────────────────────────

  Widget _buildExerciseCard() {
    final ex = _exercises[_exIdx];
    final completedSets = ex.sets.where((s) => s.done).length;
    final totalSets = ex.sets.length;

    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Exercise number badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: WW.chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${_exIdx + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '$completedSets/$totalSets sets',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: WW.border,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: WW.chipBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              ex.muscle,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: WW.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Rest timer pill
                      GestureDetector(
                        onTap: _showRestTimerPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: WW.elevated,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined,
                                  size: 12, color: WW.textSec),
                              const SizedBox(width: 4),
                              Text(
                                'Rest: ${_fmtRestTime(ex.restTime)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: WW.textSec,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Info button
                GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exercise info coming soon'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: WW.elevated,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.info_outline,
                          color: WW.primary, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Set table
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                const Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text('Set', style: _kColHeader),
                    ),
                    SizedBox(width: 5),
                    SizedBox(
                      width: 32,
                      child: Text('Type', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text('Previous', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    SizedBox(
                      width: 50,
                      child: Text('kg', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    SizedBox(
                      width: 44,
                      child: Text('Reps', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    SizedBox(width: 30),
                  ],
                ),
                const SizedBox(height: 4),
                // Set rows
                ...List.generate(ex.sets.length, (si) {
                  final set = ex.sets[si];
                  return _SetRow(
                    key: ValueKey('${_exIdx}_$si'),
                    setIndex: si,
                    data: set,
                    onTypeChanged: () => _cycleType(si),
                    onToggleDone: (kg, reps) => _markSetDone(si, kg, reps),
                    onKgStored: (v) => set.kg = v,
                    onRepsStored: (v) => set.reps = v,
                  );
                }),
                // Add set
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: _addSet,
                    child: const Text(
                      '+ Add Set',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Per-exercise note
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              controller: _noteController(_exIdx),
              onChanged: (v) => ex.note = v,
              decoration: const InputDecoration(
                hintText: 'Add note… (e.g. pause at bottom, grip width)',
                hintStyle: TextStyle(fontSize: 12, color: WW.textSec),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(fontSize: 12, color: WW.text),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 5 — Navigation footer ────────────────────────────────────────

  Widget _buildNavFooter() {
    final isFirst = _exIdx == 0;
    final isLast = _exIdx == _exercises.length - 1;

    return Container(
      color: WW.card,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              // Previous
              Expanded(
                child: GestureDetector(
                  onTap: isFirst ? null : () => setState(() => _exIdx--),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFirst ? WW.border : WW.primary,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '← Previous',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isFirst ? WW.textSec : WW.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Center label
              Text(
                'Exercise ${_exIdx + 1} of ${_exercises.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: WW.textSec,
                ),
              ),
              const SizedBox(width: 8),
              // Next / Finish
              Expanded(
                child: GestureDetector(
                  onTap: isLast
                      ? _showFinishDialog
                      : () => setState(() => _exIdx++),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: isLast ? WW.teal : WW.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (isLast ? WW.teal : WW.primary).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        isLast ? 'Finish Session ✓' : 'Next →',
                        style: const TextStyle(
                          fontSize: 14,
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
        ),
      ),
    );
  }
}

// ── Top bar icon button ───────────────────────────────────────────────────────

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ── Rest timer button ─────────────────────────────────────────────────────────

class _RestButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RestButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Set row ───────────────────────────────────────────────────────────────────
// Owns kg and reps TextEditingControllers.
// Calls onKgStored/onRepsStored (no setState) to persist values in parent.
// Calls onToggleDone with current controller text when checkmark is tapped.

class _SetRow extends StatefulWidget {
  final int setIndex;
  final _SetData data;
  final VoidCallback onTypeChanged;
  final void Function(String kg, String reps) onToggleDone;
  final ValueChanged<String> onKgStored;
  final ValueChanged<String> onRepsStored;

  const _SetRow({
    required super.key,
    required this.setIndex,
    required this.data,
    required this.onTypeChanged,
    required this.onToggleDone,
    required this.onKgStored,
    required this.onRepsStored,
  });

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _kg;
  late final TextEditingController _reps;

  @override
  void initState() {
    super.initState();
    _kg = TextEditingController(text: widget.data.kg);
    _reps = TextEditingController(text: widget.data.reps);
  }

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.data.done;
    final st = widget.data.type;

    // Set type visual properties.
    final Color typeColor;
    final Color typeBg;
    final String typeLabel;
    switch (st) {
      case _SetType.warmup:
        typeColor = WW.textSec;
        typeBg = WW.elevated;
        typeLabel = 'W';
      case _SetType.normal:
        typeColor = WW.primary;
        typeBg = WW.chipBg;
        typeLabel = 'N';
      case _SetType.dropSet:
        typeColor = WW.gold;
        typeBg = Color.alphaBlend(
          WW.gold.withValues(alpha: 0.15),
          WW.card,
        );
        typeLabel = 'D';
    }

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(
        color: done ? WW.tealBg : WW.border,
        width: 1.5,
      ),
    );

    final inputDecoration = InputDecoration(
      hintText: '—',
      hintStyle: const TextStyle(fontSize: 13, color: WW.border),
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      isDense: true,
      filled: true,
      fillColor: done ? WW.tealBg : WW.card,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: WW.primary, width: 1.5),
      ),
      disabledBorder: inputBorder,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: done ? WW.teal.withValues(alpha: 0.05) : Colors.transparent,
        border: const Border(
          bottom: BorderSide(color: WW.elevated),
        ),
      ),
      child: Row(
        children: [
          // Set number
          SizedBox(
            width: 24,
            child: Text(
              '${widget.setIndex + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: done ? WW.teal : WW.text,
              ),
            ),
          ),
          const SizedBox(width: 5),
          // Type button
          GestureDetector(
            onTap: done ? null : widget.onTypeChanged,
            child: Container(
              width: 32,
              height: 22,
              decoration: BoxDecoration(
                color: typeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: typeColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          // Previous
          Expanded(
            child: Text(
              widget.data.prev,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: WW.textSec.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(width: 5),
          // kg input
          SizedBox(
            width: 50,
            child: TextField(
              controller: _kg,
              enabled: !done,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: done ? WW.teal : WW.text,
              ),
              decoration: inputDecoration,
              onChanged: widget.onKgStored,
            ),
          ),
          const SizedBox(width: 5),
          // Reps input
          SizedBox(
            width: 44,
            child: TextField(
              controller: _reps,
              enabled: !done,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: done ? WW.teal : WW.text,
              ),
              decoration: inputDecoration,
              onChanged: widget.onRepsStored,
            ),
          ),
          const SizedBox(width: 5),
          // Checkmark button
          GestureDetector(
            onTap: () => widget.onToggleDone(_kg.text, _reps.text),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: done ? WW.teal : WW.chipBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: done ? WW.teal : WW.border,
                  width: 1.5,
                ),
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: WW.border,
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

// ── Rest timer bottom-sheet picker ────────────────────────────────────────────

class _RestTimerPicker extends StatefulWidget {
  final int currentSecs;
  final ValueChanged<int> onSet;

  const _RestTimerPicker({required this.currentSecs, required this.onSet});

  @override
  State<_RestTimerPicker> createState() => _RestTimerPickerState();
}

class _RestTimerPickerState extends State<_RestTimerPicker> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    // Snap to the nearest matching option.
    final found = _kRestOptions.any((o) => o.$2 == widget.currentSecs);
    _selected = found ? widget.currentSecs : 90;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: WW.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 15, color: WW.textSec),
                ),
              ),
              const Expanded(
                child: Text(
                  'Rest Timer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  widget.onSet(_selected);
                  Navigator.pop(context);
                },
                child: const Text(
                  'Set',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: WW.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: WW.elevated),
        // Options list
        SizedBox(
          height: 280,
          child: ListView.builder(
            itemCount: _kRestOptions.length,
            itemBuilder: (_, i) {
              final (label, secs) = _kRestOptions[i];
              final isSelected = secs == _selected;
              return ListTile(
                dense: true,
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected ? WW.primary : WW.text,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: WW.primary, size: 18)
                    : null,
                onTap: () => setState(() => _selected = secs),
              );
            },
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );
  }
}
