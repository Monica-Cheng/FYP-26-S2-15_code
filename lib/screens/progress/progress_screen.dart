// lib/screens/progress/progress_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../providers/month_activity_provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common/month_calendar.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────

class ProgressScreen extends StatefulWidget {
  // Defaults to true so this compiles/behaves exactly as before for any
  // call site that doesn't pass it — the real signal comes from MainShell
  // (home_screen.dart) passing `_selectedIndex == <progress tab index>`,
  // which this screen can't observe on its own since it lives inside an
  // IndexedStack (see didUpdateWidget() below — same mechanism
  // coach_screen.dart's CoachScreen uses for its own consent banner).
  const ProgressScreen({super.key, this.isVisible = true});

  final bool isVisible;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int _subtab = 0;
  int _timeFilter = 0;
  int _activityFilter = 0;

  // Same fixed abbreviation set _monthNames (further below) already
  // defines for the weight chart — kept as its own copy here rather than
  // reordering declarations, since Dart class members are visible
  // throughout the class regardless of declaration order; duplicating a
  // 7-entry weekday list is cheaper than restructuring for one shared
  // constant. Index via DateTime.weekday - 1 (1=Monday..7=Sunday).
  static const List<String> _weekdayAbbrevs = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  // _timeFilter's three windows are now rolling (last 7/30/365 days
  // ending today — see _loadChartData()'s own comment for why), not
  // calendar week/month/year. Bucket labels must match: the OLD fixed
  // 'Mon'..'Sun' assumed the 7-day window was always literally Monday
  // through Sunday, which is only true once every 7 days now — WRONG the
  // other 6 days (a Wednesday-anchored week would show today at bucket 6
  // labeled 'Sun'). Same problem for the 12-bucket Year labels: a fixed
  // 'Jan'..'Dec' assumed the window always started in January, which a
  // 365-day rolling window essentially never does. Both are now derived
  // from the actual rolling startDate. 'Wk 1'..'Wk 4' for This Month is
  // left as-is — those never claimed to be specific calendar weeks, so
  // they're not factually wrong for a rolling window the way named
  // weekdays/months are.
  List<String> get _chartLabels {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_timeFilter == 0) {
      final start = today.subtract(const Duration(days: 6));
      return List.generate(
        7,
        (i) => _weekdayAbbrevs[start.add(Duration(days: i)).weekday - 1],
      );
    } else if (_timeFilter == 1) {
      return ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'];
    } else {
      final start = today.subtract(const Duration(days: 364));
      return List.generate(
        12,
        (i) => _monthNames[(start.month - 1 + i) % 12],
      );
    }
  }

  int get _bucketCount {
    if (_timeFilter == 0) return 7;
    if (_timeFilter == 1) return 4;
    return 12;
  }

  List<Map<String, dynamic>> _sessions = [];
  bool _sessionsLoading = true;
  // Pagination state for the Activities tab (see _loadSessionsPage()) —
  // replaces the old live getRecentSessionsStream() subscription. _sessions
  // now holds every page fetched so far, appended in order; _sessionsHasMore
  // reflects whether the last page came back full (== pageSize), the same
  // signal FirestoreService().getSessionsPage() already computes.
  bool _sessionsLoadingMore = false;
  bool _sessionsHasMore = true;
  // Set on a failed fetch (e.g. a missing-composite-index Firestore
  // exception) so _buildActivitiesList() can show a distinct "couldn't
  // load, retry" state instead of silently rendering the same empty state
  // as "genuinely zero sessions" — the previous catch-and-swallow here is
  // exactly what turned a missing-index regression into an invisible one.
  bool _sessionsError = false;
  DocumentSnapshot<Map<String, dynamic>>? _sessionsLastDoc;
  // null = no date-range filter ("All time"). Combinable with
  // _activityFilter — both are passed to getSessionsPage() together.
  DateTime? _activityStartDate;
  DateTime? _activityEndDate;
  int _totalXp = 0;
  int _level = 1;
  List<Map<String, dynamic>> _xpEvents = [];
  bool _xpEventsLoading = true;

  List<double> _caloriesByDay = [0, 0, 0, 0, 0, 0, 0];
  List<double> _volumeByDay = [0, 0, 0, 0, 0, 0, 0];
  int _weekTotalCalories = 0;
  int _weekTotalVolume = 0;
  int _weekTotalSessions = 0;
  int _weekGymSessions = 0;
  bool _chartsLoading = true;

  // Collapsible state for each Charts-tab chart section — same
  // tap-to-toggle-chevron pattern as _weightExpanded/_calendarExpanded
  // further below, just one flag per chart instead of one shared flag,
  // since each section collapses independently. All default true so
  // nothing looks different from before until a user actually taps one.
  bool _caloriesChartExpanded = true;
  bool _gymChartExpanded = true;
  bool _sessionTypeChartExpanded = true;
  bool _distancePaceChartExpanded = true;
  bool _muscleGroupChartExpanded = true;

  // Session-type breakdown (Part B) — per-bucket counts, same indexing/
  // shape as _caloriesByDay/_volumeByDay above, from the same
  // getSessionStats() call (no separate query).
  List<double> _gymCountByDay = [0, 0, 0, 0, 0, 0, 0];
  List<double> _cardioCountByDay = [0, 0, 0, 0, 0, 0, 0];
  List<double> _combinedCountByDay = [0, 0, 0, 0, 0, 0, 0];
  List<double> _manualCountByDay = [0, 0, 0, 0, 0, 0, 0];

  // Distance/pace trend (Part C) — per-bucket summed distanceMeters, plus
  // period totals for the one overall average-pace figure shown in the
  // chart's caption (see getSessionStats()'s own doc comment for why pace
  // itself isn't bucketed).
  List<double> _distanceByDay = [0, 0, 0, 0, 0, 0, 0];
  double _totalDistanceMeters = 0;
  int _totalDistanceDurationSeconds = 0;

  // Muscle-group distribution (Part D) — set count per muscle for the
  // whole selected period, not bucketed (a composition snapshot, not a
  // sub-period trend). FirestoreService.unknownMuscleKey covers exercises
  // with a missing/null muscle field.
  Map<String, int> _muscleSetCounts = {};


  bool _checkInsLoading = true;
  Stream<List<Map<String, dynamic>>>? _checkInsStream;

  List<Map<String, dynamic>> _weightLogs = [];
  bool _weightLoading = true;
  double? _goalWeight;
  // goalWeight/weightGoalActive both live in the encrypted health-data
  // blob (this session's encryption migration) — fetched together via
  // getHealthData() in _loadGoalWeight() below, never via a live
  // Firestore stream (encrypted data can't be streamed client-side).
  // Gates whether the chart actually shows the goal line/marker — see
  // _loadGoalWeight()'s own comment for why _goalWeight != null alone
  // isn't enough.
  bool _weightGoalActive = false;
  bool _weightExpanded = true;
  StreamSubscription<List<Map<String, dynamic>>>? _weightSub;

  // The weight chart's OWN range control — fully decoupled from
  // _timeFilter (which stays scoped to the Calories/Gym charts above,
  // untouched). Reusing _timeFilter here previously meant the weight
  // chart inherited its "This Week" default, hiding almost all history
  // on load for a goal-tracking chart where the whole point is the
  // longer trend. Rolling windows (last 30/90/180 days), not
  // calendar-anchored like _timeFilter's Week/Month/Year — a
  // calendar-month "Month" option would reintroduce the exact same
  // "too-narrow on some days" bug this replaces. See
  // _buildWeightRangeFilter() and _buildWeightSection()'s filterStart
  // computation.
  int _weightChartRange = 0;
  static const List<String> _weightRangeLabels = ['1M', '3M', '6M', 'All'];

  // Activity Calendar section — collapsed by default (unlike
  // _weightExpanded above) since it's a new, opt-in addition to an
  // already chart-heavy tab, not a pre-existing section users expect open.
  // _calendarMonth is separate from _timeFilter's W/M/Y scope entirely —
  // this is its own independently-browsable month, backed by the same
  // monthActivityProvider Home's week-strip modal already uses (see
  // _buildCalendarSection() below for why they don't need to sync).
  bool _calendarExpanded = false;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  List<Map<String, dynamic>> _nutritionLogs = [];
  bool _nutritionLoading = true;

  static const List<String> _subtabLabels = [
    'Charts',
    'Activities',
    'XP History',
    'Check-ins',
    'Nutrition',
  ];
  static const List<String> _timeLabels = ['W', 'M', 'Y'];
  static const List<String> _actLabels = [
    'All',
    'Gym',
    'Cardio',
    'Manual',
    'Custom',
  ];

  // Fallback only now, matching firestore_service.dart's own
  // _kFallbackLevelThresholds convention — see _xpThresholds below and
  // _loadXpThresholds() for the live-config read that's now the actual
  // source. Previously this was the primary, only source (never synced
  // with whatever an admin actually configured), which meant an admin
  // editing an existing threshold value never showed up here — a real
  // correctness gap independent of adding new levels.
  static const _kXpThresholds = [
    0,
    500,
    1200,
    2500,
    4500,
    7000,
    10000,
    14000,
    19000,
    25000,
    32000,
  ];

  // Starts at the fallback so this card renders correctly-looking data
  // immediately (no spinner/placeholder needed — the fallback matches
  // whatever's actually configured in the common case), then updates via
  // _loadXpThresholds() once the live fetch resolves.
  List<num> _xpThresholds = _kXpThresholds;

  double _xpProgress() {
    if (_level >= _xpThresholds.length) return 1.0;
    final start = _xpThresholds[_level - 1];
    final end = _xpThresholds[_level];
    return ((_totalXp - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _loadSessionsPage(reset: true);
    _loadXpData();
    _loadXpEvents();
    _loadXpThresholds();
    _loadChartData();
    _loadCheckIns();
    _loadGoalWeight();
    _startWeightStream();
    _loadNutritionLogs();
  }

  // Global config, not per-user data — independent of _loadXpData()
  // above, so it loads in parallel rather than waiting on it.
  Future<void> _loadXpThresholds() async {
    final thresholds =
        await FirestoreService().getLevelThresholds(_kXpThresholds);
    if (!mounted) return;
    setState(() => _xpThresholds = thresholds);
  }

  @override
  void dispose() {
    _weightSub?.cancel();
    super.dispose();
  }

  // ProgressScreen lives inside MainShell's IndexedStack (home_screen.dart),
  // which keeps every tab's State alive and never re-runs initState() on a
  // tab switch — so _loadGoalWeight()'s one-time initState call goes stale
  // the moment the user changes goalWeight/weightGoalActive in Settings and
  // switches back here without a full app restart. MainShell passes
  // `isVisible: _selectedIndex == <progress tab index>`, which changes on
  // every tab switch even though this same State instance persists;
  // didUpdateWidget is what a StatefulWidget uses to notice a new widget
  // config at the same tree position, so the false→true edge here is the
  // earliest reliable "this tab just became visible again" signal
  // available without restructuring the IndexedStack itself. Same
  // mechanism as CoachScreen's own didUpdateWidget for its consent banner.
  @override
  void didUpdateWidget(covariant ProgressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadGoalWeight();
      _loadNutritionLogs();
    }
  }

  Future<void> _loadChartData() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _chartsLoading = false);
      return;
    }
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      DateTime startDate;
      DateTime endDate;
      int bucketCount;
      String bucketUnit;

      // Rolling windows ending today, NOT calendar week/month/year —
      // calendar-anchored ranges showed sparse/near-empty data early in
      // a calendar week/month/year (e.g. only 1-2 days of data on the
      // 2nd of a month) with no way to see the prior period once it
      // rolled over (no picker exists for this control — a separate,
      // deliberately out-of-scope concern). endDate is exclusive, so
      // "through today" needs the upper bound at start-of-tomorrow, same
      // convention the old code already used (start-of-day-after the
      // last included day).
      if (_timeFilter == 0) {
        // This Week — last 7 days (today minus 6 days through today)
        startDate = today.subtract(const Duration(days: 6));
        endDate = today.add(const Duration(days: 1));
        bucketCount = 7;
        bucketUnit = 'day';
      } else if (_timeFilter == 1) {
        // This Month — last 30 days (today minus 29 days through today)
        startDate = today.subtract(const Duration(days: 29));
        endDate = today.add(const Duration(days: 1));
        bucketCount = 4;
        bucketUnit = 'week';
      } else {
        // This Year — last 365 days (today minus 364 days through
        // today). Almost always crosses a calendar-year boundary now —
        // see getSessionStats()'s 'month' bucketIndex math, updated to
        // handle that (it previously assumed a single-calendar-year
        // span).
        startDate = today.subtract(const Duration(days: 364));
        endDate = today.add(const Duration(days: 1));
        bucketCount = 12;
        bucketUnit = 'month';
      }

      final stats = await FirestoreService().getSessionStats(
        uid,
        startDate: startDate,
        endDate: endDate,
        bucketCount: bucketCount,
        bucketUnit: bucketUnit,
      );

      if (!mounted) return;
      setState(() {
        _caloriesByDay = List<double>.from(stats['caloriesByDay'] as List);
        _volumeByDay = List<double>.from(stats['volumeByDay'] as List);
        _weekTotalCalories = stats['totalCalories'] as int;
        _weekTotalVolume = stats['totalVolume'] as int;
        _weekTotalSessions = stats['totalSessions'] as int;
        _weekGymSessions = stats['gymSessions'] as int;
        _gymCountByDay = List<double>.from(stats['gymCountByDay'] as List);
        _cardioCountByDay =
            List<double>.from(stats['cardioCountByDay'] as List);
        _combinedCountByDay =
            List<double>.from(stats['combinedCountByDay'] as List);
        _manualCountByDay =
            List<double>.from(stats['manualCountByDay'] as List);
        _distanceByDay = List<double>.from(stats['distanceByDay'] as List);
        _totalDistanceMeters = stats['totalDistanceMeters'] as double;
        _totalDistanceDurationSeconds =
            stats['totalDistanceDurationSeconds'] as int;
        _muscleSetCounts = Map<String, int>.from(
          stats['muscleSetCounts'] as Map,
        );
        _chartsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _chartsLoading = false);
    }
  }

  void _loadCheckIns() {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _checkInsLoading = false);
      return;
    }
    setState(() {
      _checkInsStream = FirestoreService().getMissedSessionsStream(uid);
      _checkInsLoading = false;
    });
  }

  Future<void> _loadXpData() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await FirestoreService().getUserProfile(uid);
      if (!mounted) return;
      setState(() {
        _totalXp = (profile?['totalXp'] as num?)?.toInt() ?? 0;
        _level = (profile?['level'] as num?)?.toInt() ?? 1;
      });
    } catch (_) {}
  }

  Future<void> _loadXpEvents() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _xpEventsLoading = false);
      return;
    }
    try {
      final result = await FirestoreService().getXpEvents(uid);
      if (!mounted) return;
      setState(() {
        _xpEvents = result;
        _xpEventsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _xpEventsLoading = false);
    }
  }

  // One-time paginated fetch (was a live getRecentSessionsStream()
  // subscription) — see getSessionsPage()'s own doc comment in
  // firestore_service.dart for why this moved off .snapshots(). Called with
  // reset:true on initial load and whenever a filter changes (type/date
  // range), since those change the underlying query and any
  // previously-fetched pages/cursor no longer apply. Called with
  // reset:false (the default) by the "Load More" control to fetch the next
  // page using the cursor from the last page fetched.
  Future<void> _loadSessionsPage({bool reset = false}) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _sessionsLoading = false);
      return;
    }
    if (reset) {
      setState(() {
        _sessions = [];
        _sessionsLastDoc = null;
        _sessionsHasMore = true;
        _sessionsLoading = true;
        _sessionsError = false;
      });
    } else {
      if (!_sessionsHasMore || _sessionsLoadingMore) return;
      setState(() {
        _sessionsLoadingMore = true;
        _sessionsError = false;
      });
    }

    // End date is inclusive of the whole day it falls on — a session
    // logged at, say, 8pm on the selected end date has a 'date' Timestamp
    // later than midnight, so a plain isLessThanOrEqualTo against midnight
    // would wrongly exclude it.
    DateTime? rangeStart = _activityStartDate;
    DateTime? rangeEnd = _activityEndDate == null
        ? null
        : DateTime(
            _activityEndDate!.year,
            _activityEndDate!.month,
            _activityEndDate!.day,
            23,
            59,
            59,
            999,
          );

    // Mirrors _filteredSessions' old mutually-exclusive semantics: only one
    // of type/manualOnly/customOnly is ever active at once, since
    // _activityFilter is a single-select index (see _actLabels).
    String? type;
    var manualOnly = false;
    var customOnly = false;
    if (_activityFilter == 1) {
      type = 'gym';
    } else if (_activityFilter == 2) {
      type = 'cardio';
    } else if (_activityFilter == 3) {
      manualOnly = true;
    } else if (_activityFilter == 4) {
      customOnly = true;
    }

    try {
      final page = await FirestoreService().getSessionsPage(
        uid,
        startAfterDoc: reset ? null : _sessionsLastDoc,
        type: type,
        manualOnly: manualOnly,
        customOnly: customOnly,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      if (!mounted) return;
      setState(() {
        _sessions = reset ? page.sessions : [..._sessions, ...page.sessions];
        _sessionsLastDoc = page.lastDoc ?? _sessionsLastDoc;
        _sessionsHasMore = page.hasMore;
        _sessionsLoading = false;
        _sessionsLoadingMore = false;
        _sessionsError = false;
      });
    } catch (e) {
      // Previously swallowed entirely (catch (_) {}), which is exactly why
      // a missing-composite-index Firestore exception rendered as "no
      // sessions" instead of a visible error — see this field's own doc
      // comment. Printed (not rethrown) to match this file's existing
      // fail-soft convention for background loads elsewhere.
      print('_loadSessionsPage error: $e');
      if (mounted) {
        setState(() {
          _sessionsLoading = false;
          _sessionsLoadingMore = false;
          _sessionsError = true;
        });
      }
    }
  }

  Future<void> _loadNutritionLogs() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _nutritionLoading = false);
      return;
    }
    try {
      final result = await FirestoreService().getNutritionLogsHistory(uid);
      if (!mounted) return;
      setState(() {
        _nutritionLogs = result;
        _nutritionLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _nutritionLoading = false);
    }
  }

  // goalWeight/weightGoalActive both moved off the plaintext user doc into
  // the encrypted health-data blob (this session's encryption migration) —
  // getUserProfile() no longer has either field, so this reads
  // getHealthData() instead, matching the pattern health_profile_screen.dart
  // and settings_screen.dart already use for calorieGoalActive. Called both
  // from initState() and from didUpdateWidget() above on every tab-visible
  // transition, since encrypted data can't be streamed client-side the way
  // the old (broken) raw Firestore listener assumed.
  Future<void> _loadGoalWeight() async {
    try {
      final uid = AuthService().getCurrentUser()?.uid;
      if (uid == null) return;
      final healthData = await FirestoreService().getHealthData(uid);
      if (!mounted) return;
      final raw = healthData['goalWeight'];
      setState(() {
        _goalWeight = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '');
        _weightGoalActive = healthData['weightGoalActive'] as bool? ?? false;
      });
    } catch (_) {}
  }

  void _startWeightStream() {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _weightLoading = false);
      return;
    }
    _weightSub = FirestoreService()
        .getWeightLogsStream(uid)
        .listen(
          (logs) {
            if (mounted) {
              setState(() {
                _weightLogs = logs;
                _weightLoading = false;
              });
            }
          },
          onError: (_) {
            if (mounted) setState(() => _weightLoading = false);
          },
        );
  }

  Future<void> _logWeight(double weightKg) async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    await FirestoreService().saveWeightEntry(uid, weightKg);
  }

  void _showLogWeightSheet() {
    final controller = TextEditingController();
    if (_weightLogs.isNotEmpty) {
      final last = _weightLogs.last['weightKg'];
      if (last is num) {
        controller.text = last.toStringAsFixed(1);
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log Weight',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Today · ${DateTime.now().toString().substring(0, 10)}',
              style: const TextStyle(fontSize: 12, color: WW.textSec),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: WW.text,
                    ),
                    decoration: const InputDecoration(
                      hintText: '70.0',
                      hintStyle: TextStyle(
                        color: WW.border,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const Text(
                  'kg',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                final val = double.tryParse(controller.text);
                if (val == null || val <= 0 || val > 300) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid weight'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                await _logWeight(val);
              },
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Center(
                  child: Text(
                    'Save Weight',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'Recently';
    final date = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  // Compact "Jan 5" calendar date for the weight chart's tap tooltip —
  // deliberately not _formatDate() above (relative-to-now, "3 days ago",
  // wrong here) and not the existing _formatShortDate() further below
  // (day-month-year, e.g. "5 Jan 2026" — needlessly wide for a tooltip).
  // Reuses the existing _monthNames constant that _formatShortDate()
  // already defines rather than duplicating the month-abbreviation list
  // a third time. NOT used for the axis labels below (see
  // _formatWeightAxisDate()) — a tooltip is a single floating label with
  // room to spare, a fundamentally different space budget than 4
  // simultaneous axis labels competing for the same row.
  String _formatWeightChartDate(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}';
  }

  // Compact numeric "M/d" (no leading zeros, e.g. "8/12", "9/1") for the
  // weight chart's fixed 4-label x-axis row below — shorter than the
  // "Jan 5" tooltip format specifically because 4 of these render at
  // once side by side, where every extra pixel of width narrows the
  // margin before adjacent labels crowd each other.
  String _formatWeightAxisDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  // Rounds a raw axis-tick interval up to a "nice" 1/2/5x10^n step (e.g.
  // 7.3 -> 10, 2.4 -> 5, 43 -> 50) instead of the raw division result —
  // otherwise the weight chart's y-axis showed awkward values like
  // "42, 49, 57, 64" instead of "40, 50, 60, 70".
  double _niceAxisInterval(double raw) {
    if (raw <= 0) return 1;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final normalized = raw / magnitude;
    double niceNormalized;
    if (normalized <= 1) {
      niceNormalized = 1;
    } else if (normalized <= 2) {
      niceNormalized = 2;
    } else if (normalized <= 5) {
      niceNormalized = 5;
    } else {
      niceNormalized = 10;
    }
    return niceNormalized * magnitude;
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String _formatVolume(double? v) {
    if (v == null || v == 0) return '';
    final n = v.round();
    if (n >= 1000) {
      return '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')} kg';
    }
    return '$n kg';
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WW.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            _buildSubtabs(),
            Expanded(
              child: IndexedStack(
                index: _subtab,
                children: [
                  _buildChartsTab(),
                  _buildActivitiesTab(),
                  _buildXpTab(),
                  _buildCheckInsTab(),
                  _buildNutritionTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        'Progress',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: WW.primaryDark,
        ),
      ),
    );
  }

  // ── Subtabs ───────────────────────────────────────────────────────────────

  // Evenly distributed across the full row width via spaceEvenly rather
  // than Expanded — with 4 labels here (two of them two-word, ~10 chars:
  // "Activities", "XP History"), equal-quarter Expanded segments risk
  // wrapping those onto two lines on narrow phones. spaceEvenly keeps
  // each label at its natural width and just spaces them evenly instead.
  // Horizontally scrollable rather than spaceEvenly — with 5 labels
  // (including "XP History"/"Check-ins"), an unconstrained Row here
  // overflows on narrow phones since none of these labels are wrapped in
  // Expanded/Flexible. Scrolling degrades gracefully instead.
  Widget _buildSubtabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_subtabLabels.length, (i) {
            final active = i == _subtab;
            return Padding(
              padding: EdgeInsets.only(right: i < _subtabLabels.length - 1 ? 8 : 0),
              child: GestureDetector(
                onTap: () => setState(() => _subtab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: active ? WW.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: active ? WW.primary : WW.border,
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _subtabLabels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : WW.textSec,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHARTS TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChartsTab() {
    if (_chartsLoading) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTimeFilter(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildCaloriesChart(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildGymChart(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildSessionTypeChart(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildDistancePaceChart(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildMuscleGroupChart(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildStatCardsRow(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildWeightSection(),
          const SizedBox(height: 12),
          _sectionDivider(),
          const SizedBox(height: 12),
          _buildCalendarSection(),
        ],
      ),
    );
  }

  // Thin horizontal rule between Charts-tab sections, now that they no
  // longer sit in individual card boxes. One shared divider per gap
  // (rather than a bottom line on one section plus a top line on the
  // next) avoids doubled hairlines while still marking every boundary in
  // the list. Color/height matches the divider already used inside Track
  // Weight's own header/body split (WW.elevated, 1px) for consistency
  // within this file. Spans full width within the ScrollView's existing
  // 20px side padding — no left/right border, purely horizontal.
  Widget _sectionDivider() {
    return Container(height: 1, color: WW.elevated);
  }

  // REMOVED (Progress-tab metrics expansion, Part A): this used to be a
  // "WiseCoach Insight" card — sparkle icon, WiseCoach branding, styled
  // to look like an AI-generated summary — but was actually a pure
  // client-side string template, interpolating _weekTotalSessions/
  // _weekTotalCalories/_weekTotalVolume/_weekGymSessions/_timeFilter (all
  // already-loaded local state; no OpenAI/Cloud Function call anywhere
  // in this file). Confirmed no other call site depended on the card or
  // its text-builder before deleting both. The four _week* fields it
  // read stay — _buildCaloriesChart()/_buildGymChart()/
  // _buildStatCardsRow() all still use them independently.

  // Segmented control: one continuous WW.elevated shell with a white
  // (WW.card) pill that slides to the active segment via AnimatedAlign —
  // matches Club's flattened, single-accent-color visual language instead
  // of the old 3-separate-filled-pills style.
  Widget _buildTimeFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: WW.elevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment(
                -1 + (2 * _timeFilter) / (_timeLabels.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / _timeLabels.length,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: WW.card,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
            Row(
              children: List.generate(_timeLabels.length, (i) {
                final active = i == _timeFilter;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _timeFilter = i;
                        _chartsLoading = true;
                      });
                      _loadChartData();
                    },
                    child: Center(
                      child: Text(
                        _timeLabels[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active ? WW.text : WW.textSec,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaloriesChart() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(
            () => _caloriesChartExpanded = !_caloriesChartExpanded,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WW.tealBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_fire_department_outlined,
                    color: WW.teal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Calories Burned',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                ),
                Icon(
                  _caloriesChartExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_caloriesChartExpanded) ...[
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                barGroups: List.generate(_bucketCount, (i) {
                  final val = i < _caloriesByDay.length
                      ? _caloriesByDay[i]
                      : 0.0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: val > 0 ? val : 30,
                        color: val > 0 ? WW.primary : WW.border,
                        width: 26,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        final labels = _chartLabels;
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => WW.primaryDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final val =
                          (group.x < _caloriesByDay.length
                                  ? _caloriesByDay[group.x]
                                  : 0.0)
                              .round();
                      if (val == 0) return null;
                      return BarTooltipItem(
                        '$val kcal',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: $_weekTotalCalories kcal  ·  Avg: ${_weekTotalSessions > 0 ? (_weekTotalCalories / _weekTotalSessions).round() : 0} kcal/session',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WW.textSec,
            ),
          ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGymChart() {
    return Column(
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _gymChartExpanded = !_gymChartExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WW.chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.fitness_center_rounded,
                    color: WW.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Gym Training',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                ),
                Icon(
                  _gymChartExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_gymChartExpanded) ...[
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                barGroups: List.generate(_bucketCount, (i) {
                  final val = i < _volumeByDay.length ? _volumeByDay[i] : 0.0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: val > 0 ? val : 80,
                        color: val > 0 ? WW.primary : WW.border,
                        width: 26,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        final labels = _chartLabels;
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => WW.primaryDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final val =
                          (group.x < _volumeByDay.length
                                  ? _volumeByDay[group.x]
                                  : 0.0)
                              .round();
                      if (val == 0) return null;
                      return BarTooltipItem(
                        '$val kg',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: $_weekTotalVolume kg  ·  $_weekTotalSessions sessions',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WW.textSec,
            ),
          ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Part B (Progress-tab metrics expansion): session-type breakdown,
  // stacked-bar variant of the same per-bucket BarChart shape
  // _buildCaloriesChart()/_buildGymChart() already use — one stacked bar
  // per _timeFilter bucket instead of one solid-color bar, since this is
  // a composition (which types made up that bucket), not a single scalar
  // trend. Data comes from _gym/_cardio/_combined/_manualCountByDay,
  // populated by the same getSessionStats() call the other two charts
  // already trigger — no separate query.
  Widget _buildSessionTypeChart() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(
            () => _sessionTypeChartExpanded = !_sessionTypeChartExpanded,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WW.lavenderBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.donut_small_rounded,
                    color: WW.lavender,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Session Type Breakdown',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                ),
                Icon(
                  _sessionTypeChartExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_sessionTypeChartExpanded) ...[
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                barGroups: List.generate(_bucketCount, (i) {
                  final gym =
                      i < _gymCountByDay.length ? _gymCountByDay[i] : 0.0;
                  final cardio = i < _cardioCountByDay.length
                      ? _cardioCountByDay[i]
                      : 0.0;
                  final combined = i < _combinedCountByDay.length
                      ? _combinedCountByDay[i]
                      : 0.0;
                  final manual = i < _manualCountByDay.length
                      ? _manualCountByDay[i]
                      : 0.0;
                  final total = gym + cardio + combined + manual;
                  if (total <= 0) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: 0.3,
                          color: WW.border,
                          width: 22,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ],
                    );
                  }
                  var from = 0.0;
                  final stackItems = <BarChartRodStackItem>[];
                  for (final segment in [
                    (gym, WW.primary),
                    (cardio, WW.teal),
                    (combined, WW.lavender),
                    (manual, WW.gold),
                  ]) {
                    final (count, color) = segment;
                    if (count <= 0) continue;
                    stackItems.add(
                      BarChartRodStackItem(from, from + count, color),
                    );
                    from += count;
                  }
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: total,
                        rodStackItems: stackItems,
                        width: 22,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        final labels = _chartLabels;
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => WW.primaryDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final gym = group.x < _gymCountByDay.length
                          ? _gymCountByDay[group.x]
                          : 0.0;
                      final cardio = group.x < _cardioCountByDay.length
                          ? _cardioCountByDay[group.x]
                          : 0.0;
                      final combined = group.x < _combinedCountByDay.length
                          ? _combinedCountByDay[group.x]
                          : 0.0;
                      final manual = group.x < _manualCountByDay.length
                          ? _manualCountByDay[group.x]
                          : 0.0;
                      if (gym + cardio + combined + manual <= 0) return null;
                      final parts = <String>[
                        if (gym > 0) '${gym.round()} gym',
                        if (cardio > 0) '${cardio.round()} cardio',
                        if (combined > 0) '${combined.round()} combined',
                        if (manual > 0) '${manual.round()} manual',
                      ];
                      return BarTooltipItem(
                        parts.join('\n'),
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _buildTypeLegendChip('Gym', WW.primary),
              _buildTypeLegendChip('Cardio', WW.teal),
              _buildTypeLegendChip('Combined', WW.lavender),
              _buildTypeLegendChip('Manual', WW.gold),
            ],
          ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Small color-dot + label chip — a stacked bar chart needs a legend
  // (unlike Calories/Gym's single-series bars, which don't) so a viewer
  // can tell which color is which type.
  Widget _buildTypeLegendChip(String label, Color color) {
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
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: WW.textSec,
          ),
        ),
      ],
    );
  }

  // Part C (Progress-tab metrics expansion): distance trend for outdoor
  // cardio, bucketed exactly like Calories/Gym above. Filters implicitly
  // by distanceMeters presence (baked into _distanceByDay itself — see
  // getSessionStats()'s doc comment) rather than session type, since a
  // combined session can also carry a top-level distanceMeters.
  //
  // Pace is NOT a stored field — durationSeconds/distanceMeters aren't
  // enough on their own for a per-bucket pace (would also need
  // per-bucket duration, which nothing else needs), so only ONE overall
  // average pace for the whole selected period is shown, in the caption,
  // computed from _totalDistanceMeters/_totalDistanceDurationSeconds.
  // Same 50m-floor + MM:SS/km formatting convention already duplicated
  // across post_session_summary_screen.dart/activity_detail_screen.dart/
  // outdoor_cardio_screen.dart/session_share_cards.dart — matched here
  // rather than inventing a new pace format, kept as its own private
  // copy rather than extracting a shared helper (same reasoning
  // session_share_cards.dart's own copy gives: a wider dedup not asked
  // for by this task).
  Widget _buildDistancePaceChart() {
    final avgPaceLabel = _avgPaceLabel(
      _totalDistanceMeters,
      _totalDistanceDurationSeconds,
    );
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(
            () => _distancePaceChartExpanded = !_distancePaceChartExpanded,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WW.tealBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.directions_run_rounded,
                    color: WW.teal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Distance & Pace (Outdoor)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                ),
                Icon(
                  _distancePaceChartExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_distancePaceChartExpanded) ...[
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                barGroups: List.generate(_bucketCount, (i) {
                  final meters =
                      i < _distanceByDay.length ? _distanceByDay[i] : 0.0;
                  final km = meters / 1000;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: km > 0 ? km : 0.3,
                        color: km > 0 ? WW.teal : WW.border,
                        width: 26,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        final labels = _chartLabels;
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => WW.primaryDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final meters = group.x < _distanceByDay.length
                          ? _distanceByDay[group.x]
                          : 0.0;
                      if (meters <= 0) return null;
                      return BarTooltipItem(
                        '${(meters / 1000).toStringAsFixed(2)} km',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: ${(_totalDistanceMeters / 1000).toStringAsFixed(1)} km'
            '${avgPaceLabel != null ? '  ·  Avg pace: $avgPaceLabel' : ''}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WW.textSec,
            ),
          ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String? _avgPaceLabel(double distanceMeters, int durationSeconds) {
    if (distanceMeters < 50 || durationSeconds <= 0) return null;
    final secondsPerKm = durationSeconds / (distanceMeters / 1000);
    if (!secondsPerKm.isFinite) return null;
    final mins = secondsPerKm ~/ 60;
    final secs = (secondsPerKm % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} /km';
  }

  // Part D (Progress-tab metrics expansion): muscle-group distribution —
  // set count per muscle (not volume). Gym Training above already shows
  // volume trend; a volume-weighted muscle chart would mostly re-show the
  // same signal through heavy compound lifts, whereas set count answers
  // a genuinely different question — training FREQUENCY/focus by muscle
  // — using data already denormalized onto session exercises[] entries,
  // no new lookup against the exercises collection needed. One bar per
  // muscle for the whole selected _timeFilter period (a composition
  // snapshot, not a bucketed trend — muscle categories don't have a
  // natural per-day/week/month axis the way session counts do).
  // FirestoreService.unknownMuscleKey ('Unknown') covers exercises whose
  // muscle field was missing/null when logged — shown as its own bar
  // (styled distinctly, WW.border) rather than dropped, since the
  // exercises collection is admin-managed and documented as not always
  // complete.
  Widget _buildMuscleGroupChart() {
    final entries = _muscleSetCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalSets = entries.fold<int>(0, (acc, e) => acc + e.value);
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(
            () => _muscleGroupChartExpanded = !_muscleGroupChartExpanded,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WW.chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.accessibility_new_rounded,
                    color: WW.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Muscle Group Focus',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                ),
                Icon(
                  _muscleGroupChartExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_muscleGroupChartExpanded) ...[
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No gym sets logged this period',
                  style: TextStyle(fontSize: 13, color: WW.textSec),
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  barGroups: List.generate(entries.length, (i) {
                    final isUnknown =
                        entries[i].key == FirestoreService.unknownMuscleKey;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: entries[i].value.toDouble(),
                          color: isUnknown ? WW.border : WW.primary,
                          width: 20,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              entries[i].key,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: WW.textSec,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => WW.primaryDark,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (group.x >= entries.length) return null;
                        final entry = entries[group.x];
                        return BarTooltipItem(
                          '${entry.key}\n${entry.value} set${entry.value == 1 ? '' : 's'}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Total: $totalSets set${totalSets == 1 ? '' : 's'} logged',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WW.textSec,
            ),
          ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatCardsRow() {
    final periodLabel = _timeFilter == 0
        ? 'This Week'
        : _timeFilter == 1
        ? 'This Month'
        : 'This Year';
    final items = [
      ('$_weekTotalSessions', 'sessions\n$periodLabel'),
      ('$_weekGymSessions', 'gym\nsessions'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(items.length, (i) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < items.length - 1 ? 10 : 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      items[i].$1,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: WW.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].$2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: WW.textSec,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // Weight chart's own range control — same segmented-pill visual as
  // _buildTimeFilter() above, but a fully separate, independently-wired
  // control. Purely a client-side filter over already-loaded _weightLogs
  // (no refetch needed, unlike _buildTimeFilter()'s tap handler, which
  // triggers a fresh _loadChartData() network call) — so tapping a
  // segment here is just a setState, nothing async.
  Widget _buildWeightRangeFilter() {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment(
              -1 + (2 * _weightChartRange) / (_weightRangeLabels.length - 1),
              0,
            ),
            child: FractionallySizedBox(
              widthFactor: 1 / _weightRangeLabels.length,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: WW.card,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
          Row(
            children: List.generate(_weightRangeLabels.length, (i) {
              final active = i == _weightChartRange;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _weightChartRange = i),
                  child: Center(
                    child: Text(
                      _weightRangeLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? WW.text : WW.textSec,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightSection() {
    double? startWeight;
    double? currentWeight;
    double? change;

    if (_weightLogs.isNotEmpty) {
      final first = _weightLogs.first['weightKg'];
      final last = _weightLogs.last['weightKg'];
      startWeight = first is num ? first.toDouble() : null;
      currentWeight = last is num ? last.toDouble() : null;
      if (startWeight != null && currentWeight != null) {
        change = currentWeight - startWeight;
      }
    }

    // Weight chart's own range, driven by _weightChartRange (see
    // _buildWeightRangeFilter()) — deliberately NOT _timeFilter, and
    // deliberately a ROLLING window (last N days), not calendar-anchored
    // like _timeFilter's Week/Month/Year: a calendar-month "Month" option
    // would reintroduce the same "too little data visible on some days"
    // bug this replaces (e.g. only 1 day of history showing if today
    // happens to be the 1st). Applied as a DERIVED filtered list, never
    // mutating _weightLogs itself — _weightLogs.last must keep pointing
    // at the true latest entry regardless of chart filter, both for
    // currentWeight above and for _showLogWeightSheet()'s prefill.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime filterStart;
    if (_weightChartRange == 0) {
      filterStart = today.subtract(const Duration(days: 30));
    } else if (_weightChartRange == 1) {
      filterStart = today.subtract(const Duration(days: 90));
    } else if (_weightChartRange == 2) {
      filterStart = today.subtract(const Duration(days: 180));
    } else {
      // All — no rolling lower bound. Anchored to the earliest real entry
      // purely so the goal-line/x-interval fallbacks below always have a
      // concrete start to work with; _weightLogs is already
      // ascending-ordered (see getWeightLogsStream()), so .first is the
      // earliest by construction.
      final earliestDateStr = _weightLogs.isNotEmpty
          ? _weightLogs.first['date'] as String?
          : null;
      filterStart = earliestDateStr != null
          ? (DateTime.tryParse(earliestDateStr) ?? today)
          : today;
    }
    final filterEnd = now;
    final filteredLogs = _weightChartRange == 3
        ? _weightLogs
        : _weightLogs.where((log) {
            final dateStr = log['date'] as String?;
            if (dateStr == null) return false;
            final date = DateTime.tryParse(dateStr);
            if (date == null) return false;
            return !date.isBefore(filterStart);
          }).toList();

    // Real calendar-time x-axis (millisecondsSinceEpoch) instead of array
    // index — points now space out by actual elapsed time between entries
    // (previously e.g. 3 logs spread across 3 months rendered as 3 evenly
    // -spaced points, implying a steady day-to-day trend that wasn't
    // real), and date labels/tooltip can read the date straight off
    // spot.x instead of indexing back into _weightLogs.
    final spots = <FlSpot>[];
    for (final log in filteredLogs) {
      final w = log['weightKg'];
      final dateStr = log['date'] as String?;
      if (w is! num || dateStr == null) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      spots.add(FlSpot(date.millisecondsSinceEpoch.toDouble(), w.toDouble()));
    }

    // +/-5 (was +/-3) — a bit more vertical breathing room above/below the
    // real data range, part of this section's layout/collision fix (the
    // plotted line was reported running into the bottom axis labels).
    double minY = 40;
    double maxY = 120;
    if (spots.isNotEmpty) {
      final weights = spots.map((s) => s.y).toList();
      minY = (weights.reduce((a, b) => a < b ? a : b) - 5).clamp(30, 200);
      maxY = (weights.reduce((a, b) => a > b ? a : b) + 5).clamp(50, 250);
      if (_goalWeight != null && _weightGoalActive) {
        minY = minY.clamp(0, _goalWeight! - 2);
        maxY = maxY < _goalWeight! + 2 ? _goalWeight! + 2 : maxY;
      }
    }
    // Rounded to a clean 1/2/5x10^n step (see _niceAxisInterval()) rather
    // than the raw division result, which produced awkward label values
    // like "42, 49, 57, 64" instead of "40, 50, 60, 70".
    final yLabelInterval = _niceAxisInterval((maxY - minY) / 4);
    // Sized to comfortably fit the widest label this scale can produce
    // (maxY's digit count), rather than a fixed size that only worked for
    // 2-digit numbers — maxY can reach 3 digits (clamped up to 250).
    final yAxisReservedSize =
        (maxY.toStringAsFixed(0).length * 7.0) + 16;

    // Fallback x-bounds for the goal line when there's 0 or 1 points in
    // the filtered range to anchor to — spans the selected range window
    // itself (rather than an arbitrary placeholder) so the dashed goal
    // line still reads sensibly even with sparse data in range. Also set
    // as the chart's explicit minX/maxX below, and reused again further
    // down to compute the 4 fixed x-axis label positions — one shared
    // source of truth for "what the visible window is" across the plot,
    // the goal line, and the axis labels, instead of each guessing at it
    // separately.
    final filterStartMillis = filterStart.millisecondsSinceEpoch.toDouble();
    final filterEndMillis = filterEnd.millisecondsSinceEpoch.toDouble();

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _weightExpanded = !_weightExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WW.tealBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.monitor_weight_outlined,
                    color: WW.teal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Track Weight',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _showLogWeightSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '+ Log',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _weightExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_weightExpanded) ...[
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _weightLoading
                ? const Center(
                    child: CircularProgressIndicator(color: WW.primary),
                  )
                : _weightLogs.isEmpty
                ? Column(
                    children: [
                      const Icon(
                        Icons.monitor_weight_outlined,
                        size: 36,
                        color: WW.border,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No weight logged yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WW.textSec,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap "+ Log" to record your first weight',
                        style: TextStyle(fontSize: 12, color: WW.textSec),
                      ),
                      if (_goalWeight != null && _weightGoalActive) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: WW.tealBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.flag_rounded,
                                color: WW.teal,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Goal: ${_goalWeight!.toStringAsFixed(1)} kg',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: WW.teal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWeightRangeFilter(),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 190,
                        child: LineChart(
                          LineChartData(
                            minX: filterStartMillis,
                            maxX: filterEndMillis,
                            minY: minY,
                            maxY: maxY,
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: yAxisReservedSize,
                                  interval: yLabelInterval,
                                  getTitlesWidget: (value, meta) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        right: 4,
                                      ),
                                      child: Text(
                                        value.toStringAsFixed(0),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: WW.textSec,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              // Disabled — the bottom-axis date labels are
                              // now rendered by a plain, fixed 4-label Row
                              // right below this chart (see below) instead
                              // of fl_chart's own tick-generation, so
                              // there's nothing left for this to draw.
                              bottomTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots.length == 1
                                    ? [
                                        spots[0],
                                        FlSpot(spots[0].x + 0.001, spots[0].y),
                                      ]
                                    : spots,
                                isCurved: true,
                                color: WW.primary,
                                barWidth: 2.5,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, percent, bar, index) {
                                    return FlDotCirclePainter(
                                      radius: 4,
                                      color: WW.primary,
                                      strokeWidth: 2,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: WW.primary.withOpacity(0.08),
                                ),
                              ),
                              if (_goalWeight != null && _weightGoalActive)
                                LineChartBarData(
                                  // Always the full visible window
                                  // (filterStart to filterEnd — same as
                                  // the chart's own minX/maxX above), not
                                  // spots.first.x/spots.last.x — a goal is
                                  // a constant target that applies across
                                  // the whole visible range regardless of
                                  // where the actual logged data happens
                                  // to start/end. Using the data's own
                                  // span here previously made the goal
                                  // line visually start partway across
                                  // wider ranges (e.g. 6M) whenever
                                  // logging didn't begin until partway
                                  // through the window, reading like a
                                  // data gap instead of a constant target.
                                  spots: [
                                    FlSpot(filterStartMillis, _goalWeight!),
                                    FlSpot(filterEndMillis, _goalWeight!),
                                  ],
                                  isCurved: false,
                                  color: WW.teal,
                                  barWidth: 1.5,
                                  dashArray: [6, 4],
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(show: false),
                                ),
                            ],
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) => WW.primaryDark,
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    if (spot.barIndex == 1) {
                                      return LineTooltipItem(
                                        'Goal: ${_goalWeight!.toStringAsFixed(1)} kg',
                                        const TextStyle(
                                          color: WW.teal,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      );
                                    }
                                    final date =
                                        DateTime.fromMillisecondsSinceEpoch(
                                          spot.x.toInt(),
                                        );
                                    return LineTooltipItem(
                                      '${spot.y.toStringAsFixed(1)} kg\n'
                                      '${_formatWeightChartDate(date)}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Fixed 4-label x-axis row, rendered entirely by
                      // this code — deliberately NOT fl_chart's own
                      // bottomTitles/interval/getTitlesWidget mechanism
                      // (that's now disabled below, showTitles: false).
                      // Tuning fl_chart's interval math (span/4, then a
                      // pixel-width-aware LayoutBuilder version) still
                      // left labels cramped depending on where real log
                      // dates happened to fall — fl_chart's own tick
                      // placement (getBestInitialIntervalValue's "nice"
                      // snapping, plus minIncluded/maxIncluded forcing
                      // extra edge ticks — the same mechanism the prior
                      // maxIncluded: false fix addressed for the right
                      // edge only) isn't something this code fully
                      // controls. Always exactly 4 labels — start, 1/3,
                      // 2/3, end of [filterStart, filterEnd] — laid out
                      // with a plain spaceBetween Row instead, so count
                      // and spacing no longer depend on fl_chart's
                      // internal tick-generation at all. Since fl_chart
                      // never generates a bottom-axis tick anymore, its
                      // minIncluded/maxIncluded forced-edge-label
                      // mechanism (the earlier collision's root cause)
                      // can't fire here — not just disabled via a flag,
                      // structurally inapplicable.
                      Padding(
                        padding: EdgeInsets.only(left: yAxisReservedSize),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(4, (i) {
                            final labelDate =
                                DateTime.fromMillisecondsSinceEpoch(
                                  (filterStartMillis +
                                          (filterEndMillis -
                                                  filterStartMillis) *
                                              i /
                                              3)
                                      .round(),
                                );
                            return Text(
                              _formatWeightAxisDate(labelDate),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: WW.textSec,
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (currentWeight != null)
                            Text(
                              '${currentWeight.toStringAsFixed(1)} kg',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: WW.text,
                              ),
                            ),
                          const SizedBox(width: 8),
                          if (change != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                // WW.gold has no light-tint token in
                                // app_theme.dart yet, so we blend it
                                // down ourselves — same alpha-blend
                                // approach already used for the
                                // check-in reason icon chips below.
                                color: change <= 0
                                    ? WW.tealBg
                                    : WW.gold.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: change <= 0 ? WW.teal : WW.gold,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (_goalWeight != null && _weightGoalActive)
                            Row(
                              children: [
                                const Icon(
                                  Icons.flag_rounded,
                                  color: WW.teal,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Goal: ${_goalWeight!.toStringAsFixed(1)} kg',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: WW.teal,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Recent entries',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: WW.textSec,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ..._weightLogs.reversed.take(5).map((log) {
                        final w = log['weightKg'];
                        final d = log['date'] as String? ?? '';
                        final wStr = w is num
                            ? '${w.toStringAsFixed(1)} kg'
                            : '--';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Text(
                                d,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: WW.textSec,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                wStr,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: WW.text,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  // Same collapsible header shape as _buildWeightSection() above (icon
  // chip + title + chevron, tap-to-toggle) — this section is new, so it
  // gets its own _calendarExpanded flag rather than reusing _weightExpanded,
  // and starts collapsed (see that field's own doc comment for why).
  //
  // Backed by monthActivityProvider — the exact same provider Home's
  // week-strip drill-down modal already watches, keyed by MonthKey(uid,
  // year, month). Riverpod caches per MonthKey, so revisiting a month
  // already viewed in Home's modal (or vice versa) reuses that cached
  // result instead of re-querying Firestore; navigating to a new month
  // here triggers exactly one new getMonthActivity() call, same as it
  // would from Home. _calendarMonth is this section's own independently-
  // browsable month — deliberately NOT synced with _timeFilter (the
  // existing This Week/Month/Year segmented control above): _timeFilter
  // scopes the aggregate charts to a window anchored at "now" (last 7
  // days / this calendar month / this calendar year), while this
  // calendar lets you browse ANY past month directly — forcing them
  // together would mean e.g. switching _timeFilter to "This Year" would
  // need some undefined mapping onto a single month here, and switching
  // this calendar to a past month would have to snap the whole tab's
  // charts to some equivalent past scope the Week/Year filter can't even
  // represent. They're independent by design, not an oversight.
  Widget _buildCalendarSection() {
    final uid = AuthService().getCurrentUser()?.uid;
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _calendarExpanded = !_calendarExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WW.lavenderBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: WW.lavender,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Activity Calendar',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                ),
                Icon(
                  _calendarExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: WW.textSec,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_calendarExpanded) ...[
          const Divider(height: 1, color: WW.elevated),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: uid == null
                ? const SizedBox.shrink()
                : Consumer(
                    builder: (context, ref, _) {
                      final asyncData = ref.watch(
                        monthActivityProvider(
                          MonthKey(
                            uid: uid,
                            year: _calendarMonth.year,
                            month: _calendarMonth.month,
                          ),
                        ),
                      );
                      return asyncData.when(
                        data: (data) => MonthCalendar(
                          month: _calendarMonth,
                          dayStates: data.dayStates,
                          streakDates: data.streakDates,
                          onMonthChanged: (newMonth) =>
                              setState(() => _calendarMonth = newMonth),
                        ),
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child:
                                CircularProgressIndicator(color: WW.primary),
                          ),
                        ),
                        error: (_, _) => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              "Couldn't load calendar",
                              style:
                                  TextStyle(fontSize: 13, color: WW.textSec),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVITIES TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildActivitiesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActivityFilter(),
        _buildDateRangeFilter(),
        Expanded(child: _buildActivitiesList()),
      ],
    );
  }

  Widget _buildActivitiesList() {
    if (_sessionsLoading) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }

    final sessions = _sessions;

    if (sessions.isEmpty) {
      // Distinct from the "genuinely no sessions" state below — see
      // _sessionsError's own doc comment for why this matters.
      if (_sessionsError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: WW.textSec,
              ),
              const SizedBox(height: 12),
              const Text(
                "Couldn't load activities",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Something went wrong. Tap to try again.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => _loadSessionsPage(reset: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fitness_center_rounded, size: 48, color: WW.textSec),
            SizedBox(height: 12),
            Text(
              'No sessions yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Complete a workout to see your activity here',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WW.textSec,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      // One extra trailing item for the Load More control/spinner whenever
      // a further page might exist — see _sessionsHasMore's doc comment.
      itemCount: sessions.length + (_sessionsHasMore ? 1 : 0),
      // Flat rows now (no boxed cards — see _ActivityCard), so a thin
      // divider marks the boundary between rows instead of a gap.
      separatorBuilder: (_, __) => Container(height: 0.5, color: WW.border),
      itemBuilder: (_, i) {
        if (i == sessions.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _sessionsLoadingMore
                  ? const CircularProgressIndicator(color: WW.primary)
                  : GestureDetector(
                      onTap: () => _loadSessionsPage(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: WW.elevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _sessionsError ? 'Retry' : 'Load More',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: WW.text,
                          ),
                        ),
                      ),
                    ),
            ),
          );
        }
        final s = sessions[i];
        final isManual = s['isManuallyLogged'] == true;
        final dateLabel = _formatDate(s['date'] as Timestamp?);

        if (isManual) {
          final mins = s['durationMinutes'];
          final cals = s['caloriesBurned'];
          final dist = s['distance'];
          return _ActivityCard(
            title: s['activityName'] as String? ?? 'Manual Activity',
            dateLabel: dateLabel,
            stats: [
              ('Duration', mins != null ? '$mins min' : '--'),
              ('Calories', cals != null ? '$cals kcal' : '--'),
              (
                'Distance',
                dist is num ? '${dist.toStringAsFixed(1)} km' : '--',
              ),
            ],
            xpLabel: 'Manual',
            isCardio: false,
            isManual: true,
            onTap: () => context.push(Routes.activityDetail, extra: s),
          );
        }

        final isCardio = s['type'] == 'cardio';
        final durationSecondsRaw = s['durationSeconds'] as int?;
        final duration = _formatDuration(durationSecondsRaw);
        final sets = s['totalSets'] as int? ?? 0;
        final volume = _formatVolume((s['totalVolume'] as num?)?.toDouble());
        final xp = (s['xpEarned'] as num?)?.toInt() ?? 0;
        final distanceMeters = (s['distanceMeters'] as num?)?.toDouble();
        final caloriesBurned = (s['caloriesBurned'] as num?)?.toInt();
        final activity = s['activity'] as String?;

        final List<(String, String)> stats;
        if (isCardio) {
          final distanceLabel = (distanceMeters != null && distanceMeters > 0)
              ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
              : '--';
          // Same 50m floor as outdoor_cardio_screen.dart's own pace
          // display — below that, pace math is too noisy to be
          // meaningful (a few meters of GPS jitter swings it wildly).
          var paceLabel = '--';
          if (distanceMeters != null &&
              distanceMeters >= 50 &&
              durationSecondsRaw != null &&
              durationSecondsRaw > 0) {
            final secondsPerKm = durationSecondsRaw / (distanceMeters / 1000);
            if (secondsPerKm.isFinite) {
              final paceMins = secondsPerKm ~/ 60;
              final paceSecs = (secondsPerKm % 60).round();
              paceLabel = '${paceMins.toString().padLeft(2, '0')}:'
                  '${paceSecs.toString().padLeft(2, '0')}';
            }
          }
          stats = [
            ('Distance', distanceLabel),
            ('Avg Pace', paceLabel),
            ('Time', duration.isNotEmpty ? duration : '--'),
          ];
        } else {
          stats = [
            ('Sets', sets > 0 ? '$sets' : '--'),
            ('Volume', volume.isNotEmpty ? volume : '--'),
            (
              'Calories',
              caloriesBurned != null ? '$caloriesBurned kcal' : '--',
            ),
          ];
        }

        return _ActivityCard(
          title: s['sessionName'] as String? ?? 'Workout',
          dateLabel: dateLabel,
          stats: stats,
          xpLabel: '+$xp XP',
          isCardio: isCardio,
          isCustom: s['planIsCustom'] == true,
          activity: activity,
          mapSnapshotBase64: s['mapSnapshotBase64'] as String?,
          onTap: () => context.push(Routes.activityDetail, extra: s),
        );
      },
    );
  }

  // Flat, color-only tab style — same pattern as _buildSubtabs() above and
  // Club's subtab rows (font-weight + color change, no pill background) —
  // replaces the old filled-pill chips, which were also the source of
  // this file's only two hardcoded hex colors (0xFFF2F2F7 background,
  // Colors.white active text) instead of WW.* tokens.
  Widget _buildActivityFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: List.generate(_actLabels.length, (i) {
          final active = i == _activityFilter;
          return Padding(
            padding: EdgeInsets.only(right: i < _actLabels.length - 1 ? 20 : 0),
            child: GestureDetector(
              onTap: () {
                if (i == _activityFilter) return;
                setState(() => _activityFilter = i);
                _loadSessionsPage(reset: true);
              },
              child: Text(
                _actLabels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? WW.primary : WW.textSec,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatShortDate(DateTime d) =>
      '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  // Combinable with _buildActivityFilter() above — both feed into the same
  // getSessionsPage() call in _loadSessionsPage(). Deliberately not reusing
  // MonthCalendar (lib/widgets/common/month_calendar.dart): that widget
  // renders a full day-grid with per-day workout/rest coloring sourced from
  // monthActivityProvider's own Firestore reads — the wrong shape and an
  // unnecessary extra query for what's just a date-range filter here.
  Widget _buildDateRangeFilter() {
    final start = _activityStartDate;
    final end = _activityEndDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          _buildDateChip(
            label: start == null ? 'Start' : _formatShortDate(start),
            onTap: () => _pickActivityDate(isStart: true),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('–', style: TextStyle(fontSize: 12, color: WW.textSec)),
          ),
          _buildDateChip(
            label: end == null ? 'End' : _formatShortDate(end),
            onTap: () => _pickActivityDate(isStart: false),
          ),
          if (start != null || end != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _activityStartDate = null;
                  _activityEndDate = null;
                });
                _loadSessionsPage(reset: true);
              },
              child: const Icon(
                Icons.close_rounded,
                size: 15,
                color: WW.textSec,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateChip({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_month_rounded, size: 15, color: WW.textSec),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WW.textSec,
            ),
          ),
        ],
      ),
    );
  }

  // Native Material date picker (showDatePicker, no new dependency).
  // firstDate/lastDate enforce all 3 range rules declaratively rather than
  // validating after the fact:
  //  - no future dates: lastDate is never later than today for either field
  //  - end can't be before start: End's firstDate is the chosen Start
  //  - start can't be after end: Start's lastDate is the chosen End
  // initialDate is clamped into [firstDate, lastDate] since showDatePicker
  // asserts the initial value falls within that range — e.g. picking Start
  // for the first time with an End already set in the past would otherwise
  // default to today, which could fall after that End date.
  Future<void> _pickActivityDate({required bool isStart}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate =
        isStart ? DateTime(2000) : (_activityStartDate ?? DateTime(2000));
    final lastDate = isStart ? (_activityEndDate ?? today) : today;
    final current = isStart ? _activityStartDate : _activityEndDate;
    final initialDate =
        (current != null && !current.isBefore(firstDate) && !current.isAfter(lastDate))
            ? current
            : lastDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _activityStartDate = picked;
      } else {
        _activityEndDate = picked;
      }
    });
    _loadSessionsPage(reset: true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // XP HISTORY TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildXpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLevelCard(),
          const SizedBox(height: 16),
          const Text(
            'XP HISTORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.textSec,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (_xpEventsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(color: WW.primary),
              ),
            )
          else if (_xpEvents.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.star_rounded, size: 40, color: WW.textSec),
                    SizedBox(height: 10),
                    Text(
                      'No XP history yet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Complete a workout to earn XP',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: WW.textSec,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: List.generate(_xpEvents.length, (i) {
                return _XpRow(
                  event: _xpEvents[i],
                  isLast: i == _xpEvents.length - 1,
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildLevelCard() {
    final progress = _xpProgress();
    final isMaxLevel = _level >= _xpThresholds.length;
    final nextLevelXp = isMaxLevel ? 0 : _xpThresholds[_level];
    final xpToNext = isMaxLevel ? 0 : nextLevelXp - _totalXp;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Lv.$_level',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: WW.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: WW.border,
              valueColor: const AlwaysStoppedAnimation<Color>(WW.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isMaxLevel
                ? '$_totalXp XP · Max Level'
                : '$_totalXp XP · $xpToNext XP to Level ${_level + 1}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: WW.textSec,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHECK-INS TAB
  // ══════════════════════════════════════════════════════════════════════════

  static const Map<String, Map<String, dynamic>> _reasonData = {
    'busy': {
      'label': 'Too busy',
      'sub': 'Not enough time',
      'icon': Icons.access_time_rounded,
      'color': Color(0xFF6C7EE8),
    },
    'sick': {
      'label': 'Not feeling well',
      'sub': 'Unwell or fatigued',
      'icon': Icons.thermostat_rounded,
      'color': Color(0xFFEF4444),
    },
    'injured': {
      'label': 'Injured',
      'sub': 'Needed to adapt',
      'icon': Icons.shield_outlined,
      'color': Color(0xFFF59E0B),
    },
    'rest': {
      'label': 'Needed rest',
      'sub': 'Body needed recovery',
      'icon': Icons.nightlight_round,
      'color': Color(0xFF4BB8CC),
    },
    'skip': {
      'label': 'Just skipped',
      'sub': 'No particular reason',
      'icon': Icons.skip_next_rounded,
      'color': Color(0xFF8A8A9E),
    },
  };

  Widget _buildCheckInsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _checkInsStream,
      builder: (context, snapshot) {
        if (_checkInsLoading ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: WW.primary),
          );
        }
        final checkIns = snapshot.data ?? [];
        if (checkIns.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: WW.elevated,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 32,
                    color: WW.textSec,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No missed sessions logged',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your check-in history will appear here.',
                  style: TextStyle(fontSize: 13, color: WW.textSec),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          itemCount: checkIns.length,
          itemBuilder: (context, index) {
            return _CheckInRow(
              item: checkIns[index],
              isLast: index == checkIns.length - 1,
            );
          },
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NUTRITION TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildNutritionTab() {
    if (_nutritionLoading) {
      return const Center(
        child: CircularProgressIndicator(color: WW.primary),
      );
    }

    if (_nutritionLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.restaurant_rounded, size: 48, color: WW.textSec),
            SizedBox(height: 12),
            Text(
              'No meals logged yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Scan, describe, or log a meal to see it here',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WW.textSec,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _nutritionLogs.length,
      separatorBuilder: (_, __) => Container(height: 1, color: WW.elevated),
      itemBuilder: (_, i) {
        final log = _nutritionLogs[i];
        return _NutritionLogCard(
          foodName: log['foodName'] as String? ?? 'Meal',
          calories: (log['calories'] as num?)?.toInt() ?? 0,
          dateLabel: _formatDate(log['date'] as Timestamp?),
          source: log['source'] as String? ?? 'manual',
          onTap: () => context.push(Routes.nutritionLogDetail, extra: log),
        );
      },
    );
  }
}

// ── Activity card ─────────────────────────────────────────────────────────────

// NRC-style layout: a wide banner thumbnail (route snapshot, or an
// icon-only fallback header) on top, then title + date, then a 3-stat
// row underneath — replaces the previous slim icon-left/text-right row
// now that cardio sessions can have a real map image to lead with.
// Still flat (no card border/shadow, single accent color) — only the
// content layout changed, not the "no boxed cards" design direction.
// Strava-style row: a small square thumbnail on the left (icon for
// gym/manual/custom, actual route map for cardio), everything else — title,
// type tag, date, stat row — filling the remaining width to the right.
// Replaces the previous full-width 120px icon/map header stacked above the
// text, which ate excessive vertical space for what's mostly a compact list.
class _ActivityCard extends StatelessWidget {
  final String title;
  final String dateLabel;
  final List<(String, String)> stats;
  final String xpLabel;
  final bool isCardio;
  final bool isManual;
  final bool isCustom;
  final String? activity;
  final String? mapSnapshotBase64;
  final VoidCallback? onTap;

  static const double _thumbSize = 58;

  const _ActivityCard({
    required this.title,
    required this.dateLabel,
    required this.stats,
    required this.xpLabel,
    required this.isCardio,
    this.isManual = false,
    this.isCustom = false,
    this.activity,
    this.mapSnapshotBase64,
    this.onTap,
  });

  // Matches cardio_setup_screen.dart's own Run/Walk/Cycle icon choices
  // exactly, for consistency across the app, instead of showing the same
  // running icon for every cardio type regardless of activity.
  IconData get _iconData {
    if (isManual) return Icons.edit_note_rounded;
    // Same clipboard icon used elsewhere for custom routines (e.g.
    // gym_session_screen.dart's read-only header) instead of the barbell,
    // when this session came from a custom-built plan.
    if (!isCardio) {
      return isCustom ? Icons.assignment_rounded : Icons.fitness_center_rounded;
    }
    switch (activity) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  // Same precedence _iconData uses (cardio always wins over custom) so the
  // tag text and the icon/thumbnail never disagree about what a row is.
  String get _typeTag {
    if (isManual) return 'Manual';
    if (isCardio) return 'Cardio';
    return isCustom ? 'Custom' : 'Gym';
  }

  // Fallback thumbnail when there's no map snapshot to show (gym, manual,
  // custom, or a cardio session saved before this feature existed) — same
  // footprint as the map thumbnail so rows don't resize depending on which
  // is shown.
  Widget _buildIconThumb() {
    return Container(
      width: _thumbSize,
      height: _thumbSize,
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Icon(_iconData, color: WW.textSec, size: 24)),
    );
  }

  Widget _buildStatCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: WW.textSec)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Map thumbnail replaces the icon-only square when a snapshot is
    // present (outdoor cardio sessions saved after the snapshot feature
    // landed) — same footprint either way so rows don't resize depending
    // on which is shown. Gym/manual/custom rows and any cardio session
    // saved before this field existed simply have no snapshot and fall
    // straight back to the icon square; a decode failure does the same
    // rather than breaking the row. BoxFit.cover here properly crops the
    // wider-than-square source image to fill this square slot — it does
    // not stretch it (BoxFit.fill would; this is deliberately not that).
    Widget thumb;
    final snapshot = mapSnapshotBase64;
    if (snapshot != null) {
      try {
        final bytes = base64Decode(snapshot);
        thumb = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            width: _thumbSize,
            height: _thumbSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildIconThumb(),
          ),
        );
      } catch (_) {
        thumb = _buildIconThumb();
      }
    } else {
      thumb = _buildIconThumb();
    }

    // One consistent XP-badge color regardless of session type — matches
    // the "one accent color, not one per category" flat-design principle
    // already applied to Club/Progress elsewhere. The manual/earned
    // distinction is still legible from the badge's own text ("Manual"
    // vs "+X XP"), so a separate color for that isn't needed to keep it
    // clear.
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            thumb,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: WW.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: WW.tealBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          xpLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: WW.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_typeTag · $dateLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WW.textSec,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final stat in stats)
                        Expanded(child: _buildStatCell(stat.$1, stat.$2)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Nutrition log card ──────────────────────────────────────────────────────
// Mirrors _ActivityCard's layout (left color bar, icon, title/subtitle,
// right badge) for visual consistency with the Activities tab.

class _NutritionLogCard extends StatelessWidget {
  final String foodName;
  final int calories;
  final String dateLabel;
  final String source; // 'scan' | 'barcode' | 'manual'
  final VoidCallback? onTap;

  const _NutritionLogCard({
    required this.foodName,
    required this.calories,
    required this.dateLabel,
    required this.source,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final Color iconBg;
    final IconData iconData;
    final String sourceLabel;

    switch (source) {
      case 'scan':
        iconColor = WW.primary;
        iconBg = WW.chipBg;
        iconData = Icons.camera_alt_rounded;
        sourceLabel = 'Scanned';
        break;
      case 'barcode':
        iconColor = WW.teal;
        iconBg = WW.tealBg;
        iconData = Icons.qr_code_scanner_rounded;
        sourceLabel = 'Barcode';
        break;
      default:
        iconColor = WW.lavender;
        iconBg = WW.lavenderBg;
        iconData = Icons.edit_note_rounded;
        sourceLabel = 'Manual';
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(iconData, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    foodName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$dateLabel · $sourceLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WW.textSec,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Badge: calories
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: WW.tealBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$calories kcal',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: WW.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── XP row ────────────────────────────────────────────────────────────────────

class _XpRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isLast;

  const _XpRow({required this.event, required this.isLast});

  String _formatTs(dynamic ts) {
    if (ts is! Timestamp) return 'Recently';
    final date = ts.toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final reason = event['reason'] as String? ?? 'XP earned';
    final amount = (event['amount'] as num?)?.toInt() ?? 0;
    final dateLabel = _formatTs(event['date']);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
              ),
      ),
      child: Row(
        children: [
          // Star chip
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: WW.tealBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.star_rounded, color: WW.teal, size: 18),
            ),
          ),
          const SizedBox(width: 10),

          // Reason + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
          ),

          // XP amount
          Text(
            '+$amount XP',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: WW.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Check-in row ─────────────────────────────────────────────────────────────

class _CheckInRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isLast;

  const _CheckInRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final reason = item['reason'] as String? ?? 'skip';
    final date = item['date'] as String? ?? '';
    final dayIndex = (item['dayIndex'] as num?)?.toInt() ?? 1;
    final planId = item['planId'] as String? ?? '';
    final rd = _ProgressScreenState._reasonData[reason] ??
        _ProgressScreenState._reasonData['skip']!;
    final iconColor = rd['color'] as Color;
    final icon = rd['icon'] as IconData;
    final label = rd['label'] as String;
    final sub = rd['sub'] as String;

    String displayDate = date;
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        final dt = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        displayDate =
            '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      displayDate,
                      style: const TextStyle(fontSize: 11, color: WW.textSec),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: const TextStyle(fontSize: 12, color: WW.textSec),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: WW.elevated,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Day $dayIndex',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: WW.textSec,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () async {
                      await context.push(
                        Routes.missedCheckin,
                        extra: {
                          'planId': planId,
                          'planName': '',
                          'missedDayIndex': dayIndex,
                          'existingDate': date,
                        },
                      );
                    },
                    child: const Text(
                      'Change reason',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
