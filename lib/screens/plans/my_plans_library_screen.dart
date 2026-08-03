// lib/screens/plans/my_plans_library_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import 'plans_screen.dart' show RecentPlanRow;

// Full-screen "My Plans Library" — every plan from plans_screen.dart's own
// filtered set (isCustom-and-mine, or saved), with no 3-item cap. Replaces
// the old "My plans library coming soon" dead-end toast that used to sit
// behind the Plans tab's "See all" tap.
//
// Reached via plans_screen.dart's "See all" tap, which already has this
// exact filtered list loaded (`_plans`, kept fresh by its own
// _loadPlans()/user-doc stream) and passes it straight through via `extra`
// — this screen does not re-fetch or re-filter, it only renders what it's
// given, so it stays a plain StatelessWidget.
class MyPlansLibraryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> plans;

  const MyPlansLibraryScreen({super.key, required this.plans});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  // Matches this app's other full-screen header convention (see
  // friends_screen.dart's own _buildHeader) — chevron_left_rounded here
  // (not close_rounded) since this screen is reached via context.push and
  // is meant to be stepped back through, not dismissed.
  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(bottom: BorderSide(color: WW.border, width: 0.5)),
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
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 22,
                    color: WW.primaryDark,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            'My Plans Library',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (plans.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center_rounded, size: 36, color: WW.textSec),
              SizedBox(height: 10),
              Text(
                'No plans yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Plans you save, build, or track will show up here.',
                style: TextStyle(fontSize: 13, color: WW.textSec),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: plans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final plan = plans[i];
        final name = plan['name']?.toString() ?? 'Unnamed Plan';
        final type = plan['type']?.toString() ?? '';
        final isCustom = plan['isCustom'] == true;
        return RecentPlanRow(
          name: name,
          type: type,
          isCustom: isCustom,
          imageUrl: plan['imageUrl'] as String?,
          onTap: () => context.push(Routes.planDetail, extra: plan),
        );
      },
    );
  }
}
