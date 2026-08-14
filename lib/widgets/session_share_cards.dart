// lib/widgets/session_share_cards.dart
// Builds the Map/Photo/Color ShareCardOption list for a workout session —
// shared between post_session_summary_screen.dart (right after a session
// finishes) and activity_detail_screen.dart (viewing a PAST session from
// Progress → Activities). Both read from the same Firestore session
// document shape, so this only needs the session map plus a few values
// each screen already has parsed (isCardio, routePoints) — extracted here
// specifically because this logic was originally written as private
// methods on post_session_summary_screen.dart's own State, tightly
// coupled to its instance fields, and duplicating ~100 lines of card-
// building logic across two screens would mean every future card-design
// change (new card type, new stat, etc.) has to be made twice or the two
// screens silently drift apart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'photo_background_share_card.dart';
import 'route_map_share_card.dart';
import 'route_overlay.dart';
import 'share_card_picker.dart';
import 'share_card_widget.dart';

String _fmtStatDuration(int secs) {
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

// Same 50m-floor + MM:SS/km formatting convention duplicated verbatim
// across post_session_summary_screen.dart/activity_detail_screen.dart/
// outdoor_cardio_screen.dart before this — kept as a private helper here
// too rather than also extracting it, since that's a wider, unrelated
// dedup not asked for by this task.
String? _avgPaceLabel(double distanceMeters, int durationSeconds) {
  if (distanceMeters < 50 || durationSeconds <= 0) return null;
  final secondsPerKm = durationSeconds / (distanceMeters / 1000);
  if (!secondsPerKm.isFinite) return null;
  final mins = secondsPerKm ~/ 60;
  final secs = (secondsPerKm % 60).round();
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} /km';
}

// Builds whichever of the 3 card designs are actually available for this
// session — Map only for a pure-cardio session with a route or snapshot
// (RouteMapShareCard.isAvailable — always false for combined sessions,
// since isCardio is false there and route/snapshot data lives nested
// per-block instead, out of this feature's scope), Photo only if
// photoBase64 was resolved (reused or picked by the caller), Color
// always (the universal fallback). The route overlay is applied to
// Photo/Color whenever routePoints is non-empty — the Map card already
// shows its own route via RouteMapShareCard internally.
List<ShareCardOption> buildSessionShareCardOptions({
  required Map<String, dynamic> session,
  required bool isCardio,
  required List<LatLng> routePoints,
  String? photoBase64,
}) {
  final hasRoute = routePoints.isNotEmpty;
  final sessionName = session['sessionName'] as String? ?? 'Workout';
  final elapsedSeconds = (session['durationSeconds'] as num?)?.toInt() ?? 0;
  final date = (session['date'] as Timestamp?)?.toDate() ?? DateTime.now();
  final totalSets = (session['totalSets'] as num?)?.toInt() ?? 0;
  final totalVolume = (session['totalVolume'] as num?)?.toDouble() ?? 0;
  final caloriesBurned = (session['caloriesBurned'] as num?)?.toInt() ?? 0;
  final cardioActivity = session['activity'] as String? ?? '';
  final activityLabel = cardioActivity.isNotEmpty ? cardioActivity : 'Cardio';
  final distanceMeters = (session['distanceMeters'] as num?)?.toDouble() ?? 0;
  final mapSnapshotBase64 = session['mapSnapshotBase64'] as String?;

  final cards = <ShareCardOption>[];

  if (isCardio &&
      RouteMapShareCard.isAvailable(
        mapSnapshotBase64: mapSnapshotBase64,
        routePoints: routePoints,
      )) {
    cards.add(ShareCardOption(
      label: 'Map',
      builder: (_, _) => RouteMapShareCard(
        mapSnapshotBase64: mapSnapshotBase64,
        routePoints: routePoints,
        sessionName: sessionName,
        activityLabel: activityLabel,
        distanceMeters: distanceMeters,
        durationSeconds: elapsedSeconds,
        calories: caloriesBurned,
        paceLabel: _avgPaceLabel(distanceMeters, elapsedSeconds),
        date: date,
      ),
    ));
  }

  if (photoBase64 != null) {
    final stats = isCardio
        ? [
            (_fmtStatDuration(elapsedSeconds), 'Duration'),
            ('$caloriesBurned', 'Calories'),
            (_avgPaceLabel(distanceMeters, elapsedSeconds) ?? '--:--', 'Pace'),
          ]
        : [
            (_fmtStatDuration(elapsedSeconds), 'Duration'),
            ('$caloriesBurned', 'Calories'),
            ('$totalSets', 'Sets'),
          ];
    cards.add(ShareCardOption(
      label: 'Photo',
      builder: (_, _) => SizedBox(
        width: RouteMapShareCard.width,
        height: RouteMapShareCard.height,
        child: Stack(
          children: [
            PhotoBackgroundShareCard(
              photoBase64: photoBase64,
              title: sessionName,
              badgeLabel: isCardio ? activityLabel : 'Gym',
              stats: stats,
              date: date,
            ),
            if (hasRoute)
              Positioned.fill(
                child: RouteOverlay(
                  routePoints: routePoints,
                  bounds: RouteOverlay.kSafeZone,
                ),
              ),
          ],
        ),
      ),
    ));
  }

  cards.add(ShareCardOption(
    label: 'Color',
    supportsColorPicker: true,
    // Reads the gradient LIVE from the picker sheet's current swatch
    // selection (passed in fresh on every rebuild) instead of a value
    // snapshotted once when this options list was first built — see
    // ShareCardOption.builder's own doc comment in share_card_picker.dart
    // for the bug this fixes (swatch taps silently not changing the
    // card).
    builder: (_, gradientColors) => SizedBox(
      width: RouteMapShareCard.width,
      height: RouteMapShareCard.height,
      child: Stack(
        children: [
          ShareCardWidget(
            sessionName: sessionName,
            isCardio: isCardio,
            cardioActivity: cardioActivity,
            elapsedSeconds: elapsedSeconds,
            calories: caloriesBurned,
            totalSets: totalSets,
            volume: totalVolume,
            // Not stored on the finalized session doc anywhere (it was
            // always just cardio_session_screen.dart's own local,
            // ephemeral "+5 min" goal state) — 0 matches the "no goal
            // set" display elsewhere.
            goalMinutes: 0,
            date: date,
            gradientColors: gradientColors,
          ),
          if (hasRoute)
            Positioned.fill(
              child: RouteOverlay(
                routePoints: routePoints,
                bounds: RouteOverlay.kSafeZone,
              ),
            ),
        ],
      ),
    ),
  ));

  return cards;
}
