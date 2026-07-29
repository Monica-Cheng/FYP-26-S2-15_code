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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/app_theme.dart';

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
    final distanceKm = (distanceMeters / 1000).toStringAsFixed(2);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background — snapshot image or painted route-on-gradient.
          if (hasSnapshot)
            Image.memory(
              base64Decode(mapSnapshotBase64!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildPaintedBackground(),
            )
          else
            _buildPaintedBackground(),

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

  Widget _buildPaintedBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WW.primaryDark, Color(0xFF4a4ea8)],
        ),
      ),
      child: routePoints.length >= 2
          ? CustomPaint(
              size: const Size(width, height),
              painter: _RoutePainter(points: routePoints),
            )
          : null,
    );
  }
}

// Normalizes lat/lng into card-local coordinates and draws a stylized
// polyline — not literal map tiles, just the route's shape, matching the
// minimalist look of a real map snapshot. Preserves the route's aspect
// ratio (BoxFit.contain-style) rather than stretching lat/lng
// independently, which would visibly distort its real shape.
class _RoutePainter extends CustomPainter {
  final List<LatLng> points;

  _RoutePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final latSpan = maxLat - minLat;
    final lngSpan = maxLng - minLng;

    const padding = 56.0;
    // Route confined to roughly the upper two-thirds of the card so it
    // doesn't collide with the stat block's dark scrim at the bottom.
    final drawWidth = size.width - padding * 2;
    final drawHeight = size.height * 0.62 - padding;

    if (latSpan < 1e-9 && lngSpan < 1e-9) {
      // Route with essentially no movement (e.g. a near-stationary test
      // session) — draw a single dot rather than dividing by zero below.
      canvas.drawCircle(
        Offset(size.width / 2, drawHeight / 2 + padding),
        7,
        Paint()..color = Colors.white,
      );
      return;
    }

    final scale = latSpan == 0
        ? drawWidth / lngSpan
        : lngSpan == 0
            ? drawHeight / latSpan
            : math.min(drawWidth / lngSpan, drawHeight / latSpan);
    final scaledWidth = lngSpan * scale;
    final scaledHeight = latSpan * scale;
    final offsetX = padding + (drawWidth - scaledWidth) / 2;
    final offsetY = padding + (drawHeight - scaledHeight) / 2;

    Offset project(LatLng p) {
      final x = offsetX + (p.longitude - minLng) * scale;
      final y = offsetY + (maxLat - p.latitude) * scale;
      return Offset(x, y);
    }

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Start (hollow) / end (filled) markers — a common route-map
    // convention, and a cheap way to show direction of travel.
    final start = project(points.first);
    final end = project(points.last);
    canvas.drawCircle(start, 8, Paint()..color = Colors.white);
    canvas.drawCircle(start, 5, Paint()..color = WW.primaryDark);
    canvas.drawCircle(end, 8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points != points;
}
