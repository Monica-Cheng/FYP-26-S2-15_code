// lib/screens/settings/health_profile_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Non-WW accent colors used only in this screen
const _kGreen = Color(0xFF22C55E);          // calorie toggle active + success icon
const _kSuccessBg = Color(0xFFF0FDF4);      // success banner background
const _kSuccessBorder = Color(0xFF86EFAC);  // success banner border
const _kSuccessText = Color(0xFF166534);    // success banner text
const _kDivider = Color(0xFFE8EAF8);        // row dividers

// ── Screen ─────────────────────────────────────────────────────────────────────

class HealthProfileScreen extends StatefulWidget {
  const HealthProfileScreen({super.key});

  @override
  State<HealthProfileScreen> createState() => _HealthProfileScreenState();
}

class _HealthProfileScreenState extends State<HealthProfileScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();

  bool _isLoading = true;

  // ── Section A — Body ────────────────────────────────────────────────────────
  bool _editingBody = false;
  bool _isSavingBody = false;
  bool _showBodySuccess = false;

  // View-mode display values (formatted for display)
  String _vName = '';
  String _vDob = '';    // ISO-8601 date string e.g. '1999-03-12'
  String _vHeight = ''; // e.g. '178 cm'
  String _vWeight = ''; // e.g. '76.2 kg'
  String _vSex = '';

  // Edit-mode mutable state
  final _nameCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _biologicalSex = 'Male';
  String _heightUnit = 'cm';
  String _weightUnit = 'kg';
  DateTime? _dobDate;

  // ── Section C — Calorie Goals ──────────────────────────────────────────────
  bool _calorieGoalActive = false;
  bool _isSavingCalorie = false;
  bool _showCalorieSuccess = false;
  final _dailyCalCtrl = TextEditingController();
  final _weeklyCalCtrl = TextEditingController();
  final _monthlyCalCtrl = TextEditingController();
  final _goalWeightCtrl = TextEditingController();
  DateTime? _goalDate;

  // ── Section D — Preferences ────────────────────────────────────────────────
  String _prefGoal = '';
  String _prefSport = '';
  String _prefExperience = '';
  String _prefDays = '';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final data = await _firestore.getUserProfile(uid);
      if (!mounted) return;
      if (data != null) {
        final name = data['displayName'] as String? ?? '';
        final dobStr = data['dob'] as String? ?? '';
        final heightCm = data['heightCm']?.toString() ?? '';
        final weightKg = data['weightKg']?.toString() ?? '';
        final sex = (data['biologicalSex'] as String?)?.isNotEmpty == true
            ? data['biologicalSex'] as String
            : 'Male';
        final calorieActive = data['calorieGoalActive'] as bool? ?? false;
        final dailyCal = data['dailyCalorieGoal']?.toString() ?? '';
        final weeklyCal = data['weeklyCalorieGoal']?.toString() ?? '';
        final monthlyCal = data['monthlyCalorieGoal']?.toString() ?? '';
        final goalWeight = data['goalWeight']?.toString() ?? '';

        // goalDate may be a String (ISO) or Timestamp — handle both without
        // importing cloud_firestore directly in this widget.
        DateTime? goalDate;
        final goalDateRaw = data['goalDate'];
        if (goalDateRaw is String) {
          goalDate = DateTime.tryParse(goalDateRaw);
        } else if (goalDateRaw != null) {
          try {
            goalDate = (goalDateRaw as dynamic).toDate() as DateTime;
          } catch (_) {}
        }

        setState(() {
          _vName = name;
          _vDob = dobStr;
          _vHeight = heightCm.isNotEmpty ? '$heightCm cm' : '—';
          _vWeight = weightKg.isNotEmpty ? '$weightKg kg' : '—';
          _vSex = sex;

          _nameCtrl.text = name;
          _heightCtrl.text = heightCm;
          _weightCtrl.text = weightKg;
          _biologicalSex = sex;
          _dobDate = dobStr.isNotEmpty ? DateTime.tryParse(dobStr) : null;

          _calorieGoalActive = calorieActive;
          _dailyCalCtrl.text = dailyCal;
          _weeklyCalCtrl.text = weeklyCal;
          _monthlyCalCtrl.text = monthlyCal;
          _goalWeightCtrl.text = goalWeight;
          _goalDate = goalDate;

          _prefGoal = data['primaryGoal'] as String? ?? '';
          _prefSport = data['sportPreference'] as String? ?? '';
          _prefExperience = data['experienceLevel'] as String? ?? '';
          _prefDays = data['daysPerWeek']?.toString() ?? '';

          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _dailyCalCtrl.dispose();
    _weeklyCalCtrl.dispose();
    _monthlyCalCtrl.dispose();
    _goalWeightCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: WW.primaryDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  String _fmtDob(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // ── Section A actions ──────────────────────────────────────────────────────

  void _startBodyEdit() => setState(() {
    _editingBody = true;
    _showBodySuccess = false;
  });

  void _cancelBodyEdit() {
    // Strip unit label to recover raw number from view value
    final rawH = _vHeight.replaceAll(RegExp(r'[^0-9.]'), '');
    final rawW = _vWeight.replaceAll(RegExp(r'[^0-9.]'), '');
    _nameCtrl.text = _vName;
    _heightCtrl.text = rawH;
    _weightCtrl.text = rawW;
    setState(() {
      _editingBody = false;
      _heightUnit = 'cm';
      _weightUnit = 'kg';
      _biologicalSex = _vSex.isNotEmpty ? _vSex : 'Male';
      _dobDate = _vDob.isNotEmpty ? DateTime.tryParse(_vDob) : null;
    });
  }

  Future<void> _saveBodyMetrics() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;

    double? heightCm = double.tryParse(_heightCtrl.text);
    double? weightKg = double.tryParse(_weightCtrl.text);
    if (heightCm != null && _heightUnit == 'ft') heightCm = heightCm * 30.48;
    if (weightKg != null && _weightUnit == 'lb') weightKg = weightKg / 2.20462;

    setState(() => _isSavingBody = true);
    try {
      await _firestore.updateUserProfile(uid, {
        'displayName': _nameCtrl.text.trim(),
        if (_dobDate != null) 'dob': _dobDate!.toIso8601String().substring(0, 10),
        if (heightCm != null) 'heightCm': heightCm.round(),
        if (weightKg != null) 'weightKg': double.parse(weightKg.toStringAsFixed(1)),
        'biologicalSex': _biologicalSex,
      });
      if (!mounted) return;

      // Update controllers and view values to canonical cm/kg
      if (heightCm != null) _heightCtrl.text = heightCm.round().toString();
      if (weightKg != null) _weightCtrl.text = weightKg.toStringAsFixed(1);

      setState(() {
        _vName = _nameCtrl.text.trim();
        if (_dobDate != null) _vDob = _dobDate!.toIso8601String().substring(0, 10);
        if (heightCm != null) _vHeight = '${heightCm.round()} cm';
        if (weightKg != null) _vWeight = '${weightKg.toStringAsFixed(1)} kg';
        _vSex = _biologicalSex;
        _editingBody = false;
        _isSavingBody = false;
        _heightUnit = 'cm';
        _weightUnit = 'kg';
        _showBodySuccess = true;
      });
      Future.delayed(const Duration(seconds: 3),
          () { if (mounted) setState(() => _showBodySuccess = false); });
    } catch (_) {
      if (mounted) {
        setState(() => _isSavingBody = false);
        _snack('Failed to save. Please try again.');
      }
    }
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dobDate ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1930),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: WW.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dobDate = picked);
  }

  void _toggleHeightUnit(String unit) {
    if (unit == _heightUnit) return;
    final v = double.tryParse(_heightCtrl.text);
    if (v != null) {
      _heightCtrl.text = unit == 'ft'
          ? (v / 30.48).toStringAsFixed(1)
          : (v * 30.48).round().toString();
    }
    setState(() => _heightUnit = unit);
  }

  void _toggleWeightUnit(String unit) {
    if (unit == _weightUnit) return;
    final v = double.tryParse(_weightCtrl.text);
    if (v != null) {
      _weightCtrl.text = unit == 'lb'
          ? (v * 2.20462).toStringAsFixed(1)
          : (v / 2.20462).toStringAsFixed(1);
    }
    setState(() => _weightUnit = unit);
  }

  // ── Section C actions ──────────────────────────────────────────────────────

  Future<void> _onCalorieToggle(bool val) async {
    setState(() => _calorieGoalActive = val);
    if (!val) {
      final uid = _auth.getCurrentUser()?.uid;
      if (uid == null) return;
      try {
        await _firestore.updateUserProfile(uid, {'calorieGoalActive': false});
      } catch (_) {}
    }
  }

  void _autoCalcFromDaily() {
    final daily = int.tryParse(_dailyCalCtrl.text) ?? 0;
    if (daily > 0) {
      _weeklyCalCtrl.text = (daily * 7).toString();
      _monthlyCalCtrl.text = (daily * 28).toString();
    }
  }

  Future<void> _pickGoalDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _goalDate ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: WW.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _goalDate = picked);
  }

  Future<void> _saveCalorieGoals() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    setState(() => _isSavingCalorie = true);
    try {
      await _firestore.updateUserProfile(uid, {
        'calorieGoalActive': true,
        'dailyCalorieGoal': int.tryParse(_dailyCalCtrl.text),
        'weeklyCalorieGoal': int.tryParse(_weeklyCalCtrl.text),
        'monthlyCalorieGoal': int.tryParse(_monthlyCalCtrl.text),
        'goalWeight': double.tryParse(_goalWeightCtrl.text),
        'goalDate': _goalDate?.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      setState(() {
        _calorieGoalActive = true;
        _isSavingCalorie = false;
        _showCalorieSuccess = true;
      });
      Future.delayed(const Duration(seconds: 3),
          () { if (mounted) setState(() => _showCalorieSuccess = false); });
    } catch (_) {
      if (mounted) {
        setState(() => _isSavingCalorie = false);
        _snack('Failed to save goals. Please try again.');
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
                  ? const Center(child: CircularProgressIndicator(color: WW.primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSectionA(),
                          const SizedBox(height: 24),
                          _buildSectionB(),
                          const SizedBox(height: 24),
                          _buildSectionC(),
                          const SizedBox(height: 24),
                          _buildSectionD(),
                          const SizedBox(height: 24),
                          _buildFooter(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

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
                  child: Icon(Icons.chevron_left_rounded, size: 22, color: WW.textSec),
                ),
              ),
            ),
          ),
          const Text(
            'Health Profile',
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

  // ── Section A — Body Metrics ───────────────────────────────────────────────

  Widget _buildSectionA() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'Body Metrics',
          trailing: _editingBody
              ? null
              : GestureDetector(
                  onTap: _startBodyEdit,
                  child: const Text(
                    'Edit',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WW.primary,
                    ),
                  ),
                ),
        ),
        Container(
          decoration: WW.cardDecoration,
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              _buildAvatar(),
              if (_editingBody) _buildBodyEditMode() else _buildBodyViewMode(),
            ],
          ),
        ),
        if (_editingBody) ...[
          const SizedBox(height: 12),
          _saveBtn(
            label: 'Save changes',
            loading: _isSavingBody,
            onTap: _saveBodyMetrics,
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _cancelBodyEdit,
            child: const Center(
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
            ),
          ),
        ],
        if (_showBodySuccess) ...[
          const SizedBox(height: 10),
          _successBanner('Body metrics saved successfully.'),
        ],
      ],
    );
  }

  Widget _buildAvatar() {
    final initial = _vName.isNotEmpty ? _vName[0].toUpperCase() : 'U';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: WW.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (_editingBody)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _snack('Photo upload coming soon'),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_editingBody) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _snack('Photo upload coming soon'),
              child: const Text(
                'Change photo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: WW.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBodyViewMode() {
    return Column(
      children: [
        _viewRow('Display name', _vName.isNotEmpty ? _vName : '—', first: true),
        _viewRow('Date of birth', _vDob.isNotEmpty ? _fmtDob(_vDob) : '—'),
        _viewRow('Height', _vHeight.isNotEmpty ? _vHeight : '—'),
        _viewRow('Weight', _vWeight.isNotEmpty ? _vWeight : '—'),
        _viewRow('Biological sex', _vSex.isNotEmpty ? _vSex : '—'),
      ],
    );
  }

  Widget _buildBodyEditMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Display name
        _editRow(
          label: 'Display name',
          first: true,
          child: SizedBox(
            width: 160,
            child: _underlineField(
              controller: _nameCtrl,
              align: TextAlign.right,
            ),
          ),
        ),
        // Date of birth (tap to pick)
        _tapRow(
          label: 'Date of birth',
          value: _dobDate != null ? _fmtDate(_dobDate) : 'Select date',
          placeholder: _dobDate == null,
          onTap: _pickDob,
        ),
        // Height with unit toggle
        _editRow(
          label: 'Height',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                child: _underlineField(
                  controller: _heightCtrl,
                  keyboard: TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              _unitToggle(['cm', 'ft'], _heightUnit, _toggleHeightUnit),
            ],
          ),
        ),
        // Weight with unit toggle
        _editRow(
          label: 'Weight',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                child: _underlineField(
                  controller: _weightCtrl,
                  keyboard: TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              _unitToggle(['kg', 'lb'], _weightUnit, _toggleWeightUnit),
            ],
          ),
        ),
        // Biological sex segmented control
        Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _kDivider, width: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Biological sex',
                style: TextStyle(fontSize: 13, color: WW.textSec),
              ),
              const SizedBox(height: 10),
              _segControl(
                options: const ['Male', 'Female', 'Prefer not to say'],
                selected: _biologicalSex,
                onSelect: (v) => setState(() => _biologicalSex = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section B — Injuries & Conditions ─────────────────────────────────────

  Widget _buildSectionB() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Injuries & Conditions'),
        Container(
          decoration: WW.cardDecoration,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // WiseCoach callout with left accent border
              Container(
                decoration: BoxDecoration(
                  color: WW.lavenderBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 70,
                      decoration: BoxDecoration(
                        color: WW.lavender,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          bottomLeft: Radius.circular(10),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                color: WW.lavender, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'WiseCoach reads your injuries and conditions before every plan recommendation.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: WW.lavenderText,
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
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Injury tracking coming soon',
                  style: TextStyle(
                    fontSize: 13,
                    color: WW.textSec,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section C — Calorie Goal Tracking ─────────────────────────────────────

  Widget _buildSectionC() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Calorie Goal Tracking'),
        // Toggle row
        Container(
          decoration: WW.cardDecoration,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.local_fire_department_rounded,
                      color: WW.primary, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track calorie burn goals',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: WW.text,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Set daily, weekly, and monthly targets.',
                      style: TextStyle(
                        fontSize: 12,
                        color: WW.textSec,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: _calorieGoalActive,
                onChanged: _onCalorieToggle,
                activeTrackColor: _kGreen,
                inactiveTrackColor: WW.border,
              ),
            ],
          ),
        ),
        // OFF state note
        if (!_calorieGoalActive) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: WW.bg,
              border: Border.all(color: WW.border, width: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Calorie tracking is off. Calories burned are still logged but without goal rings.',
              style: TextStyle(
                fontSize: 12,
                color: WW.textSec,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ],
        // ON state: goal fields
        if (_calorieGoalActive) ...[
          const SizedBox(height: 8),
          Container(
            decoration: WW.cardDecoration,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calorie targets',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 12),
                _calField(
                  label: 'Daily burn target',
                  ctrl: _dailyCalCtrl,
                  hint: '600',
                  onChanged: (_) => _autoCalcFromDaily(),
                  note: 'Recommended 400–700 kcal/day for your profile.',
                ),
                _calDivider(),
                _calField(
                  label: 'Weekly burn target',
                  ctrl: _weeklyCalCtrl,
                  hint: 'Auto-calculated',
                  note: 'Auto-calculated from daily × 7.',
                ),
                _calDivider(),
                _calField(
                  label: 'Monthly burn target',
                  ctrl: _monthlyCalCtrl,
                  hint: 'Auto-calculated',
                  note: 'Auto-calculated from weekly × 4.',
                ),
                _calDivider(),
                const Text(
                  'Weight loss goal',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 12),
                _calField(
                  label: 'Goal weight (optional)',
                  ctrl: _goalWeightCtrl,
                  hint: '—',
                  unit: 'kg',
                  note: 'Track body composition changes in Progress.',
                ),
                _calDivider(),
                // Target date picker row
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickGoalDate,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Target date (optional)',
                          style: TextStyle(fontSize: 13, color: WW.textSec),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: WW.primary, width: 1.5),
                          ),
                        ),
                        child: Text(
                          _fmtDate(_goalDate),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _goalDate == null ? WW.border : WW.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Shows a countdown on your Home screen.',
                  style: TextStyle(
                    fontSize: 11,
                    color: WW.textSec,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                _saveBtn(
                  label: 'Save calorie goals',
                  loading: _isSavingCalorie,
                  onTap: _saveCalorieGoals,
                ),
                if (_showCalorieSuccess) ...[
                  const SizedBox(height: 10),
                  _successBanner('Goals saved!'),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Section D — Fitness Preferences ───────────────────────────────────────

  Widget _buildSectionD() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('Fitness Preferences'),
        const Text(
          'These preferences influence WiseCoach recommendations and plan matching.',
          style: TextStyle(
            fontSize: 12,
            color: WW.textSec,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: WW.cardDecoration,
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              _viewRow('Primary goal',
                  _prefGoal.isNotEmpty ? _prefGoal : '—', first: true),
              _viewRow('Sport',
                  _prefSport.isNotEmpty ? _prefSport : '—'),
              _viewRow('Experience',
                  _prefExperience.isNotEmpty ? _prefExperience : '—'),
              _viewRow('Days per week',
                  _prefDays.isNotEmpty ? '$_prefDays days' : '—'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _snack('Retake survey coming soon'),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: WW.primary, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Retake Survey',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WW.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 12, color: WW.textSec),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'This information is used only to personalise your plan and is not shared with third parties.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: WW.textSec,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared row widgets ─────────────────────────────────────────────────────

  Widget _sectionHeader(String label, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: WW.textSec,
                letterSpacing: 0.6,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _viewRow(String label, String value, {bool first = false}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: _kDivider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: WW.textSec)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: WW.text)),
        ],
      ),
    );
  }

  Widget _editRow({
    required String label,
    required Widget child,
    bool first = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: _kDivider, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: WW.textSec))),
          child,
        ],
      ),
    );
  }

  Widget _tapRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool placeholder = false,
    bool first = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: _kDivider, width: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13, color: WW.textSec))),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: WW.primary, width: 1.5)),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: placeholder ? WW.border : WW.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input widgets ──────────────────────────────────────────────────────────

  Widget _underlineField({
    required TextEditingController controller,
    TextAlign align = TextAlign.center,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      textAlign: align,
      keyboardType: keyboard,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: WW.text),
      decoration: const InputDecoration(
        border: UnderlineInputBorder(
            borderSide: BorderSide(color: WW.primary, width: 1.5)),
        focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: WW.primary, width: 1.5)),
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: WW.primary, width: 1.5)),
        isDense: true,
        contentPadding: EdgeInsets.only(bottom: 4),
      ),
    );
  }

  Widget _unitToggle(
    List<String> units,
    String current,
    void Function(String) onTap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: units.map((u) {
          final active = u == current;
          return GestureDetector(
            onTap: () => onTap(u),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: active ? WW.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                u,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : WW.textSec,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _segControl({
    required List<String> options,
    required String selected,
    required void Function(String) onSelect,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: options.map((opt) {
          final active = opt == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? WW.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color:
                                WW.primaryDark.withValues(alpha: 0.10),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  opt,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? WW.primaryDark : WW.textSec,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _calField({
    required String label,
    required TextEditingController ctrl,
    String hint = '',
    String unit = 'kcal',
    void Function(String)? onChanged,
    String? note,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 13, color: WW.textSec)),
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: onChanged,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WW.text),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                      color: WW.border, fontWeight: FontWeight.w400),
                  border: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: WW.primary, width: 1.5)),
                  focusedBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: WW.primary, width: 1.5)),
                  enabledBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: WW.primary, width: 1.5)),
                  isDense: true,
                  contentPadding: const EdgeInsets.only(bottom: 4),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(unit,
                style: const TextStyle(fontSize: 13, color: WW.textSec)),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note,
              style: const TextStyle(
                  fontSize: 11,
                  color: WW.textSec,
                  fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _calDivider() => Container(
        height: 0.5,
        color: _kDivider,
        margin: const EdgeInsets.only(bottom: 12),
      );

  Widget _saveBtn({
    required String label,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: loading
              ? WW.primary.withValues(alpha: 0.7)
              : WW.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _successBanner(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSuccessBg,
        border: Border.all(color: _kSuccessBorder, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _kGreen, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _kSuccessText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
