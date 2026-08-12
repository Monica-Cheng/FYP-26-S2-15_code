// lib/screens/profile/all_badges_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../widgets/badge_tile.dart';

// Full-screen badge catalog — every badge from profile_screen.dart's own
// already-loaded getBadgeDefinitions()/getEarnedBadgeIds() data (both
// unpaginated reads), with no cap. Reached via the Badges section's "See
// all" tap, which already has this exact data loaded (_allBadges,
// _earnedBadgeIds) and passes it straight through via `extra` — this
// screen does not re-fetch, it only renders what it's given, so it stays
// a plain StatelessWidget (same convention as MyPlansLibraryScreen).
class AllBadgesScreen extends StatelessWidget {
  final List<Map<String, dynamic>> badges;
  final Set<String> earnedIds;

  const AllBadgesScreen({
    super.key,
    required this.badges,
    required this.earnedIds,
  });

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

  // Same full-screen header convention as my_plans_library_screen.dart's
  // own _buildHeader — chevron_left_rounded (not close_rounded) since this
  // screen is reached via context.push and is meant to be stepped back
  // through, not dismissed.
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
            'Badges',
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
    if (badges.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_rounded, size: 36, color: WW.textSec),
              SizedBox(height: 10),
              Text(
                'No badges yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Same fixed-crossAxisCount-4 / mainAxisExtent-90 grid as
    // profile_screen.dart's own badges GridView — see that widget's doc
    // comment for why mainAxisExtent (not childAspectRatio) is used.
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        mainAxisExtent: 90,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) {
        final badge = badges[i];
        final earned = earnedIds.contains(badge['id'] as String);
        return GestureDetector(
          onTap: () => showBadgeDetailSheet(context, badge, earned),
          child: BadgeTile(badge: badge, earned: earned),
        );
      },
    );
  }
}
