// lib/screens/settings/manage_app_screen.dart
// Settings > "Manage App" — a single Heart Rate toggle for the health data
// WiseWorkout reads via HealthService (HealthDataType.HEART_RATE — the only
// category any real call site checks; Steps/Active Calories toggles were
// removed since nothing in the app ever read HealthService.getTodaySteps()/
// getTodayCalories() or their corresponding healthCategoriesEnabled keys —
// confirmed via a repo-wide grep before deleting). Backed by
// users/{uid}.healthCategoriesEnabled.heartRate (read/written via
// FirestoreService.isHealthCategoryEnabled()/updateUserProfile()), defaulting
// to true so existing users see no behavior change until they actively
// switch it off.
//
// This does NOT reflect real HealthKit/Health Connect permission state.
// Apple deliberately never discloses whether READ access was granted for a
// type (see package:health's hasPermissions() doc comment), so there is no
// OS-level state to read on iOS; Android's Health Connect *can* disclose
// real grant state, but this screen doesn't query it either — same
// Firestore-boolean-only design on both platforms. Toggling off only stops
// WiseWorkout's own call sites (see cardio_session_screen.dart /
// outdoor_cardio_screen.dart) from using that category — it can't revoke
// HealthKit access itself, which iOS also has no API for (see package:
// health's revokePermissions() doc comment: Android-only). The footer note
// below makes that distinction explicit.
//
// The toggle is locked (greyed out, tap shows a "Connect" snackbar) whenever
// users/{uid}.healthConnected is false/missing. The snackbar's Connect
// action calls HealthService().requestPermissions() directly, in place —
// same real HealthKit/Health Connect request onboarding's health-connect
// step performs (see onboarding_step1_screen.dart's _handleConnectHealth) —
// rather than navigating into onboarding to trigger it. Navigating there
// previously dropped the user into unrelated onboarding UI (and its
// unrelated profile-creation form if they kept tapping through), and left
// this screen showing stale locked state on return since nothing here ever
// re-read Firestore after the fact. Connecting in place with an immediate
// setState avoids both problems.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/health_service.dart';

const _kDivider = Color(0xFFE8EAF8);

class ManageAppScreen extends StatefulWidget {
  const ManageAppScreen({super.key});

  @override
  State<ManageAppScreen> createState() => _ManageAppScreenState();
}

class _ManageAppScreenState extends State<ManageAppScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();

  bool _isLoading = true;
  bool _heartRateEnabled = true;
  // Set from onboarding's `healthConnected` (see
  // onboarding_step1_screen.dart's _handleConnectHealth) — the Heart Rate
  // toggle below is locked until this is true, since there's nothing to
  // gate otherwise (no permission has ever been granted for this user).
  bool _healthConnected = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final profile = await _firestore.getUserProfile(uid);
      final categories =
          profile?['healthCategoriesEnabled'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _heartRateEnabled = categories?['heartRate'] as bool? ?? true;
          _healthConnected = profile?['healthConnected'] as bool? ?? false;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Only writes the heartRate key now — Steps/Active Calories were removed
  // (nothing in the app ever read them; see the investigation this session
  // started from). Still a full-map overwrite, same as before — this screen
  // remains the only writer of healthCategoriesEnabled, so that's safe.
  Future<void> _savePrefs() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.updateUserProfile(uid, {
        'healthCategoriesEnabled': {
          'heartRate': _heartRateEnabled,
        },
      });
    } catch (_) {}
  }

  // ── Locked-state prompt (health not connected yet) ──────────────────────

  void _promptConnectHealth() {
    final source = Platform.isIOS ? 'Apple Health' : 'Health Connect';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connect $source first to use this.'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Connect',
          onPressed: _handleConnectHealth,
        ),
      ),
    );
  }

  // Requests HealthKit (iOS) / Health Connect (Android) permissions right
  // here, no navigation — same call onboarding's own connect step makes
  // (see onboarding_step1_screen.dart's _handleConnectHealth). Only marks
  // connected, locally and in Firestore, if the grant actually succeeded;
  // the immediate setState is what makes the row unlock right away instead
  // of showing stale locked state until some future reload.
  Future<void> _handleConnectHealth() async {
    final granted = await HealthService().requestPermissions();
    if (!mounted) return;
    final source = Platform.isIOS ? 'Apple Health' : 'Health Connect';
    if (granted) {
      final uid = _auth.getCurrentUser()?.uid;
      if (uid != null) {
        try {
          await _firestore.updateUserProfile(uid, {'healthConnected': true});
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _healthConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$source connected successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't connect $source. You can try again anytime."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: WW.primary),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionHeader('Apple Health Data'),
                          Container(
                            decoration: WW.cardDecoration,
                            clipBehavior: Clip.hardEdge,
                            child: Column(
                              children: [
                                _toggleRow(
                                  icon: Icons.favorite_rounded,
                                  title: 'Heart Rate',
                                  subtitle: _healthConnected
                                      ? 'Live heart rate during workouts.'
                                      : Platform.isIOS
                                          ? 'Connect Apple Health first.'
                                          : 'Connect Health Connect first.',
                                  value: _heartRateEnabled,
                                  first: true,
                                  enabled: _healthConnected,
                                  onLockedTap: _promptConnectHealth,
                                  onChanged: (v) {
                                    setState(() => _heartRateEnabled = v);
                                    _savePrefs();
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: WW.bg,
                              border: Border.all(color: WW.border, width: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Turning a toggle off stops WiseWorkout from using '
                              "that data — it doesn't revoke Apple Health's own "
                              'permission. ${Platform.isIOS ? 'To fully remove access, go to iOS Settings → Health → Data Access & Devices → WiseWorkout.' : "Full permission management for connected health data lives in your device's system health settings."}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: WW.textSec,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
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
                  child: Icon(Icons.chevron_left_rounded,
                      size: 22, color: WW.textSec),
                ),
              ),
            ),
          ),
          const Text(
            'Manage App',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: WW.textSec,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool first = false,
    bool enabled = true,
    VoidCallback? onLockedTap,
  }) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: _kDivider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: WW.elevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Icon(icon, color: WW.primary, size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WW.textSec,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeTrackColor: WW.primary,
            inactiveTrackColor: WW.border,
          ),
        ],
      ),
    );

    if (enabled) return row;

    // Locked state — greys the whole row out and swallows taps into
    // onLockedTap (prompting the user to go connect) rather than letting
    // any tap reach the now-disabled CupertinoSwitch underneath.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onLockedTap,
      child: Opacity(
        opacity: 0.5,
        child: IgnorePointer(child: row),
      ),
    );
  }
}
