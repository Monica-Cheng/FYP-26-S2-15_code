// lib/widgets/nutrition_share_card_widget.dart
// The shareable "post" card for a logged meal — same visual language as
// ShareCardWidget (used for workout sessions), so a shared meal looks like
// it belongs to the same app/brand.

import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class NutritionShareCardWidget extends StatelessWidget {
  final String foodName;
  final int calories;
  final int? proteinG;
  final int? carbsG;
  final int? fatG;
  final String source; // 'scan' or 'manual'
  final DateTime date;
  final List<Color> gradientColors;

  const NutritionShareCardWidget({
    super.key,
    required this.foodName,
    required this.calories,
    required this.date,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.source = 'scan',
    this.gradientColors = const [WW.primaryDark, Color(0xFF4a4ea8)],
  });

  String _fmtDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[dt.weekday - 1]}, ${dt.day} '
        '${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _fmtDate(date);

    // Fixed Story-ratio canvas — same resize approach/reasoning as
    // ShareCardWidget (see that file), same content just redistributed
    // across the full height instead of shrink-wrapping it.
    return Container(
      width: 360,
      height: 640,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Column(
        children: [
          // Top header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.fitness_center_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'WiseWorkout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    source == 'scan' ? 'AI Scanned' : 'Logged',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Food name / date / stats — centered in the space between the
          // header and the footer strip.
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      foodName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        _StatBox(value: '$calories kcal', label: 'Calories'),
                        const SizedBox(width: 10),
                        _StatBox(value: '${proteinG ?? 0}g', label: 'Protein'),
                        const SizedBox(width: 10),
                        _StatBox(value: '${carbsG ?? 0}g', label: 'Carbs'),
                        const SizedBox(width: 10),
                        _StatBox(value: '${fatG ?? 0}g', label: 'Fat'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom hashtag strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
            ),
            child: const Text(
              '#WiseWorkout  #EatSmart',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;

  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
