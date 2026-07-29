// lib/screens/nutrition/nutrition_scan_screen.dart
// Lets the user snap/upload a food photo and get an AI calorie + macro
// estimate (via NutritionService -> OpenAI vision). If the photo can't be
// recognized, falls back to a manual text-description estimate. Either path
// ends with the meal saved to users/{uid}/nutritionLogs via FirestoreService.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/barcode_service.dart';
import '../../services/firestore_service.dart';
import '../../services/nutrition_service.dart';
import '../../utils/widget_capture.dart';
import '../../widgets/caption_sheet.dart';
import '../../widgets/nutrition_share_card_widget.dart';
import '../../widgets/photo_background_share_card.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../widgets/share_card_picker.dart';

enum _Mode { scan, describe, barcode }
enum _Stage { input, loading, result, error, barcodeSummary }

class NutritionScanScreen extends StatefulWidget {
  final bool startInDescribeMode;
  const NutritionScanScreen({super.key, this.startInDescribeMode = false});

  @override
  State<NutritionScanScreen> createState() => _NutritionScanScreenState();
}

class _NutritionScanScreenState extends State<NutritionScanScreen> {
  final _nutritionService = NutritionService();
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  final _descriptionController = TextEditingController();

  _Mode _mode = _Mode.scan;
  _Stage _stage = _Stage.input;

