// lib/screens/cardio/cardio_session_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/health_service.dart';

// Same size-capped downscale-to-480px-JPEG-then-base64 pipeline already used
// by outdoor_cardio_screen.dart's _encodeImageForSession — reused here (not
// imported, since that's a private instance method on a different State
// class) for the standalone indoor-cardio finish form's own photo picker.
const int _kFinishPhotoMaxBase64Bytes = 500 * 1024;

// ── Screen ─────────────────────────────────────────────────────────────────────

class CardioSessionScreen extends StatefulWidget {
  const CardioSessionScreen({super.key});

  @override
  State<CardioSessionScreen> createState() => _CardioSessionScreenState();
}

class _CardioSessionScreenState extends State<CardioSessionScreen> {
  String _activity = 'Run';
  int _plannedMinutes = 30;
  bool _fromPlan = false;
  int _goalMinutes = 0;
  // Which in-progress plan session (and which cardio block within it) this
  // session belongs to, if reached via a plan's cardio block — see
  // cardio_setup_screen.dart's _handleStart(). Not yet used for anything
  // (see this task's scope: threading only); both stay null when this
  // screen is reached standalone.
  String? _sessionRunId;
  int? _blockIndex;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _timer;
  double _weightKg = 70.0;
  String? _uid;
  double? _liveHeartRate;
  bool _healthPermissionGranted = false;
  Timer? _heartRateTimer;
  DateTime? _sessionStartTime;
  bool _showInjuryWarning = false;
  List<Map<String, dynamic>> _activeInjuries = [];
  bool _injuryWarningDismissed = false;
  // Standalone-finish-form fields (sessionRunId == null only — see
  // _showStandaloneFinishForm()/_finishSession()). Never read/shown for a
  // plan-linked cardio block, which finishes exactly as before with no
  // form at all, per earlier design decisions for the mid-plan flow.
  final _finishNameController = TextEditingController();
  final _finishNotesController = TextEditingController();
  File? _finishPickedPhoto;

