// lib/screens/plans/build_routine_screen.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Exercise library ───────────────────────────────────────────────────────────

const _kMuscleFilters = [
  'All', 'Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Glutes', 'Cardio',
];

// ── Muscle color helpers ───────────────────────────────────────────────────────

Color _muscleColor(String muscle) {
  switch (muscle) {
    case 'Chest':
      return WW.primary;
    case 'Back':
      return WW.teal;
    case 'Shoulders':
      return WW.lavender;
    case 'Arms':
      return const Color(0xFFF97316);
    case 'Legs':
      return const Color(0xFF10B981);
    case 'Core':
      return const Color(0xFFEF4444);
    case 'Glutes':
      return const Color(0xFFD97706);
    case 'Cardio':
      return WW.teal;
    default:
      return WW.textSec;
  }
}

Color _muscleBg(String muscle) {
  switch (muscle) {
    case 'Chest':
      return WW.chipBg;
    case 'Back':
      return WW.tealBg;
    case 'Shoulders':
      return WW.lavenderBg;
    case 'Arms':
      return const Color(0xFFFFF3E0);
    case 'Legs':
      return const Color(0xFFF0FFF4);
    case 'Core':
      return const Color(0xFFFFF0F0);
    case 'Glutes':
      return const Color(0xFFFEF3C7);
    case 'Cardio':
      return WW.tealBg;
    default:
      return WW.elevated;
  }
}

// ── Set type helpers ───────────────────────────────────────────────────────────

// 'W' = Warmup, 'N' = Normal, 'D' = Drop Set
const _kSetTypes = ['W', 'N', 'D'];

String _nextSetType(String current) {
  final idx = _kSetTypes.indexOf(current);
  return _kSetTypes[(idx + 1) % _kSetTypes.length];
}

Color _setTypeColor(String type) {
  switch (type) {
    case 'W':
      return WW.textSec;
    case 'D':
      return WW.gold;
    default:
      return WW.primary;
  }
}

Color _setTypeBg(String type) {
  switch (type) {
    case 'W':
      return WW.elevated;
    case 'D':
      return const Color(0xFFFEF3C7);
    default:
      return WW.chipBg;
  }
}

// ── Rest timer helpers ─────────────────────────────────────────────────────────

// Off + 5 s, 10 s … 5 min (every 5 s)
final _kRestValues = [0, ...List.generate(60, (i) => (i + 1) * 5)];

String _fmtRest(int secs) {
  if (secs == 0) return 'Off';
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  final s = secs % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}

// ── Column header style ────────────────────────────────────────────────────────

const _kColHdr = TextStyle(
  fontSize: 9,
  fontWeight: FontWeight.w700,
  color: WW.textSec,
  letterSpacing: 0.4,
);

// ── Screen ─────────────────────────────────────────────────────────────────────

class BuildRoutineScreen extends StatefulWidget {
  const BuildRoutineScreen({super.key});

  @override
  State<BuildRoutineScreen> createState() => _BuildRoutineScreenState();
}

class _BuildRoutineScreenState extends State<BuildRoutineScreen> {
  // ── State ──────────────────────────────────────────────────────────────────

  String _routineName = 'My Custom Routine';
  int _activeDay = 0;
  late List<Map<String, dynamic>> _days;
  bool _hasChanges = false;
  bool _isSaving = false;
  bool _isLoading = false;
  String? _existingPlanId;

  // Set from extra['isCoachPlan'] (see _initFromExtra) — true only when
  // this screen was opened from coach_dashboard_screen.dart's "Create a
  // Plan" entry point, never for a normal personal-plan save (including
  // a coach account's OWN personal plans via the ordinary flow everyone
  // else uses). Read via the same GoRouterState.of(context).extra map
  // this screen already uses for planId/isCustom, rather than a new
  // constructor param — matching this screen's existing pattern.
  bool _isCoachPlan = false;

  // Unique id counter (string keys for controllers etc.)
  int _idCounter = 0;
  String _nextId() => '${_idCounter++}';

  // TextEditingControllers for set kg/reps, keyed by '${setId}_kg'/'_reps'
  final Map<String, TextEditingController> _controllers = {};

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  bool get _isEditMode => _existingPlanId != null;

