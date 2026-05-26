// lib/screens/auth/login_screen.dart
// Login screen for WiseWorkout — handles email/password and Google sign-in.
// Navigation: context.go(Routes.home) on success.
// NOTE: Routes.forgotPassword must be added to lib/core/router.dart when
// the forgot-password screen is built.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';

// Banner colours — not part of the WW brand palette, standard UI feedback only.
const _kErrorBg = Color(0xFFFEE2E2);
const _kErrorBorder = Color(0xFFFCA5A5);
const _kErrorText = Color(0xFFB91C1C);
const _kWarnBg = Color(0xFFFEF3C7);
const _kWarnBorder = Color(0xFFFCD34D);
const _kWarnText = Color(0xFF92400E);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSuspended = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Email / password sign-in
  // ---------------------------------------------------------------------------
  Future<void> _handleEmailLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSuspended = false;
    });
    try {
      await _authService.signInWithEmailPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) context.go(Routes.home);
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-disabled') {
          _isSuspended = true;
        } else {
          _errorMessage = _friendlyError(e.code);
        }
      });
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Google sign-in — returns null when user cancels (no error shown)
  // ---------------------------------------------------------------------------
  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSuspended = false;
    });
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential == null) return; // User cancelled picker
      if (mounted) context.go(Routes.home);
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-disabled') {
          _isSuspended = true;
        } else {
          _errorMessage = _friendlyError(e.code);
        }
      });
    } catch (_) {
      setState(
        () => _errorMessage = 'Google sign-in failed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Maps FirebaseAuthException codes to user-friendly messages.
  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ── Hero ───────────────────────────────────────────────────────
              const Text(
                'Welcome back',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Log in to continue your training',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: WW.textSec,
                ),
              ),
              const SizedBox(height: 26),

              // ── Error banner ───────────────────────────────────────────────
              if (_errorMessage != null) ...[
                _Banner(
                  message: _errorMessage!,
                  bg: _kErrorBg,
                  border: _kErrorBorder,
                  textColor: _kErrorText,
                  icon: Icons.info_outline,
                ),
                const SizedBox(height: 14),
              ],

              // ── Suspended banner ───────────────────────────────────────────
              if (_isSuspended) ...[
                _Banner(
                  message:
                      'Your account has been suspended. Please contact support at support@wiseworkout.app.',
                  bg: _kWarnBg,
                  border: _kWarnBorder,
                  textColor: _kWarnText,
                  icon: Icons.warning_amber_outlined,
                ),
                const SizedBox(height: 14),
              ],

              // ── Email field ────────────────────────────────────────────────
              const Text(
                'Email',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 6),
              _InputField(
                controller: _emailController,
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),

              // ── Password field ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Password',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WW.text,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push(Routes.forgotPassword),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _InputField(
                controller: _passwordController,
                hint: '••••••••',
                obscureText: _obscurePassword,
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
              const SizedBox(height: 20),

              // ── Log in button ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleEmailLogin,
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
                          'Log in',
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
              const SizedBox(height: 16),

              // ── Continue with Google ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _handleGoogleLogin,
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
                        'Continue with Google',
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
              const SizedBox(height: 26),

              // ── Footer ─────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => context.push(Routes.register),
                    child: const Text.rich(
                      TextSpan(
                        text: 'New here? ',
                        style: TextStyle(fontSize: 14, color: WW.textSec),
                        children: [
                          TextSpan(
                            text: 'Create account',
                            style: TextStyle(
                              color: WW.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Text(
                    'Register as Professional',
                    style: TextStyle(
                      fontSize: 12,
                      color: WW.textSec,
                      decoration: TextDecoration.underline,
                      decorationColor: WW.border,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared input field ─────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? suffixIcon;

  const _InputField({
    required this.controller,
    required this.hint,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
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
        obscureText: obscureText,
        keyboardType: keyboardType,
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
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

// ── Banner (error / warning) ───────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final String message;
  final Color bg;
  final Color border;
  final Color textColor;
  final IconData icon;

  const _Banner({
    required this.message,
    required this.bg,
    required this.border,
    required this.textColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textColor,
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
    // Scale from the 48×48 SVG viewBox to the actual widget size.
    canvas.scale(size.width / 48.0, size.height / 48.0);

    // Yellow — outer right arc and horizontal bar
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

    // Red — top-left arc
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

    // Green — bottom arc
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

    // Blue — right arc
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
