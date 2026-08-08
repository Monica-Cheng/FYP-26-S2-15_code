// lib/screens/plans/plan_detail_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/compress_utils.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/session_resume_prompt.dart';

// Same Running/Gym icon mapping already established elsewhere in this app
// (explore_screen.dart's _PlanCard._sportIcon(), plans_screen.dart's
// RecentPlanRow._typeIcon) — duplicated here, not imported, since those are
// private to their own files. Used by the hero's type stat pill (see
// _buildHero).
IconData _planTypeIcon(String type) {
  switch (type.toLowerCase()) {
    case 'running':
      return Icons.directions_run_rounded;
    case 'gym':
      return Icons.fitness_center_rounded;
    default:
      return Icons.sports_rounded;
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class PlanDetailScreen extends StatefulWidget {
  const PlanDetailScreen({super.key});

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  bool _overviewExpanded = false;
  bool _isTracking = false;
  bool _isTracked = false;
  bool _isSaved = false;
  bool _fromExplore = false;
  Map<String, dynamic>? _planData;
  StreamSubscription<Map<String, dynamic>?>? _planStreamSub;
  // Lifetime per-day completion ledger + current day, both fetched in
  // _checkCompletionState() from the same planProgress doc. Empty/1 until
  // that fetch resolves (fails soft, matching _checkTrackedState()'s own
  // try/catch-and-do-nothing convention) — _isDayCompleted() and
  // _hasAnyProgress correctly read as "nothing yet" in that window.
  Set<int> _completedDayIndices = {};
  int _currentDayIndex = 1;
  // See core/compress_utils.dart's CompressedDayData — shared with
  // plan_schedule_screen.dart/gym_session_screen.dart/home_screen.dart so
  // this screen's day previews can never disagree with what a tracked
  // session actually does. Loaded alongside _completedDayIndices from the
  // same planProgress doc, in _checkCompletionState() below.
  Map<int, CompressedDayData> _compressedDays = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      if (extra == null) return;
      if (mounted) {
        setState(() {
          _planData = extra;
          _fromExplore = (extra['fromExplore'] as bool?) ?? false;
        });
      }
      final planId = extra['id'] as String?;
      if (planId != null && planId.isNotEmpty) {
        _planStreamSub =
            FirestoreService().getPlanStream(planId).listen((data) {
          if (data != null && mounted) setState(() => _planData = data);
        });
      }
      _checkTrackedState();
      _checkSavedState();
      _checkCompletionState();
    });
  }

  @override
  void dispose() {
    _planStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _checkTrackedState() async {
    final planId = _planData?['id'] as String?;
    if (planId == null || planId.isEmpty) return;
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await FirestoreService().getUserProfile(uid);
      if (!mounted) return;
      final trackedId = profile?['trackedPlanId'] as String?;
      setState(() => _isTracked = trackedId == planId);
    } catch (_) {}
  }

  Future<void> _checkCompletionState() async {
    final planId = _planData?['id'] as String?;
    if (planId == null || planId.isEmpty) return;
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final progress = await FirestoreService().getPlanProgress(uid, planId);
      if (!mounted) return;
      final rawCompletedDayIndices = progress?['completedDayIndices'];
      final loadedCompletedDayIndices = rawCompletedDayIndices is List
          ? rawCompletedDayIndices.map((d) => (d as num).toInt()).toSet()
          : <int>{};
      final sessions = (_planData?['sessions'] as List<dynamic>?)
              ?.map((s) => s as Map<String, dynamic>)
              .toList() ??
          <Map<String, dynamic>>[];
      final loadedCompressedDays =
          parseCompressedDays(progress?['compressedDays'], sessions);
      setState(() {
        _completedDayIndices = loadedCompletedDayIndices;
        _currentDayIndex =
            (progress?['currentDayIndex'] as num?)?.toInt() ?? 1;
        _compressedDays = loadedCompressedDays;
      });
    } catch (_) {}
  }

  // Real, persistent check against the lifetime completedDayIndices ledger
  // (see markSessionComplete()) — replaces the old "only the single most
  // recently completed day, and only if that happened today" check, which
  // meant every OTHER genuinely-completed day showed no completion state
  // at all. Every day ever completed for this plan now shows as completed,
  // regardless of when.
  bool _isDayCompleted(int dayIndex) => _completedDayIndices.contains(dayIndex);

  // Whether this plan has any progress worth offering to reset — shown
  // regardless of current tracked/saved/custom status (see
  // _buildSessionSchedule's Restart Program link), since the whole point
  // is covering the case where a plan still has stale completed-day state
  // visible even after the user has moved on to tracking a different plan.
  bool get _hasAnyProgress =>
      _currentDayIndex > 1 || _completedDayIndices.isNotEmpty;

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

  // Tracking a fresh (non-switching) plan is now immediate, no confirmation —
  // per the save/track redesign, only switching away from a different
  // already-tracked plan still confirms first (a more consequential action,
  // since it silently stops tracking that other plan too).
  Future<void> _handleTrackPlan(Map<String, dynamic> plan) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;

    String? currentTrackedName;
    try {
      final profile = await FirestoreService().getUserProfile(uid);
      final currentTrackedId = profile?['trackedPlanId'] as String?;
      if (currentTrackedId != null &&
          currentTrackedId.isNotEmpty &&
          currentTrackedId != plan['id']) {
        currentTrackedName = profile?['trackedPlanName'] as String?;
      }
    } catch (_) {}

    final isSwitching = currentTrackedName != null && currentTrackedName.isNotEmpty;

    if (isSwitching) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: WW.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Switch to this plan?',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          content: Text(
            'You are currently tracking "$currentTrackedName". Switching will stop tracking it, but your progress will be saved.',
            style: const TextStyle(fontSize: 14, color: WW.textSec),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Switch',
                style: TextStyle(
                  color: WW.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isTracking = true);
    try {
      await FirestoreService().trackPlan(
        uid,
        plan['id'] as String? ?? '',
        plan['name'] as String? ?? 'Unnamed Plan',
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isTracking = false;
      _isTracked = true;
      _isSaved = true;
    });
  }

  Future<void> _handleUntrackPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Untrack this plan?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        content: const Text(
          'Your progress is saved and you can track it again anytime.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Untrack',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await FirestoreService().updateUserProfile(uid, {
        'trackedPlanId': '',
        'trackedPlanName': '',
      });
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isTracked = false);
  }

  Future<void> _handleDeleteCustomPlan(
      Map<String, dynamic> plan) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    final planId = plan['id'] as String? ?? '';
    final planName = plan['name'] as String? ?? '';
    if (planId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Routine?',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: WW.text),
        ),
        content: const Text(
          'This will permanently delete this routine. '
          'This cannot be undone.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // No try/catch previously existed around this call at all (unlike
    // _saveRoutine()'s own catch in build_routine_screen.dart) — a genuine
    // Firestore error here (permission, network) failed completely
    // silently: the confirm dialog had already closed, then nothing
    // further happened. Now surfaces a real error message instead of
    // leaving the user on an unchanged screen with no feedback.
    try {
      await FirestoreService().deleteCustomPlan(uid, planId, planName);
    } catch (e) {
      if (mounted) _snack('Failed to delete routine. Please try again.');
      return;
    }
    if (!mounted) return;
    _snack('Routine deleted.');
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.pop();
  }

  Future<void> _handleEditRoutine(Map<String, dynamic> plan) async {
    await context.push<bool>(Routes.editRoutine, extra: plan);
    // Stream subscription auto-updates _planData when Firestore changes.
  }

  Future<void> _checkSavedState() async {
    final planId = _planData?['id'] as String?;
    if (planId == null || planId.isEmpty) return;
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    final ids = await FirestoreService().getSavedPlanIds(uid);
    if (!mounted) return;
    setState(() => _isSaved = ids.contains(planId));
  }

  // Single instant toggle — no confirmation dialog either direction (both
  // are reversible, low-stakes), replacing the old separate
  // save/"Saved ✓"/"Remove from My Plans" controls. Optimistically flips
  // _isSaved before the write resolves, same instant-feedback pattern as
  // most icon toggles elsewhere in this app; rolled back if the write fails.
  Future<void> _handleToggleSave(Map<String, dynamic> plan) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    final planId = plan['id'] as String? ?? '';
    if (planId.isEmpty) return;
    final wasSaved = _isSaved;
    setState(() => _isSaved = !wasSaved);
    try {
      if (wasSaved) {
        await FirestoreService().unsaveExplorePlan(uid, planId);
      } else {
        await FirestoreService().saveExplorePlan(uid, planId);
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = wasSaved);
      return;
    }
    if (!mounted) return;
    _snack(wasSaved ? 'Removed from My Plans.' : 'Plan saved to My Plans.');
  }

  Future<void> _onStartDay(int dayIndex) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    final planId = _planData?['id'] as String? ?? '';
    if (planId.isEmpty) return;
    // Routes through the shared discovery-and-prompt step (see
    // widgets/session_resume_prompt.dart) — an already-abandoned
    // in-progress session for this exact planId+dayIndex offers Resume/
    // Start Over instead of silently being orphaned by a brand-new one.
    // _DayCard already hides this tap entirely for a day
    // _isDayCompleted() reports as completed (see _buildSessionSchedule),
    // so no separate completed check is needed here. The fresh-start path
    // itself (setOverrideDayIndex + push) is
    // unchanged from before this feature.
    await startOrResumeTrackedSession(
      context: context,
      uid: uid,
      planId: planId,
      dayIndex: dayIndex,
      startFresh: () async {
        await FirestoreService().setOverrideDayIndex(uid, planId, dayIndex);
        if (!mounted) return;
        context.push(Routes.gymSession, extra: {'readOnly': true});
      },
    );
  }

  // Same confirmation copy/style as plan_schedule_screen.dart's own
  // existing Restart Plan action, and delegates to the same shared
  // FirestoreService().resetPlanProgress() that action now also uses — see
  // that method's own doc comment for why the field list lives there
  // instead of being duplicated per-screen. Available regardless of
  // tracked/saved/custom state (see _hasAnyProgress).
  Future<void> _handleRestartProgram() async {
    final uid = AuthService().getCurrentUser()?.uid;
    final planId = _planData?['id'] as String?;
    if (uid == null || planId == null || planId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Restart Plan?',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: WW.text),
        ),
        content: const Text(
          'This will reset your progress back to Day 1. Your session history will not be deleted.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Restart',
              style: TextStyle(
                  color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await FirestoreService().resetPlanProgress(uid, planId);
    if (!mounted) return;
    setState(() {
      _currentDayIndex = 1;
      _completedDayIndices = {};
    });
    _snack('Plan restarted from Day 1.');
  }

  @override
  Widget build(BuildContext context) {
    final plan = _planData ?? (GoRouterState.of(context).extra as Map<String, dynamic>?);

    if (plan == null) {
      return Scaffold(
        backgroundColor: WW.bg,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 48, color: WW.textSec),
                const SizedBox(height: 12),
                const Text(
                  'Plan not found',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Go Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

    final name = plan['name'] as String? ?? 'Workout Plan';
    final type = plan['type'] as String? ?? 'Gym';
    final level = plan['level'] as String? ?? 'Beginner';
    final daysPerWeek = (plan['daysPerWeek'] as num?)?.toInt() ?? 3;
    final durationWeeks = (plan['durationWeeks'] as num?)?.toInt() ?? 8;
    final isCustom = plan['isCustom'] == true;
    final description = plan['description'] as String? ??
        'A structured training plan designed to help you reach your fitness goals through progressive overload and consistent training.';
    final equipment =
        (plan['equipment'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final goals =
        (plan['goals'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final designedBy = plan['designedBy'] as Map<String, dynamic>?;
    return Scaffold(
      backgroundColor: WW.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _buildHero(
                    name, type, level, daysPerWeek, durationWeeks,
                    isCustom: isCustom, plan: plan),
              ),
              if (!_fromExplore && !isCustom)
                SliverToBoxAdapter(
                    child: _buildShortDescription(description, plan)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_fromExplore) ...[
                      _buildBestForCard(description),
                      const SizedBox(height: 14),
                      _buildExperienceLevelCard(level),
                      const SizedBox(height: 14),
                      _buildOverviewCard(description),
                      const SizedBox(height: 14),
                    ],
                    if (designedBy != null) ...[
                      _buildCoachCard(designedBy),
                      const SizedBox(height: 14),
                    ],
                    _buildSessionSchedule(plan['sessions']),
                    if (_fromExplore) ...[
                      const SizedBox(height: 14),
                      _buildEquipmentCard(equipment),
                      if (goals.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildGoalsSection(goals),
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyBar(plan),
          ),
        ],
      ),
    );
  }

  // ── Hero ───────────────────────────────────────────────────────────────────

  // Light header — matches the app's base WW.bg background (same token
  // plans_screen.dart's own Scaffold uses), replacing the old purple/blue
  // gradient block. Title and icon buttons switched from white-on-purple to
  // dark-on-light; stat pills and the Custom Routine badge switched to the
  // soft lavender treatment (WW.lavenderBg/WW.lavenderText) used for item 2
  // below, so the whole header reads as one coherent light surface instead
  // of mixing translucent-white accents into a now-light background.
  Widget _buildHero(String name, String type, String level, int daysPerWeek,
      int durationWeeks, {required bool isCustom, required Map<String, dynamic> plan}) {
    return Container(
      color: WW.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top action row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _heroIconButton(
                    icon: Icons.chevron_left_rounded,
                    color: WW.primaryDark,
                    size: 22,
                    onTap: () => context.pop(),
                  ),
                  // Top-right actions — always in this exact spot. Custom
                  // routines have no real "saved" state (they're owned, not
                  // bookmarked), so instead of the save toggle they show two
                  // icon-only buttons: Edit and Delete (previously Delete
                  // lived as a separate text link at the bottom of the
                  // screen — moved up here, same _handleDeleteCustomPlan
                  // confirm dialog, unchanged). Every other plan keeps the
                  // single save/bookmark toggle.
                  if (isCustom)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _heroIconButton(
                          icon: Icons.edit_rounded,
                          color: WW.primaryDark,
                          onTap: () => _handleEditRoutine(plan),
                        ),
                        const SizedBox(width: 8),
                        _heroIconButton(
                          icon: Icons.delete_outline_rounded,
                          color: const Color(0xFFEF4444),
                          onTap: () => _handleDeleteCustomPlan(plan),
                        ),
                      ],
                    )
                  else
                    _heroIconButton(
                      icon: _isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: WW.primaryDark,
                      onTap: () => _handleToggleSave(plan),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Plan name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
            if (isCustom) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: WW.lavenderBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: WW.lavender.withValues(alpha: 0.25), width: 0.5),
                ),
                child: const Text(
                  'Custom Routine',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WW.lavenderText,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              const SizedBox(height: 8),
              // Certified row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: WW.lavenderBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.verified_rounded,
                          color: WW.lavender, size: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'WiseWorkout Certified',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WW.textSec,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Tag chips — soft lavender pill + icon + dark text, sitting
              // directly on the light header (replaces the old translucent-
              // white-on-purple treatment).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HeroChip(Icons.calendar_today_rounded, '$daysPerWeek days/wk'),
                    _HeroChip(Icons.date_range_rounded, '${durationWeeks}w programme'),
                    _HeroChip(Icons.trending_up_rounded, level),
                    _HeroChip(_planTypeIcon(type), type),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  // Shared 34×34 light circular icon button used by every hero top-row
  // action (back, save/bookmark toggle, and the custom-routine Edit/Delete
  // pair) — same WW.elevated container for all of them; only icon/color/
  // size/tap handler vary per caller.
  Widget _heroIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 18,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: WW.elevated,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Center(
          child: Icon(icon, color: color, size: size),
        ),
      ),
    );
  }

  // ── Best For card ──────────────────────────────────────────────────────────

  Widget _buildBestForCard(String description) {
    return _SectionCard(
      title: 'Best For',
      child: Text(
        description,
        style: const TextStyle(fontSize: 14, color: WW.text, height: 1.65),
      ),
    );
  }

  // ── Experience Level card ──────────────────────────────────────────────────

  Widget _buildExperienceLevelCard(String level) {
    final normalized = level.toLowerCase();
    final int idx;
    if (normalized.contains('inter')) {
      idx = 1;
    } else if (normalized.contains('adv')) {
      idx = 2;
    } else {
      idx = 0;
    }
    const labels = ['Beginner', 'Intermediate', 'Advanced'];
    const colors = [
      Color(0xFF22C55E),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
    ];
    const bgs = [
      Color(0xFFDCFCE7),
      Color(0xFFFEF3C7),
      Color(0xFFFEE2E2),
    ];
    const rationales = [
      'Ideal for those new to structured training. Focuses on form, movement patterns, and building a base.',
      'Suited for those with 6+ months of consistent training who want to push past beginner plateaus.',
      'Designed for experienced athletes who need high-intensity, periodised programming.',
    ];

    return _SectionCard(
      title: 'Experience Level',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: bgs[idx],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              labels[idx],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colors[idx],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rationales[idx],
            style: const TextStyle(
              fontSize: 13,
              color: WW.textSec,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Plan Overview card ─────────────────────────────────────────────────────

  Widget _buildOverviewCard(String description) {
    return _SectionCard(
      title: 'Plan Overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            firstChild: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, color: WW.text, height: 1.65),
            ),
            secondChild: Text(
              description,
              style: const TextStyle(
                  fontSize: 14, color: WW.text, height: 1.65),
            ),
            crossFadeState: _overviewExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () =>
                setState(() => _overviewExpanded = !_overviewExpanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _overviewExpanded ? 'Show less' : 'Read more',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WW.primary,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _overviewExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: WW.primary, size: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Short description (saved plan view) ───────────────────────────────────

  Widget _buildShortDescription(
      String description, Map<String, dynamic> plan) {
    final short = plan['shortDescription'] as String?;
    final text = short ??
        (description.length > 120
            ? '${description.substring(0, 120)}...'
            : description);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: WW.textSec,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ── Designed by coach card ─────────────────────────────────────────────────

  Widget _buildCoachCard(Map<String, dynamic> designedBy) {
    final name = designedBy['name'] as String? ?? '';
    final title = designedBy['title'] as String? ?? '';
    final quote = designedBy['quote'] as String?;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: WW.chipBg,
            child: Icon(Icons.person_rounded, color: WW.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Designed with',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WW.textSec,
                  ),
                ),
                if (quote != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '"$quote"',
                    style: const TextStyle(
                      fontSize: 12,
                      color: WW.textSec,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Plan Schedule ──────────────────────────────────────────────────────────

  Widget _buildSessionSchedule(dynamic rawSessions) {
    final sessions = (rawSessions as List<dynamic>?)
            ?.map((s) => s as Map<String, dynamic>)
            .toList() ??
        [];

    if (sessions.isEmpty) {
      return _SectionCard(
        title: 'Plan Schedule',
        child: const Text(
          'Session details not available yet.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Plan Schedule',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
                letterSpacing: -0.2,
              ),
            ),
            // Shown regardless of tracked/saved/custom state — see
            // _hasAnyProgress's own doc comment for why this can't live in
            // _buildStickyBar's tracked/saved/custom branches instead.
            if (_hasAnyProgress)
              GestureDetector(
                onTap: _handleRestartProgram,
                child: const Text(
                  'Restart Program',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...sessions.asMap().entries.map((entry) {
          final idx = entry.key;
          final s = entry.value;
          final dayNumber =
              (s['dayNumber'] as num?)?.toInt() ?? (idx + 1);
          final isCompleted = _isDayCompleted(dayNumber);
          return _DayCard(
            sessionData: s,
            isCompleted: isCompleted,
            compressedData: _compressedDays[dayNumber],
            onPreview: isCompleted ? null : () => _onStartDay(dayNumber),
          );
        }),
      ],
    );
  }

  // ── Equipment card ─────────────────────────────────────────────────────────

  Widget _buildEquipmentCard(List<String> equipment) {
    return _SectionCard(
      title: 'Equipment Needed',
      child: equipment.isEmpty
          ? const Text(
              'No equipment needed (bodyweight)',
              style: TextStyle(fontSize: 14, color: WW.textSec),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: equipment
                  .map((e) => _EquipmentChip(label: e))
                  .toList(),
            ),
    );
  }

  // ── Goals section ──────────────────────────────────────────────────────────

  Widget _buildGoalsSection(List<String> goals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Goals You'll Hit",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: goals
                .map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: WW.chipBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: WW.primary.withOpacity(0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: WW.primary,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  // ── Sticky bottom bar ──────────────────────────────────────────────────────

  // Single Track toggle, always present in this exact bottom-of-screen
  // position regardless of state — replaces the old State A/B/C branching
  // (a "Remove from My Plans" link, a "Currently Tracking" button + separate
  // "Untrack Plan" link, and a Save/Saved/Edit + "Track This Plan" row).
  // Save state lives in the hero's top-right toggle; for custom routines,
  // Edit and Delete now live there too (see _buildHero/_heroIconButton) —
  // this bar is identical for every plan, custom or not, just the one
  // button.
  Widget _buildStickyBar(Map<String, dynamic> plan) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: WW.border, width: 0.5)),
      ),
      child: GestureDetector(
        onTap: _isTracking
            ? null
            : (_isTracked ? _handleUntrackPlan : () => _handleTrackPlan(plan)),
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: _isTracked ? Colors.transparent : WW.primary,
            borderRadius: BorderRadius.circular(13),
            border: _isTracked
                ? Border.all(color: WW.teal, width: 1.5)
                : null,
            boxShadow: _isTracked
                ? null
                : [
                    BoxShadow(
                      color: WW.primary.withOpacity(0.35),
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isTracked
                            ? Icons.check_circle_rounded
                            : Icons.play_arrow_rounded,
                        color: _isTracked ? WW.teal : Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isTracked
                            ? 'Currently Tracking'
                            : 'Track This Plan',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _isTracked ? WW.teal : Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Hero chip ─────────────────────────────────────────────────────────────────

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: WW.lavenderBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: WW.lavender.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: WW.lavenderText),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.lavenderText,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// ── Collapsible day card ───────────────────────────────────────────────────────

class _DayCard extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  final bool showStartButton;
  final VoidCallback? onStart;
  final VoidCallback? onPreview;
  // True when this day is in the lifetime completedDayIndices ledger (see
  // _isDayCompleted()) — shows a small teal "Completed" pill (same
  // color/icon convention as home_screen.dart's
  // own completed state, and identical to plan_schedule_screen.dart's own
  // _StatusBadge 'completed' case, just sized for this compact list-row
  // context) instead of a tappable preview row. Callers are expected to
  // also pass onPreview: null when this is true (see
  // _buildSessionSchedule) — this widget doesn't re-derive that itself,
  // just reflects it visually.
  final bool isCompleted;
  // See core/compress_utils.dart's CompressedDayData. Null means this day
  // has no compression entry at all (including the common case of not
  // being tracked yet, where _compressedDays is empty for every day).
  final CompressedDayData? compressedData;

  const _DayCard({
    required this.sessionData,
    this.showStartButton = false,
    this.onStart,
    this.onPreview,
    this.isCompleted = false,
    this.compressedData,
  });

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isRest = widget.sessionData['isRestDay'] == true;
    final dayLabel = widget.sessionData['day'] as String? ?? '';
    final sessionName = widget.sessionData['name'] as String? ?? '';
    final baseEstimatedMinutes =
        (widget.sessionData['estimatedMinutes'] as num?)?.toInt() ?? 0;
    final allExercises = (widget.sessionData['exercises'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        <Map<String, dynamic>>[];
    // Applies the real per-exercise removals/cardio overrides for this
    // day, if any — this screen previously never filtered by compression
    // at all, always showing the full exercise list regardless of a
    // tracked day's actual compressed state.
    final rawExercises = applyCompression(allExercises, widget.compressedData);
    final estimatedMinutes = estimatedMinutesAfterCompression(
        baseEstimatedMinutes, widget.compressedData, allExercises);

    // Badge text: "Day 1" → "D1", anything else → first 3 chars
    final badge = dayLabel.startsWith('Day ')
        ? 'D${dayLabel.substring(4)}'
        : dayLabel.substring(0, dayLabel.length.clamp(0, 3));

    if (isRest) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WW.elevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WW.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WW.border.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('💤', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayLabel,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: WW.textSec),
                ),
                const Text(
                  'Rest Day',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WW.textSec),
                ),
              ],
            ),
          ],
        ),
      );
    }

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
          // The preview tap target (badge/name/exercise-count) and the
          // chevron's expand/collapse tap target are siblings within this
          // Row, not nested — a GestureDetector.onTap wrapping another
          // interactive descendant (the old structure: this whole Row,
          // chevron included, inside one outer GestureDetector) doesn't
          // reliably suppress the descendant's own tap recognizer, since
          // two independent TapGestureRecognizers sharing a pointer aren't
          // mutually exclusive by default — only genuinely competing
          // gesture families (tap vs. drag, etc.) are. That let a chevron
          // tap silently ALSO fire onPreview (a full navigation into
          // gym_session_screen.dart) on every expand/collapse. Restructuring
          // so the chevron (and the "Start" button, same conflict class)
          // sit outside the onPreview GestureDetector's subtree entirely
          // fixes this structurally, with no stop-propagation/absorb-pointer
          // trick needed.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onPreview,
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: WW.chipBg,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              badge,
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
                                sessionName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: WW.text,
                                ),
                              ),
                              Text(
                                '${rawExercises.length} exercises'
                                '${estimatedMinutes > 0 ? ' · ${estimatedMinutes}min' : ''}',
                                style: const TextStyle(
                                    fontSize: 11, color: WW.textSec),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.isCompleted) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: WW.tealBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, color: WW.teal, size: 11),
                        SizedBox(width: 3),
                        Text(
                          'Completed',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: WW.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.showStartButton) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: widget.onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: WW.primary,
                      minimumSize: const Size(56, 30),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Start'),
                  ),
                ],
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: WW.textSec, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded && rawExercises.isNotEmpty) ...[
            const Divider(height: 1, color: WW.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: List.generate(rawExercises.length, (i) {
                  final exMap = rawExercises[i];
                  final exName =
                      exMap['name'] as String? ?? 'Exercise';
                  final setsValue = exMap['sets'];
                  final sets = setsValue is List
                      ? setsValue.length
                      : (setsValue as num?)?.toInt() ?? 3;
                  final reps =
                      (exMap['reps'] as num?)?.toInt() ?? 0;
                  final tag = exMap['tag'] as String? ?? '';
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: i < rawExercises.length - 1
                          ? const Border(
                              bottom: BorderSide(
                                  color: WW.border, width: 0.5))
                          : null,
                    ),
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
                        Expanded(
                          child: Text(
                            exName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: WW.text,
                            ),
                          ),
                        ),
                        Text(
                          '${sets}×${reps}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WW.textSec,
                          ),
                        ),
                        if (tag.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: tag == 'Primary'
                                  ? WW.chipBg
                                  : WW.elevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: tag == 'Primary'
                                    ? WW.primary
                                    : WW.textSec,
                              ),
                            ),
                          ),
                        ],
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

// ── Equipment chip ────────────────────────────────────────────────────────────

class _EquipmentChip extends StatelessWidget {
  final String label;
  const _EquipmentChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WW.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center_rounded,
              size: 11, color: WW.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WW.text,
            ),
          ),
        ],
      ),
    );
  }
}
