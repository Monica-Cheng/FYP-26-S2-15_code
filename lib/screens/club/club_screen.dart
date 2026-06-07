// lib/screens/club/club_screen.dart
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

class ClubScreen extends StatelessWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: WW.bg,
      child: Center(
        child: Text(
          'Club — Coming Soon',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: WW.textSec),
        ),
      ),
    );
  }
}
