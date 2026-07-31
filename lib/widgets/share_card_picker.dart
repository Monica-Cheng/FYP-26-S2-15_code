// lib/widgets/share_card_picker.dart
// Swipeable picker between whichever shareable card designs (Map/Route,
// Photo, Colored) are available for a given post — shown before Share or
// Post to Feed by both post_session_summary_screen.dart and
// nutrition_scan_screen.dart. Callers pre-filter `cards` down to only
// the designs actually available for that specific post (e.g. via
// RouteMapShareCard.isAvailable()) — this widget doesn't itself decide
// availability, it just presents whatever list it's given.

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/share_card_gradients.dart';

class ShareCardOption {
  final String label;
  final WidgetBuilder builder;
  // True only for the colored-background card — gates the gradient swatch
  // row below the preview so it only shows up on the page it applies to.
  final bool supportsColorPicker;

  const ShareCardOption({
    required this.label,
    required this.builder,
    this.supportsColorPicker = false,
  });
}

// Shows the picker sheet and resolves to the chosen option's index once
// the user taps the confirm button, or null if dismissed without
// choosing (back button / tap outside) — callers should treat null as
// "cancel", same convention as caption_sheet.dart. onGradientChanged fires
// every time the user taps a swatch on the colored card's page — callers
// should store the picked colors and read them back when building the
// final card for capture (see post_session_summary_screen.dart /
// nutrition_scan_screen.dart's _selectedGradientColors field).
Future<int?> showShareCardPicker(
  BuildContext context, {
  required List<ShareCardOption> cards,
  String confirmLabel = 'Use This Design',
  ValueChanged<List<Color>>? onGradientChanged,
}) {
  assert(cards.isNotEmpty, 'showShareCardPicker requires at least one card');
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareCardPickerSheet(
      cards: cards,
      confirmLabel: confirmLabel,
      onGradientChanged: onGradientChanged,
    ),
  );
}

class _ShareCardPickerSheet extends StatefulWidget {
  final List<ShareCardOption> cards;
  final String confirmLabel;
  final ValueChanged<List<Color>>? onGradientChanged;

  const _ShareCardPickerSheet({
    required this.cards,
    required this.confirmLabel,
    this.onGradientChanged,
  });

  @override
  State<_ShareCardPickerSheet> createState() => _ShareCardPickerSheetState();
}

class _ShareCardPickerSheetState extends State<_ShareCardPickerSheet> {
  final _pageController = PageController();
  int _index = 0;
  int _gradientIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Preview size — the actual cards are a fixed 360x640 (see
    // RouteMapShareCard/PhotoBackgroundShareCard/ShareCardWidget), scaled
    // down via FittedBox to fit comfortably inside the sheet rather than
    // rendered at full size, which wouldn't fit most phone screens
    // alongside the header/dots/confirm button.
    const previewWidth = 240.0;
    const previewHeight = previewWidth * 640 / 360;

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: WW.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: WW.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Choose a design', style: WW.titleLarge),
            const SizedBox(height: 3),
            Text(
              widget.cards.length > 1 ? 'Swipe to see more' : '',
              style: WW.labelMed,
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.cards.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => Center(
                  child: SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: ClipRRect(
                      // Rounded only for the on-screen preview — the
                      // actual captured image (see widget_capture.dart)
                      // renders the card widget itself, which is a plain
                      // rectangle, so this doesn't bake rounded corners
                      // into the shared/posted PNG.
                      borderRadius: BorderRadius.circular(20),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: widget.cards[i].builder(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.cards[_index].supportsColorPicker) ...[
              const SizedBox(height: 12),
              _buildGradientSwatches(),
            ],
            if (widget.cards.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.cards.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? WW.primary : WW.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(_index),
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      widget.confirmLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientSwatches() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(ShareCardGradients.presets.length, (i) {
        final preset = ShareCardGradients.presets[i];
        final selected = i == _gradientIndex;
        return GestureDetector(
          onTap: () {
            widget.onGradientChanged?.call(preset.colors);
            setState(() => _gradientIndex = i);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: preset.colors,
              ),
              border: Border.all(
                color: selected ? WW.text : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
        );
      }),
    );
  }
}
