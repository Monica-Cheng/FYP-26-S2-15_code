// lib/screens/cardio/cardio_setup_screen.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';

// ── Activity data ──────────────────────────────────────────────────────────────

class _Activity {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const _Activity({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}

const _kActivities = [
  _Activity(
    id: 'Run',
    label: 'Run',
    icon: Icons.directions_run_rounded,
    color: WW.teal,
  ),
  _Activity(
    id: 'Walk',
    label: 'Walk',
    icon: Icons.directions_walk_rounded,
    color: Color(0xFF22C55E),
  ),
  _Activity(
    id: 'Cycle',
    label: 'Cycle',
    icon: Icons.directions_bike_rounded,
    color: WW.lavender,
  ),
];

// ── Screen ─────────────────────────────────────────────────────────────────────

class CardioSetupScreen extends StatefulWidget {
  const CardioSetupScreen({super.key});

  @override
  State<CardioSetupScreen> createState() => _CardioSetupScreenState();
}

class _CardioSetupScreenState extends State<CardioSetupScreen> {
  String _selectedActivity = 'Run';
  String _selectedMode = 'indoor';
  bool _fromPlan = false;
  String? _planActivity;
  int? _planMinutes;
  // Which in-progress plan session (and which cardio block within it) this
  // launch belongs to, if any — forwarded from gym_session_screen.dart's
  // _buildCardioPlaceholderCard via this screen's own incoming extra, and
  // re-forwarded into whichever cardio screen _handleStart() launches next
  // (see below). Both null when reached standalone (not from a plan).
  String? _sessionRunId;
  int? _blockIndex;
  String _goalType = 'time';
  int _goalMinutes = 30;
  late FixedExtentScrollController _durationController;

  @override
  void initState() {
    super.initState();
    _durationController = FixedExtentScrollController(
      initialItem: _goalMinutes - 1,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _readExtra());
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  void _readExtra() {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra == null) return;
    setState(() {
      _fromPlan = extra['fromPlan'] as bool? ?? false;
      _planActivity = extra['planActivity'] as String?;
      _planMinutes = extra['planMinutes'] as int?;
      _sessionRunId = extra['sessionRunId'] as String?;
      _blockIndex = extra['blockIndex'] as int?;
      if (_planActivity != null) _selectedActivity = _planActivity!;
    });
  }

  void _handleStart() {
    if (_selectedMode == 'outdoor') {
      // Temporary wiring: Routes.outdoorCardioTest only proves the map
      // renders and location permissions work (see OutdoorCardioScreen).
      // Once Phase A/B of outdoor GPS tracking are fully built, this
      // should push the real outdoor cardio route/flow instead, and the
      // temporary test route can be removed.
      context.push(
        Routes.outdoorCardioTest,
        extra: {
          'activity': _selectedActivity,
          'fromPlan': _fromPlan,
          'planActivity': _planActivity,
          'planMinutes': _planMinutes,
          'sessionRunId': _sessionRunId,
          'blockIndex': _blockIndex,
        },
      );
      return;
    }

    final effectiveGoalMinutes = _fromPlan
        ? (_planMinutes ?? 30)
        : (_goalType == 'time' ? _goalMinutes : 0);

    context.push(
      Routes.cardioSession,
      extra: {
        'activity': _selectedActivity,
        'mode': 'indoor',
        'plannedMinutes': effectiveGoalMinutes,
        'fromPlan': _fromPlan,
        'goalMinutes': effectiveGoalMinutes,
        'sessionRunId': _sessionRunId,
        'blockIndex': _blockIndex,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content — everything except the footer (plan info
            // row + Start button) below, so short screens (e.g. the
            // Small_Phone emulator profile) scroll instead of overflowing
            // once Activity/Mode/Goal/duration-picker no longer fit.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // ── Custom top row ───────────────────────────────────────────
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: WW.elevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.chevron_left_rounded,
                                color: WW.primaryDark,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Start Cardio',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: WW.primaryDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 38),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Activity section ─────────────────────────────────────────
                    const Text(
                      'ACTIVITY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: WW.textSec,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: _kActivities.map((activity) {
                        final isSelected = _selectedActivity == activity.id;
                        // Plan-launched cardio has its activity fixed by the plan
                        // block — lock the selector to that activity and grey out
                        // the other two, reusing the same WW.elevated/WW.textSec
                        // muted-disabled treatment as the cardio placeholder's
                        // Start button in gym_session_screen.dart's _readOnly gate,
                        // rather than inventing a new disabled style.
                        final isLockedOut =
                            _fromPlan && _planActivity != null && !isSelected;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: activity.id != 'Cycle' ? 8 : 0,
                            ),
                            child: GestureDetector(
                              onTap: isLockedOut
                                  ? null
                                  : () => setState(
                                      () => _selectedActivity = activity.id,
                                    ),
                              child: Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? activity.color.withValues(alpha: 0.12)
                                      : (isLockedOut ? WW.elevated : WW.card),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? activity.color
                                        : WW.border,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      activity.icon,
                                      size: 28,
                                      color: isLockedOut
                                          ? WW.textSec
                                          : activity.color,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      activity.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? activity.color
                                            : WW.textSec,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),

                    // ── Mode section ─────────────────────────────────────────────
                    const Text(
                      'MODE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: WW.textSec,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildModeCard(
                            id: 'indoor',
                            label: 'Indoor',
                            subtitle: 'Timer based',
                            icon: Icons.fitness_center_rounded,
                            color: WW.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildModeCard(
                            id: 'outdoor',
                            label: 'Outdoor',
                            subtitle: 'GPS tracking',
                            icon: Icons.map_rounded,
                            color: WW.teal,
                          ),
                        ),
                      ],
                    ),

                    if (!_fromPlan) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'GOAL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: WW.textSec,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Goal type toggle
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _goalType = 'time'),
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _goalType == 'time'
                                      ? WW.primary
                                      : WW.elevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'Set Duration',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _goalType == 'time'
                                          ? Colors.white
                                          : WW.textSec,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _goalType = 'open'),
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _goalType == 'open'
                                      ? WW.primary
                                      : WW.elevated,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    'Open-ended',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _goalType == 'open'
                                          ? Colors.white
                                          : WW.textSec,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Duration picker — only shown when goalType == 'time'
                      if (_goalType == 'time') ...[
                        const SizedBox(height: 12),
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: WW.elevated,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CupertinoPicker(
                            scrollController: _durationController,
                            itemExtent: 36,
                            onSelectedItemChanged: (index) {
                              setState(() => _goalMinutes = index + 1);
                            },
                            children: List.generate(
                              120,
                              (i) => Center(
                                child: Text(
                                  '${i + 1} min',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: WW.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Fixed footer — plan info row + Start button stay pinned to
            // the bottom of the screen (outside the scroll area) rather
            // than being pushed off it, matching how the Spacer() used to
            // anchor this on tall screens while still letting the content
            // above scroll on short ones.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  // ── Plan info row ────────────────────────────────────
                  if (_fromPlan && _planMinutes != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WW.chipBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: WW.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Suggested duration: $_planMinutes min',
                            style: const TextStyle(
                              fontSize: 13,
                              color: WW.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Start button ─────────────────────────────────────
                  GestureDetector(
                    onTap: _handleStart,
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        color: WW.primary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: WW.primary.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _fromPlan
                              ? 'Start $_selectedActivity · Indoor'
                              : _goalType == 'time'
                              ? 'Start · $_goalMinutes min'
                              : 'Start · Open Run',
                          style: const TextStyle(
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
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required String id,
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedMode == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = id),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : WW.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : WW.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? color : WW.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: WW.textSec),
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
