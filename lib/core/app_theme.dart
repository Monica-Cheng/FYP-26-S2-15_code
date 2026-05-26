// lib/core/app_theme.dart
// Single source of truth for ALL colors, text styles, and decorations
// NEVER hardcode hex colors anywhere else — always use WW.colorName

import 'package:flutter/material.dart';

class WW {
  WW._();

  // Backgrounds
  static const Color bg = Color(0xFFF7F8FF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color elevated = Color(0xFFEEF0FB);

  // Primary
  static const Color primary = Color(0xFF6C7EE8);
  static const Color primaryDark = Color(0xFF2D3A8C);

  // Lavender
  static const Color lavender = Color(0xFF9B84E8);
  static const Color lavenderBg = Color(0xFFF0EEFE);
  static const Color lavenderDark = Color(0xFF7B5CB8);
  static const Color lavenderText = Color(0xFF5B3F9E);

  // Teal
  static const Color teal = Color(0xFF4BB8CC);
  static const Color tealBg = Color(0xFFE0F4F8);

  // Text
  static const Color text = Color(0xFF3D3D5C);
  static const Color textSec = Color(0xFF8A8A9E);

  // Borders & chips
  static const Color border = Color(0xFFC8C8D8);
  static const Color chipBg = Color(0xFFE6EAFE);

  // Accent
  static const Color gold = Color(0xFFF59E0B);

  // Shadows
  static List<BoxShadow> get shadow => [
    BoxShadow(
      color: const Color(0xFF2D3A8C).withOpacity(0.06),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // Card decoration — use on any white card Container
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: border, width: 0.5),
    boxShadow: shadow,
  );

  // Text styles
  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: text,
    letterSpacing: -0.3,
  );
  static const TextStyle titleMed = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: text,
  );
  static const TextStyle bodyMed = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: text,
  );
  static const TextStyle labelMed = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textSec,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textSec,
  );

  // Theme data for MaterialApp
  static ThemeData get theme => ThemeData(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    fontFamily: 'SF Pro Display',
    useMaterial3: true,
  );
}
