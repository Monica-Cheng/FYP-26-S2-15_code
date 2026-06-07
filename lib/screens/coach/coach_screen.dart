// lib/screens/coach/coach_screen.dart
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: WW.bg,
      child: Center(
        child: Text(
          'Coach — Coming Soon',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: WW.textSec),
        ),
      ),
    );
  }
}
