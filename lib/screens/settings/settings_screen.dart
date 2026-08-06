// lib/screens/settings/settings_screen.dart
// firebase_auth is imported here solely to catch FirebaseAuthException by
// type for UI error-message mapping (see _ChangeEmailSheetState's own
// _friendlyAuthError()) — same precedent as login_screen.dart. Every actual
// Auth call still goes through AuthService, never FirebaseAuth directly.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';

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
  TimeOfDay _reminderTime = const TimeOfDay(hour: 7, minute: 0);
  bool _streakAlerts = true;
  bool _wiseCoachMessages = true;
  bool _aiPersonalizationConsent = false;
  bool _leaderboardVisible = true;
  bool _prefsLoading = true;

  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _userEmail = _auth.getCurrentUser()?.email;
    _loadPrefs();
    NotificationService().init();
  }

  Future<void> _loadPrefs() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _prefsLoading = false);
      return;
    }
    try {
      final profile = await _firestore.getUserProfile(uid);
      if (!mounted) return;
      setState(() {
        _pushNotif = profile?['notificationsEnabled'] as bool? ?? true;
        _workoutReminders = profile?['workoutReminders'] as bool? ?? true;
        _streakAlerts = profile?['streakAlerts'] as bool? ?? true;
        _wiseCoachMessages = profile?['wiseCoachMessages'] as bool? ?? true;
        _aiPersonalizationConsent =
            profile?['aiPersonalizationConsent'] as bool? ?? false;
        _leaderboardVisible = profile?['leaderboardVisible'] as bool? ?? true;
        final savedHour = profile?['reminderHour'] as int?;
        final savedMinute = profile?['reminderMinute'] as int?;
        if (savedHour != null && savedMinute != null) {
          _reminderTime = TimeOfDay(hour: savedHour, minute: savedMinute);
        }
        _prefsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _prefsLoading = false);
    }
  }

  Future<void> _savePrefs() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.updateUserProfile(uid, {
        'notificationsEnabled': _pushNotif,
        'workoutReminders': _workoutReminders,
        'streakAlerts': _streakAlerts,
        'wiseCoachMessages': _wiseCoachMessages,
        'reminderHour': _reminderTime.hour,
        'reminderMinute': _reminderTime.minute,
      });
    } catch (_) {}
    if (_workoutReminders) {
      await NotificationService().scheduleDailyWorkoutReminder(_reminderTime);
    } else {
      await NotificationService().cancelWorkoutReminder();
    }
  }

  // Saved standalone (not bundled into _savePrefs()) for the same reason
  // as _onLeaderboardVisibilityToggle() below — also writes
  // hasSeenAiConsentPrompt: true so coach_screen.dart's one-time consent
  // dialog never re-prompts a user who already made this choice directly
  // from Settings instead of from that dialog.
  Future<void> _onAiPersonalizationToggle(bool val) async {
    setState(() => _aiPersonalizationConsent = val);
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.updateUserProfile(uid, {
        'aiPersonalizationConsent': val,
        'hasSeenAiConsentPrompt': true,
      });
    } catch (_) {}
  }

  // Saved standalone (not bundled into _savePrefs()) so toggling this
  // doesn't rewrite the four notification fields — matches the pattern
  // used by health_profile_screen.dart's _onCalorieToggle().
  Future<void> _onLeaderboardVisibilityToggle(bool val) async {
    setState(() => _leaderboardVisible = val);
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      await _firestore.updateUserProfile(uid, {'leaderboardVisible': val});
    } catch (_) {}
  }

  Future<void> _showReminderTimePicker() async {
    await NotificationService().requestPermissions();
    if (!mounted) return;
    TimeOfDay tempTime = _reminderTime;
    await showModalBottomSheet(
      context: context,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: WW.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Workout Reminder Time',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WW.primaryDark),
              ),
              const SizedBox(height: 6),
              const Text(
                'We will remind you to work out at this time every day.',
                style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 180,
                child: CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hm,
                  initialTimerDuration: Duration(
                    hours: tempTime.hour,
                    minutes: tempTime.minute,
                  ),
                  onTimerDurationChanged: (duration) {
                    setModalState(() {
                      tempTime = TimeOfDay(
                        hour: duration.inHours,
                        minute: duration.inMinutes % 60,
                      );
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    setState(() {
                      _reminderTime = tempTime;
                      _workoutReminders = true;
                    });
                    await NotificationService()
                        .scheduleDailyWorkoutReminder(tempTime);
                    await _savePrefs();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Reminder set for ${tempTime.format(context)}',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WW.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save Reminder',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String msg, {Duration duration = const Duration(seconds: 2)}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: WW.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: duration,
      ),
    );
  }

  // ── Change Email flow ────────────────────────────────────────────────────
  // A SINGLE showModalBottomSheet call for the entire flow — re-auth (Step 0)
  // -> new email entry (Step 1) -> submit, all handled inside
  // _ChangeEmailSheet's own State via plain setState. Exactly one route is
  // ever pushed. This replaces an earlier version that chained two separate
  // Navigator-pushed modals (pop the re-auth sheet, then push a new-email
  // sheet) — that pop-then-push was inherently racy against the popped
  // route's own still-in-progress teardown, and forcing a frame via
  // WidgetsBinding.scheduleFrame() to paper over the timing made it worse
  // (it forced an out-of-band frame that touched an already-disposed
  // TextEditingController mid-transition and rippled into other screens
  // still mounted lower in the Navigator stack). Folding every step into one
  // sheet removes the race at its source instead of timing around it.
  //
  // The sheet pops itself with the new email string once
  // AuthService.changeEmail() (-> verifyBeforeUpdateEmail()) has actually
  // succeeded, or null on cancel/dismiss. verifyBeforeUpdateEmail() is NOT
  // immediate — it only completes once the user clicks the link Firebase
  // sends to the NEW address — so the confirmation snack below (shown on
  // THIS screen, after the sheet is gone) must not claim the email already
  // changed.
  Future<void> _startChangeEmailFlow() async {
    if (_auth.getCurrentUser() == null) return;

    final newEmail = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ChangeEmailSheet(authService: _auth),
    );

    if (newEmail != null && mounted) {
      _snack(
        'Verification email sent to $newEmail. Your email will update '
        'once you confirm the link.',
        duration: const Duration(seconds: 5),
      );
    }
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
                        onTap: () => context.push(Routes.editProfile),
                      ),
                      _row(
                        icon: Icons.mail_rounded,
                        iconBg: WW.teal,
                        title: 'Change Email',
                        sub: _userEmail,
                        onTap: _startChangeEmailFlow,
                      ),
                      _row(
                        icon: Icons.favorite_rounded,
                        iconBg: _kRed,
                        title: 'Health Profile',
                        sub: 'Injuries, calorie goals, conditions',
                        onTap: () => context.push(Routes.healthProfile),
                      ),
                      _row(
                        icon: Icons.devices_rounded,
                        iconBg: WW.lavender,
                        title: 'Manage App',
                        sub: 'Apple Health data categories',
                        onTap: () => context.push(Routes.manageApp),
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
                        right: _valueText(
                          '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}',
                        ),
                        onTap: _showReminderTimePicker,
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
                    if (_prefsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(color: WW.primary),
                        ),
                      )
                    else
                      _sectionCard([
                        _row(
                          icon: Icons.notifications_rounded,
                          iconBg: WW.gold,
                          title: 'Push Notifications',
                          first: true,
                          chevron: false,
                          right: _buildToggle(_pushNotif, (v) {
                            setState(() => _pushNotif = v);
                            _savePrefs();
                          }),
                        ),
                        GestureDetector(
                          onTap: _showReminderTimePicker,
                          child: _row(
                            icon: Icons.fitness_center_rounded,
                            iconBg: WW.primary,
                            title: 'Workout Reminders',
                            chevron: false,
                            right: _buildToggle(_workoutReminders, (val) async {
                              if (val) {
                                await _showReminderTimePicker();
                              } else {
                                setState(() => _workoutReminders = false);
                                await NotificationService().cancelWorkoutReminder();
                                await _savePrefs();
                              }
                            }),
                          ),
                        ),
                        _row(
                          icon: Icons.local_fire_department_rounded,
                          iconBg: WW.teal,
                          title: 'Streak Alerts',
                          chevron: false,
                          right: _buildToggle(_streakAlerts, (v) {
                            setState(() => _streakAlerts = v);
                            _savePrefs();
                          }),
                        ),
                        _row(
                          icon: Icons.auto_awesome_rounded,
                          iconBg: WW.lavender,
                          title: 'WiseCoach Messages',
                          chevron: false,
                          right: _buildToggle(_wiseCoachMessages, (v) {
                            setState(() => _wiseCoachMessages = v);
                            _savePrefs();
                          }),
                        ),
                        _row(
                          icon: Icons.psychology_rounded,
                          iconBg: WW.lavender,
                          title: 'WiseCoach Personalization',
                          sub: 'Let WiseCoach use your training data',
                          chevron: false,
                          right: _buildToggle(
                              _aiPersonalizationConsent,
                              _onAiPersonalizationToggle),
                        ),
                      ]),
                    _sectionHeader('Community'),
                    _sectionCard([
                      _row(
                        icon: Icons.visibility_rounded,
                        iconBg: WW.lavender,
                        title: "Show me on Friends' Leaderboards",
                        first: true,
                        chevron: false,
                        right: _buildToggle(
                            _leaderboardVisible, _onLeaderboardVisibilityToggle),
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

// ── Change Email sheet ───────────────────────────────────────────────────
// Single-route, 2-step content for _startChangeEmailFlow() above.
//   Step 0 — re-authenticate: a password field for email/password users, or
//   a "Continue with Google" confirm for Google users (branches once on
//   authService.isGoogleSignInUser()).
//   Step 1 — enter + submit the new email (format-validated, then
//   AuthService.changeEmail()).
// Moving between steps is a plain setState — no nested Navigator push/pop —
// so exactly one route exists for this entire flow, start to finish. Pops
// itself (Navigator.pop(context, newEmail)) only once changeEmail() has
// actually succeeded; swipe-dismiss/tap-outside at any step just pops with
// the default null, which _startChangeEmailFlow() treats as "cancelled."
class _ChangeEmailSheet extends StatefulWidget {
  final AuthService authService;
  const _ChangeEmailSheet({required this.authService});

  @override
  State<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<_ChangeEmailSheet> {
  late final bool _isGoogleUser;
  int _step = 0;
  bool _isSubmitting = false;
  String? _errorText;

  // Owned entirely by this sheet's own widget lifecycle now — created once
  // here, disposed exactly once in this State's own dispose() below. No
  // outer screen method disposes these mid-flow anymore.
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isGoogleUser = widget.authService.isGoogleSignInUser();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorText = 'Please enter your password.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      await widget.authService.reauthenticateWithPassword(password);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _step = 1;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = _friendlyAuthError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      final credential = await widget.authService.reauthenticateWithGoogle();
      if (!mounted) return;
      if (credential == null) {
        // User cancelled the Google picker — same silent-cancel convention
        // as login_screen.dart's _handleGoogleLogin(); stay on this step so
        // they can tap Continue again rather than closing the whole sheet.
        setState(() => _isSubmitting = false);
        return;
      }
      setState(() {
        _isSubmitting = false;
        _step = 1;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = _friendlyAuthError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'Google re-authentication failed. Please try again.';
      });
    }
  }

  Future<void> _submitNewEmail() async {
    final email = _emailController.text.trim();
    if (!_isValidEmailFormat(email)) {
      setState(() => _errorText = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      await widget.authService.changeEmail(email);
      if (!mounted) return;
      Navigator.pop(context, email);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = _friendlyAuthError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'Something went wrong. Please try again.';
      });
    }
  }

  // Basic format check only — Firebase itself is the source of truth
  // (invalid-email below covers whatever this misses).
  bool _isValidEmailFormat(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  // Shared by both Step 0 (wrong-password) and Step 1
  // (email-already-in-use/invalid-email/requires-recent-login) — same
  // mapping style as login_screen.dart's _friendlyError().
  String _friendlyAuthError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again.';
      case 'requires-recent-login':
        return 'This action requires you to sign in again. Please try again.';
      case 'email-already-in-use':
        return 'That email is already in use by another account.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        40 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: WW.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ..._step == 0 ? _buildStep0() : _buildStep1(),
        ],
      ),
    );
  }

  List<Widget> _buildStep0() {
    if (_isGoogleUser) {
      return [
        const Text(
          'Confirm Your Identity',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: WW.primaryDark),
        ),
        const SizedBox(height: 6),
        const Text(
          'For your security, please sign in with Google again to continue.',
          style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.5),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(_errorText!, style: const TextStyle(fontSize: 12, color: _kRed)),
        ],
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Continue with Google',
          onPressed: _isSubmitting ? null : _submitGoogle,
        ),
      ];
    }
    return [
      const Text(
        'Confirm Your Password',
        style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: WW.primaryDark),
      ),
      const SizedBox(height: 6),
      const Text(
        'For your security, please re-enter your password to continue.',
        style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.5),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _passwordController,
        obscureText: true,
        autofocus: true,
        style: const TextStyle(fontSize: 15, color: WW.text),
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: const TextStyle(fontSize: 15, color: WW.textSec),
          filled: true,
          fillColor: WW.elevated,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      if (_errorText != null) ...[
        const SizedBox(height: 8),
        Text(_errorText!, style: const TextStyle(fontSize: 12, color: _kRed)),
      ],
      const SizedBox(height: 20),
      _primaryButton(
        label: 'Continue',
        onPressed: _isSubmitting ? null : _submitPassword,
      ),
    ];
  }

  List<Widget> _buildStep1() {
    return [
      const Text(
        'New Email Address',
        style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: WW.primaryDark),
      ),
      const SizedBox(height: 6),
      const Text(
        "We'll send a verification link to this address before it becomes "
        'your new email.',
        style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.5),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _emailController,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(fontSize: 15, color: WW.text),
        decoration: InputDecoration(
          hintText: 'New email address',
          hintStyle: const TextStyle(fontSize: 15, color: WW.textSec),
          filled: true,
          fillColor: WW.elevated,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      if (_errorText != null) ...[
        const SizedBox(height: 8),
        Text(_errorText!, style: const TextStyle(fontSize: 12, color: _kRed)),
      ],
      const SizedBox(height: 20),
      _primaryButton(
        label: 'Send Verification Link',
        onPressed: _isSubmitting ? null : _submitNewEmail,
      ),
    ];
  }

  Widget _primaryButton({required String label, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: WW.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: WW.primary.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
