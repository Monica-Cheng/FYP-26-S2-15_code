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
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  const _GoalOption({
    required this.id,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
  });
}

class _LevelOption {
  final String id;
  final String label;
  final String sub;
  const _LevelOption({required this.id, required this.label, required this.sub});
}

// ── Constants ─────────────────────────────────────────────────────────────────

// Icons/colors for Build Muscle, Improve Endurance and Lose Weight match
// onboarding_step2_screen.dart's own "primary goal" question exactly
// (same underlying concept, different screen) — fitness_center_rounded/
// bolt_rounded/local_fire_department_rounded with the same color pairings,
// for visual consistency between the app's two "goal" surveys. Build
// Strength has no onboarding counterpart (that question offers "General
// Fitness" as its 4th option instead), so it gets a new icon
// (Icons.shield_rounded, distinct from the other three) — not const
// because WW.gold has no dedicated background-tint token the way
// chipBg/tealBg/lavenderBg exist for primary/teal/lavender, so its tint
// is computed at runtime via withValues() rather than a new hardcoded hex.
final _kGoalOptions = [
  const _GoalOption(
    id: 'Build Muscle',
    icon: Icons.fitness_center_rounded,
    iconBg: WW.chipBg,
    iconColor: WW.primary,
    label: 'Build Muscle',
  ),
  const _GoalOption(
    id: 'Improve Endurance',
    icon: Icons.bolt_rounded,
    iconBg: WW.lavenderBg,
    iconColor: WW.lavender,
    label: 'Improve Endurance',
  ),
  const _GoalOption(
    id: 'Lose Weight',
    icon: Icons.local_fire_department_rounded,
    iconBg: Color(0xFFFFF3E0),
    iconColor: Color(0xFFF97316),
    label: 'Lose Weight',
  ),
  _GoalOption(
    id: 'Build Strength',
    icon: Icons.shield_rounded,
    iconBg: WW.gold.withValues(alpha: 0.15),
    iconColor: WW.gold,
    label: 'Build Strength',
  ),
];

const _kLevelOptions = [
  _LevelOption(id: 'Beginner', label: 'Beginner', sub: 'New to structured training'),
  _LevelOption(id: 'Intermediate', label: 'Intermediate', sub: 'Training 6–12 months'),
  _LevelOption(id: 'Advanced', label: 'Advanced', sub: 'Training 2+ years'),
];

const _kSportOptions = ['Gym', 'Cardio', 'Combine', 'Any'];
const _kDayOptions = [2, 3, 4, 5, 6];

// Display labels for onboarding_step2_screen.dart's equipmentAvailable ids
// ('bodyweight'/'gym_weights'/'outdoor'/'both') — used only for the
// read-only "Your saved preferences" summary below now that Plan Match no
// longer asks its own separate equipment question (see
// _buildSurveyForm()'s removed Q4 and _loadSavedPrefs() below).
const _kEquipmentLabels = {
  'bodyweight': 'Home (bodyweight)',
  'gym_weights': 'Gym with weights',
  'outdoor': 'Outdoor',
  'both': 'Both',
};

// Equipment items observed in real official plan docs today (Barbell,
// Dumbbells, Cable machine, Bench) plus a few obvious close synonyms an
// admin might type instead — the admin's own Equipment field is free text
// (comma-separated), not a fixed enum, so this is a best-effort keyword
// match, not a strict taxonomy.
const _kGymWeightKeywords = [
  'barbell',
  'dumbbell',
  'kettlebell',
  'cable',
  'bench',
  'machine',
  'plate',
  'rack',
];

