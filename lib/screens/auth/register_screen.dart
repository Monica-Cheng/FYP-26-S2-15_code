// lib/screens/auth/register_screen.dart
// Registration screen for WiseWorkout — email/password and Google sign-up.
// Navigation: context.go(Routes.home) on success, context.pop() for back.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';

// Error banner colours — standard UI feedback, not part of the WW brand palette.
const _kErrorBg = Color(0xFFFEE2E2);
const _kErrorBorder = Color(0xFFFCA5A5);
const _kErrorText = Color(0xFFB91C1C);

// Inline field validation colours.
const _kFieldErrorBorder = Color(0xFFEF4444);
const _kFieldErrorFill = Color(0xFFFFF5F5);
const _kFieldErrorText = Color(0xFFEF4444);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _tried = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Inline validation — returns null when the field is valid.
  // ---------------------------------------------------------------------------
  String? get _nameError =>
      _nameController.text.trim().isEmpty ? 'Display name is required' : null;

  String? get _emailError => !_emailController.text.contains('@')
      ? 'Enter a valid email address'
      : null;

  String? get _passwordError => _passwordController.text.length < 8
      ? 'Password must be at least 8 characters'
      : null;

  String? get _confirmError =>
      _confirmController.text != _passwordController.text
          ? 'Passwords must match'
          : null;

  bool get _formValid =>
      _nameError == null &&
      _emailError == null &&
      _passwordError == null &&
      _confirmError == null;

  // ---------------------------------------------------------------------------
  // Email / password registration
  // ---------------------------------------------------------------------------
  Future<void> _handleSignUp() async {
    setState(() {
      _tried = true;
      _errorMessage = null;
    });
    if (!_formValid) return;

    setState(() => _isLoading = true);
    try {
      await _authService.registerWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) context.go(Routes.home);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Google sign-up — returns null when user cancels (no error shown)
  // ---------------------------------------------------------------------------
  Future<void> _handleGoogleSignUp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential == null) return; // User cancelled picker
      if (mounted) context.go(Routes.home);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } catch (_) {
      setState(
        () => _errorMessage = 'Google sign-up failed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Maps FirebaseAuthException codes to user-friendly messages.
  String _friendlyError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Something went wrong. Please try again.';
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back arrow ─────────────────────────────────────────────────
              GestureDetector(
                onTap: () => context.pop(),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chevron_left_rounded,
                      color: WW.primary,
                      size: 26,
                    ),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: WW.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Hero ───────────────────────────────────────────────────────
              const Text(
                'Create your account',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Start your fitness journey today',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: WW.textSec,
                ),
              ),
              const SizedBox(height: 26),

              // ── Error banner ───────────────────────────────────────────────
              if (_errorMessage != null) ...[
                _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 14),
              ],

              // ── Display Name ───────────────────────────────────────────────
              _RegisterField(
                label: 'Display Name',
                controller: _nameController,
                hint: 'How should we call you?',
                error: _tried ? _nameError : null,
                onChanged: (_) => setState(() {}),
              ),

              // ── Email ──────────────────────────────────────────────────────
              _RegisterField(
                label: 'Email',
                controller: _emailController,
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                error: _tried ? _emailError : null,
                onChanged: (_) => setState(() {}),
              ),

              // ── Password ───────────────────────────────────────────────────
              _RegisterField(
                label: 'Password',
                controller: _passwordController,
                hint: 'Min. 8 characters',
                obscureText: _obscurePassword,
                error: _tried ? _passwordError : null,
                onChanged: (_) => setState(() {}),
                suffixIcon: GestureDetector(
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: WW.textSec,
                    size: 20,
                  ),
                ),
              ),

              // ── Confirm Password ───────────────────────────────────────────
              _RegisterField(
                label: 'Confirm Password',
                controller: _confirmController,
                hint: 'Re-enter your password',
                obscureText: _obscureConfirm,
                error: _tried ? _confirmError : null,
                onChanged: (_) => setState(() {}),
                suffixIcon: GestureDetector(
                  onTap: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  child: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: WW.textSec,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // ── Sign Up button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignUp,
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
                      : const Text(
                          'Sign Up',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 22),

              // ── "or" divider ───────────────────────────────────────────────
              const Row(
                children: [
                  Expanded(child: Divider(color: WW.border, thickness: 1)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: WW.textSec,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: WW.border, thickness: 1)),
                ],
              ),
              const SizedBox(height: 14),

              // ── Sign up with Google ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _handleGoogleSignUp,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: WW.card,
                    foregroundColor: WW.text,
                    side: const BorderSide(color: WW.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _GoogleLogo(),
                      SizedBox(width: 10),
                      Text(
                        'Sign up with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: WW.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Footer: already have account ───────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => context.go(Routes.login),
                  child: const Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(fontSize: 14, color: WW.textSec),
                      children: [
                        TextSpan(
                          text: 'Log in',
                          style: TextStyle(
                            color: WW.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Footer: professional link ──────────────────────────────────
              Center(
                child: Text.rich(
                  TextSpan(
                    text: 'Registering as a fitness professional? ',
                    style: const TextStyle(fontSize: 13, color: WW.textSec),
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: () {
                            // TODO: navigate to professional registration screen
                          },
                          child: const Text(
                            'Tap here',
                            style: TextStyle(
                              fontSize: 13,
                              color: WW.primary,
                              fontWeight: FontWeight.w700,
                            ),
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
      ),
    );
  }
}

// ── Field with inline validation ───────────────────────────────────────────────

class _RegisterField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final String? error;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;

  const _RegisterField({
    required this.label,
    required this.controller,
    required this.hint,
    this.error,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: hasError ? _kFieldErrorBorder : WW.border,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: WW.text,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 50,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 15, color: WW.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 15, color: WW.textSec),
              filled: true,
              fillColor: hasError ? _kFieldErrorFill : WW.card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              border: baseBorder,
              enabledBorder: baseBorder,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError ? _kFieldErrorBorder : WW.primary,
                  width: 1.5,
                ),
              ),
              suffixIcon: suffixIcon,
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _kFieldErrorText,
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }
}

// ── Error banner ───────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kErrorBg,
        border: Border.all(color: _kErrorBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _kErrorText, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _kErrorText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Google logo (CustomPainter — no SVG package needed) ───────────────────────

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(20, 20), painter: _GoogleLogoPainter());
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48.0, size.height / 48.0);

    canvas.drawPath(
      Path()
        ..moveTo(43.6, 20.5)
        ..lineTo(42, 20.5)
        ..lineTo(42, 20)
        ..lineTo(24, 20)
        ..lineTo(24, 28)
        ..lineTo(35.3, 28)
        ..cubicTo(33.7, 32.6, 29.3, 36, 24, 36)
        ..cubicTo(17.4, 36, 12, 30.6, 12, 24)
        ..cubicTo(12, 17.4, 17.4, 12, 24, 12)
        ..cubicTo(27.1, 12, 29.8, 13.1, 31.9, 15)
        ..lineTo(37.6, 9.3)
        ..cubicTo(34, 6.4, 29.3, 4, 24, 4)
        ..cubicTo(12.9, 4, 4, 12.9, 4, 24)
        ..cubicTo(4, 35.1, 12.9, 44, 24, 44)
        ..cubicTo(35.1, 44, 44, 35.1, 44, 24)
        ..cubicTo(44, 22.8, 43.9, 21.6, 43.6, 20.5)
        ..close(),
      Paint()..color = const Color(0xFFFFC107),
    );

    canvas.drawPath(
      Path()
        ..moveTo(6.3, 14.7)
        ..lineTo(12.9, 19.5)
        ..cubicTo(14.7, 16.1, 19, 13, 24, 13)
        ..cubicTo(27.1, 13, 29.8, 14.1, 31.9, 16)
        ..lineTo(37.6, 10.3)
        ..cubicTo(34, 6.4, 29.3, 4, 24, 4)
        ..cubicTo(16.5, 4, 10, 8.3, 6.3, 14.7)
        ..close(),
      Paint()..color = const Color(0xFFFF3D00),
    );

    canvas.drawPath(
      Path()
        ..moveTo(24, 44)
        ..cubicTo(29.2, 44, 33.9, 42, 37.4, 38.8)
        ..lineTo(31.2, 33.6)
        ..cubicTo(29.4, 35.4, 26.8, 36, 24, 36)
        ..cubicTo(18.7, 36, 14.3, 32.6, 12.7, 28)
        ..lineTo(6.3, 28)
        ..cubicTo(9.9, 37.8, 16.4, 44, 24, 44)
        ..close(),
      Paint()..color = const Color(0xFF4CAF50),
    );

    canvas.drawPath(
      Path()
        ..moveTo(43.6, 20.5)
        ..lineTo(42, 20.5)
        ..lineTo(42, 20)
        ..lineTo(24, 20)
        ..lineTo(24, 28)
        ..lineTo(35.3, 28)
        ..cubicTo(34.5, 30.3, 33, 32.2, 31, 33.6)
        ..lineTo(37.2, 38.8)
        ..cubicTo(37.5, 38, 44, 33, 44, 24)
        ..cubicTo(44, 22.8, 43.9, 21.6, 43.6, 20.5)
        ..close(),
      Paint()..color = const Color(0xFF1976D2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