  File? _pickedImage;
  NutritionResult? _result;
  final List<BarcodeProduct> _scannedProducts = [];
  String? _errorMessage;
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    if (widget.startInDescribeMode) _mode = _Mode.describe;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _handleImage(File file) async {
    setState(() {
      _pickedImage = file;
      _stage = _Stage.loading;
      _errorMessage = null;
    });

    try {
      final result = await _nutritionService.analyzeFoodImage(file);
      if (!mounted) return;

      if (!result.recognized) {
        // Couldn't identify the food — fall back to manual description.
        setState(() {
          _mode = _Mode.describe;
          _stage = _Stage.input;
          _errorMessage = result.message ??
              "Couldn't recognize this food. Describe it below instead.";
        });
        return;
      }

      setState(() {
        _result = result;
        _stage = _Stage.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _submitDescription() async {
    final text = _descriptionController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _stage = _Stage.loading;
      _errorMessage = null;
    });

    try {
      final result = await _nutritionService.analyzeFoodDescription(text);
      if (!mounted) return;

      if (!result.recognized) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = result.message ??
              "Still couldn't estimate that — try adding more detail (e.g. portion size).";
        });
        return;
      }

      setState(() {
        _result = result;
        _stage = _Stage.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _logMeal() async {
    final result = _result;
    if (result == null || _isSaving) return;
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      await _firestoreService.saveNutritionLog(
        uid,
        foodName: result.foodName,
        calories: result.calories,
        source: _mode == _Mode.scan ? 'scan' : 'manual',
        proteinG: result.proteinG,
        carbsG: result.carbsG,
        fatG: result.fatG,
        confidence: result.confidence,
      );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save meal: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Downscales a photo to a small PNG (no extra image-compression package
  // needed — uses Flutter's built-in ui.instantiateImageCodec) so it stays
  // well under Firestore's 1MB document size limit once base64-encoded.
  // Returns null (post goes out without a photo) rather than failing the
  // whole post if anything goes wrong.
  // ---------------------------------------------------------------------------
  Future<String?> _encodeImageForPost(File file) async {
    try {
      final bytes = await file.readAsBytes();
      debugPrint('[PostToFeed] _encodeImageForPost: read ${bytes.length} bytes from ${file.path}');
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 480);
      final frame = await codec.getNextFrame();
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('[PostToFeed] _encodeImageForPost: toByteData returned null');
        return null;
      }
      final encoded = base64Encode(byteData.buffer.asUint8List());
      debugPrint('[PostToFeed] _encodeImageForPost: encoded length ${encoded.length}');
      return encoded;
    } catch (e, st) {
      debugPrint('[PostToFeed] _encodeImageForPost threw: $e\n$st');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Shareable card flow (shared by Share and Post to Feed) — mirrors
  // post_session_summary_screen.dart's own card flow. Reuses _pickedImage
  // (the photo already used for AI recognition) for the Photo card design
  // when available, rather than prompting for a photo a second time.
  // ---------------------------------------------------------------------------

  Future<String?> _resolveExistingResultPhotoBase64() {
    if (_mode == _Mode.scan && _pickedImage != null) {
      return _encodeImageForPost(_pickedImage!);
    }
    return Future.value(null);
  }

  Future<void> _startResultCardFlow({required bool forPost}) async {
    if (forPost ? _isPosting : _isSharing) return;
    if (_result == null) return;

    final existingPhoto = await _resolveExistingResultPhotoBase64();
    if (existingPhoto != null) {
      await _showResultCardPickerAndContinue(photoBase64: existingPhoto, forPost: forPost);
      return;
    }

    if (!mounted) return;
    await showQuickAddSheet(context, [
      QuickAddOption(
        icon: Icons.camera_alt_rounded,
        iconColor: WW.primary,
        iconBg: WW.chipBg,
        title: 'Take Photo',
        subtitle: 'Use a photo in the Photo card design',
        onTap: () => _pickPhotoThenContinueResult(ImageSource.camera, forPost: forPost),
      ),
      QuickAddOption(
        icon: Icons.photo_library_rounded,
        iconColor: WW.teal,
        iconBg: WW.tealBg,
        title: 'Choose from Gallery',
        subtitle: 'Pick an existing photo',
        onTap: () => _pickPhotoThenContinueResult(ImageSource.gallery, forPost: forPost),
      ),
      QuickAddOption(
        icon: Icons.arrow_forward_rounded,
        iconColor: WW.textSec,
        iconBg: WW.elevated,
        title: 'Skip Photo',
        subtitle: 'Only offer the Color card design',
        onTap: () => _showResultCardPickerAndContinue(photoBase64: null, forPost: forPost),
      ),
    ]);
  }

  Future<void> _pickPhotoThenContinueResult(ImageSource source, {required bool forPost}) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    String? encoded;
    if (picked != null) {
      encoded = await _encodeImageForPost(File(picked.path));
    }
    await _showResultCardPickerAndContinue(photoBase64: encoded, forPost: forPost);
  }

  Future<void> _showResultCardPickerAndContinue({
    required String? photoBase64,
    required bool forPost,
  }) async {
    if (!mounted) return;
    final cards = _buildResultCardOptions(photoBase64: photoBase64);
    final chosenIndex = await showShareCardPicker(
      context,
      cards: cards,
      confirmLabel: forPost ? 'Use This Design' : 'Share This Design',
    );
    if (chosenIndex == null || !mounted) return;
    final chosen = cards[chosenIndex];
    if (forPost) {
      await _promptCaptionAndPostResultCard(chosen);
    } else {
      await _shareResultCard(chosen);
    }
  }

  // Photo card only if a photo was resolved (reused or picked); Color
  // card always — the universal fallback. No Map card here — meals have
  // no route/location data.
  List<ShareCardOption> _buildResultCardOptions({required String? photoBase64}) {
    final result = _result!;
    final source = _mode == _Mode.scan ? 'scan' : 'manual';
    final cards = <ShareCardOption>[];

    if (photoBase64 != null) {
      cards.add(ShareCardOption(
        label: 'Photo',
        builder: (_) => PhotoBackgroundShareCard(
          photoBase64: photoBase64,
          title: result.foodName,
          badgeLabel: source == 'scan' ? 'AI Scanned' : 'Logged',
          stats: [
            ('${result.calories}', 'Calories'),
            ('${result.proteinG ?? 0}g', 'Protein'),
            ('${result.carbsG ?? 0}g', 'Carbs'),
            ('${result.fatG ?? 0}g', 'Fat'),
          ],
          date: DateTime.now(),
        ),
      ));
    }

    cards.add(ShareCardOption(
      label: 'Color',
      builder: (_) => NutritionShareCardWidget(
        foodName: result.foodName,
        calories: result.calories,
        proteinG: result.proteinG,
        carbsG: result.carbsG,
        fatG: result.fatG,
        source: source,
        date: DateTime.now(),
      ),
    ));

    return cards;
  }

  // Shows the optional-caption sheet, then posts. Dismissing the sheet
  // without tapping "Post" cancels the whole post.
  Future<void> _promptCaptionAndPostResultCard(ShareCardOption card) async {
    if (!mounted) return;
    final result = await showCaptionSheet(context, fallbackLabel: 'the meal name');
    if (result == null) return;
    await _postResultCardToFeed(card, caption: result.isEmpty ? null : result);
  }

  Future<void> _postResultCardToFeed(ShareCardOption card, {String? caption}) async {
    final result = _result;
    if (result == null || _isPosting) return;
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isPosting = true);
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      final rawName = (profile?['displayName'] as String?)?.trim();
      final authorName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Someone';

      if (!mounted) return;
      final pngBytes = await captureWidgetAsPngBytes(
        context,
        card.builder(context),
        size: const Size(360, 640),
      );
      final imageBase64 = pngBytes != null ? base64Encode(pngBytes) : null;

      await _firestoreService.createFeedPost(
        uid: uid,
        authorName: authorName,
        foodName: result.foodName,
        calories: result.calories,
        proteinG: result.proteinG,
        carbsG: result.carbsG,
        fatG: result.fatG,
        imageBase64: imageBase64,
        caption: caption,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posted to your Club feed!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _shareResultCard(ShareCardOption card) async {
    final result = _result;
    if (result == null || _isSharing) return;

    setState(() => _isSharing = true);
    try {
      if (!mounted) return;
      final bytes = await captureWidgetAsPngBytes(
        context,
        card.builder(context),
        size: const Size(360, 640),
      );
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not generate share card.')),
          );
        }
        return;
      }

      final tempDir = Directory.systemTemp;
      final file = File(
          '${tempDir.path}/wiseworkout_meal_'
          '${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Just logged ${result.foodName} on WiseWorkout! 🍽️',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Called each time the barcode scanner successfully identifies a product.
  // Adds it to the running list — the running total is shown live in the
  // scanner UI so the user can see what they've accumulated so far.
  // ---------------------------------------------------------------------------
  void _addScannedProduct(BarcodeProduct product) {
    setState(() => _scannedProducts.add(product));
  }

  void _finishBarcodeScanning() {
    setState(() => _stage = _Stage.barcodeSummary);
  }

  Future<void> _logAllBarcodeItems() async {
    if (_scannedProducts.isEmpty || _isSaving) return;
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      for (final product in _scannedProducts) {
        await _firestoreService.saveNutritionLog(
          uid,
          foodName: product.name,
          calories: product.calories,
          source: 'barcode',
          proteinG: product.proteinG,
          carbsG: product.carbsG,
          fatG: product.fatG,
          confidence: 'high',
        );
      }
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save items: $e')),
      );
    }
  }

  ({String name, int calories, int protein, int carbs, int fat})
      _barcodeSummaryTotals() {
    final totalCalories =
        _scannedProducts.fold<int>(0, (sum, p) => sum + p.calories);
    final totalProtein =
        _scannedProducts.fold<int>(0, (sum, p) => sum + (p.proteinG ?? 0));
    final totalCarbs =
        _scannedProducts.fold<int>(0, (sum, p) => sum + (p.carbsG ?? 0));
    final totalFat =
        _scannedProducts.fold<int>(0, (sum, p) => sum + (p.fatG ?? 0));
    final summaryName = _scannedProducts.length == 1
        ? _scannedProducts.first.name
        : '${_scannedProducts.length} scanned products';
    return (
      name: summaryName,
      calories: totalCalories,
      protein: totalProtein,
      carbs: totalCarbs,
      fat: totalFat,
    );
  }

  // No _pickedImage to reuse for a barcode summary (barcode scanning never
  // captures a product photo) — always prompt, matching _startResultCardFlow's
  // shape but without the "reuse an existing photo" branch.
  Future<void> _startBarcodeSummaryCardFlow() async {
    if (_isPosting || _scannedProducts.isEmpty) return;
    if (!mounted) return;
    await showQuickAddSheet(context, [
      QuickAddOption(
        icon: Icons.camera_alt_rounded,
        iconColor: WW.primary,
        iconBg: WW.chipBg,
        title: 'Take Photo',
        subtitle: 'Use a photo in the Photo card design',
        onTap: () => _pickPhotoThenContinueBarcode(ImageSource.camera),
      ),
      QuickAddOption(
        icon: Icons.photo_library_rounded,
        iconColor: WW.teal,
        iconBg: WW.tealBg,
        title: 'Choose from Gallery',
        subtitle: 'Pick an existing photo',
        onTap: () => _pickPhotoThenContinueBarcode(ImageSource.gallery),
      ),
      QuickAddOption(
        icon: Icons.arrow_forward_rounded,
        iconColor: WW.textSec,
        iconBg: WW.elevated,
        title: 'Skip Photo',
        subtitle: 'Only offer the Color card design',
        onTap: () => _showBarcodeCardPickerAndContinue(photoBase64: null),
      ),
    ]);
  }

  Future<void> _pickPhotoThenContinueBarcode(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    String? encoded;
    if (picked != null) {
      encoded = await _encodeImageForPost(File(picked.path));
    }
    await _showBarcodeCardPickerAndContinue(photoBase64: encoded);
  }

  Future<void> _showBarcodeCardPickerAndContinue({required String? photoBase64}) async {
    if (!mounted) return;
    final totals = _barcodeSummaryTotals();
    final cards = <ShareCardOption>[
      if (photoBase64 != null)
        ShareCardOption(
          label: 'Photo',
          builder: (_) => PhotoBackgroundShareCard(
            photoBase64: photoBase64,
            title: totals.name,
            badgeLabel: 'Logged',
            stats: [
              ('${totals.calories}', 'Calories'),
              ('${totals.protein}g', 'Protein'),
              ('${totals.carbs}g', 'Carbs'),
              ('${totals.fat}g', 'Fat'),
            ],
            date: DateTime.now(),
          ),
        ),
      ShareCardOption(
        label: 'Color',
        builder: (_) => NutritionShareCardWidget(
          foodName: totals.name,
          calories: totals.calories,
          proteinG: totals.protein,
          carbsG: totals.carbs,
          fatG: totals.fat,
          source: 'manual',
          date: DateTime.now(),
        ),
      ),
    ];

    final chosenIndex = await showShareCardPicker(
      context,
      cards: cards,
      confirmLabel: 'Use This Design',
    );
    if (chosenIndex == null || !mounted) return;
    await _promptCaptionAndPostBarcodeCard(cards[chosenIndex]);
  }

  Future<void> _promptCaptionAndPostBarcodeCard(ShareCardOption card) async {
    if (!mounted) return;
    final result = await showCaptionSheet(context, fallbackLabel: 'the scanned items');
    if (result == null) return;
    await _postBarcodeCardToFeed(card, caption: result.isEmpty ? null : result);
  }

  Future<void> _postBarcodeCardToFeed(ShareCardOption card, {String? caption}) async {
    if (_scannedProducts.isEmpty || _isPosting) return;
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isPosting = true);
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      final rawName = (profile?['displayName'] as String?)?.trim();
      final authorName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Someone';
      final totals = _barcodeSummaryTotals();

      if (!mounted) return;
      final pngBytes = await captureWidgetAsPngBytes(
        context,
        card.builder(context),
        size: const Size(360, 640),
      );
      final imageBase64 = pngBytes != null ? base64Encode(pngBytes) : null;

      await _firestoreService.createFeedPost(
        uid: uid,
        authorName: authorName,
        foodName: totals.name,
        calories: totals.calories,
        proteinG: totals.protein,
        carbsG: totals.carbs,
        fatG: totals.fat,
        imageBase64: imageBase64,
        caption: caption,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posted to your Club feed!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _resetBarcode() {
    setState(() {
      _scannedProducts.clear();
      _stage = _Stage.input;
    });
  }

  void _reset() {
    setState(() {
      _stage = _Stage.input;
      _result = null;
      _pickedImage = null;
      _errorMessage = null;
      _descriptionController.clear();
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      appBar: AppBar(
        backgroundColor: WW.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: WW.text, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Log a Meal', style: WW.titleMed),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_stage == _Stage.result && _result != null) {
      return _ResultView(
        result: _result!,
        image: _mode == _Mode.scan ? _pickedImage : null,
        isSaving: _isSaving,
        isSharing: _isSharing,
        isPosting: _isPosting,
        onLog: _logMeal,
        onShare: () => _startResultCardFlow(forPost: false),
        onPost: () => _startResultCardFlow(forPost: true),
        onDiscard: _reset,
      );
    }

    if (_stage == _Stage.barcodeSummary) {
      return _BarcodeSummaryView(
        products: _scannedProducts,
        isSaving: _isSaving,
        isPosting: _isPosting,
        onLogAll: _logAllBarcodeItems,
        onPost: _startBarcodeSummaryCardFlow,
        onAddMore: () => setState(() => _stage = _Stage.input),
        onDiscard: _resetBarcode,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeToggle(
          mode: _mode,
          onChanged: (m) => setState(() {
            _mode = m;
            _stage = _Stage.input;
            _errorMessage = null;
          }),
        ),
        const SizedBox(height: 20),
        if (_errorMessage != null) ...[
          _InfoBanner(message: _errorMessage!),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: _stage == _Stage.loading
              ? const _LoadingView()
              : switch (_mode) {
                  _Mode.scan => _CameraCaptureView(onImageReady: _handleImage),
                  _Mode.describe => _DescribeInputView(
                      controller: _descriptionController,
                      onSubmit: _submitDescription,
                    ),
                  _Mode.barcode => _BarcodeScannerView(
                      scannedCount: _scannedProducts.length,
                      onProductScanned: _addScannedProduct,
                      onFinished: _finishBarcodeScanning,
                    ),
                },
        ),
      ],
    );
  }
}

// ── Mode toggle ────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _ToggleTab(
            label: 'Scan',
            icon: Icons.camera_alt_rounded,
            selected: mode == _Mode.scan,
            onTap: () => onChanged(_Mode.scan),
          ),
          _ToggleTab(
            label: 'Barcode',
            icon: Icons.qr_code_scanner_rounded,
            selected: mode == _Mode.barcode,
            onTap: () => onChanged(_Mode.barcode),
          ),
          _ToggleTab(
            label: 'Describe',
            icon: Icons.edit_note_rounded,
            selected: mode == _Mode.describe,
            onTap: () => onChanged(_Mode.describe),
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? WW.card : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected ? WW.shadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? WW.primary : WW.textSec),
              const SizedBox(width: 6),
              Text(
                label,
                style: WW.labelMed.copyWith(
                  color: selected ? WW.primary : WW.textSec,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Live camera viewfinder ─────────────────────────────────────────────────
// Full-bleed camera preview with a flash toggle, a shutter button, and a
// gallery button — captured or picked photos are handed back via
// onImageReady(File), which the parent screen sends to NutritionService.

class _CameraCaptureView extends StatefulWidget {
  final ValueChanged<File> onImageReady;
  const _CameraCaptureView({required this.onImageReady});

  @override
  State<_CameraCaptureView> createState() => _CameraCaptureViewState();
}

class _CameraCaptureViewState extends State<_CameraCaptureView>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();
  CameraController? _controller;
  FlashMode _flashMode = FlashMode.off;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found on this device.');
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            "Couldn't access the camera. You can still pick a photo below.");
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  IconData get _flashIcon => switch (_flashMode) {
        FlashMode.off => Icons.flash_off_rounded,
        FlashMode.auto => Icons.flash_auto_rounded,
        _ => Icons.flash_on_rounded,
      };

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      setState(() => _flashMode = next);
    } catch (_) {
      // Some devices/simulators don't support flash — ignore silently.
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      widget.onImageReady(File(file.path));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture photo. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;
    widget.onImageReady(File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              _CoverCameraPreview(controller: controller)
            else
              Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: _CircleIconButton(
                icon: _flashIcon,
                onTap: ready ? _toggleFlash : null,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CircleIconButton(
                    icon: Icons.photo_library_rounded,
                    onTap: _pickFromGallery,
                    size: 46,
                  ),
                  const SizedBox(width: 28),
                  GestureDetector(
                    onTap: ready ? _capture : null,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.white54, width: 3),
                      ),
                      child: _capturing
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: WW.primary,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 28),
                  const SizedBox(width: 46), // balances the gallery button
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Scales the camera preview to fill (cover) its container, cropping any
// overflow — otherwise CameraPreview letterboxes to its native aspect ratio.
class _CoverCameraPreview extends StatelessWidget {
  final CameraController controller;
  const _CoverCameraPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        var scale = size.aspectRatio * controller.value.aspectRatio;
        if (scale < 1) scale = 1 / scale;
        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(child: CameraPreview(controller)),
          ),
        );
      },
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.4),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

// ── Describe input ───────────────────────────────────────────────────────

class _DescribeInputView extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  const _DescribeInputView({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Describe your meal', style: WW.titleMed),
        const SizedBox(height: 6),
        const Text(
          'e.g. "Grilled chicken breast with rice and broccoli"',
          style: WW.labelMed,
        ),
        const SizedBox(height: 16),
        Container(
          decoration: WW.cardDecoration,
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: controller,
            maxLines: 4,
            style: WW.bodyMed,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(14),
              hintText: 'What did you eat?',
              hintStyle: WW.labelMed,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onSubmit,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Estimate Calories'),
          style: ElevatedButton.styleFrom(
            backgroundColor: WW.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Loading ─────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: WW.primary),
          SizedBox(height: 16),
          Text('Analyzing your food…', style: WW.labelMed),
        ],
      ),
    );
  }
}

// ── Info banner (used for fallback / hint messages) ───────────────────────

class _InfoBanner extends StatelessWidget {
  final String message;
  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WW.tealBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: WW.teal, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: WW.labelMed.copyWith(color: WW.text)),
          ),
        ],
      ),
    );
  }
}

