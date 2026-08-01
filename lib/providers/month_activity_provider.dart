// lib/providers/month_activity_provider.dart
// Backs the shared MonthCalendar widget (lib/widgets/common/
// month_calendar.dart) for both call sites (Home's week-strip drill-down
// modal, Progress > Charts) — both watch monthActivityProvider for a given
// MonthKey so navigating months / switching screens never re-runs the same
// Firestore query twice.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firestore_service.dart';
import '../widgets/common/month_calendar.dart' show MonthDayState;

// Identifies one user's one calendar month — the family key for
// monthActivityProvider below.
class MonthKey {
  final String uid;
  final int year;
  final int month;

  const MonthKey({required this.uid, required this.year, required this.month});

  @override
  bool operator ==(Object other) =>
      other is MonthKey &&
      other.uid == uid &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(uid, year, month);
}

// UI-ready result for one month: every day in the month gets an explicit
// MonthDayState (defaulting to `neither`, which also covers dates that
// predate dailyActivityLog's existence for this user — see
// getMonthActivity()'s doc comment in firestore_service.dart), plus the
// subset of streakDates that falls within this specific month.
class MonthActivityData {
  final Map<String, MonthDayState> dayStates;
  final Set<String> streakDates;

  const MonthActivityData({required this.dayStates, required this.streakDates});
}

final _firestoreService = FirestoreService();

// Cached per-uid, INDEPENDENT of month — deliberately its own provider,
// not folded into monthActivityProvider below. calculateStreakDates() does
// a full unbounded scan of the user's whole sessions + dailyActivityLog
// history (same cost calculateStreak() already pays elsewhere in the
// app), and the currently active streak is one global fact anchored at
// today, not scoped to whichever month is being viewed — a streak can
// span a month boundary. Keeping this as a separate family-by-uid-only
// provider means Riverpod caches one result per uid and reuses it across
// every month the user navigates to, instead of re-running the full scan
// on every prev/next tap.
final _streakDatesProvider = FutureProvider.family<Set<String>, String>((ref, uid) {
  return _firestoreService.calculateStreakDates(uid);
});

// The month-calendar widget's single data source. Combines the
// month-bounded getMonthActivity() read with the separately-cached global
// streak-dates fetch above, intersecting streakDates down to just this
// month's own dates for the widget's fire-icon overlay.
final monthActivityProvider =
    FutureProvider.family<MonthActivityData, MonthKey>((ref, key) async {
  final activity =
      await _firestoreService.getMonthActivity(key.uid, key.year, key.month);
  final streakDates = await ref.watch(_streakDatesProvider(key.uid).future);

  final workoutDates = activity['workoutDates'] ?? const <String>{};
  final protectedRestDates = activity['protectedRestDates'] ?? const <String>{};

  final daysInMonth = DateTime(key.year, key.month + 1, 0).day;
  final dayStates = <String, MonthDayState>{};
  for (int d = 1; d <= daysInMonth; d++) {
    final dateKey =
        '${key.year}-${key.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
    if (workoutDates.contains(dateKey)) {
      dayStates[dateKey] = MonthDayState.workout;
    } else if (protectedRestDates.contains(dateKey)) {
      dayStates[dateKey] = MonthDayState.protectedRest;
    } else {
      dayStates[dateKey] = MonthDayState.neither;
    }
  }

  final monthStreakDates =
      streakDates.where((d) => dayStates.containsKey(d)).toSet();

  return MonthActivityData(dayStates: dayStates, streakDates: monthStreakDates);
});
