// lib/widgets/route_overlay.dart
// A route-line-only, transparent-background overlay — the stylized
// polyline drawing originally built as RouteMapShareCard's painted
// (no-snapshot) background, extracted here so the same drawing can be
// layered on TOP of any card background (map, photo, or color) instead of
// only existing as its own standalone card design. See
// post_session_summary_screen.dart's _buildCardOptions() for where this
// gets stacked onto the Photo/Color cards when route data is available for
// that session; route_map_share_card.dart reuses RoutePainter directly for
// its own painted-background fallback.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/app_theme.dart';

class RouteOverlay extends StatelessWidget {
  final List<LatLng> routePoints;

  const RouteOverlay({super.key, required this.routePoints});

  @override
  Widget build(BuildContext context) {
    if (routePoints.length < 2) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: RoutePainter(points: routePoints)),
    );
  }
}

// Normalizes lat/lng into local coordinates and draws a stylized
// polyline — not literal map tiles, just the route's shape, matching the
// minimalist look of a real map snapshot. Preserves the route's aspect
// ratio (BoxFit.contain-style) rather than stretching lat/lng
// independently, which would visibly distort its real shape.
class RoutePainter extends CustomPainter {
  final List<LatLng> points;

  RoutePainter({required this.points});

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
    // doesn't collide with the stat block's dark scrim at the bottom, on
    // any of the 3 card backgrounds this can be overlaid on.
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
  bool shouldRepaint(covariant RoutePainter oldDelegate) =>
      oldDelegate.points != points;
}
