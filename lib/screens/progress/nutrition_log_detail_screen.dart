// lib/screens/progress/nutrition_log_detail_screen.dart
// Detail view for a single nutritionLogs entry, tapped into from the
// Progress screen's Nutrition tab (_NutritionLogCard) — mirrors
// activity_detail_screen.dart's structural pattern (top bar, header
// card, stats row, notes) scoped to what a nutrition log actually has.
// No map/WiseCoach/XP sections here — those are workout-session concepts
// that don't apply to a logged meal. Photo section only shows for
// photo-scanned meals (saveNutritionLog only writes imageBase64 when
// nutrition_scan_screen.dart's _logMeal() resolved one) — described/
// manual entries and anything logged before this field existed simply
// have none, so the section is omitted rather than showing a placeholder.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';

class NutritionLogDetailScreen extends StatelessWidget {
  const NutritionLogDetailScreen({super.key});

  Map<String, dynamic> _log(BuildContext context) =>
      GoRouterState.of(context).extra as Map<String, dynamic>? ?? {};

  String _formatDate(dynamic ts) {
    DateTime date;
    if (ts is Timestamp) {
      date = ts.toDate();
    } else {
      return 'Unknown date';
    }
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  ({IconData icon, String label}) _sourceMeta(String source) {
    switch (source) {
      case 'scan':
        return (icon: Icons.camera_alt_rounded, label: 'Scanned');
      case 'barcode':
        return (icon: Icons.qr_code_scanner_rounded, label: 'Barcode');
      default:
        return (icon: Icons.edit_note_rounded, label: 'Manual');
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = _log(context);
    final foodName = log['foodName'] as String? ?? 'Meal';
    final calories = (log['calories'] as num?)?.toInt() ?? 0;
    final proteinG = (log['proteinG'] as num?)?.toInt();
    final carbsG = (log['carbsG'] as num?)?.toInt();
    final fatG = (log['fatG'] as num?)?.toInt();
    final source = log['source'] as String? ?? 'manual';
    final notes = log['notes'] as String?;
    final hasNotes = notes != null && notes.isNotEmpty;
    final sourceMeta = _sourceMeta(source);
    final dateLabel = _formatDate(log['date']);
    final photoWidget = _buildPhotoWidget(log['imageBase64'] as String?);

    return Scaffold(
      backgroundColor: WW.bg,
      body: Column(
        children: [
          _buildTopBar(context, foodName),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderCard(foodName, dateLabel, sourceMeta),
                  if (photoWidget != null) ...[
                    const SizedBox(height: 16),
                    photoWidget,
                  ],
                  const SizedBox(height: 16),
                  _buildStatsRow(calories, proteinG, carbsG, fatG),
                  if (hasNotes) ...[
                    const SizedBox(height: 16),
                    _buildNotesSection(notes),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Photo (scanned meals only) ───────────────────────────────────────────
  // Same base64Decode + Image.memory pattern already used for stored
  // photos elsewhere (FeedPostCard, activity_detail_screen.dart) — a
  // decode failure falls back to no photo section rather than breaking
  // the page.

  Widget? _buildPhotoWidget(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context, String title) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: WW.card,
          border: Border(bottom: BorderSide(color: WW.border, width: 0.5)),
          boxShadow: WW.shadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16, color: WW.primaryDark),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeaderCard(
    String foodName,
    String dateLabel,
    ({IconData icon, String label}) sourceMeta,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: WW.elevated,
            shape: BoxShape.circle,
          ),
          child: Icon(sourceMeta.icon, color: WW.text, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                foodName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$dateLabel · ${sourceMeta.label}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────
  // Same minimal 2-color treatment (WW.primary icon + WW.text value, no
  // per-stat colored boxes) established for FeedPostCard's stat row —
  // reused here instead of the old 4-colored-pill style.

  Widget _buildStatsRow(int calories, int? proteinG, int? carbsG, int? fatG) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _statItem(Icons.local_fire_department_rounded, '$calories cal'),
          _statItem(Icons.egg_alt_rounded, '${proteinG ?? 0}g protein'),
          _statItem(Icons.grain_rounded, '${carbsG ?? 0}g carbs'),
          _statItem(Icons.water_drop_rounded, '${fatG ?? 0}g fat'),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: WW.primary),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: WW.text,
          ),
        ),
      ],
    );
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  Widget _buildNotesSection(String notes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NOTES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: WW.textSec,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          notes,
          style: const TextStyle(fontSize: 14, color: WW.text, height: 1.5),
        ),
      ],
    );
  }
}