  @override
  void initState() {
    super.initState();
    _days = [_newDay('Day 1')];
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFromExtra());
  }

  Future<void> _initFromExtra() async {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra == null) return;

    if (extra['isCoachPlan'] == true) {
      setState(() {
        _isCoachPlan = true;
        _routineName = 'New Coach Plan';
      });
    }

    final planId = extra['id'] as String?;

    if (planId != null && planId.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _existingPlanId = planId;
      });
      try {
        final plan = await FirestoreService().getPlan(planId);
        if (!mounted) return;
        if (plan == null) {
          _snack('Could not load routine');
          setState(() => _isLoading = false);
          return;
        }
        _populateFromPlan(plan);
      } catch (e) {
        if (!mounted) return;
        _snack('Failed to load routine');
        setState(() => _isLoading = false);
      }
    } else if (extra['isCustom'] == true) {
      _populateFromPlan(extra);
    }
  }

  void _populateFromPlan(Map<String, dynamic> plan) {
    final rawSessions = (plan['sessions'] as List<dynamic>?)
            ?.map((s) => s as Map<String, dynamic>)
            .toList() ??
        [];

    final mappedDays = rawSessions.map((session) {
      final rawExs = (session['exercises'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];

      final exercises = rawExs.map((ex) {
        final rawSets = ex['sets'];
        final List<Map<String, dynamic>> sets;
        if (rawSets is List && rawSets.isNotEmpty) {
          sets = (rawSets as List<dynamic>).map((s) {
            final sm = s as Map<String, dynamic>;
            final sid = _nextId();
            return <String, dynamic>{
              'id': sid,
              'type': sm['type'] as String? ?? 'N',
              'kg': sm['kg']?.toString() ?? '',
              'reps': sm['reps']?.toString() ?? '',
            };
          }).toList();
        } else {
          sets = [_newSet()];
        }

        return <String, dynamic>{
          'id': _nextId(),
          'name': ex['name'] as String? ?? '',
          'muscle': ex['muscle'] as String? ?? '',
          'restTime': (ex['restTime'] as num?)?.toInt() ?? 90,
          // Preserves whatever this exercise was actually saved with —
          // without this, re-opening an existing routine for edit would
          // silently reset every exercise back to the 'Primary' default
          // the moment it's saved again, discarding any Accessory choice
          // made in an earlier edit.
          'tag': ex['tag'] as String? ?? 'Primary',
          'sets': sets,
        };
      }).toList();

      return <String, dynamic>{
        'id': _nextId(),
        'label': session['day'] as String? ?? session['name'] as String? ?? 'Day',
        'exercises': exercises,
      };
    }).toList();

    setState(() {
      _routineName = plan['name'] as String? ?? 'My Custom Routine';
      _existingPlanId = plan['id'] as String?;
      _days = mappedDays.isNotEmpty ? mappedDays : [_newDay('Day 1')];
      _activeDay = 0;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Factories ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _newDay(String label) => {
        'id': _nextId(),
        'label': label,
        'exercises': <Map<String, dynamic>>[],
      };

  Map<String, dynamic> _newExercise(String name, String muscle) => {
        'id': _nextId(),
        'name': name,
        'muscle': muscle,
        'restTime': 90,
        // Safe default — matches admin-authored plans' own default (see
        // PlanSessionsEditor.js's emptyExercise()). No equivalent field on
        // cardio blocks (see _addCardioBlock) — compression handles cardio
        // via duration override, not removal, so tagging one Accessory
        // would have no effect.
        'tag': 'Primary',
        'sets': <Map<String, dynamic>>[
          _newSet(),
        ],
      };

  Map<String, dynamic> _newSet({String type = 'N'}) => {
        'id': _nextId(),
        'type': type,
        'kg': '',
        'reps': '',
      };

  // ── Controller getter ──────────────────────────────────────────────────────

  TextEditingController _ctrl(String key, String initial) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initial));

  void _removeCtrlsForSet(Map<String, dynamic> set) {
    final id = set['id'] as String;
    _controllers.remove('${id}_kg')?.dispose();
    _controllers.remove('${id}_reps')?.dispose();
  }

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get _canSave =>
      _days.any((d) => (d['exercises'] as List).isNotEmpty);

  List<Map<String, dynamic>> get _currentExercises =>
      List<Map<String, dynamic>>.from(
          _days[_activeDay]['exercises'] as List);

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: WW.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showDiscardDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Discard routine?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: WW.text),
        ),
        content: const Text(
          'All changes will be lost.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w700, color: WW.textSec)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.pop();
            },
            child: const Text('Discard',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _routineName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Rename Routine',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: WW.text),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Routine name',
            hintStyle: const TextStyle(color: WW.textSec),
            filled: true,
            fillColor: WW.elevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WW.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w700, color: WW.textSec)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _routineName = name;
                  _hasChanges = true;
                });
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w700, color: WW.primary)),
          ),
        ],
      ),
    );
  }

  void _showDayRenameDialog(int dayIdx) {
    final ctrl = TextEditingController(text: _days[dayIdx]['label'] as String);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Rename Day',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: WW.text),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Day name',
            hintStyle: const TextStyle(color: WW.textSec),
            filled: true,
            fillColor: WW.elevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WW.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w700, color: WW.textSec)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _days[dayIdx]['label'] = name;
                  _hasChanges = true;
                });
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w700, color: WW.primary)),
          ),
        ],
      ),
    );
  }

  // ── Exercise actions ───────────────────────────────────────────────────────

  void _addExercise(String name, String muscle) {
    setState(() {
      (_days[_activeDay]['exercises'] as List<Map<String, dynamic>>)
          .add(_newExercise(name, muscle));
      _hasChanges = true;
    });
  }

  void _deleteExercise(int exIdx) {
    final ex = _currentExercises[exIdx];
    // Clean up controllers for all sets
    for (final s in (ex['sets'] as List<Map<String, dynamic>>)) {
      _removeCtrlsForSet(s);
    }
    setState(() {
      (_days[_activeDay]['exercises'] as List).removeAt(exIdx);
      _hasChanges = true;
    });
  }

  void _deleteDay(int dayIdx) {
    if (_days.length <= 1) return;
    // Clean up controllers for every set in every exercise on this day
    final exercises =
        _days[dayIdx]['exercises'] as List<Map<String, dynamic>>;
    for (final ex in exercises) {
      for (final s in (ex['sets'] as List<Map<String, dynamic>>)) {
        _removeCtrlsForSet(s);
      }
    }
    setState(() {
      _days.removeAt(dayIdx);
      if (_activeDay > dayIdx) {
        _activeDay--;
      } else if (_activeDay == dayIdx) {
        _activeDay = _activeDay.clamp(0, _days.length - 1);
      }
      _hasChanges = true;
    });
  }

  // ── Rest timer picker ──────────────────────────────────────────────────────

  void _showRestPicker(int exIdx) {
    final ex = _currentExercises[exIdx];
    final current = ex['restTime'] as int? ?? 90;
    int selected = current;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheetState) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: WW.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Rest Timer',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: WW.border),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _kRestValues.length,
                    itemBuilder: (ctx3, i) {
                      final val = _kRestValues[i];
                      final isSelected = val == selected;
                      return InkWell(
                        onTap: () => setSheetState(() => selected = val),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _fmtRest(val),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: isSelected ? WW.primary : WW.text,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_rounded,
                                    color: WW.primary, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() {
                        (_days[_activeDay]['exercises']
                            as List<Map<String, dynamic>>)[exIdx]['restTime'] = selected;
                        _hasChanges = true;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: WW.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          selected == 0
                              ? 'Turn Off Rest Timer'
                              : 'Set — Rest ${_fmtRest(selected)}',
                          style: const TextStyle(
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
        },
      ),
    );
  }

  // ── Exercise search sheet ──────────────────────────────────────────────────

  void _showExerciseSheet() {
    final currentNames = _currentExercises.map((e) => e['name'] as String).toSet();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WW.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ExerciseSearchSheet(
        alreadyAdded: currentNames,
        onAdd: (name, muscle) {
          Navigator.of(ctx).pop();
          _addExercise(name, muscle);
        },
      ),
    );
  }

  // ── Cardio sheet ───────────────────────────────────────────────────────────

  void _showCardioSheet() {
    String selectedActivity = 'Run';
    int selectedMinutes = 30;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Cardio Block',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Indoor/outdoor choice is made when starting the session.',
                style: TextStyle(fontSize: 12, color: WW.textSec),
              ),
              const SizedBox(height: 16),
              Row(
                children: ['Run', 'Walk', 'Cycle'].map((activity) {
                  final isSelected = selectedActivity == activity;
                  final icon = activity == 'Run'
                      ? Icons.directions_run_rounded
                      : activity == 'Walk'
                          ? Icons.directions_walk_rounded
                          : Icons.directions_bike_rounded;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setModal(() => selectedActivity = activity),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? WW.primary : WW.elevated,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(icon,
                                color:
                                    isSelected ? Colors.white : WW.textSec,
                                size: 22),
                            const SizedBox(height: 4),
                            Text(
                              activity,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    isSelected ? Colors.white : WW.textSec,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Duration (minutes)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CupertinoPicker(
                  itemExtent: 36,
                  scrollController: FixedExtentScrollController(
                    initialItem: selectedMinutes - 1,
                  ),
                  onSelectedItemChanged: (index) {
                    setModal(() => selectedMinutes = index + 1);
                  },
                  children: List.generate(
                    120,
                    (i) => Center(
                      child: Text(
                        '${i + 1} min',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: WW.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  _addCardioBlock(selectedActivity, selectedMinutes);
                },
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: WW.teal,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Center(
                    child: Text(
                      'Add Cardio Block',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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

  void _addCardioBlock(String activity, int minutes) {
    setState(() {
      (_days[_activeDay]['exercises'] as List<Map<String, dynamic>>)
          .add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': '$activity ${minutes}min',
        'muscle': 'Cardio',
        'restTime': 0,
        'isCardio': true,
        'cardioActivity': activity,
        'cardioMinutes': minutes,
        'sets': [
          {
            'id': '1',
            'type': 'N',
            'kg': '',
            'reps': minutes.toString(),
          }
        ],
      });
      _hasChanges = true;
    });
    _snack('$activity block added to ${_days[_activeDay]['label']}.');
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _saveRoutine() async {
    if (_routineName.trim().isEmpty) {
      _snack('Please enter a routine name');
      return;
    }
    if (!_canSave) {
      _snack('Add at least one exercise to save');
      return;
    }

    setState(() => _isSaving = true);

    // Captured before any await. The previous fix gated BOTH the success
    // SnackBar and the pop behind a single `if (mounted)` check made AFTER
    // the Firestore write — so if this widget became unusable for any
    // reason during that async gap, the entire feedback block (snackbar
    // included) was silently skipped even though the write itself had
    // already succeeded. Confirmed via live testing: edit-mode saves DO
    // persist to Firestore with zero visible feedback — exactly this
    // symptom. Grabbing the ScaffoldMessengerState up front means showing
    // the success snackbar no longer depends on `context`/`mounted` still
    // being valid once the write resolves; only the actual navigation
    // (which genuinely does require a live widget) stays behind the
    // mounted guard below.
    final messenger = ScaffoldMessenger.of(context);
    final wasEditMode = _isEditMode;

    try {
      print('Saving routine: $_routineName');
      final uid = AuthService().getCurrentUser()?.uid;
      if (uid == null) {
        _snack('Please sign in to save');
        return;
      }
      print('UID: $uid');

      final sessions = _days.asMap().entries.map((entry) {
        final i = entry.key;
        final day = entry.value;
        final exercises =
            (day['exercises'] as List<Map<String, dynamic>>).map((ex) {
          final sets = (ex['sets'] as List<Map<String, dynamic>>).map((s) {
            final sid = s['id'] as String;
            return {
              'type': s['type'],
              'kg': _controllers['${sid}_kg']?.text ?? s['kg'],
              'reps': _controllers['${sid}_reps']?.text ?? s['reps'],
            };
          }).toList();

          return {
            'name': ex['name'],
            'muscle': ex['muscle'],
            'restTime': ex['restTime'],
            // No tag at all for cardio blocks — matches admin-authored
            // plans' own emptyCardioBlock() default (no tag field),
            // consistent with compression treating cardio as a duration
            // override rather than something to remove.
            if (ex['isCardio'] != true)
              'tag': ex['tag'] as String? ?? 'Primary',
            'sets': sets,
            if (ex['isCardio'] == true) ...{
              'isCardio': true,
              'cardioActivity': ex['cardioActivity'] ?? 'Run',
              'cardioMinutes': ex['cardioMinutes'] ?? 30,
            },
          };
        }).toList();

        return {
          'name': day['label'],
          'day': 'Day ${i + 1}',
          'type': 'gym',
          'isRestDay': false,
          'exercises': exercises,
        };
      }).toList();

      print('Sessions: $sessions');

      final activeDays =
          _days.where((d) => (d['exercises'] as List).isNotEmpty).length;

      if (_isEditMode) {
        await FirestoreService().updateCustomRoutine(
          planId: _existingPlanId!,
          routineName: _routineName.trim(),
          sessions: sessions,
          daysPerWeek: activeDays,
        );
      } else {
        await FirestoreService().saveCustomRoutine(
          uid: uid,
          routineName: _routineName.trim(),
          sessions: sessions,
          daysPerWeek: activeDays,
          isCoachPlan: _isCoachPlan,
        );
      }

      print('Saved successfully!');

      if (mounted) setState(() => _hasChanges = false);
      // Uses the messenger captured before the write, not _snack(context) —
      // see this method's own note above on why: showing this no longer
      // depends on the widget still being mounted at this point.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              wasEditMode ? 'Routine updated.' : 'Routine saved to All Plans.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: WW.primaryDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      // Same short delay plan_detail_screen.dart's _handleDeleteCustomPlan
      // already uses between showing a SnackBar and popping — popping
      // immediately after showSnackBar() tears the route down before the
      // SnackBar has actually rendered, so it was never visible at all.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      context.pop(wasEditMode);
    } catch (e) {
      print('Save error: $e');
      if (mounted) _snack('Failed to save. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(),
              _buildDayTabs(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: WW.primary),
                      )
                    : _buildExerciseList(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildFooter(),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // × close
          GestureDetector(
            onTap: () {
              if (_hasChanges) {
                _showDiscardDialog();
              } else {
                context.pop();
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.close_rounded, color: WW.textSec, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Routine name (tappable)
          Expanded(
            child: GestureDetector(
              onTap: _showRenameDialog,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _routineName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: WW.primaryDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_rounded, size: 13, color: WW.textSec),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Save button
          GestureDetector(
            onTap: _canSave && !_isSaving ? _saveRoutine : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: _canSave ? WW.primary : WW.elevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isEditMode ? 'Update' : 'Save',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _canSave ? Colors.white : WW.textSec,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Day tabs ───────────────────────────────────────────────────────────────

  Widget _buildDayTabs() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _days.length + 1,
        itemBuilder: (ctx, i) {
          // "+" add day tab
          if (i == _days.length) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _days.add(_newDay('Day ${_days.length + 1}'));
                    _activeDay = _days.length - 1;
                    _hasChanges = true;
                  });
                },
                child: Container(
                  width: 40,
                  height: 36,
                  decoration: BoxDecoration(
                    color: WW.elevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: WW.border, width: 1),
                  ),
                  child: const Center(
                    child: Icon(Icons.add_rounded, size: 18, color: WW.textSec),
                  ),
                ),
              ),
            );
          }

          final active = i == _activeDay;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _DayTab(
              label: _days[i]['label'] as String,
              active: active,
              canDelete: _days.length > 1,
              onTap: () => setState(() => _activeDay = i),
              onRename: () => _showDayRenameDialog(i),
              onDelete: () => _deleteDay(i),
            ),
          );
        },
      ),
    );
  }

  // ── Exercise list ──────────────────────────────────────────────────────────

  Widget _buildExerciseList() {
    final exercises = _currentExercises;

    if (exercises.isEmpty) {
      return _buildEmptyDayState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: exercises.length,
      itemBuilder: (ctx, exIdx) {
        final ex = exercises[exIdx];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ExerciseCard(
            key: ValueKey(ex['id']),
            exercise: ex,
            getCtrl: _ctrl,
            onChanged: () => setState(() => _hasChanges = true),
            onDelete: () => _deleteExercise(exIdx),
            onDeleteSet: (set) {
              _removeCtrlsForSet(set);
              setState(() => _hasChanges = true);
            },
            onShowRest: () => _showRestPicker(exIdx),
            onSnack: _snack,
          ),
        );
      },
    );
  }

  Widget _buildEmptyDayState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: WW.chipBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Icon(Icons.fitness_center_rounded,
                    size: 30, color: WW.primary),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No exercises yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap + Add Exercise below to start building\nyour workout.',
              style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      color: WW.card,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _showExerciseSheet,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: WW.primary.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '+ Add Exercise',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _showCardioSheet,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WW.teal, width: 1.5),
                    ),
                    child: const Center(
                      child: Text(
                        '+ Add Cardio',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: WW.teal,
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

// ── Day tab ────────────────────────────────────────────────────────────────────
// Mirrors _ExerciseCard's overflow-menu pattern below: a small trigger opens
// an Overlay-based popup (Rename / Delete Day) instead of only exposing
// rename via long-press. Delete is guarded by widget.canDelete (hidden when
// this is the last remaining day) — see _deleteDay's own guard in
// _BuildRoutineScreenState.

class _DayTab extends StatefulWidget {
  final String label;
  final bool active;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _DayTab({
    required this.label,
    required this.active,
    required this.canDelete,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_DayTab> createState() => _DayTabState();
}

class _DayTabState extends State<_DayTab> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  void _openMenu() {
    const menuWidth = 170.0;
    // The old fixed Offset(-130, 28) was copied from _ExerciseCard's "⋮"
    // menu below, whose CompositedTransformTarget wraps only a small icon
    // near the right edge of a wide card — subtracting 130px there still
    // lands on-screen. Here the target is the *whole* day-tab pill, which
    // (for Day 1) sits flush against the row's left padding, so the same
    // negative offset pushed the menu off-screen to the left. Instead,
    // measure the tapped tab's real on-screen position/size and clamp the
    // menu's left edge to stay within the screen on both sides, for any
    // tab position.
    final targetBox = context.findRenderObject() as RenderBox;
    final targetGlobalPos = targetBox.localToGlobal(Offset.zero);
    final targetSize = targetBox.size;
    final screenWidth = MediaQuery.of(context).size.width;
    final clampedLeft = targetGlobalPos.dx.clamp(8.0, screenWidth - menuWidth - 8.0);
    final menuOffset = Offset(
      clampedLeft - targetGlobalPos.dx,
      targetSize.height + 8,
    );

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeMenu,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            width: menuWidth,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: menuOffset,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: WW.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WW.border, width: 0.5),
                    boxShadow: WW.shadow,
                  ),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _menuItem(
                          icon: Icons.edit_outlined,
                          label: 'Rename Day',
                          onTap: () {
                            _closeMenu();
                            widget.onRename();
                          },
                        ),
                        if (widget.canDelete)
                          _menuItem(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete Day',
                            color: const Color(0xFFEF4444),
                            onTap: () {
                              _closeMenu();
                              widget.onDelete();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = WW.text,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onRename,
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: BoxDecoration(
            color: widget.active ? WW.primary : WW.elevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.active ? Colors.white : WW.textSec,
                ),
              ),
              GestureDetector(
                onTap: _openMenu,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: widget.active ? Colors.white : WW.textSec,
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

// ── Exercise card ──────────────────────────────────────────────────────────────

class _ExerciseCard extends StatefulWidget {
  final Map<String, dynamic> exercise;
  final TextEditingController Function(String key, String initial) getCtrl;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final void Function(Map<String, dynamic> set) onDeleteSet;
  final VoidCallback onShowRest;
  final void Function(String msg) onSnack;

  const _ExerciseCard({
    required super.key,
    required this.exercise,
    required this.getCtrl,
    required this.onChanged,
    required this.onDelete,
    required this.onDeleteSet,
    required this.onShowRest,
    required this.onSnack,
  });

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  bool _menuOpen = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  Map<String, dynamic> get _ex => widget.exercise;
  List<Map<String, dynamic>> get _sets =>
      List<Map<String, dynamic>>.from(_ex['sets'] as List);

  void _addSet() {
    final sets = _ex['sets'] as List<Map<String, dynamic>>;
    final newSet = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': 'N',
      'kg': '',
      'reps': '',
      'done': false,
    };
    sets.add(newSet);
    widget.onChanged();
  }

  void _deleteSet(int setIdx) {
    final sets = _ex['sets'] as List<Map<String, dynamic>>;
    final set = sets[setIdx];
    widget.onDeleteSet(set);
    sets.removeAt(setIdx);
    widget.onChanged();
  }

  void _cycleType(int setIdx) {
    final set = (_ex['sets'] as List<Map<String, dynamic>>)[setIdx];
    set['type'] = _nextSetType(set['type'] as String? ?? 'N');
    widget.onChanged();
  }

  // Toggles this exercise between Primary/Accessory — same tap-to-cycle
  // pattern as _cycleType() above, just a 2-value cycle instead of 3. No
  // equivalent exists (or is called) for cardio blocks — see the tag pill's
  // own `if (!isCardio)` gate in build() below.
  void _cycleTag() {
    final current = _ex['tag'] as String? ?? 'Primary';
    _ex['tag'] = current == 'Accessory' ? 'Primary' : 'Accessory';
    widget.onChanged();
  }

  void _toggleMenu() {
    if (_menuOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeMenu,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            width: 180,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(-140, 28),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: WW.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WW.border, width: 0.5),
                    boxShadow: WW.shadow,
                  ),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _menuItem(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Replace Exercise',
                          onTap: () {
                            _closeMenu();
                            widget.onSnack('Replace coming soon');
                          },
                        ),
                        _menuItem(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete Exercise',
                          color: const Color(0xFFEF4444),
                          onTap: () {
                            _closeMenu();
                            widget.onDelete();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    setState(() => _menuOpen = true);
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = _ex['name'] as String? ?? '';
    final muscle = _ex['muscle'] as String? ?? '';
    final restTime = _ex['restTime'] as int? ?? 90;
    final isCardio = _ex['isCardio'] as bool? ?? false;
    final cardioActivity = _ex['cardioActivity'] as String? ?? '';
    final cardioMinutes = _ex['cardioMinutes'] as int? ?? 30;
    final tag = _ex['tag'] as String? ?? 'Primary';
    final isAccessory = tag == 'Accessory';
    final mc = _muscleColor(muscle);
    final mb = _muscleBg(muscle);
    final isOff = restTime == 0;

    return Stack(
      children: [
        Container(
          decoration: WW.cardDecoration,
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                // Muscle icon dot
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: mb,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: mc.withValues(alpha: 0.15), width: 0.5),
                  ),
                  child: Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: mc,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Name + muscle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (!isCardio) ...[
                      const SizedBox(height: 4),
                      // Rest timer pill + Primary/Accessory tag pill — Wrap
                      // (not Row) so the two pills fall to a second line
                      // instead of overflowing on narrow screens (see the
                      // Small_Phone-profile overflow lessons elsewhere in
                      // this app).
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          GestureDetector(
                        onTap: widget.onShowRest,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOff ? WW.elevated : WW.tealBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isOff
                                  ? WW.border
                                  : WW.teal.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 10,
                                color: isOff ? WW.textSec : WW.teal,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOff
                                    ? 'Rest: Off'
                                    : 'Rest: ${_fmtRest(restTime)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isOff ? WW.textSec : WW.teal,
                                ),
                              ),
                            ],
                          ),
                        ),
                          ),
                          // Primary/Accessory tag pill — tap to cycle, same
                          // interaction pattern as a set's type cycling
                          // (_cycleType). Determines whether Compress can
                          // ever offer to remove this exercise; defaults to
                          // Primary (never removed) until the user marks it
                          // otherwise.
                          GestureDetector(
                            onTap: () => setState(() => _cycleTag()),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isAccessory ? WW.elevated : WW.chipBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isAccessory
                                      ? WW.border
                                      : WW.primary.withValues(alpha: 0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isAccessory
                                        ? Icons.low_priority_rounded
                                        : Icons.push_pin_rounded,
                                    size: 10,
                                    color: isAccessory ? WW.textSec : WW.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          isAccessory ? WW.textSec : WW.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    ],
                  ),
                ),
                // ⓘ info button
                if (!isCardio) ...[
                  GestureDetector(
                    onTap: () => context.push(
                      Routes.exerciseDetail,
                      extra: {
                        'name': _ex['name'] as String? ?? '',
                        'muscle': _ex['muscle'] as String? ?? '',
                      },
                    ),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: WW.elevated,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.info_outline,
                            size: 16, color: WW.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                // ⋮ more menu
                CompositedTransformTarget(
                  link: _layerLink,
                  child: GestureDetector(
                    onTap: _toggleMenu,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.more_vert_rounded,
                          size: 18, color: WW.textSec),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isCardio) ...[
            // Cardio summary row — no sets, no columns
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Row(
                children: [
                  Icon(
                    cardioActivity == 'Run'
                        ? Icons.directions_run_rounded
                        : cardioActivity == 'Walk'
                            ? Icons.directions_walk_rounded
                            : Icons.directions_bike_rounded,
                    size: 16,
                    color: WW.teal,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$cardioActivity · $cardioMinutes min',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WW.textSec,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Indoor/outdoor at session start',
                    style: TextStyle(
                      fontSize: 11,
                      color: WW.textSec,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── Set table header ─────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 2),
              child: Row(
                children: [
                  SizedBox(
                      width: 24,
                      child: Text('SET', style: _kColHdr, textAlign: TextAlign.center)),
                  SizedBox(width: 5),
                  SizedBox(
                      width: 32,
                      child: Text('TYPE', style: _kColHdr, textAlign: TextAlign.center)),
                  SizedBox(width: 5),
                  Expanded(
                      child: Text('PREV', style: _kColHdr, textAlign: TextAlign.center)),
                  SizedBox(width: 5),
                  SizedBox(
                      width: 50,
                      child: Text('KG', style: _kColHdr, textAlign: TextAlign.center)),
                  SizedBox(width: 5),
                  SizedBox(
                      width: 44,
                      child: Text('REPS', style: _kColHdr, textAlign: TextAlign.center)),
                ],
              ),
            ),

            // ── Set rows ─────────────────────────────────────────────────────
            ...List.generate(_sets.length, (si) => _buildSetRow(si)),

            // ── + Add Set ─────────────────────────────────────────────────────
            InkWell(
              onTap: _addSet,
              child: Container(
                width: double.infinity,
                height: 34,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: WW.elevated, width: 1)),
                ),
                child: const Center(
                  child: Text(
                    '+ Add Set',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: WW.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetRow(int si) {
    final sets = _ex['sets'] as List<Map<String, dynamic>>;
    final set = sets[si];
    final sid = set['id'] as String;
    final type = set['type'] as String? ?? 'N';

    final kgCtrl = widget.getCtrl('${sid}_kg', set['kg'] as String? ?? '');
    final repsCtrl =
        widget.getCtrl('${sid}_reps', set['reps'] as String? ?? '');

    return Dismissible(
      key: Key('set_$sid'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        if (sets.length <= 1) {
          widget.onSnack('Must keep at least 1 set');
          return false;
        }
        return true;
      },
      onDismissed: (direction) {
        setState(() => _deleteSet(si));
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: const Color(0xFFEF4444),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
      ),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            // Set number
            SizedBox(
              width: 24,
              child: Text(
                '${si + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: WW.textSec,
                ),
              ),
            ),
          const SizedBox(width: 5),
          // Type button
          GestureDetector(
            onTap: () => setState(() => _cycleType(si)),
            child: Container(
              width: 32,
              height: 22,
              decoration: BoxDecoration(
                color: _setTypeBg(type),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Center(
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _setTypeColor(type),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          // Previous
          const Expanded(
            child: Text(
              '—',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: WW.textSec),
            ),
          ),
          const SizedBox(width: 5),
          // kg
          SizedBox(
            width: 50,
            height: 30,
            child: TextField(
              controller: kgCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              onChanged: (v) {
                set['kg'] = v;
                widget.onChanged();
              },
              decoration: InputDecoration(
                hintText: '—',
                hintStyle: const TextStyle(fontSize: 12, color: WW.textSec),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: WW.border, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: WW.border, width: 1),
                ),
                filled: true,
                fillColor: WW.bg,
              ),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WW.text,
              ),
            ),
          ),
          const SizedBox(width: 5),
          // Reps
          SizedBox(
            width: 44,
            height: 30,
            child: TextField(
              controller: repsCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (v) {
                set['reps'] = v;
                widget.onChanged();
              },
              decoration: InputDecoration(
                hintText: '—',
                hintStyle: const TextStyle(fontSize: 12, color: WW.textSec),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: WW.border, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: WW.border, width: 1),
                ),
                filled: true,
                fillColor: WW.bg,
              ),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: WW.text,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = WW.text,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Exercise search bottom sheet ───────────────────────────────────────────────

class _ExerciseSearchSheet extends StatefulWidget {
  final Set<String> alreadyAdded;
  final void Function(String name, String muscle) onAdd;

  const _ExerciseSearchSheet({
    required this.alreadyAdded,
    required this.onAdd,
  });

  @override
  State<_ExerciseSearchSheet> createState() => _ExerciseSearchSheetState();
}

class _ExerciseSearchSheetState extends State<_ExerciseSearchSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _muscleFilter = 'All';

  // Fetched once when the sheet opens (see _loadExercises) rather than
  // re-querying Firestore on every chip/search keystroke — _results below
  // filters this in-memory list client-side. Used to filter the hardcoded
  // _kExerciseLibrary const directly; that const has since been removed
  // now that this Firestore-backed fetch is confirmed working.
  List<Map<String, dynamic>> _allExercises = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final exercises = await FirestoreService().getAllExercises();
      if (!mounted) return;
      setState(() {
        _allExercises = exercises;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // muscle ?? 'Other' — some real exercise documents may lack a muscle
  // field (see getAllExercises()'s own doc comment on incomplete
  // documents); falling back to 'Other' here rather than an empty string
  // keeps both the muscle-chip filter and the row's muscle label sensible
  // instead of silently matching nothing / displaying blank.
  List<Map<String, dynamic>> get _results {
    return _allExercises.where((e) {
      final name = (e['name'] as String?) ?? '';
      final muscle = (e['muscle'] as String?) ?? 'Other';
      final nameMatch = _query.isEmpty ||
          name.toLowerCase().contains(_query.toLowerCase());
      final muscleMatch = _muscleFilter == 'All' || muscle == _muscleFilter;
      return nameMatch && muscleMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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

          // Title
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Text(
              'Add Exercise',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
              ),
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: WW.border, width: 0.5),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(Icons.search_rounded,
                        size: 16, color: WW.textSec),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: false,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search exercises...',
                        hintStyle: TextStyle(
                            fontSize: 13, color: WW.textSec),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          fontSize: 13, color: WW.text),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: WW.textSec),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Muscle filter chips
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: _kMuscleFilters.map((m) {
                final active = _muscleFilter == m;
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: GestureDetector(
                    onTap: () => setState(() => _muscleFilter = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? WW.chipBg : WW.elevated,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: active ? WW.primary : WW.border,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? WW.primary : WW.textSec,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: WW.border),

          // Results / loading / error
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: WW.primary),
                  )
                : _hasError
                    ? _buildErrorState()
                    : results.isEmpty
                        ? const Center(
                            child: Text(
                              'No exercises found',
                              style: TextStyle(
                                  fontSize: 13, color: WW.textSec),
                            ),
                          )
                        : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    itemCount: results.length,
                    separatorBuilder: (ctx2, idx2) =>
                        const Divider(height: 1, color: WW.border),
                    itemBuilder: (ctx3, i) {
                      final e = results[i];
                      final name = (e['name'] as String?) ?? '';
                      final muscle = (e['muscle'] as String?) ?? 'Other';
                      final added = widget.alreadyAdded.contains(name);
                      final mc = _muscleColor(muscle);
                      final mb = _muscleBg(muscle);

                      return InkWell(
                        onTap: added
                            ? null
                            : () => widget.onAdd(name, muscle),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              // Muscle dot
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: mb,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: mc,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: WW.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      muscle,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: mc,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (added)
                                const Icon(Icons.check_circle_rounded,
                                    size: 18, color: WW.teal)
                              else
                                const Icon(Icons.chevron_right_rounded,
                                    size: 18, color: WW.textSec),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: WW.textSec),
          const SizedBox(height: 10),
          const Text(
            "Couldn't load exercises",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _loadExercises,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
