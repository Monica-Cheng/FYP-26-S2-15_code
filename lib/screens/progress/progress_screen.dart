// lib/screens/progress/progress_screen.dart
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: WW.bg,
      child: Center(
        child: Text(
          'Progress — Coming Soon',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: WW.textSec),
        ),
      ),
    );
  }
}
