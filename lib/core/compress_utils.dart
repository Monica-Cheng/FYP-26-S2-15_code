// lib/core/compress_utils.dart
// Shared Compress-feature data model + helpers. Used identically by every
// screen that displays or applies a tracked plan day's compression state
// (plan_schedule_screen.dart, gym_session_screen.dart, home_screen.dart,
// plan_detail_screen.dart) — factored out here, the same way xp_levels.dart
// was, specifically because each screen previously reimplementing its own
// version of "what does compressed mean for this day's exercises" is
// exactly how the tag == 'Primary' vs tag != 'Accessory' inconsistency
// happened. One shared transform, one place to fix it, going forward.

/// Per-day compression state: which exercise array-indices (within that
/// day's exercises list, as stored in Firestore) are removed, and which
/// cardio-block indices have an overridden (shortened) duration.
class CompressedDayData {
  final Set<int> removedExercises;
  final Map<int, int> cardioOverrides;

  const CompressedDayData({
    required this.removedExercises,
    required this.cardioOverrides,
  });

  bool get isEmpty => removedExercises.isEmpty && cardioOverrides.isEmpty;
}

/// A day's exercises, addressed the same way dayIndex is addressed
/// elsewhere in this app (1-based, flat across all weeks) — dayIndex - 1
/// is a direct index into a flat, per-day sessions list.
List<Map<String, dynamic>> exercisesForDay(
  int dayIndex,
  List<Map<String, dynamic>> sessions,
) {
  final flatIndex = dayIndex - 1;
  if (flatIndex < 0 || flatIndex >= sessions.length) return [];
  return (sessions[flatIndex]['exercises'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      [];
}

/// Parses users/{uid}/planProgress/{planId}.compressedDays, handling both
/// shapes it may hold:
///   - New format: `{"dayIndex": {"removedExercises": [int, ...],
///     "cardioOverrides": {"exerciseIndex": minutes, ...}}}`
///   - Legacy format (a plain boolean list, e.g. [3, 5]): a day either was
///     or wasn't compressed, with no per-exercise selection ever recorded
///     and no cardio overrides ever possible — the old behavior was
///     always "remove every Accessory-tagged exercise, never touch
///     cardio." Rather than crash or silently drop these days' compressed
///     state, this resolves each legacy dayIndex against that day's REAL
///     current exercises to reconstruct the equivalent removedExercises
///     set, with an empty cardioOverrides map.
/// Both shapes normalize into the same in-memory map; the next time a
/// consuming screen writes compressedDays back (compress or restore), the
/// whole field is re-serialized in the new format only (see
/// serializeCompressedDays()) — a lazy, on-touch migration rather than a
/// one-time rewrite of every user's doc.
Map<int, CompressedDayData> parseCompressedDays(
  dynamic raw,
  List<Map<String, dynamic>> sessions,
) {
  final result = <int, CompressedDayData>{};

  if (raw is List) {
    for (final d in raw) {
      final dayIndex = (d as num).toInt();
      final exercises = exercisesForDay(dayIndex, sessions);
      final accessoryIndices = <int>{
        for (var i = 0; i < exercises.length; i++)
          if (exercises[i]['tag'] == 'Accessory') i,
      };
      result[dayIndex] = CompressedDayData(
        removedExercises: accessoryIndices,
        cardioOverrides: {},
      );
    }
  } else if (raw is Map) {
    raw.forEach((key, value) {
      final dayIndex = int.tryParse(key.toString());
      if (dayIndex == null || value is! Map) return;

      final removed = <int>{
        for (final e in (value['removedExercises'] as List? ?? []))
          (e as num).toInt(),
      };

      final overrides = <int, int>{};
      final rawOverrides = value['cardioOverrides'];
      if (rawOverrides is Map) {
        rawOverrides.forEach((k, v) {
          final idx = int.tryParse(k.toString());
          final minutes = (v as num?)?.toInt();
          if (idx != null && minutes != null) overrides[idx] = minutes;
        });
      }

      result[dayIndex] = CompressedDayData(
        removedExercises: removed,
        cardioOverrides: overrides,
      );
    });
  }

  return result;
}

/// Inverse of parseCompressedDays() — always serializes the new map
/// format, regardless of what shape was originally read.
Map<String, dynamic> serializeCompressedDays(
    Map<int, CompressedDayData> data) {
  return {
    for (final entry in data.entries)
      entry.key.toString(): {
        'removedExercises': entry.value.removedExercises.toList(),
        'cardioOverrides': entry.value.cardioOverrides
            .map((k, v) => MapEntry(k.toString(), v)),
      },
  };
}

/// Applies a day's compression state to its raw exercises list: drops
/// removed indices, and for surviving cardio blocks with an override,
/// returns a copy with cardioMinutes replaced. Returns an unmodified copy
/// if [dayData] is null/empty. This is the single shared transform every
/// consuming screen applies — kept here so all call sites can never drift
/// into different filtering rules again the way tag == 'Primary' vs
/// tag != 'Accessory' did.
List<Map<String, dynamic>> applyCompression(
  List<Map<String, dynamic>> rawExercises,
  CompressedDayData? dayData,
) {
  if (dayData == null || dayData.isEmpty) return List.of(rawExercises);
  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < rawExercises.length; i++) {
    if (dayData.removedExercises.contains(i)) continue;
    final override = dayData.cardioOverrides[i];
    result.add(override != null
        ? {...rawExercises[i], 'cardioMinutes': override}
        : rawExercises[i]);
  }
  return result;
}

/// Updated time estimate after compression — a real calculation on both
/// sides now, not an approximation. For each removed (non-cardio) exercise,
/// looks up its actual sets_count × (estTimePerSet + restTime) from
/// [rawExercises] (sets_count resolves the same dual shape
/// _computeEstimatedMinutes() in build_routine_screen.dart does: the admin
/// scalar `sets` count, or a custom/coach plan's `sets` array length) and
/// subtracts that real value — replacing the old flat "4 min per removed
/// exercise" heuristic. The cardio portion is unchanged: the real cardio
/// minutes actually shaved off each overridden cardio block (original
/// cardioMinutes, looked up from [rawExercises] since cardioOverrides only
/// ever stores the new value, minus the override). Never returns a
/// negative number, and never exceeds [baseMinutes].
int estimatedMinutesAfterCompression(
  int baseMinutes,
  CompressedDayData? dayData,
  List<Map<String, dynamic>> rawExercises,
) {
  if (dayData == null || dayData.isEmpty) return baseMinutes;

  var fromRemovedSeconds = 0;
  for (final index in dayData.removedExercises) {
    if (index < 0 || index >= rawExercises.length) continue;
    final ex = rawExercises[index];
    final rawSets = ex['sets'];
    final setsCount =
        rawSets is List ? rawSets.length : (rawSets as num?)?.toInt() ?? 0;
    final estTimePerSet = (ex['estTimePerSet'] as num?)?.toInt() ?? 0;
    final restTime = (ex['restTime'] as num?)?.toInt() ?? 0;
    fromRemovedSeconds += setsCount * (estTimePerSet + restTime);
  }
  final fromRemoved = (fromRemovedSeconds / 60).round();

  var fromCardio = 0;
  dayData.cardioOverrides.forEach((index, newMinutes) {
    if (index < 0 || index >= rawExercises.length) return;
    final original =
        (rawExercises[index]['cardioMinutes'] as num?)?.toInt() ?? newMinutes;
    fromCardio += (original - newMinutes).clamp(0, original);
  });

  return (baseMinutes - fromRemoved - fromCardio).clamp(0, baseMinutes);
}
