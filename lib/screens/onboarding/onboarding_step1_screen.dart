// lib/screens/onboarding/onboarding_step1_screen.dart
// Onboarding Step 1 — two sub-sections:
//   Sub-step 0: Health & wearable connection
//   Sub-step 1: Body profile form
// Saves via FirestoreService.saveOnboardingStep1() then navigates to Routes.onboardingStep2.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

class OnboardingStep1Screen extends StatefulWidget {
  const OnboardingStep1Screen({super.key});

  @override
  State<OnboardingStep1Screen> createState() => _OnboardingStep1ScreenState();
}

class _OnboardingStep1ScreenState extends State<OnboardingStep1Screen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _displayNameController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

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
    'wearable': false,
  };

  @override
  void dispose() {
    _displayNameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
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
  // Marks a health source as connected and auto-advances when all three done.
  // Always shows a Snackbar because actual SDK integration is not yet available.
  // ---------------------------------------------------------------------------
  void _handleConnect(String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This feature connects on your device type. Setup will be available in a future update.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() {
      _connected[key] = true;
      if (_connected.values.every((v) => v)) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _subStep = 1);
        });
      }
    });
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

    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      // Convert to metric for storage regardless of display unit.
      final rawHeight = double.tryParse(_heightController.text.trim());
      final rawWeight = double.tryParse(_weightController.text.trim());
      final heightCm =
          rawHeight == null ? null : (_heightUnit == 'cm' ? rawHeight : rawHeight * 2.54);
      final weightKg =
          rawWeight == null ? null : (_weightUnit == 'kg' ? rawWeight : rawWeight * 0.453592);

      final data = <String, dynamic>{
        'displayName': _displayNameController.text.trim(),
        if (_dob != null) 'dob': _dob!.toIso8601String(),
        if (_biologicalSex.isNotEmpty) 'biologicalSex': _biologicalSex,
        if (heightCm != null) 'heightCm': heightCm,
        if (weightKg != null) 'weightKg': weightKg,
        'preferredUnits': _heightUnit == 'cm' ? 'metric' : 'imperial',
        'healthConnected':
            _connected['apple'] == true || _connected['google'] == true,
        'wearableConnected': _connected['wearable'] == true,
      };

      await _firestoreService.saveOnboardingStep1(uid, data);
      if (mounted) context.go(Routes.onboardingStep2);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
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
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(subStep: _subStep),
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

  // ── Sub-step 0: Health & wearable connection ─────────────────────────────

  Widget _buildHealthSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect your\nhealth data',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Link your health apps and devices to get personalised insights and automatic workout syncing.',
            style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.6),
          ),
          const SizedBox(height: 28),

          _HealthCard(
            icon: _AppleHealthIcon(),
            title: 'Apple Health',
            description: 'Sync heart rate, steps, sleep, and workouts.',
            isConnected: _connected['apple']!,
            onConnect: () => _handleConnect('apple'),
          ),
          const SizedBox(height: 12),

          _HealthCard(
            icon: _GoogleHealthIcon(),
            title: 'Google Health Connect',
            description: 'Access fitness and wellness data on Android.',
            isConnected: _connected['google']!,
            onConnect: () => _handleConnect('google'),
          ),
          const SizedBox(height: 12),

          _HealthCard(
            icon: _WearableIcon(),
            title: 'Wearable Device',
            description:
                'Connect Apple Watch, Garmin, Samsung Galaxy Watch and more.',
            isConnected: _connected['wearable']!,
            onConnect: () => _handleConnect('wearable'),
          ),
          const SizedBox(height: 36),

          Center(
            child: GestureDetector(
              onTap: () => setState(() => _subStep = 1),
              child: const Text(
                'Skip for now',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WW.textSec,
                ),
              ),
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
  const _ProgressHeader({required this.subStep});

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
              const Text(
                'Step 1 of 3',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WW.textSec,
                  letterSpacing: 0.3,
                ),
              ),
              // Three dot indicators — first dot is elongated to show active
              Row(
                children: List.generate(3, (i) {
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

  const _PlainTextField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType = TextInputType.text,
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

class _WearableIcon extends StatelessWidget {
  const _WearableIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.watch_rounded, color: WW.primary, size: 26),
    );
  }
}
