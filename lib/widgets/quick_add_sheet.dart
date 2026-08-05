// lib/widgets/quick_add_sheet.dart
// A reusable bottom sheet for multi-purpose "+"/picker buttons — shows a
// list of tappable options (icon, title, subtitle) under a heading/subheading
// that's also caller-supplied (defaults to "Quick Add" / "What would you
// like to log?", the Home tab FAB's original use case). Also reused by
// profile_screen.dart's photo picker and post_session_summary_screen.dart's
// share-card photo picker, each passing their own copy.

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class QuickAddOption {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const QuickAddOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

// ---------------------------------------------------------------------------
// Shows the sheet. The chosen option's onTap fires *after* the sheet has
// closed, so it's safe to call context.push(...) directly inside onTap.
// ---------------------------------------------------------------------------
Future<void> showQuickAddSheet(
  BuildContext context,
  List<QuickAddOption> options, {
  String title = 'Quick Add',
  String subtitle = 'What would you like to log?',
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _QuickAddSheet(options: options, title: title, subtitle: subtitle),
  );
}

class _QuickAddSheet extends StatelessWidget {
  final List<QuickAddOption> options;
  final String title;
  final String subtitle;
  const _QuickAddSheet({required this.options, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          decoration: BoxDecoration(
            color: WW.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: WW.shadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: WW.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(title, style: WW.titleLarge),
              const SizedBox(height: 3),
              Text(subtitle, style: WW.labelMed),
              const SizedBox(height: 16),
              for (final option in options) _QuickAddTile(option: option),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAddTile extends StatelessWidget {
  final QuickAddOption option;
  const _QuickAddTile({required this.option});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).pop();
            option.onTap();
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WW.elevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: option.iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(option.icon, color: option.iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        style: WW.titleMed.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(option.subtitle, style: WW.labelMed),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: WW.textSec),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
