// lib/screens/auth/forgot_password_screen.dart
// Password reset screen for WiseWorkout.
// Input state: user enters email and taps "Send reset email".
// Success state: confirmation shown with option to go back to login.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';

// Green success colours — not in the WW brand palette, used only for the
// success checkmark illustration.
const _kSuccessBg = Color(0xFFD1FAE5);
const _kSuccessIcon = Color(0xFF059669);

// Inline field error colours — standard validation feedback.
const _kFieldErrorBorder = Color(0xFFEF4444);
const _kFieldErrorFill = Color(0xFFFFF5F5);
const _kFieldErrorText = Color(0xFFEF4444);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Validate email format and call sendPasswordReset.
  // ---------------------------------------------------------------------------
  Future<void> _handleSend() async {
    final email = _emailController.text.trim();

    // Client-side format check before hitting Firebase.
    if (!email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendPasswordReset(email);
      if (mounted) setState(() => _emailSent = true);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with that email address.';
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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: _emailSent ? _buildSuccess() : _buildInput(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Input state
  // ---------------------------------------------------------------------------
  Widget _buildInput() {
    final hasError = _errorMessage != null;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: hasError ? _kFieldErrorBorder : WW.border,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Back button ──────────────────────────────────────────────────────
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: WW.text.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chevron_left_rounded,
              color: WW.text,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 32),

        // ── Lock icon ────────────────────────────────────────────────────────
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: WW.elevated,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.lock_outline_rounded, color: WW.primary, size: 32),
        ),
        const SizedBox(height: 20),

        // ── Title + subtitle ─────────────────────────────────────────────────
        const Text(
          'Forgot password?',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "Enter your email and we'll send a reset link.",
          style: TextStyle(fontSize: 15, color: WW.textSec, height: 1.5),
        ),
        const SizedBox(height: 32),

        // ── Email field ──────────────────────────────────────────────────────
        const Text(
          'Email address',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: WW.text,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 50,
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _errorMessage = null),
            style: const TextStyle(fontSize: 15, color: WW.text),
            decoration: InputDecoration(
              hintText: 'you@example.com',
              hintStyle: const TextStyle(fontSize: 15, color: WW.textSec),
              filled: true,
              fillColor: hasError ? _kFieldErrorFill : WW.card,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              border: fieldBorder,
              enabledBorder: fieldBorder,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: hasError ? _kFieldErrorBorder : WW.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(
            _errorMessage!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _kFieldErrorText,
            ),
          ),
        ],
        const SizedBox(height: 20),

        // ── Send button ──────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSend,
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
                    'Send reset email',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Success state
  // ---------------------------------------------------------------------------
  Widget _buildSuccess() {
    final sentEmail = _emailController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Back button (keeps consistent chrome) ────────────────────────────
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: WW.text.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                color: WW.text,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),

        // ── Green checkmark circle ───────────────────────────────────────────
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: _kSuccessBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: _kSuccessIcon,
            size: 40,
          ),
        ),
        const SizedBox(height: 24),

        // ── Title ────────────────────────────────────────────────────────────
        const Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),

        // ── Sent-to copy ─────────────────────────────────────────────────────
        Text.rich(
          TextSpan(
            text: 'Reset link sent to\n',
            style: const TextStyle(
              fontSize: 15,
              color: WW.textSec,
              height: 1.6,
            ),
            children: [
              TextSpan(
                text: sentEmail,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),

        // ── Spam hint ────────────────────────────────────────────────────────
        const Text(
          "Check your spam folder if you don't see it.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: WW.textSec),
        ),
        const SizedBox(height: 40),

        // ── Back to Log In button ────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => context.go(Routes.login),
            style: ElevatedButton.styleFrom(
              backgroundColor: WW.elevated,
              foregroundColor: WW.primaryDark,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Back to Log In',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Try a different email ─────────────────────────────────────────────
        TextButton(
          onPressed: () => setState(() {
            _emailSent = false;
            _emailController.clear();
          }),
          child: const Text(
            'Try a different email',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WW.primary,
            ),
          ),
        ),
      ],
    );
  }
}