  @override
  void initState() {
    super.initState();
    _uid = AuthService().getCurrentUser()?.uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      setState(() {
        _activity = extra?['activity'] as String? ?? 'Run';
        _plannedMinutes = extra?['plannedMinutes'] as int? ?? 30;
        _fromPlan = extra?['fromPlan'] as bool? ?? false;
        _goalMinutes = extra?['goalMinutes'] as int? ??
            extra?['plannedMinutes'] as int? ?? 0;
        _sessionRunId = extra?['sessionRunId'] as String?;
        _blockIndex = extra?['blockIndex'] as int?;
      });
      _loadUserWeight();
      _loadInjuryWarning();
      _startTimer();
      _sessionStartTime = DateTime.now();
      _initHealthKit();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heartRateTimer?.cancel();
    _finishNameController.dispose();
    _finishNotesController.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadUserWeight() async {
    if (_uid == null) return;
    final profile = await FirestoreService().getUserProfile(_uid!);
    if (!mounted) return;
    final raw = profile?['weight'];
    if (raw is num) {
      setState(() => _weightKg = raw.toDouble());
    } else if (raw is String) {
      final parsed = double.tryParse(
          raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (parsed != null) setState(() => _weightKg = parsed);
    }
  }

  Future<void> _loadInjuryWarning() async {
    if (_uid == null) return;
    try {
      final data = await FirestoreService()
          .getUserInjuryData(_uid!);
      final enabled =
          data['injuryFilteringEnabled'] as bool? ?? false;
      if (!enabled) return;
      final injuries = List<Map<String, dynamic>>.from(
          data['injuries'] as List? ?? []);
      if (injuries.isEmpty) return;
      if (mounted) {
        setState(() {
          _activeInjuries = injuries;
          _showInjuryWarning = true;
        });
      }
    } catch (_) {}
  }

  double get _calories {
    final met = _activity == 'Run'
        ? 9.0
        : _activity == 'Walk'
            ? 3.5
            : 6.0;
    return met * _weightKg * (_elapsedSeconds / 3600);
  }

  Future<void> _initHealthKit() async {
    final granted = await HealthService().requestPermissions();
    if (!mounted) return;
    setState(() => _healthPermissionGranted = granted);
    if (granted) {
      _heartRateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        final hr = await HealthService().getLatestHeartRate();
        if (!mounted) return;
        setState(() => _liveHeartRate = hr);
      });
    }
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _isRunning = true;
    _isPaused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_goalMinutes > 0 && _elapsedSeconds >= _goalMinutes * 60) {
        _timer?.cancel();
        _handleFinishRequest();
      }
    });
  }

  void _togglePause() {
    setState(() {
      if (_isPaused) {
        _isPaused = false;
        _startTimer();
      } else {
        _isPaused = true;
        _timer?.cancel();
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  // Routes a finish request (manual "Finish" tap or the goal-reached
  // auto-finish in _startTimer()) through the standalone name/notes/photo
  // form first, but only for a genuinely standalone session — a plan-linked
  // cardio block (_sessionRunId != null) goes straight to _finishSession(),
  // completely unchanged, per earlier design decisions for the mid-plan
  // flow (mid-plan cardio blocks don't get their own name, and notes/photo
  // collection for those happens exclusively on
  // mid_plan_cardio_complete_screen.dart instead).
  void _handleFinishRequest() {
    _timer?.cancel();
    if (_sessionRunId == null) {
      _showStandaloneFinishForm();
    } else {
      _finishSession();
    }
  }

  // ── Standalone finish form (name/notes/photo) ─────────────────────────────
  // Same flat WW Title/Notes/photo-picker pattern as
  // outdoor_cardio_screen.dart's own _buildFinishedSummary() form, reused
  // here as a bottom sheet since this screen (unlike outdoor cardio) has no
  // dedicated "finished" body state to swap into.

  void _showStandaloneFinishForm() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: _buildFinishFormSheet,
    );
  }

  Widget _buildFinishFormSheet(BuildContext sheetContext) {
    // StatefulBuilder so picking/clearing a photo updates this sheet's own
    // displayed preview immediately — a showModalBottomSheet's builder is
    // only invoked once when the sheet is pushed, so a setState on the
    // parent CardioSessionScreen State (which _finishPickedPhoto also lives
    // on) wouldn't by itself cause this already-mounted sheet content to
    // rebuild.
    return StatefulBuilder(
      builder: (sheetContext, sheetSetState) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: WW.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Session complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Title',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: WW.cardDecoration,
                  padding: const EdgeInsets.all(4),
                  child: TextField(
                    controller: _finishNameController,
                    style: const TextStyle(fontSize: 14, color: WW.text),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                      hintText: '$_activity · Indoor',
                      hintStyle: const TextStyle(fontSize: 14, color: WW.textSec),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: WW.cardDecoration,
                  padding: const EdgeInsets.all(4),
                  child: TextField(
                    controller: _finishNotesController,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 14, color: WW.text),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(14),
                      hintText: "How'd it go?",
                      hintStyle: TextStyle(fontSize: 14, color: WW.textSec),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _pickFinishPhoto(sheetSetState),
                  child: _finishPickedPhoto == null
                      ? Container(
                          height: 90,
                          decoration: WW.cardDecoration,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_a_photo_rounded,
                                  size: 22,
                                  color: WW.textSec,
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Add a photo',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: WW.textSec,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              Image.file(
                                _finishPickedPhoto!,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () => sheetSetState(
                                      () => _finishPickedPhoto = null),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _finishSession();
                  },
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text(
                        'Save & Finish',
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
        );
      },
    );
  }

  Future<void> _pickFinishPhoto(StateSetter sheetSetState) async {
    final source = await _chooseFinishPhotoSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;
    sheetSetState(() => _finishPickedPhoto = File(picked.path));
  }

  // Camera-vs-gallery choice sheet — same visual pattern as
  // outdoor_cardio_screen.dart's own _buildPhotoSourceSheet (icon circle,
  // title, primary filled button, plain-text secondary button).
  Future<ImageSource?> _chooseFinishPhotoSource() async {
    if (!mounted) return null;
    return showModalBottomSheet<ImageSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: _buildFinishPhotoSourceSheet,
    );
  }

  Widget _buildFinishPhotoSourceSheet(BuildContext sheetContext) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(sheetContext).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: WW.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_a_photo_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Add a photo',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Center(
                child: Text(
                  'Take Photo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            child: Container(
              width: double.infinity,
              height: 50,
              alignment: Alignment.center,
              child: const Text(
                'Choose from Library',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WW.textSec,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Same downscale-to-480px-wide-JPEG-then-base64 pipeline as
  // outdoor_cardio_screen.dart's _encodeImageForSession.
  Future<String?> _encodeFinishPhotoForSession(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(decoded, width: 480);
      final jpegBytes = img.encodeJpg(resized, quality: 75);
      final encoded = base64Encode(jpegBytes);
      if (encoded.length > _kFinishPhotoMaxBase64Bytes) {
        debugPrint(
          'Cardio session: finish photo dropped — encoded size '
          '${encoded.length} bytes exceeds the safety threshold.',
        );
        return null;
      }
      return encoded;
    } catch (_) {
      return null;
    }
  }

  // Branches on whether this session was launched from a plan's cardio
  // block (see cardio_setup_screen.dart's _handleStart(), which forwards
  // sessionRunId/blockIndex through from gym_session_screen.dart). If not
  // (both null), everything below the branch is byte-for-byte the original
  // standalone behavior — untouched. If launched from a plan, this block's
  // result is persisted through the in-progress-session flow instead of
  // creating a separate standalone saveCardioSession() doc, so it ends up
  // inside the one combined session document finalizeInProgressSession()
  // eventually produces rather than an orphaned duplicate.
  Future<void> _finishSession() async {
    _timer?.cancel();
    final uid = _uid;
    final sessionRunId = _sessionRunId;
    final blockIndex = _blockIndex;

    if (uid != null && sessionRunId != null && blockIndex != null) {
      double? avgHR;
      double? maxHR;
      try {
        if (_sessionStartTime != null) {
          final hrData = await HealthService()
              .getHeartRateInRange(_sessionStartTime!, DateTime.now());
          if (hrData.isNotEmpty) {
            final bpms = hrData.map((e) => e.bpm).toList();
            avgHR = bpms.reduce((a, b) => a + b) / bpms.length;
            maxHR = bpms.reduce((a, b) => a > b ? a : b);
          }
        }
      } catch (_) {}

      // isCardio: true must be included — updateInProgressSessionBlock
      // replaces the whole block rather than merging, and
      // finalizeInProgressSession's gym-vs-cardio composition check keys
      // off this field, so leaving it out would silently reclassify this
      // block as a gym exercise with no valid sets data.
      final blockData = <String, dynamic>{
        'isCardio': true,
        'activity': _activity,
        'mode': 'indoor',
        'durationSeconds': _elapsedSeconds,
        'caloriesBurned': _calories.round(),
        'avgHeartRate': ?avgHR,
        'maxHeartRate': ?maxHR,
      };
      // TEMPORARY DEBUG — remove once the second-cardio-block bug is
      // confirmed fixed.
      print('DEBUG_BLOCKINDEX: cardio_session_screen finish uid=$uid '
          'sessionRunId=$sessionRunId blockIndex=$blockIndex');
      await FirestoreService()
          .updateInProgressSessionBlock(uid, sessionRunId, blockIndex, blockData);

      final fullyDone = await FirestoreService()
          .isInProgressSessionFullyDone(uid, sessionRunId);

      if (!mounted) return;

      if (!fullyDone) {
        context.pushReplacement(Routes.midPlanCardioComplete, extra: {
          'sessionRunId': sessionRunId,
          'blockIndex': blockIndex,
          'blockData': blockData,
        });
        return;
      }

      String? finalSessionId;
      try {
        finalSessionId = await FirestoreService()
            .finalizeInProgressSession(uid, sessionRunId);
      } catch (_) {}

      if (!mounted) return;
      context.pushReplacement(Routes.postSessionSummary, extra: {
        'planId': null,
        'sessionName': '$_activity · Indoor',
        'elapsedSeconds': _elapsedSeconds,
        'date': DateTime.now(),
        'exercises': <dynamic>[],
        'isCardio': true,
        'cardioActivity': _activity,
        'cardioCalories': _calories.round(),
        'goalMinutes': _goalMinutes,
        'sessionId': finalSessionId,
      });
      return;
    }

    // Optional name/notes/photo collected via the standalone finish form
    // shown just before this was reached (see _handleFinishRequest()/
    // _showStandaloneFinishForm()) — trimmedName falls back to the same
    // default sessionName saveCardioSession() itself already uses when left
    // blank (see saveCardioSession's own name-fallback logic).
    final trimmedFinishName = _finishNameController.text.trim();
    final trimmedFinishNotes = _finishNotesController.text.trim();
    final defaultSessionName = '$_activity · Indoor';
    final finishSessionName =
        trimmedFinishName.isEmpty ? defaultSessionName : trimmedFinishName;

    String? sessionId;
    if (uid != null) {
      try {
        double? avgHR;
        double? maxHR;
        if (_sessionStartTime != null) {
          final hrData = await HealthService()
              .getHeartRateInRange(_sessionStartTime!, DateTime.now());
          if (hrData.isNotEmpty) {
            final bpms = hrData.map((e) => e.bpm).toList();
            avgHR = bpms.reduce((a, b) => a + b) / bpms.length;
            maxHR = bpms.reduce((a, b) => a > b ? a : b);
          }
        }
        String? photoBase64;
        final finishPhoto = _finishPickedPhoto;
        if (finishPhoto != null) {
          photoBase64 = await _encodeFinishPhotoForSession(finishPhoto);
        }
        sessionId = await FirestoreService().saveCardioSession(
          uid: uid,
          activity: _activity,
          durationSeconds: _elapsedSeconds,
          caloriesBurned: _calories.round(),
          mode: 'indoor',
          avgHeartRate: avgHR,
          maxHeartRate: maxHR,
          name: trimmedFinishName.isEmpty ? null : trimmedFinishName,
          notes: trimmedFinishNotes.isEmpty ? null : trimmedFinishNotes,
          photoBase64: photoBase64,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    context.pushReplacement(Routes.postSessionSummary, extra: {
      'planId': null,
      'sessionName': finishSessionName,
      'elapsedSeconds': _elapsedSeconds,
      'date': DateTime.now(),
      'exercises': <dynamic>[],
      'isCardio': true,
      'cardioActivity': _activity,
      'cardioCalories': _calories.round(),
      'goalMinutes': _goalMinutes,
      'sessionId': sessionId,
    });
  }

  void _showAbandonDialog() {
    _timer?.cancel();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'End session?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: WW.text,
          ),
        ),
        content: const Text(
          'Your progress will not be saved.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Resume timer if session was running
              if (!_isPaused) _startTimer();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WW.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.pop();
            },
            child: const Text(
              'End',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  IconData get _activityIcon {
    switch (_activity) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  Color get _activityColor {
    switch (_activity) {
      case 'Walk':
        return const Color(0xFF22C55E);
      case 'Cycle':
        return WW.lavender;
      default:
        return WW.teal;
    }
  }

  Widget _buildInjuryWarningBanner() {
    if (!_showInjuryWarning || _injuryWarningDismissed) {
      return const SizedBox.shrink();
    }
    final injuryNames = _activeInjuries
        .map((i) => i['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF3C7),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 10,
        12,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.healing_rounded,
                color: Color(0xFFD97706), size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Injury Alert',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Active injuries: $injuryNames. Listen to your body and stop if you feel pain. This is not medical advice.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF92400E),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _injuryWarningDismissed = true);
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final progressValue = _goalMinutes > 0
        ? (_elapsedSeconds / (_goalMinutes * 60)).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: WW.primaryDark,
      body: Column(
        children: [
          _buildInjuryWarningBanner(),
          // ── Top section ───────────────────────────────────────────────────
          Container(
            color: WW.primaryDark,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Header row
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _showAbandonDialog,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.chevron_left_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_activityIcon,
                                  color: _activityColor, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                _activity,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Big elapsed time
                    Text(
                      _fmtTime(_elapsedSeconds),
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _goalMinutes > 0
                          ? 'of $_goalMinutes min goal'
                          : 'Open run',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.15),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(WW.teal),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Stats row ─────────────────────────────────────────────────────
          Container(
            color: WW.card,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                          color: WW.teal, size: 18),
                      const SizedBox(height: 4),
                      Text(
                        '${_calories.round()} kcal',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                        ),
                      ),
                      const Text(
                        'Calories',
                        style: TextStyle(fontSize: 11, color: WW.textSec),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: WW.border),
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.timer_outlined,
                          color: WW.primary, size: 18),
                      const SizedBox(height: 4),
                      Text(
                        _fmtTime(_elapsedSeconds),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                        ),
                      ),
                      const Text(
                        'Time',
                        style: TextStyle(fontSize: 11, color: WW.textSec),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: WW.border),
                Expanded(
                  child: Column(
                    children: [
                      const Icon(Icons.favorite_rounded,
                          color: Color(0xFFEF4444), size: 18),
                      const SizedBox(height: 4),
                      Text(
                        _liveHeartRate != null
                            ? '${_liveHeartRate!.round()} bpm'
                            : '--',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                        ),
                      ),
                      const Text(
                        'Heart Rate',
                        style: TextStyle(fontSize: 11, color: WW.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Middle — big calories + goal status ──────────────────────────
          Expanded(
            child: Container(
              color: WW.bg,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_calories.round()}',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w800,
                        color: WW.text,
                        letterSpacing: -2,
                      ),
                    ),
                    const Text(
                      'kcal burned',
                      style: TextStyle(
                        fontSize: 14,
                        color: WW.textSec,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: WW.elevated,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _goalMinutes > 0
                            ? _elapsedSeconds >= _goalMinutes * 60
                                ? 'Goal reached! Keep going 🏆'
                                : '${_goalMinutes - (_elapsedSeconds ~/ 60)} min remaining'
                            : 'Open run — finish when ready',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WW.textSec,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom controls ───────────────────────────────────────────────
          Container(
            color: WW.card,
            padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Finish button
                GestureDetector(
                  onTap: _handleFinishRequest,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: WW.elevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_rounded,
                            color: WW.textSec, size: 22),
                        SizedBox(height: 4),
                        Text(
                          'Finish',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WW.textSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Pause/Resume button
                GestureDetector(
                  onTap: _togglePause,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _isPaused ? WW.teal : WW.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: WW.primary.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),

                // +5 min / Set goal button
                GestureDetector(
                  onTap: () => setState(() {
                    _goalMinutes =
                        (_goalMinutes > 0 ? _goalMinutes : 30) + 5;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: WW.elevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: WW.primary, size: 22),
                        const SizedBox(height: 4),
                        Text(
                          _goalMinutes > 0 ? '+5 min' : 'Set goal',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: WW.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
