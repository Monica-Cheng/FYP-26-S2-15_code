// lib/screens/onboarding/onboarding_step1_screen.dart
// Onboarding Step 1 — two sub-sections:
//   Sub-step 0: Health connection
//   Sub-step 1: Body profile form
// Saves via FirestoreService.saveOnboardingStep1() then navigates to Routes.onboardingStep2.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/health_service.dart';

class OnboardingStep1Screen extends StatefulWidget {
  const OnboardingStep1Screen({super.key});

  @override
  State<OnboardingStep1Screen> createState() => _OnboardingStep1ScreenState();
}

class _OnboardingStep1ScreenState extends State<OnboardingStep1Screen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _usernameFocusNode = FocusNode();

  String? _usernameError;
  bool _usernameChecking = false;
  bool _usernameValid = false;

  int _subStep = 0;
  String _displayName = '';
  DateTime? _dob;
  String _biologicalSex = '';
  double? _heightCm;
  double? _weightKg;
  String _heightUnit = 'cm';
  String _weightUnit = 'kg';
  bool _isLoading = false;
  Map<String, bool> _connected = {
    'apple': false,
    'google': false,
  };
  bool _healthGranted = false;

  @override
  void initState() {
    super.initState();
    _usernameFocusNode.addListener(_onUsernameFocusChange);
  }

  @override
  void dispose() {
    _usernameFocusNode.removeListener(_onUsernameFocusChange);
    _usernameFocusNode.dispose();
    _displayNameController.dispose();
    _usernameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // On-blur username validation — runs format checks, then the async
  // uniqueness check, updating inline state for _buildBodySection() to show.
  // ---------------------------------------------------------------------------
  void _onUsernameFocusChange() {
    if (_usernameFocusNode.hasFocus) return;
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() {
        _usernameError = null;
        _usernameValid = false;
        _usernameChecking = false;
      });
      return;
    }
    _validateUsernameInline(username);
  }

  Future<void> _validateUsernameInline(String username) async {
    if (username.length < 3 || username.length > 20) {
      setState(() {
        _usernameError = 'Username must be between 3 and 20 characters.';
        _usernameValid = false;
        _usernameChecking = false;
      });
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() {
        _usernameError =
            'Username can only contain lowercase letters, numbers, and underscores.';
        _usernameValid = false;
        _usernameChecking = false;
      });
      return;
    }
    setState(() {
      _usernameError = null;
      _usernameChecking = true;
      _usernameValid = false;
    });
    try {
      final isTaken = await _firestoreService.isUsernameTaken(username);
      if (!mounted) return;
      setState(() {
        _usernameChecking = false;
        if (isTaken) {
          _usernameError = 'That username is already taken.';
          _usernameValid = false;
        } else {
          _usernameError = null;
          _usernameValid = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _usernameChecking = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Opens native date picker and stores the result.
  // ---------------------------------------------------------------------------
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20),
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 5),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: WW.primary,
            onPrimary: Colors.white,
            surface: WW.card,
            onSurface: WW.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  // ---------------------------------------------------------------------------
  // Apple Health — requests real HealthKit permissions via HealthService.
  // ---------------------------------------------------------------------------
  Future<void> _handleAppleHealth() async {
    final granted = await HealthService().requestPermissions();
    if (!mounted) return;
    setState(() => _connected['apple'] = true);
    if (granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apple Health connected successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apple Health connected. You can manage permissions in Settings → Health.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    _checkAllConnected();
  }

  void _handleGoogleHealth() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Health Connect is available on Android devices.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() => _connected['google'] = true);
    _checkAllConnected();
  }

  void _handleGoogleHealthUnsupported() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Health Connect is only available on Android devices.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _checkAllConnected() {
    if (_connected.values.every((v) => v)) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _subStep = 1);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Validates, converts units, saves to Firestore, and navigates forward.
  // ---------------------------------------------------------------------------
  Future<void> _handleNext() async {
    if (_displayNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your display name.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a username.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (username.length < 3 || username.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Username must be between 3 and 20 characters.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Username can only contain lowercase letters, numbers, and underscores.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      final isTaken = await _firestoreService.isUsernameTaken(username);
      if (isTaken) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That username is already taken.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Convert to metric for storage regardless of display unit.
      final rawHeight = double.tryParse(_heightController.text.trim());
      final rawWeight = double.tryParse(_weightController.text.trim());
      final heightCm =
          rawHeight == null ? null : (_heightUnit == 'cm' ? rawHeight : rawHeight * 2.54);
      final weightKg =
          rawWeight == null ? null : (_weightUnit == 'kg' ? rawWeight : rawWeight * 0.453592);

      final data = <String, dynamic>{
        'displayName': _displayNameController.text.trim(),
        'username': username,
        if (_dob != null) 'dob': _dob!.toIso8601String(),
        if (_biologicalSex.isNotEmpty) 'biologicalSex': _biologicalSex,
        if (heightCm != null) 'heightCm': heightCm,
        if (weightKg != null) 'weightKg': weightKg,
        'preferredUnits': _heightUnit == 'cm' ? 'metric' : 'imperial',
        'healthConnected':
            _connected['apple'] == true || _connected['google'] == true,
      };

      await _firestoreService.saveOnboardingStep1(uid, data);
      if (mounted) context.go(Routes.onboardingStep2);
    } catch (e) {
      // Was a bare `catch (_)` that silently discarded the exception —
      // this step's failure (e.g. a Firestore PERMISSION_DENIED from a
      // rules regression) was previously indistinguishable from any other
      // failure, both in the console and to the user. Logged here so a
      // future issue like that shows up immediately instead of needing to
      // be independently investigated from scratch.
      print('onboarding_step1_screen: save failed: $e');
      if (mounted) {
        final isNetworkError = e is SocketException ||
            e.toString().toLowerCase().contains('network');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNetworkError
                  ? 'No internet connection. Please check your connection and try again.'
                  : 'Something went wrong saving your profile. Please try again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    VoidCallback? onBack;
    if (_subStep == 1) {
      onBack = () => setState(() => _subStep = 0);
    }
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(subStep: _subStep, onBack: onBack),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  )),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _subStep == 0
                    ? KeyedSubtree(
                        key: const ValueKey('health'),
                        child: _buildHealthSection(),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('body'),
                        child: _buildBodySection(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sub-step 0: Health connection ─────────────────────────────────────────

  Widget _buildHealthSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect your\nhealth data',
            style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w800,
              color: WW.primaryDark, letterSpacing: -0.5, height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Link Apple Health to get personalised insights and automatic workout syncing.',
            style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.6),
          ),
          const SizedBox(height: 28),
          _HealthCard(
            icon: _AppleHealthIcon(),
            title: 'Apple Health',
            description: 'Sync heart rate, steps, sleep, and workouts.',
            isConnected: _connected['apple']!,
            onConnect: _handleAppleHealth,
          ),
          const SizedBox(height: 12),
          _HealthCard(
            icon: _GoogleHealthIcon(),
            title: 'Google Health Connect',
            description: Platform.isIOS
                ? 'Available on Android devices only.'
                : 'Access fitness and wellness data on Android.',
            isConnected: _connected['google']!,
            onConnect: Platform.isIOS ? _handleGoogleHealthUnsupported : _handleGoogleHealth,
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => setState(() => _subStep = 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: WW.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () => setState(() => _subStep = 1),
              child: const Text('Skip for now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WW.textSec)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-step 1: Body profile form ────────────────────────────────────────

  Widget _buildBodySection() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tell us about you',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: WW.primaryDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This helps personalise your plan and track progress accurately.',
                  style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.6),
                ),
                const SizedBox(height: 24),

                // ── Display Name ──────────────────────────────────────────────
                _FieldLabel('Display Name'),
                const SizedBox(height: 6),
                _PlainTextField(
                  controller: _displayNameController,
                  hint: 'e.g. Alex',
                  onChanged: (v) => setState(() => _displayName = v),
                ),
                const SizedBox(height: 16),

                // ── Username ──────────────────────────────────────────────────
                _FieldLabel('Username'),
                const SizedBox(height: 6),
                _PlainTextField(
                  controller: _usernameController,
                  hint: 'e.g. alex_92',
                  focusNode: _usernameFocusNode,
                ),
                if (_usernameChecking) ...[
                  const SizedBox(height: 6),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: WW.primary,
                    ),
                  ),
                ] else if (_usernameError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _usernameError!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                  ),
                ] else if (_usernameValid) ...[
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: Color(0xFF22C55E),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Date of Birth ─────────────────────────────────────────────
                _FieldLabel('Date of Birth'),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: WW.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WW.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dob != null
                                ? DateFormat('dd MMM yyyy').format(_dob!)
                                : 'Select date',
                            style: TextStyle(
                              fontSize: 15,
                              color: _dob != null ? WW.text : WW.textSec,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.calendar_today_outlined,
                          color: WW.textSec,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Biological Sex ────────────────────────────────────────────
                _FieldLabel('Biological Sex'),
                const SizedBox(height: 8),
                _SegmentedChips(
                  options: const ['Male', 'Female', 'Prefer not to say'],
                  selected: _biologicalSex,
                  onSelect: (v) => setState(() => _biologicalSex = v),
                ),
                const SizedBox(height: 16),

                // ── Height ────────────────────────────────────────────────────
                _FieldLabel('Height'),
                const SizedBox(height: 6),
                _UnitTextField(
                  controller: _heightController,
                  hint: _heightUnit == 'cm' ? '175' : '69',
                  unitA: 'cm',
                  unitB: 'ft',
                  selectedUnit: _heightUnit,
                  onUnitToggle: (u) => setState(() => _heightUnit = u),
                ),
                const SizedBox(height: 16),

                // ── Weight ────────────────────────────────────────────────────
                _FieldLabel('Weight'),
                const SizedBox(height: 6),
                _UnitTextField(
                  controller: _weightController,
                  hint: _weightUnit == 'kg' ? '70' : '154',
                  unitA: 'kg',
                  unitB: 'lbs',
                  selectedUnit: _weightUnit,
                  onUnitToggle: (u) => setState(() => _weightUnit = u),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // ── Sticky footer — Next button ───────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: WW.bg,
            border: Border(top: BorderSide(color: WW.border, width: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: WW.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: WW.primary.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Next',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

}

// ── Progress header ────────────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  final int subStep;
  final VoidCallback? onBack;
  const _ProgressHeader({required this.subStep, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (onBack != null)
                GestureDetector(
                  onTap: onBack,
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: WW.textSec),
                )
              else
                const Text(
                  'Step 1 of 2',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WW.textSec,
                    letterSpacing: 0.3,
                  ),
                ),
              // Two dot indicators — first dot is elongated to show active
              Row(
                children: List.generate(2, (i) {
                  final active = i == 0;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(left: 6),
                    width: active ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? WW.primary : WW.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: const LinearProgressIndicator(
              value: 1 / 3,
              backgroundColor: WW.elevated,
              color: WW.primary,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Field label ────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: WW.text,
      ),
    );
  }
}

// ── Health connection card ─────────────────────────────────────────────────────

class _HealthCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String description;
  final bool isConnected;
  final VoidCallback onConnect;

  const _HealthCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isConnected,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: WW.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WW.textSec,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          isConnected
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 14, color: Color(0xFF16A34A)),
                      SizedBox(width: 4),
                      Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                )
              : TextButton(
                  onPressed: onConnect,
                  style: TextButton.styleFrom(
                    backgroundColor: WW.chipBg,
                    foregroundColor: WW.primary,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Connect',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Segmented chip selector ────────────────────────────────────────────────────

class _SegmentedChips extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  const _SegmentedChips({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: options.map((o) {
          final active = selected == o;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 38,
                decoration: BoxDecoration(
                  color: active ? WW.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active ? WW.shadow : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  o,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? WW.primary : WW.textSec,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Plain text input ───────────────────────────────────────────────────────────

class _PlainTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final FocusNode? focusNode;

  const _PlainTextField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: WW.border),
    );
    return SizedBox(
      height: 50,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 15, color: WW.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 15, color: WW.textSec),
          filled: true,
          fillColor: WW.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: WW.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ── Number input with inline unit toggle ──────────────────────────────────────

class _UnitTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String unitA;
  final String unitB;
  final String selectedUnit;
  final ValueChanged<String> onUnitToggle;

  const _UnitTextField({
    required this.controller,
    required this.hint,
    required this.unitA,
    required this.unitB,
    required this.selectedUnit,
    required this.onUnitToggle,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: WW.border),
    );
    return SizedBox(
      height: 50,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 15, color: WW.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 15, color: WW.textSec),
          filled: true,
          fillColor: WW.card,
          contentPadding: const EdgeInsets.only(left: 14, right: 8),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: WW.primary, width: 1.5),
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.symmetric(vertical: 7),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [unitA, unitB].map((u) {
                  final active = selectedUnit == u;
                  return GestureDetector(
                    onTap: () => onUnitToggle(u),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: active ? WW.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        u,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : WW.textSec,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Health source icons ────────────────────────────────────────────────────────

class _AppleHealthIcon extends StatelessWidget {
  const _AppleHealthIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B8A), Color(0xFFFF2D55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF2D55).withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
    );
  }
}

class _GoogleHealthIcon extends StatelessWidget {
  const _GoogleHealthIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.health_and_safety_outlined,
        color: Color(0xFF34A853),
        size: 26,
      ),
    );
  }
}