// ── Result view ─────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final NutritionResult result;
  final File? image;
  final bool isSaving;
  final bool isSharing;
  final bool isPosting;
  final VoidCallback onLog;
  final VoidCallback onShare;
  final VoidCallback onPost;
  final VoidCallback onDiscard;

  const _ResultView({
    required this.result,
    required this.image,
    required this.isSaving,
    required this.isSharing,
    required this.isPosting,
    required this.onLog,
    required this.onShare,
    required this.onPost,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(image!, height: 180, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(18),
          decoration: WW.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(result.foodName, style: WW.titleLarge),
                  ),
                  _ConfidenceChip(confidence: result.confidence),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.local_fire_department_rounded, color: WW.gold, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    '${result.calories} cal',
                    style: WW.titleMed.copyWith(fontSize: 22, color: WW.gold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _MacroPill(label: 'Protein', value: result.proteinG, color: WW.lavender),
                  const SizedBox(width: 10),
                  _MacroPill(label: 'Carbs', value: result.carbsG, color: WW.teal),
                  const SizedBox(width: 10),
                  _MacroPill(label: 'Fat', value: result.fatG, color: WW.gold),
                ],
              ),
              if (result.message != null && result.message!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(result.message!, style: WW.labelMed),
              ],
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: isSaving ? null : onLog,
          icon: isSaving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded),
          label: Text(isSaving ? 'Saving…' : 'Log This Meal'),
          style: ElevatedButton.styleFrom(
            backgroundColor: WW.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isPosting ? null : onPost,
                icon: isPosting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: WW.primary),
                      )
                    : const Icon(Icons.dynamic_feed_rounded, size: 18),
                label: Text(isPosting ? 'Posting…' : 'Post to Feed'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WW.primary,
                  side: const BorderSide(color: WW.border),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isSharing ? null : onShare,
                icon: isSharing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: WW.primary),
                      )
                    : const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(isSharing ? 'Preparing…' : 'Share'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WW.primary,
                  side: const BorderSide(color: WW.border),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: isSaving ? null : onDiscard,
          child: const Text('Try Again', style: TextStyle(color: WW.textSec)),
        ),
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  final String confidence;
  const _ConfidenceChip({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final label = switch (confidence) {
      'high' => 'High confidence',
      'low' => 'Low confidence',
      _ => 'Estimate',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: WW.caption.copyWith(color: WW.primaryDark)),
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String label;
  final int? value;
  final Color color;
  const _MacroPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('${value ?? 0}g', style: WW.titleMed.copyWith(fontSize: 15, color: color)),
            const SizedBox(height: 2),
            Text(label, style: WW.caption),
          ],
        ),
      ),
    );
  }
}

