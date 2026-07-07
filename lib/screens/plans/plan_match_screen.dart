// lib/screens/plans/plan_match_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

class _GoalOption {
  final String id;
  final String emoji;
  final String label;
  const _GoalOption({required this.id, required this.emoji, required this.label});
}

class _LevelOption {
  final String id;
  final String label;
  final String sub;
  const _LevelOption({required this.id, required this.label, required this.sub});
}

// ── Constants ─────────────────────────────────────────────────────────────────

const _kGoalOptions = [
  _GoalOption(id: 'Build Muscle', emoji: '💪', label: 'Build Muscle'),
  _GoalOption(id: 'Improve Endurance', emoji: '🏃', label: 'Improve Endurance'),
  _GoalOption(id: 'Lose Weight', emoji: '🔥', label: 'Lose Weight'),
  _GoalOption(id: 'Build Strength', emoji: '🏋️', label: 'Build Strength'),
];

const _kLevelOptions = [
  _LevelOption(id: 'Beginner', label: 'Beginner', sub: 'New to structured training'),
  _LevelOption(id: 'Intermediate', label: 'Intermediate', sub: 'Training 6–12 months'),
  _LevelOption(id: 'Advanced', label: 'Advanced', sub: 'Training 2+ years'),
];

const _kSportOptions = ['Gym only', 'Running only', 'Both'];
const _kEquipmentOptions = ['Home (bodyweight)', 'Gym with weights', 'Outdoor', 'Both'];
const _kDayOptions = [2, 3, 4, 5, 6];

const List<Map<String, dynamic>> _kPreviewGym = [
  {
    'day': 'Mon',
    'session': 'Push A',
    'exercises': ['Bench Press 4×8', 'Overhead Press 3×10', 'Tricep Pushdown 3×12'],
  },
  {
    'day': 'Wed',
    'session': 'Pull A',
    'exercises': ['Pull-ups 4×8', 'Barbell Row 3×10', 'Face Pull 3×15'],
  },
  {
    'day': 'Fri',
    'session': 'Legs A',
    'exercises': ['Squat 4×8', 'Romanian Deadlift 3×10', 'Leg Press 3×12'],
  },
];

const List<Map<String, dynamic>> _kPreviewRun = [
  {
    'day': 'Tue',
    'session': 'Easy Run',
    'exercises': ['20–30 min easy pace'],
  },
  {
    'day': 'Thu',
    'session': 'Intervals',
    'exercises': ['6×400m at 5K pace'],
  },
  {
    'day': 'Sat',
    'session': 'Long Run',
    'exercises': ['45–60 min easy pace'],
  },
];

// ── Screen ────────────────────────────────────────────────────────────────────

class PlanMatchScreen extends StatefulWidget {
  const PlanMatchScreen({super.key});

  @override
  State<PlanMatchScreen> createState() => _PlanMatchScreenState();
}

class _PlanMatchScreenState extends State<PlanMatchScreen> {
  // 0 = survey, 1 = loading, 2 = result
  int _state = 0;

  // Survey preferences
  String _goal = 'Build Muscle';
  String _sport = 'Both';
  String _level = 'Beginner';
  final Set<String> _equipment = {'Gym with weights'};
  int _days = 3;
  bool _editingPrefs = false;

  // Profile loading
  bool _isLoadingPrefs = true;
  bool _hasSavedPrefs = false;

  // Match result
  Map<String, dynamic>? _matchedPlan;
  int _matchScore = 0;
  bool _isTracking = false;
  bool _isSaved = false;

