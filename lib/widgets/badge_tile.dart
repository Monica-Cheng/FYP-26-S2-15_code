// lib/widgets/badge_tile.dart
// Shared badge rendering — extracted from profile_screen.dart so both the
// Profile screen's capped grid and all_badges_screen.dart's full catalog
// grid render identical tiles/detail sheets with no duplication.

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

// Off-white — locked-badge background not present in WW palette.
const kLockedBadgeBg = Color(0xFFF2F2F7);

// Locked badges: dimmed (reduced opacity) AND greyscale (a standard
// luminance-preserving color matrix) together — either alone read as too
// subtle a distinction from an earned badge at this tile size.
Widget _buildBadgeImage(String imageUrl, double size, bool earned) {
  final image = Image.network(
    imageUrl,
    width: size,
    height: size,
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => Icon(
      Icons.emoji_events_rounded,
      size: size * 0.4,
      color: earned ? WW.primary : WW.border,
    ),
  );
  if (earned) return image;
  return Opacity(
    opacity: 0.35,
    child: ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: image,
    ),
  );
}

// A single badge tile — icon/image (earned: full color, locked: dimmed +
// greyscale + lock overlay) plus a name label below. Used both in a grid
// (default size) and in showBadgeDetailSheet's header (size: 72).
class BadgeTile extends StatelessWidget {
  final Map<String, dynamic> badge;
  final bool earned;
  final double size;

  const BadgeTile({
    super.key,
    required this.badge,
    required this.earned,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = badge['imageUrl'] as String? ?? '';
    final name = badge['name'] as String? ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: earned ? WW.chipBg : kLockedBadgeBg,
            borderRadius: BorderRadius.circular(size * 0.28),
            border: earned ? null : Border.all(color: WW.border, width: 1.5),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (imageUrl.isNotEmpty)
                _buildBadgeImage(imageUrl, size, earned)
              else
                Icon(
                  Icons.emoji_events_rounded,
                  size: size * 0.4,
                  color: earned ? WW.primary : WW.border,
                ),
              if (!earned)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.lock_rounded, size: size * 0.28, color: Colors.white),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: size,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: earned ? WW.text : WW.border,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

// Plain-language phrasing for one condition — e.g. {statType: 'level',
// value: 5} -> "reach level 5". Used by describeBadgeConditions() below,
// joined into a single readable sentence rather than shown as raw
// statType/value pairs.
String _describeCondition(Map<String, dynamic> cond) {
  final statType = cond['statType'] as String? ?? '';
  final rawValue = cond['value'];
  if (rawValue is! num) return 'meet a special condition';
  String fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  switch (statType) {
    case 'level':
      return 'reach level ${fmt(rawValue)}';
    case 'totalXp':
      return 'earn ${fmt(rawValue)} total XP';
    case 'sessionCount':
      return 'complete ${fmt(rawValue)} session${rawValue == 1 ? '' : 's'}';
    case 'totalVolume':
      return 'lift ${fmt(rawValue)} kg total volume';
    case 'totalDistance':
      // Badge conditions store distance in the same unit as
      // computeChallengeProgress()'s 'km'-converted output — see
      // FirestoreService.checkAndAwardBadges()'s totalDistance stat, which
      // reads getLifetimeStats()'s totalDistanceMeters and is compared
      // directly against this condition's raw value, so this value is
      // already in km, not meters, for a readable admin-facing number.
      return 'cover ${fmt(rawValue)} km total distance';
    case 'streak':
      return 'reach a ${fmt(rawValue)}-day streak';
    default:
      return 'meet a special condition';
  }
}

String describeBadgeConditions(List<dynamic> conditions) {
  final parts = conditions
      .whereType<Map>()
      .map((c) => _describeCondition(Map<String, dynamic>.from(c)))
      .toList();
  if (parts.isEmpty) return 'No conditions set';
  final joined = parts.length == 1
      ? parts.first
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  return joined[0].toUpperCase() + joined.substring(1);
}

// Badge detail bottom sheet — name/description/unlock-condition display.
// Shared by profile_screen.dart and all_badges_screen.dart so tapping any
// badge tile, in either the capped grid or the full catalog, opens the
// identical sheet.
void showBadgeDetailSheet(
  BuildContext context,
  Map<String, dynamic> badge,
  bool earned,
) {
  final name = badge['name'] as String? ?? 'Badge';
  final description = badge['description'] as String? ?? '';
  final conditions = (badge['conditions'] as List?) ?? const [];
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: WW.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BadgeTile(badge: badge, earned: earned, size: 72),
            const SizedBox(height: 16),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: WW.textSec),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    earned ? Icons.check_circle_rounded : Icons.flag_rounded,
                    color: earned ? WW.teal : WW.textSec,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      earned ? 'Unlocked!' : describeBadgeConditions(conditions),
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
          ],
        ),
      );
    },
  );
}
