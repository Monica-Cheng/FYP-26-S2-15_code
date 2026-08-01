// lib/widgets/common/month_calendar.dart
// Shared full-month calendar grid — reused by Home's week-strip drill-down
// modal and Progress > Charts (see monthActivityProvider in
// lib/providers/month_activity_provider.dart for where the data behind
// dayStates/streakDates comes from). Pure/stateless: this widget only
// renders whatever state it's given and reports taps back via callbacks —
// it does no Firestore reads or provider watching itself, matching
// AGENT.md's "never call Firestore directly from a widget" and keeping
// this reusable across both call sites without duplicating fetch logic.
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

// A day either had a real completed workout, was a scheduled rest day that
// streak logic protected (see calculateStreakDates()'s doc comment in
// firestore_service.dart), or neither — which also covers dates that
// predate dailyActivityLog's existence for this user; those simply have no
// entry in dayStates and render as `neither`, no separate "unknown" state
// needed (see monthActivityProvider — it fills every day in the month with
// a default of `neither` before overlaying whatever data was found).
enum MonthDayState { workout, protectedRest, neither }

class MonthCalendar extends StatelessWidget {
  // Only year/month are used — day/time-of-day on this DateTime are ignored.
  final DateTime month;
  final Map<String, MonthDayState> dayStates;
  final Set<String> streakDates;
  final ValueChanged<DateTime>? onMonthChanged;
  final ValueChanged<DateTime>? onDayTap;

  const MonthCalendar({
    super.key,
    required this.month,
    required this.dayStates,
    this.streakDates = const {},
    this.onMonthChanged,
    this.onDayTap,
  });

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Leading blanks so day 1 lands under the correct weekday column —
    // weekday is 1=Mon..7=Sun, and the grid is Mon-first (same convention
    // as home_screen.dart's _WeekCalendar/_DayCell), so 0..6 blanks.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          Row(
            children: _weekLabels
                .map((l) => Expanded(
                      child: Center(
                        child: Text(
                          l,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WW.textSec,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
            ),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final dayNum = index - leadingBlanks + 1;
              final day = DateTime(firstOfMonth.year, firstOfMonth.month, dayNum);
              final key = _dateKey(day);
              final isToday = day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;
              return _MonthDayCell(
                dayNum: dayNum,
                state: dayStates[key] ?? MonthDayState.neither,
                isToday: isToday,
                isStreak: streakDates.contains(key),
                onTap: onDayTap == null ? null : () => onDayTap!(day),
              );
            },
          ),
          const SizedBox(height: 14),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: onMonthChanged == null
              ? null
              : () => onMonthChanged!(DateTime(month.year, month.month - 1, 1)),
          child: Icon(Icons.chevron_left_rounded,
              color: onMonthChanged == null ? WW.border : WW.textSec, size: 26),
        ),
        Expanded(
          child: Text(
            '${_monthNames[month.month - 1]} ${month.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
            ),
          ),
        ),
        GestureDetector(
          onTap: onMonthChanged == null
              ? null
              : () => onMonthChanged!(DateTime(month.year, month.month + 1, 1)),
          child: Icon(Icons.chevron_right_rounded,
              color: onMonthChanged == null ? WW.border : WW.textSec, size: 26),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _legendDot(WW.teal, 'Workout'),
        const SizedBox(width: 14),
        _legendDot(WW.lavender, 'Rest day'),
        const Spacer(),
        const Icon(Icons.local_fire_department_rounded, color: WW.teal, size: 13),
        const SizedBox(width: 4),
        const Text(
          'Streak',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: WW.textSec),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: WW.textSec),
        ),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  final int dayNum;
  final MonthDayState state;
  final bool isToday;
  final bool isStreak;
  final VoidCallback? onTap;

  const _MonthDayCell({
    required this.dayNum,
    required this.state,
    required this.isToday,
    required this.isStreak,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Border? border;

    // Precedence mirrors _DayCell's existing one in home_screen.dart
    // (completed > today > default), just with protectedRest inserted
    // between workout and today.
    if (state == MonthDayState.workout) {
      bgColor = WW.teal;
      textColor = Colors.white;
    } else if (state == MonthDayState.protectedRest) {
      bgColor = WW.lavender;
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = WW.chipBg;
      textColor = WW.primary;
      border = Border.all(color: WW.primary, width: 1.5);
    } else {
      bgColor = Colors.transparent;
      textColor = WW.textSec;
      border = Border.all(color: WW.border, width: 1);
    }

    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle, border: border),
              child: Center(
                child: Text(
                  '$dayNum',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
                ),
              ),
            ),
            if (isStreak)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(color: WW.card, shape: BoxShape.circle),
                  child: const Icon(Icons.local_fire_department_rounded,
                      color: WW.teal, size: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
