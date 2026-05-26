// lib/screens/auth/forgot_password_screen.dart
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: WW.bg,
      body: Center(
        child: Text(
          'Forgot Password — Coming Soon',
          style: TextStyle(color: WW.text),
        ),
      ),
    );
  }
}
