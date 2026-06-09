// lib/screens/plans/plan_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Sample week data ──────────────────────────────────────────────────────────

const List<Map<String, dynamic>> _kGymWeek = [
  {
    'day': 'Mon',
    'session': 'Push A',
    'exercises': [
      'Bench Press 4×8',
      'Overhead Press 3×10',
      'Tricep Pushdown 3×12',
      'Lateral Raise 3×15',
    ],
  },
  {
    'day': 'Wed',
    'session': 'Pull A',
    'exercises': [
      'Pull-ups 4×8',
      'Barbell Row 3×10',
      'Face Pull 3×15',
      'Bicep Curl 3×12',
    ],
  },
  {
    'day': 'Fri',
    'session': 'Legs A',
    'exercises': [
      'Squat 4×8',
      'Romanian Deadlift 3×10',
      'Leg Press 3×12',
      'Calf Raise 4×15',
    ],
  },
];

const List<Map<String, dynamic>> _kRunWeek = [
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTrackedState());
  }

  Future<void> _checkTrackedState() async {
    final plan = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final planId = plan?['id'] as String?;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Track this plan?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        content: const Text(
          'This will replace your current tracked plan.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: WW.textSec),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Confirm',
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

    setState(() => _isTracking = true);
    try {
      final uid = AuthService().getCurrentUser()?.uid;
      if (uid != null) {
        await FirestoreService().trackPlan(
          uid,
          plan['id'] as String? ?? '',
          plan['name'] as String? ?? 'Unnamed Plan',
        );
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isTracking = false;
      _isTracked = true;
    });
    context.pop();
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

  @override
  Widget build(BuildContext context) {
    final plan = GoRouterState.of(context).extra as Map<String, dynamic>?;

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
    final description = plan['description'] as String? ??
        'A structured training plan designed to help you reach your fitness goals through progressive overload and consistent training.';
    final equipment =
        (plan['equipment'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final goals =
        (plan['goals'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final isRunning = type.toLowerCase().contains('run');
    final sampleWeek = isRunning ? _kRunWeek : _kGymWeek;

    return Scaffold(
      backgroundColor: WW.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _buildHero(
                    name, type, level, daysPerWeek, durationWeeks),
              ),
              SliverToBoxAdapter(child: _buildInjuryNotice()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildBestForCard(description),
                    const SizedBox(height: 14),
                    _buildExperienceLevelCard(level),
                    const SizedBox(height: 14),
                    _buildOverviewCard(description),
                    const SizedBox(height: 14),
                    _buildSampleWeek(sampleWeek),
                    const SizedBox(height: 14),
                    _buildEquipmentCard(equipment),
                    if (goals.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildGoalsSection(goals),
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
      int durationWeeks) {
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
                  GestureDetector(
                    onTap: () => _snack('Save to library coming soon'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Center(
                        child: Icon(Icons.bookmark_border_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
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
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
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
        ),
      ),
    );
  }

  // ── Injury notice ──────────────────────────────────────────────────────────

  Widget _buildInjuryNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: WW.lavenderBg,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: WW.lavender, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.auto_awesome_rounded, color: WW.lavender, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Some exercises adjusted for your health profile. Shoulder exercises replaced with safer alternatives.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WW.lavenderText,
                height: 1.45,
              ),
            ),
          ),
        ],
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

  // ── Sample Week ────────────────────────────────────────────────────────────

  Widget _buildSampleWeek(List<Map<String, dynamic>> week) {
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
        ...week.map((day) => _DayCard(dayData: day)),
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
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: WW.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _snack('Save to library coming soon'),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: WW.primary, width: 1.5),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border_rounded,
                          color: WW.primary, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Save',
                        style: TextStyle(
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
  final Map<String, dynamic> dayData;
  const _DayCard({required this.dayData});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.dayData['day'] as String;
    final session = widget.dayData['session'] as String;
    final exercises = (widget.dayData['exercises'] as List)
        .map((e) => e.toString())
        .toList();

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
                          '${exercises.length} exercises',
                          style: const TextStyle(
                              fontSize: 11, color: WW.textSec),
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
                    decoration: BoxDecoration(
                      border: i < exercises.length - 1
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
