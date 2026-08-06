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
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/barcode_service.dart';
import '../../services/firestore_service.dart';
import '../../services/nutrition_service.dart';
import '../../widgets/caption_sheet.dart';

enum _Mode { scan, describe, barcode }
// correcting: shown when the user flags a photo-scan result as wrong (see
// _ResultView's confirm prompt) — a text-description re-estimate step,
// styled like _Mode.describe's own input but with correction-specific
// copy. Only ever entered from a scan-mode result; describe/barcode
// results never show the "is this right?" prompt that leads here.
enum _Stage { input, loading, result, error, barcodeSummary, correcting }

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

  // Entered from _ResultView's "No, let me fix it" confirm prompt (scan-
  // mode results only). Same re-estimate call as _submitDescription()
  // (analyzeFoodDescription) — on success, replaces _result in place and
  // returns to the same result screen with corrected data; _mode/
  // _pickedImage are left untouched, so the original photo still shows
  // and is still reusable for the share-card Photo option, exactly as
  // before the correction.
  Future<void> _submitCorrection() async {
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
      final imageBase64 = await _resolveExistingResultPhotoBase64();
      await _firestoreService.saveNutritionLog(
        uid,
        foodName: result.foodName,
        calories: result.calories,
        source: _mode == _Mode.scan ? 'scan' : 'manual',
        proteinG: result.proteinG,
        carbsG: result.carbsG,
        fatG: result.fatG,
        confidence: result.confidence,
        imageBase64: imageBase64,
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
  // Returns null (post/log goes out without a photo) rather than failing
  // the whole save if anything goes wrong. Used by _logMeal() below to
  // attach the scan photo to the saved nutritionLogs entry — unrelated to
  // the share-card flow further down (that one never attaches a photo,
  // see the comment there).
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

  Future<String?> _resolveExistingResultPhotoBase64() {
    if (_mode == _Mode.scan && _pickedImage != null) {
      return _encodeImageForPost(_pickedImage!);
    }
    return Future.value(null);
  }

  // ---------------------------------------------------------------------------
  // Share / Post to Feed — no card generation at all. Uses the meal's
  // actual scanned/picked photo (already encoded by
  // _resolveExistingResultPhotoBase64, same helper _logMeal() uses) as
  // the post/share image directly, exactly like older meal posts — no
  // NutritionShareCardWidget, no RenderRepaintBoundary capture step. If
  // the meal has no photo at all (describe-mode, no image ever picked),
  // posts/shares without an image — FeedPostCard already renders a
  // photo-less post fine, and native share falls back to text-only.
  // ---------------------------------------------------------------------------

  Future<void> _startResultCardFlow({required bool forPost}) async {
    if (forPost ? _isPosting : _isSharing) return;
    if (_result == null) return;
    if (forPost) {
      await _promptCaptionAndPostResultCard();
    } else {
      await _shareResultCard();
    }
  }

  // Shows the optional-caption sheet, then posts. Dismissing the sheet
  // without tapping "Post" cancels the whole post.
  Future<void> _promptCaptionAndPostResultCard() async {
    if (!mounted) return;
    final result = await showCaptionSheet(context, fallbackLabel: 'the meal name');
    if (result == null) return;
    await _postResultCardToFeed(caption: result.isEmpty ? null : result);
  }

  Future<void> _postResultCardToFeed({String? caption}) async {
    final result = _result;
    if (result == null || _isPosting) return;
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isPosting = true);
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      final rawName = (profile?['displayName'] as String?)?.trim();
      final authorName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Someone';
      final authorPhotoBase64 = profile?['photoBase64'] as String?;
      final imageBase64 = await _resolveExistingResultPhotoBase64();

      await _firestoreService.createFeedPost(
        uid: uid,
        authorName: authorName,
        authorPhotoBase64: authorPhotoBase64,
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

  Future<void> _shareResultCard() async {
    final result = _result;
    if (result == null || _isSharing) return;

    setState(() => _isSharing = true);
    try {
      final image = _mode == _Mode.scan ? _pickedImage : null;
      final text = 'Just logged ${result.foodName} on WiseWorkout! 🍽️';
      if (image != null) {
        await Share.shareXFiles([XFile(image.path)], text: text);
      } else {
        await Share.share(text);
      }
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

  Future<void> _startBarcodeSummaryCardFlow() async {
    if (_isPosting || _scannedProducts.isEmpty) return;
    await _promptCaptionAndPostBarcodeCard();
  }

  Future<void> _promptCaptionAndPostBarcodeCard() async {
    if (!mounted) return;
    final result = await showCaptionSheet(context, fallbackLabel: 'the scanned items');
    if (result == null) return;
    await _postBarcodeCardToFeed(caption: result.isEmpty ? null : result);
  }

  Future<void> _postBarcodeCardToFeed({String? caption}) async {
    if (_scannedProducts.isEmpty || _isPosting) return;
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isPosting = true);
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      final rawName = (profile?['displayName'] as String?)?.trim();
      final authorName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Someone';
      final authorPhotoBase64 = profile?['photoBase64'] as String?;
      final totals = _barcodeSummaryTotals();

      // Barcode-scanned products never have an attached photo (no camera
      // step in that flow) — posts without an image, same as a
      // describe-mode meal with none.
      await _firestoreService.createFeedPost(
        uid: uid,
        authorName: authorName,
        authorPhotoBase64: authorPhotoBase64,
        foodName: totals.name,
        calories: totals.calories,
        proteinG: totals.protein,
        carbsG: totals.carbs,
        fatG: totals.fat,
        imageBase64: null,
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
        isScanMode: _mode == _Mode.scan,
        onLog: _logMeal,
        onShare: () => _startResultCardFlow(forPost: false),
        onPost: () => _startResultCardFlow(forPost: true),
        onDiscard: _reset,
        onIncorrect: () => setState(() {
          _descriptionController.clear();
          _stage = _Stage.correcting;
        }),
      );
    }

    if (_stage == _Stage.correcting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _DescribeInputView(
              controller: _descriptionController,
              onSubmit: _submitCorrection,
              title: 'What is it actually?',
              subtitle: 'Describe the food so we can get a corrected estimate.',
              hintText: 'e.g. "Fish burger with fries"',
              buttonLabel: 'Get Corrected Estimate',
              autofocus: true,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _stage = _Stage.result),
            child: const Text('Cancel — keep original result',
                style: TextStyle(color: WW.textSec)),
          ),
        ],
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
      final resized = await _resizeCapturedPhoto(File(file.path));
      widget.onImageReady(resized);
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

  // CameraController.takePicture() has no size/quality parameters of its
  // own (unlike ImagePicker.pickImage() below), so a live camera capture
  // previously went out unresized/uncompressed — inconsistent with
  // _pickFromGallery()'s already-capped output, and a real payload-size
  // risk once analyzeFoodImage() relays through a Cloud Function instead
  // of calling OpenAI directly. Downscales after the fact to roughly match
  // ImagePicker(maxWidth: 1024, imageQuality: 80)'s output, using the
  // `image` package — already a pubspec dependency, same decode/
  // copyResize/encodeJpg pattern outdoor_cardio_screen.dart's
  // _encodeImageForSession() already uses. Only downsizes (never upscales
  // a smaller capture), matching ImagePicker's own maxWidth semantics.
  // Falls back to the original unresized file if decoding fails for any
  // reason, rather than blocking the capture entirely over a resize
  // failure.
  Future<File> _resizeCapturedPhoto(File original) async {
    try {
      final bytes = await original.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return original;
      final resized =
          decoded.width > 1024 ? img.copyResize(decoded, width: 1024) : decoded;
      final jpegBytes = img.encodeJpg(resized, quality: 80);
      await original.writeAsBytes(jpegBytes);
      return original;
    } catch (_) {
      return original;
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
  // Parametrized (with defaults matching the original describe-mode copy)
  // so the correction flow (_Stage.correcting) can reuse this exact
  // widget/styling with its own copy instead of a near-duplicate.
  final String title;
  final String subtitle;
  final String hintText;
  final String buttonLabel;
  final bool autofocus;

  const _DescribeInputView({
    required this.controller,
    required this.onSubmit,
    this.title = 'Describe your meal',
    this.subtitle = 'e.g. "Grilled chicken breast with rice and broccoli"',
    this.hintText = 'What did you eat?',
    this.buttonLabel = 'Estimate Calories',
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    // Scrollable — this widget is placed inside an Expanded by both of its
    // callers (describe mode and the correction flow), which gives it a
    // bounded but potentially short height (e.g. small screens, or the
    // keyboard eating vertical space once the field is focused). Its
    // content has no flexible children of its own, so wrapping it here is
    // enough to let it scroll instead of overflow.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: WW.titleMed),
          const SizedBox(height: 6),
          Text(subtitle, style: WW.labelMed),
          const SizedBox(height: 16),
          Container(
            decoration: WW.cardDecoration,
            padding: const EdgeInsets.all(4),
            child: TextField(
              controller: controller,
              maxLines: 4,
              autofocus: autofocus,
              style: WW.bodyMed,
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                hintText: hintText,
                hintStyle: WW.labelMed,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(buttonLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: WW.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
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
  // Gates the "Is this right?" confirm prompt — only a photo scan can be
  // misidentified by AI vision; a describe-mode result is already
  // whatever the user typed, and barcode results (a different screen
  // entirely, _BarcodeSummaryView) come from a real product database.
  final bool isScanMode;
  final VoidCallback onLog;
  final VoidCallback onShare;
  final VoidCallback onPost;
  final VoidCallback onDiscard;
  final VoidCallback onIncorrect;

  const _ResultView({
    required this.result,
    required this.image,
    required this.isSaving,
    required this.isSharing,
    required this.isPosting,
    required this.isScanMode,
    required this.onLog,
    required this.onShare,
    required this.onPost,
    required this.onDiscard,
    required this.onIncorrect,
  });

  @override
  Widget build(BuildContext context) {
    // Scrollable content above a fixed footer (Log/Post/Share/Try Again),
    // rather than a single non-scrolling Column with a Spacer — on short
    // screens (e.g. the Small_Phone emulator profile) the stats card plus
    // the "Is this right?" confirm section no longer fit above the
    // buttons, so this needs to scroll instead of overflow. Spacer()
    // can't be used here at all since it requires bounded/flex space,
    // which conflicts with a scrollable region.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
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
                if (isScanMode) ...[
                  const SizedBox(height: 14),
                  _ConfirmAccuracyPrompt(onIncorrect: onIncorrect),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
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

// "Is this right?" confirm prompt — scan-mode results only (see
// _ResultView.isScanMode). "Yes" just acknowledges locally (no data
// change, matches "proceeds exactly as today"); "No" hands off to the
// parent's onIncorrect, which switches to the correction stage. Its own
// tiny bit of local state (whether it's been confirmed) is kept here
// rather than lifted to the parent screen — nothing outside this widget
// needs to know about it.
class _ConfirmAccuracyPrompt extends StatefulWidget {
  final VoidCallback onIncorrect;
  const _ConfirmAccuracyPrompt({required this.onIncorrect});

  @override
  State<_ConfirmAccuracyPrompt> createState() => _ConfirmAccuracyPromptState();
}

class _ConfirmAccuracyPromptState extends State<_ConfirmAccuracyPrompt> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    if (_confirmed) {
      return Row(
        children: const [
          Icon(Icons.check_circle_rounded, color: WW.teal, size: 16),
          SizedBox(width: 6),
          Text('Marked as correct', style: WW.labelMed),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Is this right?',
            style: WW.labelMed.copyWith(fontWeight: FontWeight.w700, color: WW.text),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _confirmed = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WW.teal,
                    side: const BorderSide(color: WW.teal),
                    minimumSize: const Size.fromHeight(38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    "Yes, that's correct",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onIncorrect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WW.textSec,
                    side: const BorderSide(color: WW.border),
                    minimumSize: const Size.fromHeight(38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'No, let me fix it',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