// Maps one of the user's onboarding equipmentAvailable ids to whether a
// given plan is a reasonable match. Deliberately coarse, matching the
// 4-category granularity of the onboarding question against the plan's
// own free-text equipment[] list (specific named items) and its
// sport/type — there's no shared vocabulary between the two sides, so
// this is a heuristic, not an exact comparison (see the earlier
// equipment-scoring investigation this session for why a direct string
// match isn't possible here the way level/goal/sport/days already are).
// 'bodyweight' only matches a plan with a genuinely EMPTY equipment[] (or
// missing entirely) — deliberately not attempting to infer "bodyweight-
// only" from a non-empty-but-non-gym-weight list (e.g. a Cardio plan's
// ["Running shoes"]), since that would incorrectly credit cardio plans as
// bodyweight matches.
bool _equipmentMatchesPlan(String equipmentId, Map<String, dynamic> plan) {
  final rawEquipment = (plan['equipment'] as List?)
          ?.map((e) => e.toString().toLowerCase())
          .toList() ??
      [];
  final hasGymWeight = rawEquipment
      .any((item) => _kGymWeightKeywords.any((kw) => item.contains(kw)));
  final sport = (plan['sport'] ?? plan['type'] ?? '').toString().toLowerCase();

  switch (equipmentId) {
    case 'gym_weights':
      return hasGymWeight;
    case 'outdoor':
      return sport == 'cardio' && !hasGymWeight;
    case 'bodyweight':
      return rawEquipment.isEmpty;
    case 'both':
      return true; // Wildcard — user has access to everything.
    default:
      return false;
  }
}

// users/{uid}.equipmentAvailable is a multi-select list (onboarding lets a
// user pick more than one) — matches this plan if ANY selected category
// matches. A selected 'both' anywhere in the list is an unconditional
// wildcard, the same idea as _sport's own 'any' wildcard, just under
// onboarding's own id for the equivalent concept.
bool _userEquipmentMatchesPlan(
    List<String> userEquipment, Map<String, dynamic> plan) {
  if (userEquipment.isEmpty) return false;
  return userEquipment.any((id) => _equipmentMatchesPlan(id, plan));
}