  final _auth = AuthService();
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadSavedPrefs();
  }

  Future<void> _loadSavedPrefs() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingPrefs = false);
      return;
    }
    try {
      final profile = await _firestore.getUserProfile(uid);
      if (!mounted) return;
      final goal = profile?['planMatchGoal'] as String?;
      final sport = profile?['planMatchSport'] as String?;
      final level = profile?['planMatchLevel'] as String?;
      final equipmentRaw = profile?['planMatchEquipment'] as List<dynamic>?;
      final days = (profile?['planMatchDays'] as num?)?.toInt();

      if (goal != null) {
        _goal = goal;
        if (sport != null) _sport = sport;
        if (level != null) _level = level;
        if (equipmentRaw != null && equipmentRaw.isNotEmpty) {
          _equipment.clear();
          _equipment.addAll(equipmentRaw.map((e) => e.toString()));
        }
        if (days != null) _days = days;
        setState(() {
          _hasSavedPrefs = true;
          _isLoadingPrefs = false;
        });
      } else {
        setState(() => _isLoadingPrefs = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPrefs = false);
    }
  }

  Future<void> _savePrefsAndGenerate() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid != null) {
      try {
        await _firestore.updateUserProfile(uid, {
          'planMatchGoal': _goal,
          'planMatchSport': _sport,
          'planMatchLevel': _level,
          'planMatchEquipment': _equipment.toList(),
          'planMatchDays': _days,
        });
      } catch (_) {}
    }

    setState(() => _state = 1);

    await Future.wait([
      Future<void>.delayed(const Duration(seconds: 2)),
      _runMatchAlgorithm(),
    ]);

    if (mounted) {
      setState(() {
        _state = 2;
        _editingPrefs = false;
        _hasSavedPrefs = true;
      });
    }
  }

  Future<void> _runMatchAlgorithm() async {
    try {
      final plans = await _firestore.getPlans();
      int bestScore = -1;
      Map<String, dynamic>? bestPlan;

      for (final plan in plans) {
        int score = 0;

        // Level match is now worth 6 points (was 3) — most important factor
        final matchLevel = plan['matchLevel'] as String? ?? '';
        final levelMatches = matchLevel.toLowerCase() == _level.toLowerCase();
        if (levelMatches) score += 6;

        // Goal match — 3 points
        final matchGoals = (plan['matchGoals'] as List<dynamic>?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ?? [];
        if (matchGoals.contains(_goal.toLowerCase())) score += 3;

        // Sport match — fuzzy contains-based comparison, 3 points
        final matchSport = (plan['matchSport'] as String? ?? '').toLowerCase();
        final userSport = _sport.toLowerCase();
        final sportMatches = matchSport == userSport ||
            matchSport.contains(userSport.split(' ').first) ||
            userSport.contains(matchSport.split(' ').first) ||
            matchSport == 'both' ||
            userSport == 'both';
        if (sportMatches) score += 3;

        // Days per week — within +/-1, 2 points
        final planDays = (plan['daysPerWeek'] as num?)?.toInt() ?? 3;
        if ((planDays - _days).abs() <= 1) score += 2;

        // Hard penalty: if level does not match at all, heavily
        // deprioritize this plan so a correct-level plan always wins
        // when one exists
        if (!levelMatches) score -= 4;

        if (score > bestScore) {
          bestScore = score;
          bestPlan = plan;
        }
      }

      if (mounted) {
        setState(() {
          _matchedPlan = bestPlan;
          _matchScore = bestScore < 0 ? 0 : bestScore;
        });
      }
    } catch (_) {}
  }

  Future<void> _trackPlan() async {
    final plan = _matchedPlan;
    if (plan == null) return;
    setState(() => _isTracking = true);
    final uid = _auth.getCurrentUser()?.uid;
    if (uid != null) {
      try {
        await _firestore.trackPlan(
          uid,
          plan['id'] as String? ?? '',
          plan['name'] as String? ?? 'Matched Plan',
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _isTracking = false;
      _isSaved = true;
    });
    context.go(Routes.home);
  }

  Future<void> _savePlan() async {
    final plan = _matchedPlan;
    if (plan == null) return;
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.saveExplorePlan(uid, plan['id'] as String? ?? '');
      if (mounted) {
        setState(() => _isSaved = true);
        _snack('Saved to My Plans.');
      }
    } catch (_) {}
  }

  int get _matchPercent => ((_matchScore / 14) * 100).round().clamp(0, 100);

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_state == 1) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [WW.primaryDark, Color(0xFF4A4EA8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Finding your perfect plan...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Analysing your goals and preferences',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: _state == 2 ? _buildResultState() : _buildSurveyState(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: WW.card,
        border: Border(bottom: BorderSide(color: WW.border, width: 0.5)),
        boxShadow: WW.shadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
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
          ),
          const Text(
            'Plan Match',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SURVEY STATE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSurveyState() {
    if (_isLoadingPrefs) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: WW.primary)),
      );
    }
    if (_hasSavedPrefs && !_editingPrefs) return _buildSurveySummary();
    return _buildSurveyForm();
  }

  // -- Saved preferences summary --

  Widget _buildSurveySummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: WW.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your saved preferences',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _buildPrefItem('Goal', _goal)),
                  Expanded(child: _buildPrefItem('Sport', _sport)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildPrefItem('Level', _level)),
                  Expanded(child: _buildPrefItem('Days / week', '$_days days')),
                ],
              ),
              const SizedBox(height: 12),
              _buildPrefItem(
                'Equipment',
                _equipment.isEmpty ? 'None' : _equipment.join(', '),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _editingPrefs = true),
          child: Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(color: WW.border, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Edit Preferences',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WW.textSec,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildGenerateButton('Generate Recommendation'),
      ],
    );
  }

  Widget _buildPrefItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: WW.textSec,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // -- Full survey form --

  Widget _buildSurveyForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_editingPrefs) ...[
          const Text(
            'Update your preferences below.',
            style: TextStyle(fontSize: 13, color: WW.textSec),
          ),
          const SizedBox(height: 16),
        ],

        // Q1 — Goal
        _sectionLabel("What's your primary goal?"),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.7,
          children: _kGoalOptions.map((g) {
            final active = _goal == g.id;
            return GestureDetector(
              onTap: () => setState(() => _goal = g.id),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: active ? WW.chipBg : WW.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? WW.primary : WW.border,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(g.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(
                      g.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active ? WW.primary : WW.text,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Q2 — Sport
        _sectionLabel('Preferred sport type'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kSportOptions.map((s) {
            final active = _sport == s;
            return GestureDetector(
              onTap: () => setState(() => _sport = s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? WW.chipBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? WW.primary : WW.border,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  s,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? WW.primary : WW.textSec,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Q3 — Level
        _sectionLabel('Experience level'),
        const SizedBox(height: 8),
        ..._kLevelOptions.map((opt) {
          final active = _level == opt.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _level = opt.id),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: active ? WW.chipBg : WW.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? WW.primary : WW.border,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            active ? WW.primary : Colors.transparent,
                        border: Border.all(
                          color: active ? WW.primary : WW.border,
                          width: 2,
                        ),
                      ),
                      child: active
                          ? const Icon(Icons.circle,
                              size: 7, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: active ? WW.primary : WW.text,
                          ),
                        ),
                        Text(
                          opt.sub,
                          style: const TextStyle(
                              fontSize: 11, color: WW.textSec),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),

        // Q4 — Equipment
        _sectionLabel('Available equipment'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kEquipmentOptions.map((e) {
            final active = _equipment.contains(e);
            return GestureDetector(
              onTap: () => setState(() {
                if (active) {
                  _equipment.remove(e);
                } else {
                  _equipment.add(e);
                }
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? WW.chipBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? WW.primary : WW.border,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  e,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? WW.primary : WW.textSec,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Q5 — Days per week
        _sectionLabel('Days per week'),
        const SizedBox(height: 8),
        Row(
          children: _kDayOptions.map((d) {
            final active = _days == d;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _days = d),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: active ? WW.primary : WW.elevated,
                    borderRadius: BorderRadius.circular(12),
                    border: active
                        ? null
                        : Border.all(color: WW.border, width: 1),
                  ),
                  child: Center(
                    child: Text(
                      '$d',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : WW.textSec,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),

        _buildGenerateButton('Generate My Plan'),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: WW.text,
      ),
    );
  }

  Widget _buildGenerateButton(String label) {
    return GestureDetector(
      onTap: _savePrefsAndGenerate,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: WW.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: WW.primary.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESULT STATE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildResultState() {
    final plan = _matchedPlan;

    if (plan == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: WW.cardDecoration,
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: WW.textSec),
            const SizedBox(height: 12),
            const Text(
              'No matching plan found',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: WW.text),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try adjusting your preferences',
              style: TextStyle(fontSize: 13, color: WW.textSec),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => setState(() {
                _state = 0;
                _editingPrefs = true;
              }),
              child: Container(
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Edit Preferences',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final name = plan['name'] as String? ?? 'Workout Plan';
    final type = plan['type'] as String? ?? 'Gym';
    final level = plan['level'] as String? ?? _level;
    final daysPerWeek = (plan['daysPerWeek'] as num?)?.toInt() ?? _days;
    final durationWeeks = (plan['durationWeeks'] as num?)?.toInt() ?? 8;
    final isRunning = type.toLowerCase().contains('run');
    final previewWeek = isRunning ? _kPreviewRun : _kPreviewGym;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMatchCard(name, type, level, daysPerWeek, durationWeeks),
        const SizedBox(height: 12),
        _buildExplanationCard(daysPerWeek),
        const SizedBox(height: 12),
        _buildPreviewSection(previewWeek),
        const SizedBox(height: 20),

        // Track This Plan
        GestureDetector(
          onTap: _isTracking ? null : _trackPlan,
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              color: WW.primary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: WW.primary.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: _isTracking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Track This Plan',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Save to All Plans
        GestureDetector(
          onTap: _isSaved ? null : _savePlan,
          child: Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WW.primary, width: 1.5),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: WW.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isSaved ? 'Saved to My Plans' : 'Save to My Plans',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WW.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Regenerate / Edit Preferences
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _state = 0;
                  _editingPrefs = false;
                }),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border.all(color: WW.border, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Regenerate',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: WW.textSec,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _state = 0;
                  _editingPrefs = true;
                }),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border.all(color: WW.border, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Edit Preferences',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: WW.textSec,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMatchCard(
      String name, String type, String level, int days, int weeks) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [WW.primaryDark, Color(0xFF4A4EA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: WW.shadow,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'YOUR PLAN MATCH',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: WW.teal,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_matchPercent% match',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _heroChip('$days days/wk'),
              _heroChip('${weeks}w programme'),
              _heroChip(level),
              _heroChip(type),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildExplanationCard(int daysPerWeek) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WW.lavenderBg,
        borderRadius: BorderRadius.circular(14),
        border: const Border(left: BorderSide(color: WW.lavender, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: WW.lavender,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 13),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Why this plan?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WW.lavenderDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bullet('Matches your $_goal goal'),
          const SizedBox(height: 6),
          _bullet('$daysPerWeek days/week fits your schedule'),
          const SizedBox(height: 6),
          _bullet('$_level level matches your experience'),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_rounded,
            size: 14, color: WW.lavender),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: WW.lavenderText,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection(List<Map<String, dynamic>> week) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sample Week',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        ...week.map((day) => _PreviewDayCard(dayData: day)),
      ],
    );
  }
}

// ── Preview Day Card ──────────────────────────────────────────────────────────

class _PreviewDayCard extends StatefulWidget {
  final Map<String, dynamic> dayData;
  const _PreviewDayCard({required this.dayData});

  @override
  State<_PreviewDayCard> createState() => _PreviewDayCardState();
}

class _PreviewDayCardState extends State<_PreviewDayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.dayData['day'] as String;
    final session = widget.dayData['session'] as String;
    final exercises =
        (widget.dayData['exercises'] as List).map((e) => e.toString()).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WW.border, width: 0.5),
        boxShadow: WW.shadow,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: WW.chipBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          fontSize: 11,
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
                          session,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: WW.text,
                          ),
                        ),
                        Text(
                          '${exercises.length} exercise${exercises.length == 1 ? '' : 's'}',
                          style:
                              const TextStyle(fontSize: 11, color: WW.textSec),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: WW.textSec, size: 18),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: WW.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: List.generate(exercises.length, (i) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: i < exercises.length - 1
                        ? const BoxDecoration(
                            border: Border(
                              bottom:
                                  BorderSide(color: WW.border, width: 0.5),
                            ),
                          )
                        : null,
                    child: Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: WW.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          exercises[i],
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: WW.text,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
