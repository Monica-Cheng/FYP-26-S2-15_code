// lib/widgets/caption_sheet.dart
// A reusable bottom sheet for adding an optional caption before a feed
// post — shared by the nutrition and workout "Post to Feed" flows so
// captioning behaves identically in both.

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

// ---------------------------------------------------------------------------
// Shows the sheet. Resolves to:
//   - the trimmed caption text (possibly empty) once "Post" is tapped
//   - null if the sheet is dismissed without tapping "Post" (back button,
//     tap outside) — callers should treat that as "cancel the whole post",
//     not "post with no caption".
// ---------------------------------------------------------------------------
Future<String?> showCaptionSheet(
  BuildContext context, {
  String fallbackLabel = 'your post',
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CaptionSheet(fallbackLabel: fallbackLabel),
  );
}

class _CaptionSheet extends StatefulWidget {
  final String fallbackLabel;
  const _CaptionSheet({required this.fallbackLabel});

  @override
  State<_CaptionSheet> createState() => _CaptionSheetState();
}

class _CaptionSheetState extends State<_CaptionSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: const BoxDecoration(
            color: WW.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const Text('Add a caption', style: WW.titleLarge),
              const SizedBox(height: 3),
              Text(
                'Optional — leave blank to just show ${widget.fallbackLabel}',
                style: WW.labelMed,
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 280,
                  style: WW.bodyMed,
                  decoration: const InputDecoration(
                    hintText: 'Add a caption (optional)',
                    hintStyle: WW.labelMed,
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(_controller.text.trim()),
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'Post',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
