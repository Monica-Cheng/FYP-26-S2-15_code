// lib/widgets/photo_background_share_card.dart
// One of the shareable Story-ratio (1080x1920 @ pixelRatio 3.0, so this
// widget is sized 360x640 logical) card designs — a user-picked (or
// already-attached) photo as a full-bleed background, dark scrim, stats
// on top. Generic over (value, label) stat pairs so both meal-type and
// workout-type posts can reuse the same widget instead of near-duplicate
// meal/workout variants — see post_session_summary_screen.dart /
// nutrition_scan_screen.dart's card-picker wiring for what each passes.
//
// Always available once a photo exists (no availability gate the way
// RouteMapShareCard has) — either reused from photoBase64 already on the
// session (see PhotoBackgroundShareCard.reusablePhotoBase64), or freshly
// picked via ImagePicker by the caller before this widget is even built.

import 'dart:convert';

import 'package:flutter/material.dart';

class PhotoBackgroundShareCard extends StatelessWidget {
  static const double width = 360;
  static const double height = 640;

  final String photoBase64;
  final String title;
  final String badgeLabel;
  final List<(String value, String label)> stats;
  final DateTime date;

  const PhotoBackgroundShareCard({
    super.key,
    required this.photoBase64,
    required this.title,
    required this.badgeLabel,
    required this.stats,
    required this.date,
  });

  // Reads whatever photo is already attached to a fetched session doc
  // (see post_session_summary_screen.dart's _session), so the picker
  // doesn't ask the user to pick a photo a second time if they already
  // attached one during the session (e.g. outdoor cardio's own photo
  // step). Top-level only, matching that screen's own
  // _buildPhotoWidget() convention — a combined session's photo lives
  // nested in cardioBlocks[] instead, out of scope here the same way it
  // is there.
  static String? reusablePhotoBase64(Map<String, dynamic> session) {
    final raw = session['photoBase64'] as String?;
    return (raw != null && raw.isNotEmpty) ? raw : null;
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
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            base64Decode(photoBase64),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: Colors.black87),
          ),

          // Dark scrim, top-to-bottom, so both the brand row and the
          // stat block stay legible over an arbitrarily bright photo.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  stops: const [0, 0.25, 0.55, 1],
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
                    badgeLabel,
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

          // Title + stat row, bottom.
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final stat in stats) _statColumn(stat.$1, stat.$2),
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
}
