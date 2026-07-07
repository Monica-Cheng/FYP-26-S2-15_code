// lib/screens/plans/plan_detail_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

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

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isSwitching ? 'Switch to this plan?' : 'Track this plan?',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        content: Text(
          isSwitching
              ? 'You are currently tracking "$currentTrackedName". Switching will stop tracking it, but your progress will be saved.'
              : 'This plan will be added to My Plans and tracked as your active plan.',
          style: const TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              isSwitching ? 'Switch' : 'Track',
              style: const TextStyle(
                color: WW.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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
          'Stop tracking this plan?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        content: const Text(
          'Your progress will be saved but this plan will no longer be tracked.',
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

    await FirestoreService().deleteCustomPlan(uid, planId, planName);
    if (!mounted) return;
    _snack('Routine deleted.');
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.pop();
  }

  Future<void> _handleUnsaveExplorePlan(
      Map<String, dynamic> plan) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    final planId = plan['id'] as String? ?? '';
    if (planId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove from My Plans?',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: WW.text),
        ),
        content: const Text(
          'This plan will be removed from your saved plans.',
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
              'Remove',
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

    await FirestoreService().unsaveExplorePlan(uid, planId);
    if (!mounted) return;
    setState(() => _isSaved = false);
    _snack('Removed from My Plans.');
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

  Future<void> _handleSavePlan(Map<String, dynamic> plan) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    final planId = plan['id'] as String? ?? '';
    if (planId.isEmpty) return;
    await FirestoreService().saveExplorePlan(uid, planId);
    if (!mounted) return;
    setState(() => _isSaved = true);
    _snack('Plan saved to My Plans.');
  }

  Future<void> _onStartDay(int dayIndex) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    final planId = _planData?['id'] as String? ?? '';
    if (planId.isEmpty) return;
    await FirestoreService().setOverrideDayIndex(uid, planId, dayIndex);
    if (!mounted) return;
    context.push(Routes.gymSession);
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

  Widget _buildHero(String name, String type, String level, int daysPerWeek,
      int durationWeeks, {required bool isCustom, required Map<String, dynamic> plan}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WW.primaryDark, Color(0xFF4a4ea8)],
        ),
      ),
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
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Center(
                        child: Icon(Icons.chevron_left_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  if (_fromExplore)
                    GestureDetector(
                      onTap: isCustom
                          ? () => _handleEditRoutine(plan)
                          : (_isSaved ? null : () => _handleSavePlan(plan)),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Center(
                          child: Icon(
                            isCustom
                                ? Icons.edit_rounded
                                : (_isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    )
                  else if (!_isTracked && !isCustom)
                    GestureDetector(
                      onTap: _isTracking
                          ? null
                          : () => _handleTrackPlan(plan),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.white.withOpacity(0.6),
                              width: 1.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Track',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 34),
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
                  color: Colors.white,
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
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Custom Routine',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.verified_rounded,
                          color: Colors.white, size: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'WiseWorkout Certified',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Tag chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HeroChip('$daysPerWeek days/wk'),
                    _HeroChip('${durationWeeks}w programme'),
                    _HeroChip(level),
                    _HeroChip(type),
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
        const Text(
          'Plan Schedule',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 10),
        ...sessions.asMap().entries.map((entry) {
          final idx = entry.key;
          final s = entry.value;
          final dayNumber =
              (s['dayNumber'] as num?)?.toInt() ?? (idx + 1);
          return _DayCard(
            sessionData: s,
            showStartButton: !_fromExplore,
            onStart: _fromExplore ? null : () => _onStartDay(dayNumber),
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

  Widget _buildStickyBar(Map<String, dynamic> plan) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final isCustom = plan['isCustom'] == true;

    // State A — saved Explore plan viewed from Plans tab (not fromExplore,
    // not custom, not tracked): show "Remove from My Plans" link.
    if (!_fromExplore && !isCustom && !_isTracked) {
      if (!_isSaved) return const SizedBox.shrink();
      return Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
        decoration: const BoxDecoration(
          color: WW.card,
          border: Border(top: BorderSide(color: WW.border, width: 0.5)),
        ),
        child: GestureDetector(
          onTap: () => _handleUnsaveExplorePlan(plan),
          child: const Center(
            child: Text(
              'Remove from My Plans',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ),
      );
    }

    // State B — currently tracked.
    if (_isTracked) {
      return Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
        decoration: const BoxDecoration(
          color: WW.card,
          border: Border(top: BorderSide(color: WW.border, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: WW.teal,
                borderRadius: BorderRadius.circular(13),
                boxShadow: [
                  BoxShadow(
                    color: WW.teal.withOpacity(0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Currently Tracking',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _handleUntrackPlan,
              child: const Text(
                'Untrack Plan',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
            if (isCustom) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _handleDeleteCustomPlan(plan),
                child: const Text(
                  'Delete Routine',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // State C — not tracked; either fromExplore or isCustom.
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: WW.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _fromExplore && !isCustom
                    ? (_isSaved
                        ? Container(
                            height: 50,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              border:
                                  Border.all(color: WW.border, width: 1.5),
                            ),
                            child: const Center(
                              child: Text(
                                'Saved ✓',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: WW.textSec,
                                ),
                              ),
                            ),
                          )
                        : GestureDetector(
                            onTap: () => _handleSavePlan(plan),
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                    color: WW.primary, width: 1.5),
                              ),
                              child: const Center(
                                child: Text(
                                  'Save to My Plans',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: WW.primary,
                                  ),
                                ),
                              ),
                            ),
                          ))
                    : GestureDetector(
                        onTap: isCustom
                            ? () => _handleEditRoutine(plan)
                            : (_isSaved ? null : () => _handleSavePlan(plan)),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            border:
                                Border.all(color: WW.primary, width: 1.5),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isCustom
                                      ? Icons.edit_rounded
                                      : (_isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                                  color: WW.primary,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isCustom ? 'Edit Routine' : (_isSaved ? 'Saved' : 'Save'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: WW.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _isTracking ? null : () => _handleTrackPlan(plan),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
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
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Track This Plan',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Delete link for custom routines
          if (isCustom) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _handleDeleteCustomPlan(plan),
              child: const Text(
                'Delete Routine',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
          // Remove link when viewing a saved Explore plan from Explore
          if (_fromExplore && !isCustom && _isSaved) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _handleUnsaveExplorePlan(plan),
              child: const Text(
                'Remove from My Plans',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Hero chip ─────────────────────────────────────────────────────────────────

class _HeroChip extends StatelessWidget {
  final String label;
  const _HeroChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: Colors.white.withOpacity(0.3), width: 0.5),
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

  const _DayCard({
    required this.sessionData,
    this.showStartButton = false,
    this.onStart,
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
    final estimatedMinutes =
        (widget.sessionData['estimatedMinutes'] as num?)?.toInt() ?? 0;
    final rawExercises =
        (widget.sessionData['exercises'] as List<dynamic>?) ?? [];

    // Badge text: "Day 1" → "D1", anything else → first 3 chars
    final badge = dayLabel.startsWith('Day ')
        ? 'D${dayLabel.substring(4)}'
        : dayLabel.substring(0, dayLabel.length.clamp(0, 3));

    if (isRest) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                borderRadius: BorderRadius.circular(9),
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
                  if (widget.showStartButton) ...[
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
                    const SizedBox(width: 8),
                  ],
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
          if (_expanded && rawExercises.isNotEmpty) ...[
            const Divider(height: 1, color: WW.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: List.generate(rawExercises.length, (i) {
                  final exMap =
                      rawExercises[i] as Map<String, dynamic>;
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
