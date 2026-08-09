// lib/screens/plans/plan_schedule_screen.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/compress_utils.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/session_resume_prompt.dart';

class PlanScheduleScreen extends StatefulWidget {
  const PlanScheduleScreen({super.key});

  @override
  State<PlanScheduleScreen> createState() => _PlanScheduleScreenState();
}

class _PlanScheduleScreenState extends State<PlanScheduleScreen> {
  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _sessions = [];

  String? _uid;
  String? _planId;
  int _currentDayIndex = 1;
  bool _breakModeActive = false;
  String? _breakStartDate;
  String? _breakEndDate;
  int _breakDays = 3;
  // Anchor for home_screen.dart's _checkMissedSession() 24h grace period —
  // loaded here (not just written) so _endBreak() can shift it forward by
  // the break's duration when the user ends a break early. See
  // _breakShiftedStart() below for why.
  Timestamp? _trackedPlanStartedAt;
  // Lifetime per-day completion ledger — captured from the same
  // getPlanProgress() call _init() already makes for _currentDayIndex,
  // just reading one more field off the same result. Used by _statusOf()
  // for a real, persistent completed check instead of inferring it from
  // index position (see that method's own comment).
  Set<int> _completedDayIndices = {};

  int _selectedWeekIdx = 0;
  bool _isLoading = true;
  // Keyed by dayIndex. See core/compress_utils.dart's CompressedDayData
  // for the shape and parseCompressedDays() for how this is built from
  // whatever Firestore actually has (new map format, legacy boolean-array
  // format, or nothing at all) — shared with gym_session_screen.dart/
  // home_screen.dart/plan_detail_screen.dart so all 4 screens can never
  // disagree on what "compressed" means for a given day again.
  Map<int, CompressedDayData> _compressedDays = {};

