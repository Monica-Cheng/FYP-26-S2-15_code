// lib/screens/onboarding/onboarding_step1_screen.dart
// Onboarding Step 1 — two sub-sections:
//   Sub-step 0: Health & wearable connection
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
  String? _selectedWearable;
  bool _healthGranted = false;

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

  Future<void> _handleWearable() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _WearablePickerSheet(
        onSelected: (deviceName) {
          Navigator.pop(ctx);
          setState(() => _connected['wearable'] = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$deviceName connected via Apple Health.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _checkAllConnected();
        },
        onSkip: () => Navigator.pop(ctx),
      ),
    );
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
    VoidCallback? onBack;
    if (_subStep > 0 && _subStep < 4) {
      onBack = () => setState(() => _subStep = _subStep - 1);
    } else if (_subStep == 4) {
      onBack = _selectedWearable != null
          ? () => setState(() => _subStep = 3)
          : () => setState(() => _subStep = 0);
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
                    : _subStep == 1
                        ? KeyedSubtree(
                            key: const ValueKey('wearables'),
                            child: _buildWearablesSection(),
                          )
                        : _subStep == 2
                            ? KeyedSubtree(
                                key: const ValueKey('checklist'),
                                child: _buildChecklistSection(),
                              )
                            : _subStep == 3
                                ? KeyedSubtree(
                                    key: const ValueKey('complete'),
                                    child: _buildCompleteSection(),
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
              onTap: () => setState(() => _subStep = 4),
              child: const Text('Skip for now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WW.textSec)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-step 4: Body profile form ────────────────────────────────────────

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

  // ── Sub-step 1: Wearable picker ──────────────────────────────────────────

  Widget _buildWearablesSection() {
    final devices = [
      {'id': 'apple', 'name': 'Apple Watch', 'desc': 'Connect via Apple Health'},
      {'id': 'samsung', 'name': 'Samsung Galaxy Watch', 'desc': 'Connect via Samsung Health'},
      {'id': 'garmin', 'name': 'Garmin', 'desc': 'Connect via Garmin Connect'},
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Connect a\nWearable',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
              color: WW.primaryDark, letterSpacing: -0.5, height: 1.2)),
          const SizedBox(height: 8),
          const Text('Choose your device to sync workout and health data automatically.',
            style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.6)),
          const SizedBox(height: 28),
          ...devices.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedWearable = d['id'];
                  _connected['wearable'] = true;
                  _subStep = 2;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WW.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: WW.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: WW.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.watch_rounded, color: WW.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['name']!, style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: WW.text)),
                          const SizedBox(height: 2),
                          Text(d['desc']!, style: const TextStyle(
                            fontSize: 12, color: WW.textSec)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: WW.textSec, size: 20),
                  ],
                ),
              ),
            ),
          )),
          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              onTap: () => setState(() => _subStep = 4),
              child: const Text('Skip for now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WW.textSec)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-step 2: Wearable setup checklist ─────────────────────────────────

  Widget _buildChecklistSection() {
    final deviceName = _selectedWearable == 'apple' ? 'Apple Watch'
        : _selectedWearable == 'samsung' ? 'Samsung Galaxy Watch' : 'Garmin';
    final steps = [
      'Open the companion app on your phone',
      'Grant WiseWorkout health & fitness permissions',
      'Enable workout and activity data sync',
      'You\'re all set — start your first tracked workout',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set up\n$deviceName',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
              color: WW.primaryDark, letterSpacing: -0.5, height: 1.2)),
          const SizedBox(height: 8),
          const Text('Follow these steps to complete your wearable setup.',
            style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.6)),
          const SizedBox(height: 28),
          ...steps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: WW.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${e.key + 1}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: WW.primary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(e.value,
                      style: const TextStyle(fontSize: 14, color: WW.text, height: 1.5)),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => setState(() => _subStep = 3),
              style: ElevatedButton.styleFrom(
                backgroundColor: WW.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text("I've done this", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-step 3: Wearable connected confirmation ───────────────────────────

  Widget _buildCompleteSection() {
    final deviceName = _selectedWearable == 'apple' ? 'Apple Watch'
        : _selectedWearable == 'samsung' ? 'Samsung Galaxy Watch' : 'Garmin';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: WW.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.watch_rounded, color: WW.primary, size: 52),
          ),
          const SizedBox(height: 24),
          Text("$deviceName\nConnected!",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
              color: WW.primaryDark, letterSpacing: -0.5, height: 1.2)),
          const SizedBox(height: 12),
          const Text('Your wearable is set up. WiseWorkout will now sync your workout and health data automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.6)),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => setState(() => _subStep = 4),
              style: ElevatedButton.styleFrom(
                backgroundColor: WW.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
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

// ── Wearable picker bottom sheet ──────────────────────────────────────────────

class _WearablePickerSheet extends StatelessWidget {
  final void Function(String deviceName) onSelected;
  final VoidCallback onSkip;

  const _WearablePickerSheet({
    required this.onSelected,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final devices = [
      {'id': 'apple', 'name': 'Apple Watch', 'desc': 'Connect via Apple Health', 'icon': Icons.watch_rounded, 'color': const Color(0xFF6C7EE8)},
      {'id': 'samsung', 'name': 'Samsung Galaxy Watch', 'desc': 'Connect via Samsung Health', 'icon': Icons.watch_rounded, 'color': const Color(0xFF1A6FD4)},
      {'id': 'garmin', 'name': 'Garmin', 'desc': 'Connect via Garmin Connect', 'icon': Icons.watch_rounded, 'color': const Color(0xFF007CC0)},
    ];

    return Padding(
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
            'Connect a Wearable',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WW.primaryDark),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose your device to sync workout and health data.',
            style: TextStyle(fontSize: 13, color: WW.textSec, height: 1.5),
          ),
          const SizedBox(height: 20),
          ...devices.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => onSelected(d['name'] as String),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WW.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: WW.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: (d['color'] as Color).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(d['icon'] as IconData, color: d['color'] as Color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['name'] as String,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: WW.text)),
                          const SizedBox(height: 2),
                          Text(d['desc'] as String,
                            style: const TextStyle(fontSize: 12, color: WW.textSec)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: WW.textSec, size: 20),
                  ],
                ),
              ),
            ),
          )),
          Center(
            child: GestureDetector(
              onTap: onSkip,
              child: const Text(
                'Skip for now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WW.textSec),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
