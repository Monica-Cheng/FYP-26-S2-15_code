// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: const Center(
        child: Text(
          'Login Screen — Coming Soon',
          style: TextStyle(color: WW.text),
        ),
      ),
    );
  }
}
