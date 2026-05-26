// lib/screens/home/home_screen.dart
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: const Center(
        child: Text(
          'Home Screen — Coming Soon',
          style: TextStyle(color: WW.text),
        ),
      ),
    );
  }
}
