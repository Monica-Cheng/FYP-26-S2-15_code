// lib/widgets/route_map_share_card.dart
// One of the shareable Story-ratio (1080x1920 @ pixelRatio 3.0, so this
// widget is sized 360x640 logical) card designs offered by
// post_session_summary_screen.dart for an outdoor cardio session — see
// that screen's card-picker flow. Two backgrounds, picked automatically:
//   - mapSnapshotBase64 present: used directly as the background image
//     (already has the route baked in from capture time).
//   - mapSnapshotBase64 absent but routePoints present (e.g. a
//     plan-linked pure-cardio session before the finalizeInProgressSession
//     promotion fix, or any future path that saves route without a
//     snapshot): a CustomPainter draws a stylized route line on a dark
//     gradient background instead — not literal map tiles, just the
//     route's shape.
// Callers should only offer this card at all when at least one of
// mapSnapshotBase64/routePoints is non-empty — see RouteMapShareCard.isAvailable.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/app_theme.dart';
import 'route_overlay.dart';

class RouteMapShareCard extends StatelessWidget {
  static const double width = 360;
  static const double height = 640;

  final String? mapSnapshotBase64;
  final List<LatLng> routePoints;
  final String sessionName;
  final String activityLabel;
  final double distanceMeters;
  final int durationSeconds;
  final int calories;
  final String? paceLabel;
  final DateTime date;

  const RouteMapShareCard({
    super.key,
    this.mapSnapshotBase64,
    this.routePoints = const [],
    required this.sessionName,
    required this.activityLabel,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.calories,
    this.paceLabel,
    required this.date,
  });

  static bool isAvailable({
    String? mapSnapshotBase64,
    List<LatLng> routePoints = const [],
  }) =>
      (mapSnapshotBase64?.isNotEmpty ?? false) || routePoints.isNotEmpty;

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasSnapshot = mapSnapshotBase64?.isNotEmpty ?? false;
    // Diagnostic for the "map card shows a blank/grey gradient instead of
    // the real map" bug — confirms whether this session's
    // mapSnapshotBase64 actually reached this widget with real content
    // (upstream capture problem, see outdoor_cardio_screen.dart's
    // _captureMapSnapshot) vs. arrived fine and the CustomPainter/gradient
    // fallback is being shown for some other reason (a rendering issue in
    // this widget itself). Check this line's output the next time the bug
    // reproduces before assuming which case it is.
    debugPrint('[RouteMapShareCard] hasSnapshot=$hasSnapshot '
        'mapSnapshotBase64.length=${mapSnapshotBase64?.length ?? 0} '
        'routePoints.length=${routePoints.length}');
    final distanceKm = (distanceMeters / 1000).toStringAsFixed(2);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background — snapshot image or painted gradient. NOT relied
          // on alone for the route line anymore (see RouteOverlay below)
          // — a snapshot's baked-in route depends on a completely
          // separate pipeline (outdoor_cardio_screen.dart's
          // _drawRouteOnSnapshot, using the `image` package, its own
          // Mercator projection, and a WW.primary-colored line with no
          // contrast outline) succeeding, and previously had no fallback
          // at all here if it didn't draw clearly. RouteOverlay is now
          // always stacked on top when there's route data, independent
          // of whether the snapshot's own baked-in line is visible.
          if (hasSnapshot)
            Image.memory(
              base64Decode(mapSnapshotBase64!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildPaintedBackground(),
            )
          else
            _buildPaintedBackground(),

          if (routePoints.length >= 2)
            Positioned.fill(
              child: RouteOverlay(
                routePoints: routePoints,
                bounds: RouteOverlay.kSafeZone,
              ),
            ),

          // Dark scrim behind the bottom stat block, for legibility over
          // either a bright map snapshot or a bright photo-like painted
          // route.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),

          // Brand row, top.
          Positioned(
            top: 28,
            left: 24,
            right: 24,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.fitness_center_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'WiseWorkout',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    activityLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Stat block, bottom.
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sessionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      distanceKm,
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'km',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _statColumn(_fmtDuration(durationSeconds), 'Duration'),
                    _statColumn(paceLabel ?? '--:--', 'Pace'),
                    _statColumn('$calories', 'Calories'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _fmtDate(date),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  // Just the gradient now — the route line itself is drawn by the
  // RouteOverlay stacked on top in build() (same mechanism used for
  // both this card's snapshot case and the Photo/Color cards), not
  // painted here directly anymore.
  Widget _buildPaintedBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WW.primaryDark, Color(0xFF4a4ea8)],
        ),
      ),
    );
  }
}
