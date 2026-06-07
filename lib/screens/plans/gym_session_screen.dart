// lib/screens/plans/gym_session_screen.dart
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class GymSessionScreen extends StatelessWidget {
  const GymSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: WW.bg,
      body: Center(
        child: Text(
          'Gym Session — Coming Soon',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: WW.textSec),
        ),
      ),
    );
  }
}
