// lib/screens/business/coach_register_screen.dart
// "Register as Professional" — linked from the pre-auth login screen, so
// this route is public (see router.dart's redirect) and this screen
// itself gates on auth state: unauthenticated visitors see a prompt to
// sign in/create an account first (the actual registration write needs a
// real uid), rather than the form. An already-registered applicant
// (businessPartners/{uid} already exists) skips straight to
// coach_dashboard_screen.dart instead of re-showing the form.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Same 4 categories find_professional_screen.dart already filters by
// (minus its own 'All' chip, which doesn't apply to picking one type
// here) — kept in sync manually since neither file imports the other.
const List<String> _kCoachTypes = [
  'Trainer',
  'Running Coach',
  'Physiotherapist',
  'Nutritionist',
];

class CoachRegisterScreen extends StatefulWidget {
  const CoachRegisterScreen({super.key});

  @override
  State<CoachRegisterScreen> createState() => _CoachRegisterScreenState();
}

class _CoachRegisterScreenState extends State<CoachRegisterScreen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  String _selectedType = _kCoachTypes.first;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingApplication();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _experienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingApplication() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final existing = await _firestoreService.getBusinessPartnerProfile(uid);
      if (!mounted) return;
      if (existing != null) {
        // Already applied (pending or approved) — coach_dashboard_screen
        // itself branches on isApproved, so just forward there instead of
        // letting them resubmit a second application.
        context.pushReplacement(Routes.coachDashboard);
        return;
      }
      setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty && _bioCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null || !_canSubmit || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await _firestoreService.registerAsCoach(
        uid: uid,
        name: _nameCtrl.text.trim(),
        type: _selectedType,
        bio: _bioCtrl.text.trim(),
        experience: _experienceCtrl.text.trim(),
        email: _authService.getCurrentUser()?.email,
      );
      if (!mounted) return;
      context.pushReplacement(Routes.coachDashboard);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Could not submit application: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _authService.getCurrentUser() != null;

    return Scaffold(
      backgroundColor: WW.bg,
      appBar: AppBar(
        backgroundColor: WW.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: WW.text, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Register as Professional', style: WW.titleMed),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: WW.primary))
            : !isSignedIn
                ? _buildSignInPrompt()
                : _buildForm(),
      ),
    );
  }

  // ── Sign-in-first prompt (unauthenticated visitors) ──────────────────────

  Widget _buildSignInPrompt() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.badge_outlined, size: 56, color: WW.textSec),
          const SizedBox(height: 16),
          const Text(
            'Create an account first',
            style: WW.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'You need a WiseWorkout account before applying as a coach — '
            'sign in if you already have one, or create a new account.',
            style: WW.labelMed,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              // Consumed by router.dart's redirect once auth (and, for a
              // brand-new account, onboarding) actually completes — see
              // pendingCoachRegistration's own doc comment there.
              pendingCoachRegistration = true;
              context.push(Routes.register);
            },
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'Create Account',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              pendingCoachRegistration = true;
              context.push(Routes.login);
            },
            child: const Text('I already have an account', style: TextStyle(color: WW.primary)),
          ),
        ],
      ),
    );
  }

  // ── Registration form ─────────────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tell us about yourself',
            style: WW.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Your application will be reviewed before your profile goes live.',
            style: WW.labelMed,
          ),
          const SizedBox(height: 20),

          _fieldLabel('YOUR NAME'),
          const SizedBox(height: 6),
          _buildTextField(_nameCtrl, hint: 'e.g. Jordan Lee'),
          const SizedBox(height: 18),

          _fieldLabel('COACH TYPE'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kCoachTypes.map((type) {
              final selected = _selectedType == type;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? WW.primary : WW.elevated,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : WW.textSec,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          _fieldLabel('EXPERIENCE'),
          const SizedBox(height: 6),
          _buildTextField(_experienceCtrl, hint: 'e.g. 5 years, NASM certified'),
          const SizedBox(height: 18),

          _fieldLabel('BIO'),
          const SizedBox(height: 6),
          _buildTextField(_bioCtrl, hint: 'A short introduction clients will see', maxLines: 4),

          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],

          const SizedBox(height: 24),
          GestureDetector(
            onTap: _canSubmit && !_isSubmitting ? _submit : null,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: _canSubmit ? WW.primary : WW.border,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Submit Application',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: WW.textSec,
          letterSpacing: 0.5,
        ),
      );

  Widget _buildTextField(TextEditingController controller, {required String hint, int maxLines = 1}) {
    return Container(
      decoration: WW.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 15, color: WW.text),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: WW.border),
        ),
      ),
    );
  }
}
