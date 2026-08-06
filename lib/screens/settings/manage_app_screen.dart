// lib/screens/settings/manage_app_screen.dart
// Settings > "Manage App" — per-category toggles for the health data
// WiseWorkout reads via HealthService (HealthDataType.HEART_RATE/STEPS/
// ACTIVE_ENERGY_BURNED, see HealthService._readTypes). Each toggle is backed
// by users/{uid}.healthCategoriesEnabled (read/written via
// FirestoreService.isHealthCategoryEnabled()/updateUserProfile()), defaulting
// to true so existing users see no behavior change until they actively
// switch something off.
//
// This does NOT reflect real HealthKit permission state — Apple deliberately
// never discloses whether READ access was granted for a given type (see
// package:health's hasPermissions() doc comment), so there is no OS-level
// state to read here. Toggling off only stops WiseWorkout's own call sites
// (see cardio_session_screen.dart / outdoor_cardio_screen.dart) from using
// that category — it can't revoke HealthKit access itself, which iOS also
// has no API for (see package:health's revokePermissions() doc comment:
// Android-only). The footer note below makes that distinction explicit.
//
// iOS-focused for now — Android's "Google Health Connect" button in
// onboarding is a UI stub with no real permission request behind it, so
// these toggles just gate Firestore-side usage on Android too, for
// consistency, rather than reflecting any real platform permission there.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

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
  bool _stepsEnabled = true;
  bool _activeCaloriesEnabled = true;

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
          _stepsEnabled = categories?['steps'] as bool? ?? true;
          _activeCaloriesEnabled =
              categories?['activeCalories'] as bool? ?? true;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Always writes the full 3-key map — this screen is the only writer of
  // healthCategoriesEnabled and always holds all 3 values in memory, so a
  // full overwrite here can never clobber a key some other caller set.
  Future<void> _savePrefs() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.updateUserProfile(uid, {
        'healthCategoriesEnabled': {
          'heartRate': _heartRateEnabled,
          'steps': _stepsEnabled,
          'activeCalories': _activeCaloriesEnabled,
        },
      });
    } catch (_) {}
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
                                  subtitle: 'Live heart rate during workouts.',
                                  value: _heartRateEnabled,
                                  first: true,
                                  onChanged: (v) {
                                    setState(() => _heartRateEnabled = v);
                                    _savePrefs();
                                  },
                                ),
                                _toggleRow(
                                  icon: Icons.directions_walk_rounded,
                                  title: 'Steps',
                                  subtitle: 'Daily step count.',
                                  value: _stepsEnabled,
                                  onChanged: (v) {
                                    setState(() => _stepsEnabled = v);
                                    _savePrefs();
                                  },
                                ),
                                _toggleRow(
                                  icon: Icons.local_fire_department_rounded,
                                  title: 'Active Calories',
                                  subtitle: 'Calories burned from Apple Health.',
                                  value: _activeCaloriesEnabled,
                                  onChanged: (v) {
                                    setState(() => _activeCaloriesEnabled = v);
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
  }) {
    return Container(
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
            onChanged: onChanged,
            activeTrackColor: WW.primary,
            inactiveTrackColor: WW.border,
          ),
        ],
      ),
    );
  }
}