  final _fs = FirestoreService();
  final _auth = AuthService();
  StreamSubscription<Map<String, dynamic>?>? _planStreamSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _planStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra == null) {
      setState(() => _isLoading = false);
      return;
    }

    final planId = extra['id'] as String?;
    // Seed from extra so the screen renders immediately while the stream loads.
    _plan = extra;
    _sessions = (extra['sessions'] as List<dynamic>?)
            ?.map((s) => Map<String, dynamic>.from(s as Map))
            .toList() ??
        [];

    // Real-time subscription: auto-refreshes when the plan doc changes in
    // Firestore without relying on initState re-running (widget stays alive
    // in GoRouter's stack).
    if (planId != null && planId.isNotEmpty) {
      _planStreamSub = _fs.getPlanStream(planId).listen((data) {
        if (data != null && mounted) {
          setState(() {
            _plan = data;
            _sessions = (data['sessions'] as List<dynamic>?)
                    ?.map((s) => Map<String, dynamic>.from(s as Map))
                    .toList() ??
                [];
            if (_sessions.isNotEmpty) {
              _selectedWeekIdx =
                  ((_currentDayIndex - 1) ~/ 7).clamp(0, _totalWeeks - 1);
            }
          });
        }
      });
    }

    _uid = _auth.getCurrentUser()?.uid;
    _planId = planId;
    if (_uid != null && planId != null && planId.isNotEmpty) {
      try {
        final progress = await _fs.getPlanProgress(_uid!, planId);
        if (!mounted) return;

        final rawBreakStart = progress?['breakStartDate'] as String?;
        final rawBreakEnd = progress?['breakEndDate'] as String?;
        final today = DateTime.now().toString().substring(0, 10);
        bool breakActive = progress?['breakModeActive'] as bool? ?? false;
        Timestamp? startedAt =
            progress?['trackedPlanStartedAt'] as Timestamp?;

        if (breakActive && rawBreakEnd != null && rawBreakEnd.compareTo(today) < 0) {
          breakActive = false;
          // Shift by the break's originally-scheduled length (start →
          // scheduled end), not by however long it's been since then —
          // extra idle time after the break was due to end is real
          // elapsed time again, not break time, even though this auto-
          // expiry check only runs lazily whenever this screen next loads.
          final shifted = _breakShiftedStart(startedAt, rawBreakStart, rawBreakEnd);
          final updates = <String, dynamic>{
            'breakModeActive': false,
            'breakEndDate': null,
            'breakStartDate': null,
            'breakDays': null,
          };
          if (shifted != null) {
            updates['trackedPlanStartedAt'] = shifted;
            startedAt = shifted;
          }
          await _fs.updatePlanProgress(_uid!, planId, updates);
          await _resumeWorkoutReminder();
        }

        final currentDay = (progress?['currentDayIndex'] as num?)?.toInt() ?? 1;

        final loadedCompressedDays =
            parseCompressedDays(progress?['compressedDays'], _sessions);

        final rawCompletedDayIndices = progress?['completedDayIndices'];
        Set<int> loadedCompletedDayIndices = {};
        if (rawCompletedDayIndices is List) {
          loadedCompletedDayIndices =
              rawCompletedDayIndices.map((d) => (d as num).toInt()).toSet();
        }

        setState(() {
          _currentDayIndex = currentDay;
          _breakModeActive = breakActive;
          _breakStartDate = rawBreakStart;
          _breakEndDate = rawBreakEnd;
          _trackedPlanStartedAt = startedAt;
          _compressedDays = loadedCompressedDays;
          _completedDayIndices = loadedCompletedDayIndices;
          _isLoading = false;
          if (_sessions.isNotEmpty) {
            _selectedWeekIdx = ((currentDay - 1) ~/ 7).clamp(0, _totalWeeks - 1);
          }
        });
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  int get _totalWeeks => (_sessions.length / 7).ceil().clamp(1, 999);

  List<Map<String, dynamic>> get _currentWeekSessions {
    final start = _selectedWeekIdx * 7;
    final end = (start + 7).clamp(0, _sessions.length);
    if (start >= _sessions.length) return [];
    return _sessions.sublist(start, end);
  }

  int _dayIndexOf(int weekIdx, int posInWeek) => weekIdx * 7 + posInWeek + 1;

  // dayIndex < _currentDayIndex used to be the only way this reported
  // 'completed' — a pure index-position inference, wrong whenever a day
  // was skipped rather than genuinely done (it would still show
  // "completed" for anything before the current day). Now checks the real
  // lifetime completedDayIndices ledger (see markSessionComplete()) instead
  // — this also naturally covers the "today, already done" case a separate
  // lastCompletedDate check used to be needed for: markSessionComplete()
  // adds to the ledger in the same write it sets lastCompletedDate, so a
  // day that's genuinely just been completed today is already in
  // _completedDayIndices by the time this runs, with no extra check
  // required. The ledger check runs first, ahead of the 'today' check, so
  // an already-completed "today" still correctly resolves to 'completed'
  // rather than 'today'.
  String _statusOf(int dayIndex, bool isRest) {
    if (isRest) return 'rest';
    if (_completedDayIndices.contains(dayIndex)) return 'completed';
    if (dayIndex == _currentDayIndex) return 'today';
    return 'upcoming';
  }

  // Wired to _ScheduleDayCard's Start Session button instead of that card
  // navigating straight to Routes.gymSession — routes through the shared
  // discovery-and-prompt step (see widgets/session_resume_prompt.dart)
  // first, so an already-abandoned in-progress session for this
  // planId+dayIndex offers Resume/Start Over instead of silently being
  // orphaned by a brand-new one. This button only ever renders for
  // status == 'today' (see _buildDayCards' showTodayActions), and
  // _statusOf() above already excludes an already-completed "today" from
  // that status, so no separate completed check is needed here.
  Future<void> _handleStartSession(int dayIndex) async {
    final uid = _uid;
    final planId = _planId;
    if (uid == null || planId == null || planId.isEmpty) return;
    await startOrResumeTrackedSession(
      context: context,
      uid: uid,
      planId: planId,
      dayIndex: dayIndex,
      startFresh: () async => context.push(Routes.gymSession),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: WW.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Shifts trackedPlanStartedAt forward by the number of days between
  // [breakStartStr] and [breakThroughStr], so the days a plan spent on a
  // break don't count toward home_screen.dart's _checkMissedSession() 24h
  // grace period — a true pause rather than merely hiding the banner while
  // breakModeActive is true (which alone wouldn't help once the break
  // ends: by then the clock would already read >=24h and the banner could
  // fire immediately on return). Written back to the stored timestamp
  // itself, so it stacks correctly across repeated breaks. Returns null if
  // there's nothing to shift (no stored start yet, no break-start date, or
  // an unparseable/non-positive range).
  Timestamp? _breakShiftedStart(
      Timestamp? current, String? breakStartStr, String breakThroughStr) {
    if (current == null || breakStartStr == null) return null;
    try {
      final breakStart = DateTime.parse(breakStartStr);
      final breakThrough = DateTime.parse(breakThroughStr);
      final days = breakThrough.difference(breakStart).inDays;
      if (days <= 0) return null;
      return Timestamp.fromDate(current.toDate().add(Duration(days: days)));
    } catch (_) {
      return null;
    }
  }

  // Re-schedules the daily workout reminder using the user's actual saved
  // time (never a hardcoded default) — reads reminderHour/reminderMinute/
  // workoutReminders straight off the user profile rather than assuming
  // settings_screen.dart's widget state, since this screen has no access
  // to that. Respects workoutReminders == false (the user's own opt-out)
  // by not rescheduling at all, matching _savePrefs()'s own gating in
  // settings_screen.dart — resuming a break must not silently re-enable a
  // reminder the user deliberately turned off.
  //
  // Safe to call more than once in a row (e.g. if this screen's own
  // auto-expiry check and home_screen.dart's races against the same
  // expired break): scheduleDailyWorkoutReminder() already cancels any
  // existing scheduled notification with the same id before scheduling
  // the new one, so repeat calls just re-cancel-and-reschedule the same
  // single reminder rather than stacking duplicates.
  Future<void> _resumeWorkoutReminder() async {
    if (_uid == null) return;
    try {
      final profile = await _fs.getUserProfile(_uid!);
      final workoutRemindersOn =
          profile?['workoutReminders'] as bool? ?? true;
      if (!workoutRemindersOn) return;
      final hour = (profile?['reminderHour'] as num?)?.toInt() ?? 7;
      final minute = (profile?['reminderMinute'] as num?)?.toInt() ?? 0;
      await NotificationService()
          .scheduleDailyWorkoutReminder(TimeOfDay(hour: hour, minute: minute));
    } catch (_) {}
  }

  Future<void> _endBreak() async {
    if (_uid == null || _planId == null) return;
    try {
      final today = DateTime.now().toString().substring(0, 10);
      final shifted =
          _breakShiftedStart(_trackedPlanStartedAt, _breakStartDate, today);
      final updates = <String, dynamic>{
        'breakModeActive': false,
        'breakEndDate': null,
        'breakStartDate': null,
        'breakDays': null,
      };
      if (shifted != null) updates['trackedPlanStartedAt'] = shifted;
      await _fs.updatePlanProgress(_uid!, _planId!, updates);
      await _resumeWorkoutReminder();
      if (mounted) {
        setState(() {
          _breakModeActive = false;
          _breakEndDate = null;
          _breakStartDate = null;
          if (shifted != null) _trackedPlanStartedAt = shifted;
        });
        _snack('Break ended. Welcome back! 💪');
      }
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _startBreak() async {
    if (_uid == null || _planId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Take a $_breakDays day break?',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: WW.text),
        ),
        content: Text(
          'Your plan will resume automatically after $_breakDays days.',
          style: const TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Start Break',
              style: TextStyle(color: WW.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final today = DateTime.now();
      final startStr = today.toString().substring(0, 10);
      final endStr = today.add(Duration(days: _breakDays)).toString().substring(0, 10);
      await _fs.updatePlanProgress(_uid!, _planId!, {
        'breakModeActive': true,
        'breakStartDate': startStr,
        'breakEndDate': endStr,
        'breakDays': _breakDays,
      });
      await NotificationService().cancelWorkoutReminder();
      if (!mounted) return;
      setState(() {
        _breakModeActive = true;
        _breakStartDate = startStr;
        _breakEndDate = endStr;
      });
      _snack('Break mode activated! 🌟');
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _stopTracking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Stop tracking this plan?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: WW.text),
        ),
        content: const Text(
          'Your previous sessions will be kept, but this plan will no longer be tracked.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Stop Tracking',
              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_uid == null) return;
    try {
      await _fs.updateUserProfile(_uid!, {
        'trackedPlanId': '',
        'trackedPlanName': '',
      });
      if (mounted) context.pop();
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    }
  }

  void _showCompressSheet(Map<String, dynamic> session, int dayIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CompressSheet(
        session: session,
        onConfirm: (removedExercises, cardioOverrides) async {
          Navigator.of(ctx).pop();
          if (_uid != null && _planId != null) {
            setState(() {
              _compressedDays = {
                ..._compressedDays,
                dayIndex: CompressedDayData(
                  removedExercises: removedExercises,
                  cardioOverrides: cardioOverrides,
                ),
              };
            });
            await _fs.updatePlanProgress(_uid!, _planId!, {
              'compressedDays': serializeCompressedDays(_compressedDays),
            });
            await _deleteStaleInProgressSession(dayIndex);
          }
          if (mounted) _snack('Session compressed! ⚡');
        },
      ),
    );
  }

  // Deletes any existing inProgressSessions doc for this exact day, if one
  // exists — called after a compression change or a restore. Without this,
  // _hydrateFromInProgressSession() in gym_session_screen.dart would keep
  // resuming a frozen blocks[] snapshot taken whenever that doc was first
  // created (as early as the user merely opening the session once, even if
  // they backed out immediately), silently ignoring any compression change
  // made afterward — the exact bug this fixes. findInProgressSessionRunId()
  // returning null (nothing to delete) is the common, expected case, not an
  // error — deleteInProgressSession() is only called when a real doc was
  // found. Best-effort: a failure here isn't surfaced to the user, since
  // compressedDays itself was already saved successfully by the time this
  // runs — matching this method's own existing fail-soft convention
  // elsewhere in this file (e.g. _restoreDaySession's try/catch below).
  Future<void> _deleteStaleInProgressSession(int dayIndex) async {
    if (_uid == null || _planId == null) return;
    try {
      final existingSessionRunId =
          await _fs.findInProgressSessionRunId(_uid!, _planId!, dayIndex);
      if (existingSessionRunId != null) {
        await _fs.deleteInProgressSession(_uid!, existingSessionRunId);
      }
    } catch (_) {}
  }

  // Just clears this day's entry from the map — compression has always
  // been a display-time filter, never a mutation to the plan's actual
  // stored exercise list (see _showCompressSheet's onConfirm above, which
  // never touches session['exercises']), so restoring is still trivially
  // correct: nothing was ever removed from storage to restore. Also
  // deletes any stale in-progress session doc for this day (see
  // _deleteStaleInProgressSession's own doc comment) — a resume after
  // restoring should see the plan's original, uncompressed exercises, not
  // whatever was frozen into blocks[] while the day was still compressed.
  Future<void> _restoreDaySession(int dayIndex) async {
    if (_uid == null || _planId == null) return;
    setState(() => _compressedDays.remove(dayIndex));
    try {
      await _fs.updatePlanProgress(_uid!, _planId!, {
        'compressedDays': serializeCompressedDays(_compressedDays),
      });
      await _deleteStaleInProgressSession(dayIndex);
      if (mounted) _snack('Session restored to full workout');
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    }
  }

  // Delegates the actual field reset to FirestoreService().resetPlanProgress()
  // — shared with plan_detail_screen.dart's own Restart Program action —
  // rather than listing the fields here, so the two screens can't drift
  // out of sync on what "restart" actually resets.
  Future<void> _restartPlan() async {
    if (_uid == null || _planId == null) return;
    await _fs.resetPlanProgress(_uid!, _planId!);
    if (!mounted) return;
    setState(() {
      _currentDayIndex = 1;
      _compressedDays = {};
      _completedDayIndices = {};
      _selectedWeekIdx = 0;
    });
    _snack('Plan restarted from Day 1.');
  }

  Widget _buildRestartButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: WW.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Restart Plan?',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: WW.text),
              ),
              content: const Text(
                'This will reset your progress back to Day 1. Your session history will not be deleted.',
                style: TextStyle(fontSize: 14, color: WW.textSec),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel',
                      style: TextStyle(color: WW.textSec)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Restart',
                    style: TextStyle(
                        color: WW.primary,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          );
          if (confirmed == true) await _restartPlan();
        },
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: WW.primary, width: 1.5),
          foregroundColor: WW.primary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13)),
        ),
        child: const Text(
          'Restart from Day 1',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WW.primary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planName = _plan?['name'] as String? ?? 'Plan Schedule';

    return Scaffold(
      backgroundColor: WW.bg,
      body: Column(
        children: [
          _buildTopBar(planName),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: WW.primary)),
            )
          else
            Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildTopBar(String planName) {
    return Container(
      color: WW.card,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 16,
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: WW.elevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Icon(Icons.chevron_left_rounded, color: WW.textSec, size: 20),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 60),
                    child: Text(
                      planName,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: WW.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5, color: WW.border),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProgressCard(),
          const SizedBox(height: 14),
          _buildWeekSelector(),
          const SizedBox(height: 12),
          ..._buildDayCards(),
          const SizedBox(height: 8),
          _buildBreakModeCard(),
          const SizedBox(height: 16),
          _buildRestartButton(),
          const SizedBox(height: 12),
          _buildStopTrackingButton(),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final planName = _plan?['name'] as String? ?? 'Workout Plan';
    final totalSessions = _sessions.length;
    final daysPerWeek = (_plan?['daysPerWeek'] as num?)?.toInt() ?? 0;
    final level = _plan?['level'] as String? ?? '';
    final type = _plan?['type'] as String? ?? '';

    final progress = totalSessions > 0 ? (_currentDayIndex - 1) / totalSessions : 0.0;
    final percent = (progress * 100).round();
    final currentWeekNum = ((_currentDayIndex - 1) ~/ 7) + 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            planName,
            style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: WW.primaryDark,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Day $_currentDayIndex of $totalSessions · Week $currentWeekNum of $_totalWeeks',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WW.text),
              ),
              Text(
                '$percent%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WW.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PlanProgressBar(progress: progress),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (daysPerWeek > 0) _InfoChip('$daysPerWeek days/wk'),
              if (level.isNotEmpty) _InfoChip(level),
              if (type.isNotEmpty) _InfoChip(type),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSelector() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _totalWeeks,
        separatorBuilder: (ctx2, idx2) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final active = i == _selectedWeekIdx;
          return GestureDetector(
            onTap: () => setState(() => _selectedWeekIdx = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? WW.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? WW.primary : WW.border, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                'Week ${i + 1}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : WW.textSec,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildDayCards() {
    final weekSessions = _currentWeekSessions;
    return List.generate(weekSessions.length, (i) {
      final session = weekSessions[i];
      final dayIndex = _dayIndexOf(_selectedWeekIdx, i);
      final isRest = session['isRestDay'] == true;
      final status = _statusOf(dayIndex, isRest);
      final isCompressed = _compressedDays.containsKey(dayIndex);

      final exercises = (session['exercises'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];
      final hasAccessory = exercises.any((e) => e['tag'] == 'Accessory');

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _ScheduleDayCard(
          session: session,
          dayIndex: dayIndex,
          status: status,
          compressedData: _compressedDays[dayIndex],
          showTodayActions: status == 'today',
          showCompress: hasAccessory && !isCompressed,
          onStartSession: () => _handleStartSession(dayIndex),
          onCompress: () => _showCompressSheet(session, dayIndex),
          onRestore: () => _restoreDaySession(dayIndex),
        ),
      );
    });
  }

  // Always-visible break mode card — shows active state or day picker.
  Widget _buildBreakModeCard() {
    if (_breakModeActive) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WW.elevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WW.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('☕', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  'Break active until ${_breakEndDate ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _endBreak,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: WW.primary),
                  foregroundColor: WW.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('End Break Early'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WW.border, width: 1),
        boxShadow: WW.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('☕', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text(
                'Need a Break?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pause your plan and notifications for a few days.',
            style: TextStyle(fontSize: 13, color: WW.textSec),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [1, 2, 3, 5, 7, 14].map((d) {
                final selected = _breakDays == d;
                return GestureDetector(
                  onTap: () => setState(() => _breakDays = d),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? WW.primary : WW.elevated,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$d ${d == 1 ? "day" : "days"}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : WW.text,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: WW.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _startBreak,
              child: Text('Start $_breakDays Day Break'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopTrackingButton() {
    return Center(
      child: GestureDetector(
        onTap: _stopTracking,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Stop Tracking This Plan',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEF4444),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Plan progress bar ─────────────────────────────────────────────────────────
// Public (not the usual leading-underscore private convention for a
// single-file widget) so plans_screen.dart's Current Plan card can reuse this
// exact bar instead of duplicating a second copy of it — the only two places
// in the app that show plan-progress as a bar.

class PlanProgressBar extends StatelessWidget {
  final double progress;
  final double height;

  const PlanProgressBar({
    super.key,
    required this.progress,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        backgroundColor: WW.elevated,
        valueColor: const AlwaysStoppedAnimation<Color>(WW.primary),
        minHeight: height,
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: WW.textSec),
      ),
    );
  }
}

// ── Schedule day card ─────────────────────────────────────────────────────────
// Always shows full exercise list (no collapse). Filters to Primary when compressed.

class _ScheduleDayCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final int dayIndex;
  final String status;
  // Null means this day has no compression entry at all — replaces the
  // old plain isCompressed bool so this widget can actually apply the
  // real per-exercise removals/cardio overrides (via
  // core/compress_utils.dart's applyCompression()) instead of the old
  // blanket tag == 'Primary' filter below.
  final CompressedDayData? compressedData;
  final bool showTodayActions;
  final bool showCompress;
  final VoidCallback? onStartSession;
  final VoidCallback? onCompress;
  final VoidCallback? onRestore;

  const _ScheduleDayCard({
    required this.session,
    required this.dayIndex,
    required this.status,
    required this.compressedData,
    required this.showTodayActions,
    required this.showCompress,
    required this.onStartSession,
    required this.onCompress,
    required this.onRestore,
  });

  bool get isCompressed => compressedData != null;

  Color get _stripColor {
    switch (status) {
      case 'completed':
        return WW.teal;
      case 'today':
        return isCompressed ? WW.lavender : WW.primary;
      case 'rest':
        return const Color(0xFFE8EAF8);
      default:
        return WW.border;
    }
  }

  // Same Run/Walk/Cycle icon mapping already used by cardio_setup_screen.dart's
  // _kActivities and activity_detail_screen.dart's _headerIcon — reused here
  // (duplicated, not imported, since those are private to their own files)
  // rather than inventing a new mapping. Run/unrecognized falls back to the
  // running icon, matching both of those files' own default.
  IconData _cardioIcon(String activity) {
    switch (activity) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRest = status == 'rest';
    final dayLabel = session['day'] as String? ?? 'Day $dayIndex';
    final sessionName = session['name'] as String? ?? '';
    // estimatedMinutes is now always computed and stored at save time (both
    // admin and custom/coach plans) — 0 here is a defensive floor only, not
    // a guessed placeholder. Kept consistent with the same fallback used in
    // plan_detail_screen.dart/home_screen.dart.
    final baseEstimatedMinutes =
        (session['estimatedMinutes'] as num?)?.toInt() ?? 0;

    final allExercises = (session['exercises'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    // Applies this day's real per-exercise removals/cardio overrides —
    // replaces the old blanket tag == 'Primary' filter (which not only
    // disagreed with gym_session_screen.dart's tag != 'Accessory' but,
    // more importantly, never reflected the user's actual checkbox/cardio
    // choices from the Compress sheet at all).
    final displayExercises = applyCompression(allExercises, compressedData);
    final estimatedMinutes = estimatedMinutesAfterCompression(
        baseEstimatedMinutes, compressedData, allExercises);

    return Container(
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WW.border, width: 0.5),
        boxShadow: WW.shadow,
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: _stripColor),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dayLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isRest ? WW.textSec : WW.text,
                                ),
                              ),
                              if (!isRest && sessionName.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  sessionName,
                                  style: const TextStyle(fontSize: 12, color: WW.textSec),
                                ),
                              ],
                              if (isRest) ...[
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: WW.chipBg,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Icon(
                                        Icons.nightlight_round,
                                        size: 11,
                                        color: WW.border,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'Rest Day',
                                      style: TextStyle(fontSize: 12, color: WW.textSec),
                                    ),
                                  ],
                                ),
                              ],
                              // FIX 2: compressed chip + restore button in header
                              if (isCompressed && !isRest) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: WW.lavenderBg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        '⚡ Compressed',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: WW.lavender,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: onRestore,
                                      child: const Text(
                                        '↩ Restore',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: WW.textSec,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _StatusBadge(status),
                            if (!isRest && estimatedMinutes > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${estimatedMinutes}min',
                                style: const TextStyle(fontSize: 11, color: WW.textSec),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // FIX 2: always show full exercise list (no collapse/preview).
                  if (!isRest && displayExercises.isNotEmpty) ...[
                    const Divider(height: 1, color: WW.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Column(
                        children: List.generate(displayExercises.length, (i) {
                          final ex = displayExercises[i];
                          final isCardio = ex['isCardio'] == true;
                          final name = isCardio
                              ? (ex['cardioActivity'] as String? ?? 'Cardio')
                              : (ex['name'] as String? ?? 'Exercise');
                          final sets = (ex['sets'] is List)
                              ? (ex['sets'] as List).length
                              : (ex['sets'] as num?)?.toInt() ?? 3;
                          final reps = (ex['reps'] as num?)?.toInt() ?? 0;
                          final cardioMinutes =
                              (ex['cardioMinutes'] as num?)?.toInt();
                          final tag = ex['tag'] as String? ?? '';
                          final isAccessory = tag == 'Accessory';

                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              border: i < displayExercises.length - 1
                                  ? const Border(
                                      bottom: BorderSide(color: WW.border, width: 0.5))
                                  : null,
                            ),
                            child: Row(
                              children: [
                                isCardio
                                    ? Icon(_cardioIcon(name), size: 12, color: WW.primary)
                                    : Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: WW.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: WW.text,
                                    ),
                                  ),
                                ),
                                Text(
                                  isCardio
                                      ? (cardioMinutes != null && cardioMinutes > 0
                                          ? '$cardioMinutes min'
                                          : '')
                                      : '$sets×$reps',
                                  style: const TextStyle(fontSize: 11, color: WW.textSec),
                                ),
                                if (tag.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isAccessory ? WW.elevated : WW.chipBg,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: isAccessory ? WW.textSec : WW.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],

                  // Today's actions: Start Session + Compress button (when not compressed)
                  if (showTodayActions) ...[
                    const Divider(height: 1, color: WW.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: onStartSession,
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: WW.primary,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: WW.primary.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'Start Session',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Compress button: only for non-compressed today cards
                          if (showCompress) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: onCompress,
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: WW.lavender, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.bolt_rounded,
                                            color: WW.lavender, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'Compress',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: WW.lavender,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'completed':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: WW.tealBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, color: WW.teal, size: 11),
              SizedBox(width: 3),
              Text(
                'Completed',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: WW.teal),
              ),
            ],
          ),
        );
      case 'today':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: WW.chipBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'TODAY',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: WW.primary),
          ),
        );
      case 'rest':
        return const SizedBox.shrink();
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: WW.elevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Upcoming',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: WW.textSec),
          ),
        );
    }
  }
}

// ── Compress bottom sheet ─────────────────────────────────────────────────────
// Rework of the original StatelessWidget version: now stateful so the user
// can actually adjust the auto-identified candidates (checkboxes on
// accessory-tagged strength exercises, default all-checked — "auto-identify
// candidates, user confirms/adjusts") and shorten cardio blocks (a stepper
// on cardioMinutes, floored at 5) with a live-updating time-saved estimate,
// instead of the previous fully-automatic, non-interactive version.
//
// Cardio blocks (isCardio: true) get their own section — the original
// version had no cardio handling at all and would have rendered them in
// the "KEEPING" list using sets/reps fields a cardio block doesn't
// actually have at the top level (reps lives nested in sets[0] on a real
// cardio block), producing a nonsensical "1×0" row. They're never
// eligible for removal here, only duration reduction — accidentally
// stripping a whole cardio block isn't the intent of a "shorten my
// workout" action.
class _CompressSheet extends StatefulWidget {
  final Map<String, dynamic> session;
  final Future<void> Function(Set<int> removedExercises, Map<int, int> cardioOverrides)
      onConfirm;

  const _CompressSheet({required this.session, required this.onConfirm});

  @override
  State<_CompressSheet> createState() => _CompressSheetState();
}

class _CompressSheetState extends State<_CompressSheet> {
  // Suggested floor so a "shortened" cardio block never gets reduced to
  // something not worth doing at all.
  static const _kMinCardioMinutes = 5;
  static const _kCardioStepMinutes = 5;

  late final List<Map<String, dynamic>> _allExercises;
  late final List<int> _cardioIndices;
  late final List<int> _accessoryIndices;
  late final List<int> _primaryIndices;

  // Mutable selection state — starts with every accessory exercise
  // pre-checked for removal (the "auto-identify candidates" default) and
  // every cardio block at its original duration.
  late final Set<int> _selectedForRemoval;
  late final Map<int, int> _originalCardioMinutes;
  late final Map<int, int> _cardioMinutes;

  @override
  void initState() {
    super.initState();
    _allExercises = (widget.session['exercises'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    _cardioIndices = [];
    _accessoryIndices = [];
    _primaryIndices = [];
    for (var i = 0; i < _allExercises.length; i++) {
      final e = _allExercises[i];
      if (e['isCardio'] == true) {
        _cardioIndices.add(i);
      } else if (e['tag'] == 'Accessory') {
        _accessoryIndices.add(i);
      } else {
        _primaryIndices.add(i);
      }
    }

    _selectedForRemoval = _accessoryIndices.toSet();
    _originalCardioMinutes = {
      for (final i in _cardioIndices)
        i: (_allExercises[i]['cardioMinutes'] as num?)?.toInt() ?? 0,
    };
    _cardioMinutes = Map.of(_originalCardioMinutes);
  }

  // 4 min/removed exercise (same flat heuristic the original sheet used)
  // plus the real cardio minutes actually shaved off — live-updating as
  // the user toggles checkboxes or adjusts cardio duration, unlike the
  // original's fixed accessory.length * 4 that never reflected user choice.
  int get _savedMinutes {
    final fromRemoved = _selectedForRemoval.length * 4;
    final fromCardio = _cardioIndices.fold<int>(
        0, (total, i) => total + (_originalCardioMinutes[i]! - _cardioMinutes[i]!));
    return fromRemoved + fromCardio;
  }

  void _adjustCardio(int index, int delta) {
    setState(() {
      final original = _originalCardioMinutes[index]!;
      final current = _cardioMinutes[index]!;
      _cardioMinutes[index] =
          (current + delta).clamp(_kMinCardioMinutes, original);
    });
  }

  // Same Run/Walk/Cycle icon mapping the original _CompressSheet never had
  // (it never rendered cardio at all) — matches the convention already
  // used by _ScheduleDayCard._cardioIcon() elsewhere in this file.
  IconData _cardioIcon(String activity) {
    switch (activity) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: WW.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "Compress Today's Session",
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: WW.primaryDark,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close_rounded, color: WW.textSec, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              "Short on time? Uncheck anything you'd rather keep, or shorten your cardio below.",
              style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                if (_cardioIndices.isNotEmpty) ...[
                  const Text(
                    'CARDIO',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: WW.textSec, letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: WW.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WW.border, width: 0.5),
                    ),
                    child: Column(
                      children: List.generate(_cardioIndices.length, (i) {
                        final index = _cardioIndices[i];
                        final ex = _allExercises[index];
                        final activity = ex['cardioActivity'] as String? ?? 'Run';
                        final minutes = _cardioMinutes[index]!;
                        final atFloor = minutes <= _kMinCardioMinutes;
                        final atOriginal = minutes >= _originalCardioMinutes[index]!;
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: i < _cardioIndices.length - 1
                                ? const Border(
                                    bottom: BorderSide(color: WW.border, width: 0.5))
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(_cardioIcon(activity), size: 14, color: WW.teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(activity,
                                    style: const TextStyle(fontSize: 13, color: WW.text)),
                              ),
                              GestureDetector(
                                onTap: atFloor
                                    ? null
                                    : () => _adjustCardio(index, -_kCardioStepMinutes),
                                child: Icon(Icons.remove_circle_outline,
                                    size: 18, color: atFloor ? WW.border : WW.lavender),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text('$minutes min',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12, color: WW.textSec)),
                              ),
                              GestureDetector(
                                onTap: atOriginal
                                    ? null
                                    : () => _adjustCardio(index, _kCardioStepMinutes),
                                child: Icon(Icons.add_circle_outline,
                                    size: 18, color: atOriginal ? WW.border : WW.lavender),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_primaryIndices.isNotEmpty) ...[
                  const Text(
                    'KEEPING',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: WW.textSec, letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: WW.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WW.border, width: 0.5),
                    ),
                    child: Column(
                      children: List.generate(_primaryIndices.length, (i) {
                        final ex = _allExercises[_primaryIndices[i]];
                        final name = ex['name'] as String? ?? 'Exercise';
                        final sets = (ex['sets'] is List)
                            ? (ex['sets'] as List).length
                            : (ex['sets'] as num?)?.toInt() ?? 0;
                        final reps = (ex['reps'] as num?)?.toInt() ?? 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: i < _primaryIndices.length - 1
                                ? const Border(
                                    bottom: BorderSide(color: WW.border, width: 0.5))
                                : null,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_rounded, size: 14,
                                  color: Color(0xFF22C55E)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 13, color: WW.text),
                                ),
                              ),
                              Text(
                                '$sets×$reps',
                                style: const TextStyle(fontSize: 12, color: WW.textSec),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_accessoryIndices.isNotEmpty) ...[
                  const Text(
                    'ACCESSORY EXERCISES',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: WW.textSec, letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: WW.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WW.border, width: 0.5),
                    ),
                    child: Column(
                      children: List.generate(_accessoryIndices.length, (i) {
                        final index = _accessoryIndices[i];
                        final ex = _allExercises[index];
                        final name = ex['name'] as String? ?? 'Exercise';
                        final willRemove = _selectedForRemoval.contains(index);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            if (willRemove) {
                              _selectedForRemoval.remove(index);
                            } else {
                              _selectedForRemoval.add(index);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              border: i < _accessoryIndices.length - 1
                                  ? const Border(
                                      bottom: BorderSide(color: WW.border, width: 0.5))
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: willRemove,
                                  onChanged: (v) => setState(() {
                                    if (v ?? false) {
                                      _selectedForRemoval.add(index);
                                    } else {
                                      _selectedForRemoval.remove(index);
                                    }
                                  }),
                                  activeColor: const Color(0xFFEF4444),
                                ),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: willRemove ? const Color(0xFFEF4444) : WW.text,
                                      decoration:
                                          willRemove ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: willRemove
                                        ? const Color(0xFFFEE2E2)
                                        : WW.elevated,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Accessory',
                                    style: TextStyle(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      color: willRemove
                                          ? const Color(0xFFEF4444)
                                          : WW.textSec,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Color(0xFF22C55E), size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Saves approximately $_savedMinutes minutes',
                        style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: WW.primary, width: 1.5),
                          ),
                          child: const Center(
                            child: Text(
                              'Keep Original',
                              style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: WW.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          final overrides = <int, int>{
                            for (final i in _cardioIndices)
                              if (_cardioMinutes[i] != _originalCardioMinutes[i])
                                i: _cardioMinutes[i]!,
                          };
                          widget.onConfirm(_selectedForRemoval, overrides);
                        },
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: WW.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'Compress (save ~${_savedMinutes}min)',
                              style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
