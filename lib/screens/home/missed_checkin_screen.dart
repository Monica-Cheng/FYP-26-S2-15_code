// lib/screens/home/missed_checkin_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Reason model ───────────────────────────────────────────────────────────────

class _Reason {
  final String id;
  final IconData icon;
  final Color iconBg;
  final String label;
  final String sub;

  const _Reason({
    required this.id,
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.sub,
  });
}

const _kReasons = [
  _Reason(
    id: 'busy',
    icon: Icons.access_time_rounded,
    iconBg: WW.primary,
    label: 'Too busy',
    sub: 'Not enough time today',
  ),
  _Reason(
    id: 'sick',
    icon: Icons.thermostat_rounded,
    iconBg: Color(0xFFEF4444),
    label: 'Not feeling well',
    sub: 'Unwell or fatigued',
  ),
  _Reason(
    id: 'injured',
    icon: Icons.shield_outlined,
    iconBg: Color(0xFFF59E0B),
    label: 'Injured',
    sub: 'Something hurts — I need to adapt',
  ),
  _Reason(
    id: 'rest',
    icon: Icons.nightlight_round,
    iconBg: WW.teal,
    label: 'Needed rest',
    sub: 'Body needed a recovery day',
  ),
  _Reason(
    id: 'skip',
    icon: Icons.skip_next_rounded,
    iconBg: WW.textSec,
    label: 'Just skipped',
    sub: 'No particular reason',
  ),
];

// ── Screen ─────────────────────────────────────────────────────────────────────

class MissedCheckinScreen extends StatefulWidget {
  const MissedCheckinScreen({super.key});

  @override
  State<MissedCheckinScreen> createState() => _MissedCheckinScreenState();
}

class _MissedCheckinScreenState extends State<MissedCheckinScreen> {
  String? _selectedReason;
  bool _isLogging = false;

  String _planId = '';
  String _planName = '';
  int _missedDayIndex = 1;
  String? _existingDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readExtra());
  }

  void _readExtra() {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra == null) return;
    setState(() {
      _planId = extra['planId'] as String? ?? '';
      _planName = extra['planName'] as String? ?? '';
      _missedDayIndex = extra['missedDayIndex'] as int? ?? 1;
      _existingDate = extra['existingDate'] as String?;
    });
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

  Future<void> _handleLog() async {
    if (_selectedReason == null) {
      _snack('Please select a reason');
      return;
    }

    setState(() => _isLogging = true);

    try {
      final uid = AuthService().getCurrentUser()?.uid;
      if (uid != null && _planId.isNotEmpty) {
        await FirestoreService().logMissedSession(
          uid,
          _planId,
          _missedDayIndex,
          _selectedReason!,
          date: _existingDate,
        );
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isLogging = false);

    final advice = _adviceFor(_selectedReason!);
    _snack(advice);
    context.pop();
  }

  String _adviceFor(String reason) {
    switch (reason) {
      case 'busy':
        return 'Tip: You can compress today\'s session in Plan Schedule to save time.';
      case 'sick':
        return 'Take care! You can activate Break Mode in Plan Schedule.';
      case 'injured':
        return 'Stay safe. Consider Break Mode or speak to a professional.';
      case 'rest':
        return 'Rest is part of training. Resume when ready.';
      case 'skip':
      default:
        return 'Logged. Let\'s get back on track!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      appBar: AppBar(
        backgroundColor: WW.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: const Icon(Icons.chevron_left_rounded,
              color: WW.primaryDark, size: 28),
        ),
        title: const Text(
          'Missed Workout',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subtitle
              Center(
                child: Text(
                  'Day $_missedDayIndex · $_planName',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // What happened heading
              const Text(
                'What happened?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 14),

              // Reason cards
              Expanded(
                child: ListView(
                  children: _kReasons.map((reason) => _buildReasonCard(reason)).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Log & Continue button
              GestureDetector(
                onTap: _isLogging ? null : _handleLog,
                child: Container(
                  width: double.infinity,
                  height: 50,
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
                    child: _isLogging
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Log & Continue',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Skip link
              Center(
                child: GestureDetector(
                  onTap: () => context.pop(),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WW.textSec,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasonCard(_Reason reason) {
    final selected = _selectedReason == reason.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? WW.primary : WW.border,
          width: selected ? 2 : 1,
        ),
        boxShadow: WW.shadow,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: reason.iconBg.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(reason.icon, color: reason.iconBg, size: 22),
        ),
        title: Text(
          reason.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
        subtitle: Text(
          reason.sub,
          style: const TextStyle(fontSize: 12, color: WW.textSec),
        ),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded,
                color: WW.primary, size: 20)
            : null,
        onTap: () => setState(() => _selectedReason = reason.id),
      ),
    );
  }
}
