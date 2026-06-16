// lib/screens/plans/plan_schedule_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

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
  String? _breakEndDate;
  int _breakDays = 3;

  int _selectedWeekIdx = 0;
  bool _isLoading = true;
  Set<int> _compressedDays = {};

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

        final rawBreakEnd = progress?['breakEndDate'] as String?;
        final today = DateTime.now().toString().substring(0, 10);
        bool breakActive = progress?['breakModeActive'] as bool? ?? false;

        if (breakActive && rawBreakEnd != null && rawBreakEnd.compareTo(today) < 0) {
          breakActive = false;
          await _fs.updatePlanProgress(_uid!, planId, {
            'breakModeActive': false,
            'breakEndDate': null,
            'breakStartDate': null,
            'breakDays': null,
          });
        }

        final currentDay = (progress?['currentDayIndex'] as num?)?.toInt() ?? 1;

        final rawCompressedDays = progress?['compressedDays'];
        Set<int> loadedCompressedDays = {};
        if (rawCompressedDays is List) {
          loadedCompressedDays =
              rawCompressedDays.map((d) => (d as num).toInt()).toSet();
        }

        setState(() {
          _currentDayIndex = currentDay;
          _breakModeActive = breakActive;
          _breakEndDate = rawBreakEnd;
          _compressedDays = loadedCompressedDays;
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

  String _statusOf(int dayIndex, bool isRest) {
    if (isRest) return 'rest';
    if (dayIndex < _currentDayIndex) return 'completed';
    if (dayIndex == _currentDayIndex) return 'today';
    return 'upcoming';
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

  Future<void> _endBreak() async {
    if (_uid == null || _planId == null) return;
    try {
      await _fs.updatePlanProgress(_uid!, _planId!, {
        'breakModeActive': false,
        'breakEndDate': null,
        'breakStartDate': null,
        'breakDays': null,
      });
      if (mounted) {
        setState(() {
          _breakModeActive = false;
          _breakEndDate = null;
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
      if (!mounted) return;
      setState(() {
        _breakModeActive = true;
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
        onConfirm: (_) async {
          Navigator.of(ctx).pop();
          if (_uid != null && _planId != null) {
            final updated = {..._compressedDays, dayIndex};
            setState(() => _compressedDays = updated);
            await _fs.updatePlanProgress(_uid!, _planId!, {
              'compressedDays': updated.toList(),
            });
          }
          if (mounted) _snack('Session compressed! ⚡');
        },
      ),
    );
  }

  Future<void> _restoreDaySession(int dayIndex) async {
    if (_uid == null || _planId == null) return;
    setState(() => _compressedDays.remove(dayIndex));
    try {
      await _fs.updatePlanProgress(_uid!, _planId!, {
        'compressedDays': _compressedDays.toList(),
      });
      if (mounted) _snack('Session restored to full workout');
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _restartPlan() async {
    if (_uid == null || _planId == null) return;
    await _fs.updatePlanProgress(_uid!, _planId!, {
      'currentDayIndex': 1,
      'lastCompletedDate': '',
      'lastCompletedDayIndex': 0,
      'compressedDays': [],
    });
    if (!mounted) return;
    setState(() {
      _currentDayIndex = 1;
      _compressedDays = {};
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
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          );
          if (confirmed == true) await _restartPlan();
        },
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          foregroundColor: const Color(0xFFEF4444),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13)),
        ),
        child: const Text(
          'Restart from Day 1',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEF4444)),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: WW.elevated,
              valueColor: const AlwaysStoppedAnimation<Color>(WW.primary),
              minHeight: 8,
            ),
          ),
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
      final isCompressed = _compressedDays.contains(dayIndex);

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
          isCompressed: isCompressed,
          showTodayActions: status == 'today',
          showCompress: hasAccessory && !isCompressed,
          onStartSession: () => context.push(Routes.gymSession),
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
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WW.gold, width: 1),
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
                    color: Color(0xFF92400E),
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
                  side: const BorderSide(color: Color(0xFF92400E)),
                  foregroundColor: const Color(0xFF92400E),
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
        border: Border(left: BorderSide(color: WW.gold, width: 3)),
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
                      color: selected ? WW.gold : WW.elevated,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$d ${d == 1 ? "day" : "days"}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? const Color(0xFF92400E) : WW.textSec,
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
                backgroundColor: WW.gold,
                foregroundColor: const Color(0xFF92400E),
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
  final bool isCompressed;
  final bool showTodayActions;
  final bool showCompress;
  final VoidCallback? onStartSession;
  final VoidCallback? onCompress;
  final VoidCallback? onRestore;

  const _ScheduleDayCard({
    required this.session,
    required this.dayIndex,
    required this.status,
    required this.isCompressed,
    required this.showTodayActions,
    required this.showCompress,
    required this.onStartSession,
    required this.onCompress,
    required this.onRestore,
  });

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

  @override
  Widget build(BuildContext context) {
    final isRest = status == 'rest';
    final dayLabel = session['day'] as String? ?? 'Day $dayIndex';
    final sessionName = session['name'] as String? ?? '';
    final estimatedMinutes = (session['estimatedMinutes'] as num?)?.toInt() ?? 0;

    final allExercises = (session['exercises'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    // FIX 2: filter to Primary-only when compressed.
    final displayExercises = isCompressed
        ? allExercises.where((e) => e['tag'] == 'Primary').toList()
        : allExercises;

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
                                const Text(
                                  'Rest Day',
                                  style: TextStyle(fontSize: 12, color: WW.textSec),
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
                          final name = ex['name'] as String? ?? 'Exercise';
                          final sets = (ex['sets'] is List)
                              ? (ex['sets'] as List).length
                              : (ex['sets'] as num?)?.toInt() ?? 3;
                          final reps = (ex['reps'] as num?)?.toInt() ?? 0;
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
                                Container(
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
                                  '$sets×$reps',
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

class _CompressSheet extends StatelessWidget {
  final Map<String, dynamic> session;
  final Future<void> Function(List<Map<String, dynamic>>) onConfirm;

  const _CompressSheet({required this.session, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final exercises = (session['exercises'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    final primary = exercises.where((e) => e['tag'] != 'Accessory').toList();
    final accessory = exercises.where((e) => e['tag'] == 'Accessory').toList();
    final savedMinutes = accessory.length * 4;

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
              "Short on time? We'll remove accessory exercises to shorten your workout while keeping the important stuff.",
              style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                if (primary.isNotEmpty) ...[
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
                      children: List.generate(primary.length, (i) {
                        final ex = primary[i];
                        final name = ex['name'] as String? ?? 'Exercise';
                        final sets = (ex['sets'] is List)
                            ? (ex['sets'] as List).length
                            : (ex['sets'] as num?)?.toInt() ?? 0;
                        final reps = (ex['reps'] as num?)?.toInt() ?? 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: i < primary.length - 1
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
                if (accessory.isNotEmpty) ...[
                  const Text(
                    'REMOVING',
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
                      children: List.generate(accessory.length, (i) {
                        final ex = accessory[i];
                        final name = ex['name'] as String? ?? 'Exercise';
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: i < accessory.length - 1
                                ? const Border(
                                    bottom: BorderSide(color: WW.border, width: 0.5))
                                : null,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.close_rounded, size: 14,
                                  color: Color(0xFFEF4444)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFEF4444),
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Accessory',
                                  style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w700,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ),
                            ],
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
                        'Saves approximately $savedMinutes minutes',
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
                        onTap: () => onConfirm(primary),
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: WW.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'Compress (save ~${savedMinutes}min)',
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
