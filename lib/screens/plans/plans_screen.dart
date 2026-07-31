// lib/screens/plans/plans_screen.dart
// Plans Hub — Start Cardio CTA, Choose a Way to Train cards,
// Tracked Plan card, and All Plans vertical list.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/session_resume_prompt.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;
  bool _hasError = false;
  Map<String, dynamic>? _trackedPlan;
  bool _trackedPlanLoading = true;
  StreamSubscription<DocumentSnapshot>? _userDocSub;
  // Fetched alongside _trackedPlan (see _loadTrackedPlan()) — same
  // getPlanProgress() data home_screen.dart's own _todayCompleted and the
  // discovery step in session_resume_prompt.dart both need.
  // _trackedPlanDayIndex is the day the tracked-plan card's tap should
  // target (mirrors home_screen.dart's _currentDayIndex); the other two
  // feed _trackedPlanCompletedToday, matching home_screen.dart's own
  // _todayCompleted convention exactly.
  int _trackedPlanDayIndex = 1;
  String? _lastCompletedDate;
  int? _lastCompletedDayIndex;

  @override
  void initState() {
    super.initState();
    _loadPlans();
    _loadTrackedPlan();
    _startUserDocStream();
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    super.dispose();
  }

  void _startUserDocStream() {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .skip(1) // skip initial snapshot — initState already called _loadPlans()
        .listen((snap) {
      if (mounted) {
        _loadPlans();
        _loadTrackedPlan();
      }
    });
  }

  Future<void> _loadPlans() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final plans = await _firestoreService.getPlans();
      final uid = _authService.getCurrentUser()?.uid;
      List<String> savedIds = [];
      if (uid != null) {
        savedIds = await _firestoreService.getSavedPlanIds(uid);
      }
      final filtered = plans.where((p) {
        if (p['isCustom'] == true) {
          return (p['createdBy'] as String?) == uid;
        }
        final id = p['id'] as String? ?? '';
        return savedIds.contains(id);
      }).toList();
      if (mounted) {
        setState(() {
          _plans = filtered;
          _isLoading = false;
        });
      }
    } catch (_) {
      // No more silent fallback to fake plan data on failure — a genuine
      // fetch error now shows a real error state instead (see the
      // _isLoading/_hasError branch in build()), matching this app's
      // existing error-state convention elsewhere (e.g. the "Add
      // Exercise" search sheets' error/retry state).
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTrackedPlan() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _trackedPlanLoading = false);
      return;
    }
    try {
      final plan = await _firestoreService.getTrackedPlan(uid);
      if (!mounted) return;
      final planId = plan?['id'] as String?;
      // Same getPlanProgress() call home_screen.dart's own
      // _loadTodaySession()/_startProgressStream() make — needed both for
      // the tap target's dayIndex and for the completed-today check below.
      Map<String, dynamic>? progress;
      if (planId != null && planId.isNotEmpty) {
        try {
          progress = await _firestoreService.getPlanProgress(uid, planId);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _trackedPlan = plan;
        _trackedPlanDayIndex =
            (progress?['currentDayIndex'] as num?)?.toInt() ?? 1;
        _lastCompletedDate = progress?['lastCompletedDate'] as String?;
        _lastCompletedDayIndex =
            (progress?['lastCompletedDayIndex'] as num?)?.toInt();
        _trackedPlanLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _trackedPlanLoading = false);
    }
  }

  // Matches home_screen.dart's own _todayCompleted check exactly
  // (lastCompletedDate == today, for the specific day that was completed)
  // — this card previously had no completion-awareness at all, unlike
  // Home/Plan Detail/Plan Schedule, which is why it could unconditionally
  // restart an already-completed day's session.
  bool get _trackedPlanCompletedToday {
    if (_lastCompletedDayIndex != _trackedPlanDayIndex) return false;
    final today = DateTime.now().toString().substring(0, 10);
    return _lastCompletedDate == today;
  }

  // Wired to _buildTrackedPlanCard's tap instead of navigating straight to
  // Routes.gymSession — routes through the same shared discovery-and-
  // prompt step already used by home_screen.dart, plan_detail_screen.dart,
  // and plan_schedule_screen.dart (session_resume_prompt.dart), so an
  // already-abandoned in-progress session for this planId+dayIndex offers
  // Resume/Start Over instead of silently being orphaned by a brand-new
  // one. Only reachable when the card isn't already showing the completed
  // state (see _buildTrackedPlanCard), so no separate completed check is
  // needed here.
  Future<void> _handleStartTrackedPlan() async {
    final uid = _authService.getCurrentUser()?.uid;
    final planId = _trackedPlan?['id'] as String?;
    if (uid == null || planId == null || planId.isEmpty) return;
    await startOrResumeTrackedSession(
      context: context,
      uid: uid,
      planId: planId,
      dayIndex: _trackedPlanDayIndex,
      startFresh: () async =>
          context.push(Routes.gymSession, extra: {'readOnly': true}),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WW.bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),
              const SizedBox(height: 20),
              _buildStartCardioButton(),
              const SizedBox(height: 24),
              _buildTrainSection(),
              const SizedBox(height: 24),
              _buildTrackedPlanSection(),
              const SizedBox(height: 24),
              _buildAllPlansSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section 1 — Top bar ───────────────────────────────────────────────────

  Widget _buildTopBar() {
    return const Text(
      'Plans',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: WW.primaryDark,
        letterSpacing: -0.5,
      ),
    );
  }

  // ── Section 2 — Start Cardio ──────────────────────────────────────────────

  Widget _buildStartCardioButton() {
    return GestureDetector(
      onTap: () => context.push(Routes.cardioSetup),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: WW.teal,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: WW.teal.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_run_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text(
              'Start Cardio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section 3 — Choose a way to train ────────────────────────────────────

  Widget _buildTrainSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CHOOSE A WAY TO TRAIN',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: WW.textSec,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _TrainCard(
                label: 'Plan Match',
                subtitle: 'AI recommends',
                iconData: Icons.auto_awesome_rounded,
                bgColor: WW.lavenderBg,
                iconColor: WW.lavender,
                onTap: () => context.push(Routes.planMatch),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TrainCard(
                label: 'Explore',
                subtitle: 'Browse catalog',
                iconData: Icons.grid_view_rounded,
                bgColor: WW.chipBg,
                iconColor: WW.primary,
                onTap: () => context.push(Routes.explore),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TrainCard(
                label: 'Build',
                subtitle: 'Create your own',
                iconData: Icons.edit_rounded,
                bgColor: WW.tealBg,
                iconColor: WW.teal,
                onTap: () => context
                    .push(Routes.buildRoutine)
                    .then((_) => _loadPlans()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Section 4 — Tracked Plan ──────────────────────────────────────────────

  Widget _buildTrackedPlanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Tracked Plan',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        const SizedBox(height: 10),
        if (_trackedPlanLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(color: WW.primary),
            ),
          )
        else if (_trackedPlan == null)
          _buildNoTrackedPlan()
        else
          _buildTrackedPlanCard(_trackedPlan!),
      ],
    );
  }

  Widget _buildNoTrackedPlan() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: WW.cardDecoration,
      child: const Column(
        children: [
          Icon(Icons.fitness_center_rounded, size: 36, color: WW.textSec),
          SizedBox(height: 10),
          Text(
            'No tracked plan',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Choose a plan below to start tracking',
            style: TextStyle(fontSize: 13, color: WW.textSec),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTrackedPlanCard(Map<String, dynamic> plan) {
    final name = plan['name'] as String? ?? 'Unnamed Plan';
    final type = plan['type'] as String? ?? '';
    final level = plan['level'] as String? ?? '';
    final days = (plan['daysPerWeek'] as num?)?.toInt() ?? 0;

    final isCompletedToday = _trackedPlanCompletedToday;

    return GestureDetector(
      onTap: isCompletedToday ? null : _handleStartTrackedPlan,
      child: Container(
        decoration: WW.cardDecoration,
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dark header strip
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              color: WW.primaryDark,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'TRACKED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push(
                        Routes.planSchedule,
                        extra: _trackedPlan),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white38, width: 1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month_rounded,
                              color: Colors.white70, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Schedule',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: WW.text,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: WW.textSec, size: 20),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: WW.elevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$type · $level · $days days/week',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: WW.textSec,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Same teal check-circle "Completed today!" convention
                  // as home_screen.dart's own Today's Plan card — see
                  // _trackedPlanCompletedToday's own doc comment.
                  if (isCompletedToday)
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: WW.teal, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Completed today!',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: WW.teal,
                          ),
                        ),
                      ],
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.play_circle_outline_rounded,
                            color: WW.primary, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Tap to preview & start session',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: WW.primary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section 5 — All Plans ─────────────────────────────────────────────────

  Widget _buildAllPlansSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'All Plans',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            GestureDetector(
              onTap: () => _snack('My plans library coming soon'),
              child: const Text(
                'See all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WW.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(color: WW.primary),
            ),
          )
        else if (_hasError)
          _buildPlansErrorState()
        else
          ...List.generate(_plans.length, (i) {
            final plan = _plans[i];
            final name = plan['name']?.toString() ?? 'Unnamed Plan';
            final type = plan['type']?.toString() ?? '';
            final level = plan['level']?.toString() ?? '';
            final days = (plan['daysPerWeek'] as num?)?.toInt() ?? 0;
            final isCustom = level.toLowerCase() == 'custom';
            return Padding(
              padding: EdgeInsets.only(bottom: i < _plans.length - 1 ? 10 : 0),
              child: _PlanCard(
                name: name,
                type: type,
                level: level,
                days: days,
                chipLabel: isCustom ? 'Custom' : null,
                chipTextColor: isCustom ? WW.teal : null,
                chipBgColor: isCustom ? WW.tealBg : null,
                onTap: () => context
                    .push(Routes.planDetail, extra: plan)
                    .then((_) {
                      _loadTrackedPlan();
                      _loadPlans();
                    }),
              ),
            );
          }),
      ],
    );
  }

  // Shown when _loadPlans() genuinely fails — replaces the old silent
  // fallback to hardcoded fake plan data (_kFallbackPlans, removed) with a
  // real error state, same icon+message+retry convention already used
  // elsewhere in this app (e.g. the "Add Exercise" search sheets' error
  // state in build_routine_screen.dart/gym_session_screen.dart).
  Widget _buildPlansErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: WW.textSec),
            const SizedBox(height: 10),
            const Text(
              "Couldn't load plans",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _loadPlans,
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
      ),
    );
  }
}

// ── Train card ────────────────────────────────────────────────────────────────

class _TrainCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData iconData;
  final Color bgColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _TrainCard({
    required this.label,
    required this.subtitle,
    required this.iconData,
    required this.bgColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        decoration: BoxDecoration(
          color: WW.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WW.border, width: 0.5),
          boxShadow: WW.shadow,
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: WW.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: WW.textSec,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String name;
  final String type;
  final String level;
  final int days;
  final String? chipLabel;
  final Color? chipTextColor;
  final Color? chipBgColor;
  final VoidCallback onTap;

  const _PlanCard({
    required this.name,
    required this.type,
    required this.level,
    required this.days,
    this.chipLabel,
    this.chipTextColor,
    this.chipBgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: WW.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chipLabel != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  chipLabel!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: chipTextColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: WW.text,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Tag(type),
                const SizedBox(width: 6),
                _Tag(level),
                const SizedBox(width: 6),
                _Tag('$days days/week'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: WW.textSec,
        ),
      ),
    );
  }
}
