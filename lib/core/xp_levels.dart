// lib/core/xp_levels.dart
// Shared XP/level curve — extracted so user_profile_screen.dart's "game
// profile" stats can genuinely reuse the same table/logic
// progress_screen.dart's own _buildLevelCard() uses, rather than a second
// hand-copied version. progress_screen.dart keeps its own existing
// private copy untouched (not broken, not in scope to change) — this is
// only consumed by the new profile-screen code for now.

import '../services/firestore_service.dart';

class XpLevels {
  XpLevels._();

  // Fallback only, matching firestore_service.dart's own
  // _kFallbackLevelThresholds convention — the real values now come from
  // the live appConfig/gamification config (see loadThresholds() below),
  // used only if that fetch is unavailable. Previously this was the
  // primary, only source (a hardcoded copy never synced with whatever an
  // admin actually configured), which meant an admin editing an existing
  // threshold value never showed up here — a real correctness gap
  // independent of adding new levels.
  static const List<num> fallbackThresholds = [
    0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000,
  ];

  // Reads the live levelThresholds array via
  // FirestoreService.getLevelThresholds(), which itself goes through
  // getGamificationConfig()'s existing static cache — safe/cheap to call
  // from every screen that needs it (progress_screen.dart,
  // profile_screen.dart, and this file's own caller,
  // user_profile_screen.dart); only the first call anywhere in the app
  // session actually hits Firestore.
  static Future<List<num>> loadThresholds() {
    return FirestoreService().getLevelThresholds(fallbackThresholds);
  }

  // [thresholds] is the caller's currently-loaded array (from
  // loadThresholds(), or fallbackThresholds while that's still in
  // flight) — no longer reads the static thresholds constant directly,
  // so this always reflects whatever the caller actually has loaded.
  static double progress(int level, int totalXp, List<num> thresholds) {
    if (level >= thresholds.length) return 1.0;
    final start = thresholds[level - 1];
    final end = thresholds[level];
    return ((totalXp - start) / (end - start)).clamp(0.0, 1.0);
  }
}