// Maps users/{uid}.sportPreference (set once during onboarding, lowercase
// ids) to the equivalent Plan Match sport-survey label — used only as a
// one-time initial default for a user's first-ever Plan Match visit (see
// _loadSavedPrefs() below), never written back to sportPreference.
// Recognizes both the current onboarding ids ('gym'/'cardio'/'combine')
// and the pre-rename legacy values ('running'/'both') a user who onboarded
// before onboarding_step2_screen.dart's own rename may still have stored,
// so their default isn't silently dropped just because their doc predates
// that fix.
String? _sportFromOnboardingPreference(String? sportPreference) {
  switch (sportPreference) {
    case 'gym':
      return 'Gym';
    case 'cardio':
      return 'Cardio';
    case 'combine':
      return 'Combine';
    case 'any':
      return 'Any';
    case 'running': // legacy, pre-rename
      return 'Cardio';
    case 'both': // legacy, pre-rename
      return 'Combine';
    default:
      return null;
  }
}

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
  String _sport = 'Any';
  String _level = 'Beginner';
  // Read-only, borrowed directly from users/{uid}.equipmentAvailable
  // (onboarding) every time this screen loads — no separate Plan-Match-
  // side equipment survey/state anymore (see the removed Q4 in
  // _buildSurveyForm() and the summary in _loadSavedPrefs() below).
  List<String> _userEquipment = [];
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
      final days = (profile?['planMatchDays'] as num?)?.toInt();

      // Equipment has no Plan-Match-side survey/state of its own anymore —
      // unlike sport (which keeps its own editable planMatchSport for a
      // deliberate in-session override), equipment is read straight from
      // onboarding's equipmentAvailable every time this screen loads, no
      // "prior choice wins" branching needed since there's no separate
      // prior choice to compare against.
      _userEquipment = (profile?['equipmentAvailable'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      // A user's own prior Plan Match choice (planMatchSport) always wins
      // when one exists — unchanged from before. Only when Plan Match has
      // never been used (no planMatchSport saved yet) do we borrow a
      // one-time initial default from onboarding's sportPreference —
      // read-only here, never written back to sportPreference by this
      // screen. Runs regardless of whether the rest of the survey
      // (planMatchGoal/Level/etc, gated below) has ever been saved, since
      // this is specifically about seeding the sport chip's initial
      // selection, not the "has this user used Plan Match before" state.
      if (sport != null) {
        _sport = sport;
      } else {
        final borrowed =
            _sportFromOnboardingPreference(profile?['sportPreference'] as String?);
        if (borrowed != null) _sport = borrowed;
      }

      if (goal != null) {
        _goal = goal;
        if (level != null) _level = level;
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
        // A deactivated official plan should never be recommendable, not
        // just deprioritized — excluded outright rather than penalized.
        // Only an EXPLICIT isActive == false skips a plan; a plan with no
        // isActive field at all (custom/coach plans never have one) or
        // isActive == true is unaffected, since absence isn't the same as
        // an admin having actually turned it off.
        if (plan['isActive'] == false) continue;

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

        // Sport match — fuzzy contains-based comparison, 3 points.
        // userSport == 'any' is a user-side-only wildcard ("no
        // preference — match everything"), replacing the old
        // userSport == 'both' clause now that 'Combine' is its own
        // exact-match category (see 'combine' below) rather than a
        // stand-in wildcard. There is deliberately no matchSport == 'any'
        // counterpart — a plan itself is never "any" type, only a user's
        // preference can be.
        final matchSport = (plan['matchSport'] as String? ?? '').toLowerCase();
        final userSport = _sport.toLowerCase();
        final sportMatches = matchSport == userSport ||
            matchSport.contains(userSport.split(' ').first) ||
            userSport.contains(matchSport.split(' ').first) ||
            userSport == 'any';
        if (sportMatches) score += 3;

        // Days per week — within +/-1, 2 points
        final planDays = (plan['daysPerWeek'] as num?)?.toInt() ?? 3;
        if ((planDays - _days).abs() <= 1) score += 2;

        // Equipment match — 2 points, same scale as days/week. Borrowed
        // read-only from onboarding's equipmentAvailable (see
        // _userEquipment's own doc comment) rather than a separate
        // Plan-Match-side answer — see _userEquipmentMatchesPlan()/
        // _equipmentMatchesPlan() above for the category-to-plan mapping.
        if (_userEquipmentMatchesPlan(_userEquipment, plan)) score += 2;

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

  // Max possible raw score: level(6) + goal(3) + sport(3) + days(2) +
  // equipment(2) = 16 — was 14 before equipment became a scored
  // dimension; this denominator has to move in lockstep with the sum of
  // every scoring clause in _runMatchAlgorithm() above, or this percentage
  // silently misrepresents what fraction of the max a plan actually hit.
  int get _matchPercent => ((_matchScore / 16) * 100).round().clamp(0, 100);

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_state == 1) {
      // Lighter lavender gradient (was the dark WW.primaryDark/0xFF4A4EA8
      // pairing) — both stops are existing WW tokens, no new hardcoded
      // hex. Text/spinner colors switched from white/white70 to
      // lavenderDark/lavenderText/lavender to stay legible against the
      // now-light background — WW's own established dark-purple-on-
      // light-lavender pairing (also used by, e.g., WW.lavenderDark/
      // WW.lavenderText elsewhere in this app for text on WW.lavenderBg).
      // decoration: TextDecoration.none is explicit on both lines — no
      // TextDecoration was actually set anywhere in this file or in
      // app_theme.dart/main.dart (grepped both), so this is a defensive,
      // guaranteed-correct fix regardless of whatever was rendering an
      // underline before (most likely an inherited/fallback-font
      // rendering quirk from 'SF Pro Display' not being a bundled font,
      // rather than an explicit style bug).
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [WW.lavenderBg, WW.lavender],
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
                  color: WW.lavenderDark,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Finding your perfect plan...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: WW.lavenderDark,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Analysing your goals and preferences',
                style: TextStyle(
                  fontSize: 13,
                  color: WW.lavenderText,
                  decoration: TextDecoration.none,
                ),
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
                _userEquipment.isEmpty
                    ? 'None set — see onboarding'
                    : _userEquipment
                        .map((id) => _kEquipmentLabels[id] ?? id)
                        .join(', '),
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
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: _kGoalOptions.map((g) {
            final active = _goal == g.id;
            return GestureDetector(
              onTap: () => setState(() => _goal = g.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: active ? WW.chipBg : WW.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? WW.primary : WW.border,
                    width: active ? 1.5 : 1.0,
                  ),
                  boxShadow: WW.shadow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: active
                            ? WW.primary.withValues(alpha: 0.14)
                            : g.iconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(g.icon, color: g.iconColor, size: 18),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      g.label,
                      style: TextStyle(
                        fontSize: 12,
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

        // Equipment is no longer asked here — it's read straight from
        // onboarding's "What equipment do you have?" answer instead (see
        // _userEquipment/_loadSavedPrefs() above), so this survey no
        // longer duplicates that question with a second, differently-
        // shaped copy of the same 4 options.

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
    final previewWeek = _buildRealPreviewWeek(plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMatchCard(name, type, level, daysPerWeek, durationWeeks),
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

  // Derives a real "what a typical week looks like" preview directly from
  // the matched plan's own sessions[] — replaces the old hardcoded
  // _kPreviewGym/_kPreviewRun sample data entirely. Every non-rest session
  // in the plan is included (not just the first one) so the preview shows
  // the plan's actual real week, matching _buildPreviewSection's existing
  // multi-card visual format (originally 3 cards of invented sample
  // text — now however many real training days this specific plan
  // actually has). Output shape matches exactly what _PreviewDayCard
  // already expects ({day, session, exercises: List<String>}), so that
  // widget itself needed no changes.
  List<Map<String, dynamic>> _buildRealPreviewWeek(Map<String, dynamic> plan) {
    final sessions = (plan['sessions'] as List<dynamic>?) ?? [];
    return sessions
        .whereType<Map>()
        .where((s) => s['isRestDay'] != true)
        .map((s) {
      final rawExercises = (s['exercises'] as List<dynamic>?) ?? [];
      final exerciseLines = rawExercises
          .whereType<Map>()
          .map((e) => _formatPreviewExercise(Map<String, dynamic>.from(e)))
          .toList();
      return <String, dynamic>{
        'day': s['day'] as String? ?? '',
        'session': s['name'] as String? ?? 'Session',
        'exercises':
            exerciseLines.isNotEmpty ? exerciseLines : <String>['Rest'],
      };
    }).toList();
  }

  // "ExerciseName SxR" for a normal strength exercise (matching the old
  // fake data's "Bench Press 4×8" format), or "Activity — N min" for a
  // cardio block — falls back gracefully to just the exercise name if
  // sets/reps aren't present in a parseable shape. sets can be either a
  // plain int (seeded plan templates) or a List of per-set maps (custom
  // routines) — both are handled, matching the same ambiguity
  // FirestoreService.parseExerciseSets() already accounts for elsewhere.
  String _formatPreviewExercise(Map<String, dynamic> ex) {
    final name = ex['name'] as String? ?? 'Exercise';
    if (ex['isCardio'] == true) {
      final activity = ex['cardioActivity'] as String? ?? 'Cardio';
      final minutes = (ex['cardioMinutes'] as num?)?.toInt();
      return minutes != null ? '$activity — $minutes min' : activity;
    }
    final rawSets = ex['sets'];
    final setsCount =
        rawSets is List ? rawSets.length : (rawSets as num?)?.toInt() ?? 0;
    final reps = (ex['reps'] as num?)?.toInt();
    if (setsCount > 0 && reps != null && reps > 0) {
      return '$name $setsCount×$reps';
    }
    if (setsCount > 0) return '$name — $setsCount sets';
    return name;
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
