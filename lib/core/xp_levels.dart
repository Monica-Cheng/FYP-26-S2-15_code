// lib/core/xp_levels.dart
// Shared XP/level curve — extracted so user_profile_screen.dart's "game
// profile" stats can genuinely reuse the same table/logic
// progress_screen.dart's own _buildLevelCard() uses, rather than a second
// hand-copied version. progress_screen.dart keeps its own existing
// private copy untouched (not broken, not in scope to change) — this is
// only consumed by the new profile-screen code for now.

class XpLevels {
  XpLevels._();

  static const thresholds = [
    0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000,
  ];

  static String levelName(int level) {
    const names = [
      '', 'Rookie', 'Beginner', 'Apprentice', 'Contender',
      'Challenger', 'Warrior', 'Iron Athlete', 'Steel Athlete',
      'Elite Athlete', 'Champion', 'Legend',
    ];
    if (level < 1 || level >= names.length) return 'Level $level';
    return names[level];
  }

  static double progress(int level, int totalXp) {
    if (level >= thresholds.length) return 1.0;
    final start = thresholds[level - 1];
    final end = thresholds[level];
    return ((totalXp - start) / (end - start)).clamp(0.0, 1.0);
  }
}
