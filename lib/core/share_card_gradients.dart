// lib/core/share_card_gradients.dart
// Preset gradient pairs offered by the color-picker swatches on the
// colored-background share card (ShareCardWidget / NutritionShareCardWidget)
// — see share_card_picker.dart's swatch row, wired up from
// post_session_summary_screen.dart / nutrition_scan_screen.dart. The first
// preset matches what used to be the only, hardcoded gradient, so it stays
// the default when a card is built without an explicit selection.

import 'package:flutter/material.dart';
import 'app_theme.dart';

class ShareCardGradient {
  final String label;
  final List<Color> colors;

  const ShareCardGradient({required this.label, required this.colors});
}

class ShareCardGradients {
  ShareCardGradients._();

  static const List<ShareCardGradient> presets = [
    ShareCardGradient(
        label: 'Indigo', colors: [WW.primaryDark, Color(0xFF4A4EA8)]),
    ShareCardGradient(
        label: 'Lavender', colors: [WW.lavenderDark, WW.lavender]),
    ShareCardGradient(label: 'Teal', colors: [Color(0xFF1F6B78), WW.teal]),
    ShareCardGradient(label: 'Gold', colors: [Color(0xFFB8790A), WW.gold]),
    ShareCardGradient(
        label: 'Midnight', colors: [Color(0xFF15161F), Color(0xFF32354A)]),
  ];
}
