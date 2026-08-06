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
  // Region (in the same logical coordinate space as the card, e.g.
  // 360x640) the route should be drawn/centered within — lets each card
  // type carve out a safe zone that doesn't collide with its own text
  // (see RouteMapShareCard/PhotoBackgroundShareCard/ShareCardWidget, all
  // of which now pass the same shared zone for visual consistency).
  // Falls back to the original upper-card zone if omitted.
  final Rect? bounds;

  // Shared safe zone all 3 card types pass — sits below every card's
  // brand-row header (which ends around y=84) and well above where the
  // Map/Photo cards' bottom-anchored text blocks start (y~430-490) and
  // where ShareCardWidget's title now starts after its own reserved
  // spacer (see that widget) — one rect reused everywhere so the route
  // renders in the same place/size on all 3 designs.
  static const Rect kSafeZone = Rect.fromLTWH(36, 96, 288, 204);

  const RouteOverlay({super.key, required this.routePoints, this.bounds});

  @override
  Widget build(BuildContext context) {
    if (routePoints.length < 2) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: RoutePainter(points: routePoints, bounds: bounds)),
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
  final Rect? bounds;

  RoutePainter({required this.points, this.bounds});

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

    // Falls back to the original upper-card zone (roughly the top 62%,
    // minus padding) for any caller that doesn't pass an explicit bounds
    // rect.
    final drawRect = bounds ??
        Rect.fromLTWH(56, 56, size.width - 112, size.height * 0.62 - 56);
    final drawWidth = drawRect.width;
    final drawHeight = drawRect.height;

    if (latSpan < 1e-9 && lngSpan < 1e-9) {
      // Route with essentially no movement (e.g. a near-stationary test
      // session) — draw a single dot, centered in the bounds rect,
      // rather than dividing by zero below.
      final dot = drawRect.center;
      canvas.drawCircle(dot, 8.5, Paint()..color = Colors.black.withValues(alpha: 0.45));
      canvas.drawCircle(dot, 7, Paint()..color = Colors.white);
      return;
    }

    final scale = latSpan == 0
        ? drawWidth / lngSpan
        : lngSpan == 0
            ? drawHeight / latSpan
            : math.min(drawWidth / lngSpan, drawHeight / latSpan);
    final scaledWidth = lngSpan * scale;
    final scaledHeight = latSpan * scale;
    final offsetX = drawRect.left + (drawWidth - scaledWidth) / 2;
    final offsetY = drawRect.top + (drawHeight - scaledHeight) / 2;

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

    // A dark outline stroke drawn first, slightly wider than the colored
    // line on top of it, so the route stays visible regardless of what's
    // underneath — this overlay gets stacked on 3 genuinely different
    // background types (map snapshot, user photo, color gradient).
    // Classic "sticker" outline technique, not just a guess — same idea
    // as the start/end markers already having a white ring for contrast.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // WW.primary — the exact color activity_detail_screen.dart's own live
    // route line uses (see its _drawRouteLine()'s
    // lineColor: WW.primary.toHexStringRGB()) — reused verbatim rather
    // than a new purple, for visual consistency between the live map and
    // these share cards. Was plain white, too thick (strokeWidth 6, with
    // a 9-wide outline).
    canvas.drawPath(
      path,
      Paint()
        ..color = WW.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Start (hollow) / end (filled) markers — a common route-map
    // convention, and a cheap way to show direction of travel. Same dark
    // outline treatment for the same reason as the line above.
    final start = project(points.first);
    final end = project(points.last);
    canvas.drawCircle(start, 9.5, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawCircle(start, 8, Paint()..color = Colors.white);
    canvas.drawCircle(start, 5, Paint()..color = WW.primaryDark);
    canvas.drawCircle(end, 9.5, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawCircle(end, 8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant RoutePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.bounds != bounds;
}