// ── Live barcode scanner ────────────────────────────────────────────────
// Full-bleed camera view that detects barcodes via mobile_scanner. Each
// detection looks the product up via BarcodeService (Open Food Facts),
// then asks "scan another product?" so multiple packaged items eaten in
// one sitting can be built up into a single running list.

class _BarcodeScannerView extends StatefulWidget {
  final int scannedCount;
  final ValueChanged<BarcodeProduct> onProductScanned;
  final VoidCallback onFinished;

  const _BarcodeScannerView({
    required this.scannedCount,
    required this.onProductScanned,
    required this.onFinished,
  });

  @override
  State<_BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<_BarcodeScannerView> {
  final _scannerController = MobileScannerController();
  final _barcodeService = BarcodeService();
  final _picker = ImagePicker();
  bool _busy = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (code == null || code.isEmpty) return;

    setState(() => _busy = true);
    await _scannerController.stop();
    await _lookupAndShowSheet(code);
  }

  // ---------------------------------------------------------------------------
  // Lets the user pick an existing photo of a barcode instead of using the
  // live camera. mobile_scanner can analyze a static image file directly —
  // no custom decoding needed.
  // ---------------------------------------------------------------------------
  Future<void> _pickFromGallery() async {
    if (_busy) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    await _scannerController.stop();

    BarcodeCapture? capture;
    try {
      capture = await _scannerController.analyzeImage(picked.path);
    } catch (_) {
      capture = null;
    }
    final code = (capture != null && capture.barcodes.isNotEmpty)
        ? capture.barcodes.first.rawValue
        : null;

    if (code == null || code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No barcode found in that photo — try again or use the camera instead.",
          ),
        ),
      );
      await _scannerController.start();
      if (mounted) setState(() => _busy = false);
      return;
    }

    await _lookupAndShowSheet(code);
  }

  // ---------------------------------------------------------------------------
  // Shared by both live detection and gallery-picked photos: looks the code
  // up, shows the found/not-found "scan another?" sheet, then either wraps
  // up scanning or resumes the live camera based on the user's choice.
  // ---------------------------------------------------------------------------
  Future<void> _lookupAndShowSheet(String code) async {
    try {
      final product = await _barcodeService.lookupBarcode(code);
      if (!mounted) return;

      if (product.found) {
        widget.onProductScanned(product);
      }

      final keepGoing = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        builder: (_) => _ProductFoundSheet(
          product: product,
          totalScanned: widget.scannedCount + (product.found ? 1 : 0),
        ),
      );

      if (!mounted) return;
      if (keepGoing == false) {
        widget.onFinished();
        return;
      }
      await _scannerController.start();
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lookup failed: $e')),
      );
      await _scannerController.start();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: _handleDetect,
            ),
            // Scan-frame guide
            Center(
              child: Container(
                width: 240,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.scannedCount > 0
                        ? '${widget.scannedCount} product${widget.scannedCount == 1 ? '' : 's'} scanned'
                        : 'Point at a barcode',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CircleIconButton(
                    icon: Icons.photo_library_rounded,
                    onTap: _busy ? null : _pickFromGallery,
                    size: 46,
                  ),
                  if (widget.scannedCount > 0)
                    ElevatedButton.icon(
                      onPressed: widget.onFinished,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text("I'm Done"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WW.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                ],
              ),
            ),
            if (_busy)
              Container(
                color: Colors.black.withValues(alpha: 0.4),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Bottom sheet shown after each barcode lookup — either shows the found
// product, or a "not found" message — and always asks whether to keep
// scanning or wrap up.
class _ProductFoundSheet extends StatelessWidget {
  final BarcodeProduct product;
  final int totalScanned;

  const _ProductFoundSheet({required this.product, required this.totalScanned});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: WW.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: WW.shadow,
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
              const SizedBox(height: 16),
              if (product.found) ...[
                Row(
                  children: [
                    Expanded(child: Text(product.name, style: WW.titleMed)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: WW.chipBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Added', style: WW.caption.copyWith(color: WW.primaryDark)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Per 100g, as declared by the product', style: WW.caption),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: WW.gold, size: 20),
                    const SizedBox(width: 6),
                    Text('${product.calories} cal',
                        style: WW.titleMed.copyWith(fontSize: 18, color: WW.gold)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MacroPill(label: 'Protein', value: product.proteinG, color: WW.lavender),
                    const SizedBox(width: 10),
                    _MacroPill(label: 'Carbs', value: product.carbsG, color: WW.teal),
                    const SizedBox(width: 10),
                    _MacroPill(label: 'Fat', value: product.fatG, color: WW.primary),
                  ],
                ),
              ] else ...[
                Text('Product not found', style: WW.titleMed),
                const SizedBox(height: 4),
                const Text(
                  "This barcode isn't in the food database yet — try another "
                  "product, or use Describe instead for this one.",
                  style: WW.labelMed,
                ),
              ],
              const SizedBox(height: 20),
              Text(
                totalScanned > 0
                    ? 'Still have products to scan?'
                    : 'Scan a product to get started',
                style: WW.titleMed.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: WW.primary,
                        side: const BorderSide(color: WW.border),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text("No, I'm Done"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WW.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Scan Another'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Barcode multi-item summary ──────────────────────────────────────────

class _BarcodeSummaryView extends StatelessWidget {
  final List<BarcodeProduct> products;
  final bool isSaving;
  final bool isPosting;
  final VoidCallback onLogAll;
  final VoidCallback onPost;
  final VoidCallback onAddMore;
  final VoidCallback onDiscard;

  const _BarcodeSummaryView({
    required this.products,
    required this.isSaving,
    required this.isPosting,
    required this.onLogAll,
    required this.onPost,
    required this.onAddMore,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final totalCalories = products.fold<int>(0, (sum, p) => sum + p.calories);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${products.length} product${products.length == 1 ? '' : 's'} scanned',
            style: WW.titleLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: WW.gold, size: 20),
            const SizedBox(width: 6),
            Text('$totalCalories cal total',
                style: WW.titleMed.copyWith(fontSize: 18, color: WW.gold)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final p = products[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: WW.cardDecoration,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: WW.bodyMed.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${p.calories} cal · per 100g', style: WW.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: isSaving ? null : onLogAll,
          icon: isSaving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded),
          label: Text(isSaving ? 'Saving…' : 'Log All to My Nutrition'),
          style: ElevatedButton.styleFrom(
            backgroundColor: WW.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isPosting ? null : onPost,
                icon: isPosting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: WW.primary),
                      )
                    : const Icon(Icons.dynamic_feed_rounded, size: 18),
                label: Text(isPosting ? 'Posting…' : 'Post to Feed'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WW.primary,
                  side: const BorderSide(color: WW.border),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddMore,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add More'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WW.primary,
                  side: const BorderSide(color: WW.border),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onDiscard,
          child: const Text('Discard All', style: TextStyle(color: WW.textSec)),
        ),
      ],
    );
  }
}
