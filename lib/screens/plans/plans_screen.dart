// lib/screens/plans/plans_screen.dart
// Plans Hub — Start Cardio CTA, Choose a Way to Train cards,
// Tracked Plan card, and All Plans vertical list.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

const List<Map<String, dynamic>> _kFallbackPlans = [
  {'name': 'Beginner Push-Pull-Legs', 'type': 'Gym', 'level': 'Beginner', 'daysPerWeek': 3},
  {'name': '5K Running Plan', 'type': 'Running', 'level': 'Beginner', 'daysPerWeek': 4},
  {'name': 'My Custom Push', 'type': 'Gym', 'level': 'Custom', 'daysPerWeek': 3},
];

class _PlansScreenState extends State<PlansScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;
  Map<String, dynamic>? _trackedPlan;
  bool _trackedPlanLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
    _loadTrackedPlan();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await _firestoreService.getPlans();
      if (mounted) {
        setState(() {
          _plans = plans.isNotEmpty ? plans : _kFallbackPlans;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _plans = _kFallbackPlans;
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
      setState(() {
        _trackedPlan = plan;
        _trackedPlanLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _trackedPlanLoading = false);
    }
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
      onTap: () => _snack('Cardio tracking coming soon'),
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
                onTap: () => _snack('Build coming soon'),
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

    return Container(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      letterSpacing: 0.4,
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
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: WW.primaryDark,
                    letterSpacing: -0.2,
                  ),
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
                const SizedBox(height: 14),
                // Buttons row
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push(Routes.gymSession),
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: WW.primary,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: [
                              BoxShadow(
                                color: WW.primary.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Continue Session',
                              style: TextStyle(
                                fontSize: 13,
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
                        onTap: () => context.push(Routes.planSchedule, extra: _trackedPlan),
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: WW.primary, width: 1.5),
                          ),
                          child: const Center(
                            child: Text(
                              'Schedule',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: WW.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
                    .then((_) => _loadTrackedPlan()),
              ),
            );
          }),
      ],
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
