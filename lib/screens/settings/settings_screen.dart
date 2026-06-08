// lib/screens/settings/settings_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Danger red and support green — specific accent colors not in WW palette
const _kRed = Color(0xFFEF4444);
const _kGreen = Color(0xFF22C55E);

// ── Screen ────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();

  bool _pushNotif = true;
  bool _workoutReminders = true;
  bool _streakAlerts = true;
  bool _wiseCoachMessages = true;

  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _userEmail = _auth.getCurrentUser()?.email;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: WW.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleLogOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Log Out', style: const TextStyle(color: _kRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _auth.signOut();
    if (mounted) context.go(Routes.login);
  }

  Future<void> _onPushNotifChanged(bool val) async {
    setState(() => _pushNotif = val);
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.updateUserProfile(uid, {'pushNotificationsEnabled': val});
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionHeader('Account'),
                    _sectionCard([
                      _row(
                        icon: Icons.person_rounded,
                        iconBg: WW.primary,
                        title: 'Edit Profile',
                        sub: 'Name, username, photo, bio',
                        first: true,
                        onTap: () => _snack('Edit profile coming soon'),
                      ),
                      _row(
                        icon: Icons.mail_rounded,
                        iconBg: WW.teal,
                        title: 'Change Email',
                        sub: _userEmail,
                        onTap: () => _snack('Change email coming soon'),
                      ),
                      _row(
                        icon: Icons.favorite_rounded,
                        iconBg: _kRed,
                        title: 'Health Profile',
                        sub: 'Injuries, calorie goals, conditions',
                        onTap: () => _snack('Health profile coming soon'),
                      ),
                      _row(
                        icon: Icons.account_circle_rounded,
                        iconBg: WW.primary,
                        title: 'About You',
                        sub: 'Age, height, weight, sex',
                        onTap: () => _snack('About you coming soon'),
                      ),
                      _row(
                        icon: Icons.devices_rounded,
                        iconBg: WW.lavender,
                        title: 'Manage Apps & Devices',
                        sub: 'Apple Watch · Apple Health',
                        onTap: () => _snack('Manage devices coming soon'),
                      ),
                    ]),
                    _sectionHeader('Preferences'),
                    _sectionCard([
                      _row(
                        icon: Icons.straighten_rounded,
                        iconBg: WW.primary,
                        title: 'Units',
                        first: true,
                        right: _valueText('Metric'),
                        onTap: () => _snack('Units coming soon'),
                      ),
                      _row(
                        icon: Icons.access_time_rounded,
                        iconBg: WW.teal,
                        title: 'Preferred Workout Time',
                        right: _valueText('07:00'),
                        onTap: () => _snack('Workout time coming soon'),
                      ),
                      _row(
                        icon: Icons.local_fire_department_rounded,
                        iconBg: WW.gold,
                        title: 'Calorie Goals',
                        right: _valueText('Active'),
                        onTap: () => _snack('Calorie goals coming soon'),
                      ),
                    ]),
                    _sectionHeader('Notifications'),
                    _sectionCard([
                      _row(
                        icon: Icons.notifications_rounded,
                        iconBg: WW.gold,
                        title: 'Push Notifications',
                        first: true,
                        chevron: false,
                        right: _buildToggle(_pushNotif, _onPushNotifChanged),
                      ),
                      _row(
                        icon: Icons.fitness_center_rounded,
                        iconBg: WW.primary,
                        title: 'Workout Reminders',
                        chevron: false,
                        right: _buildToggle(
                          _workoutReminders,
                          (v) => setState(() => _workoutReminders = v),
                        ),
                      ),
                      _row(
                        icon: Icons.local_fire_department_rounded,
                        iconBg: WW.teal,
                        title: 'Streak Alerts',
                        chevron: false,
                        right: _buildToggle(
                          _streakAlerts,
                          (v) => setState(() => _streakAlerts = v),
                        ),
                      ),
                      _row(
                        icon: Icons.auto_awesome_rounded,
                        iconBg: WW.lavender,
                        title: 'WiseCoach Messages',
                        chevron: false,
                        right: _buildToggle(
                          _wiseCoachMessages,
                          (v) => setState(() => _wiseCoachMessages = v),
                        ),
                      ),
                    ]),
                    _sectionHeader('Community'),
                    _sectionCard([
                      _row(
                        icon: Icons.visibility_rounded,
                        iconBg: WW.lavender,
                        title: 'Profile Visibility',
                        first: true,
                        right: _valueText('Friends'),
                        onTap: () => _snack('Visibility coming soon'),
                      ),
                      _row(
                        icon: Icons.block_rounded,
                        iconBg: WW.lavender,
                        title: 'Blocked Users',
                        sub: '0 blocked',
                        onTap: () => _snack('Blocked users coming soon'),
                      ),
                    ]),
                    _sectionHeader('Support'),
                    _sectionCard([
                      _row(
                        icon: Icons.star_rounded,
                        iconBg: WW.gold,
                        title: 'Your Plan',
                        first: true,
                        right: _freeBadge(),
                        onTap: () => _snack('Upgrade coming soon'),
                      ),
                      _row(
                        icon: Icons.help_outline_rounded,
                        iconBg: _kGreen,
                        title: 'Help & FAQ',
                        sub: 'FAQs, contact, report a bug',
                        onTap: () => _snack('Help coming soon'),
                      ),
                      _row(
                        icon: Icons.shield_rounded,
                        iconBg: _kGreen,
                        title: 'Privacy Policy',
                        onTap: () => _snack('Privacy policy coming soon'),
                      ),
                      _row(
                        icon: Icons.info_outline_rounded,
                        iconBg: WW.elevated,
                        iconColor: WW.textSec,
                        title: 'App Version',
                        right: _valueText('v1.0.0'),
                        chevron: false,
                      ),
                    ]),
                    _sectionHeader('Danger Zone', danger: true),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: WW.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: WW.border, width: 0.5),
                        boxShadow: WW.shadow,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        children: [
                          _row(
                            icon: Icons.logout_rounded,
                            iconBg: WW.textSec,
                            title: 'Log Out',
                            first: true,
                            chevron: false,
                            onTap: _handleLogOut,
                          ),
                          _deleteRow(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
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
        border: Border(
          bottom: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
        ),
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
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 22,
                    color: WW.textSec,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            'Settings',
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

  // ── Row helpers ───────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: danger ? _kRed : WW.textSec,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WW.border, width: 0.5),
        boxShadow: WW.shadow,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: children),
    );
  }

  Widget _row({
    required String title,
    IconData? icon,
    Color? iconBg,
    Color iconColor = Colors.white,
    String? sub,
    Widget? right,
    bool chevron = true,
    bool first = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(
                  top: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg ?? WW.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(icon, size: 16, color: iconColor),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WW.text,
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WW.textSec,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (right != null) ...[
              const SizedBox(width: 8),
              right,
            ] else if (chevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: WW.border,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Delete account row — naked red icon, no icon box
  Widget _deleteRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _snack('Delete account coming soon'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.delete_rounded, size: 18, color: _kRed),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete or deactivate account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _kRed,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: _kRed),
          ],
        ),
      ),
    );
  }

  // ── Right-side widgets ────────────────────────────────────────────────────

  Widget _valueText(String val) {
    return Text(
      val,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: WW.textSec,
      ),
    );
  }

  Widget _freeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Free',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: WW.primary,
        ),
      ),
    );
  }

  Widget _buildToggle(bool value, ValueChanged<bool> onChanged) {
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: WW.primary,
      inactiveTrackColor: WW.border,
    );
  }
}
