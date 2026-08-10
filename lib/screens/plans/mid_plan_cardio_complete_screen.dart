// lib/screens/plans/mid_plan_cardio_complete_screen.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Same size-capped base64-JPEG approach as outdoor_cardio_screen.dart's own
// _encodeImageForSession — see that file's doc comment for why JPEG (via
// the `image` package) rather than dart:ui's PNG-only encoder, and why a
// safety cap is checked afterward regardless.
const int _kMaxImageBase64Bytes = 500 * 1024;

// Shown after a cardio block finishes mid-plan-session, when other blocks
// in the same plan day still remain — see cardio_session_screen.dart's and
// outdoor_cardio_screen.dart's _finishSession()/_saveActivity(), which push
// here (via pushReplacement, replacing themselves in the stack) instead of
// post_session_summary_screen.dart whenever
// FirestoreService().isInProgressSessionFullyDone() comes back false.
//
// Deliberately no back/close button: by the time this screen is reached,
// the cardio activity is already finished and saved (see blockData below)
// — there's nothing meaningful to go "back" to, only forward to the next
// block. This mirrors outdoor_cardio_screen.dart's own finished-summary
// step, which is similarly forward-only once tracking has stopped.
class MidPlanCardioCompleteScreen extends StatefulWidget {
  const MidPlanCardioCompleteScreen({super.key});

  @override
  State<MidPlanCardioCompleteScreen> createState() =>
      _MidPlanCardioCompleteScreenState();
}

class _MidPlanCardioCompleteScreenState
    extends State<MidPlanCardioCompleteScreen> {
  String? _sessionRunId;
  String? _blockId;
  Map<String, dynamic> _blockData = {};

  // planId/dayIndex — needed by "Next" to resume gym_session_screen.dart
  // via context.go(Routes.gymSession, extra: {...}). Not otherwise
  // available here: cardio_setup_screen.dart's extra passthrough (the
  // screen that originally launched the cardio activity this screen
  // follows) isn't part of this task's editable files, so rather than
  // thread these two fields through that screen too, they're read
  // directly off the in-progress session doc itself —
  // createInProgressSession() already stores both there, so a single
  // getInProgressSession() call recovers them independently of how this
  // screen was reached.
  String? _planId;
  int? _dayIndex;

  final _notesController = TextEditingController();
  File? _pickedPhoto;
  // Preview-only decode of any photoBase64 already present in the incoming
  // blockData (e.g. carried over from upstream before Fix 1 made that
  // unreachable in practice, or from a retry of this same screen) — set
  // once in initState, cleared if the user removes it or picks a new
  // photo. _pickedPhoto (a fresh local pick) always takes precedence over
  // this in the UI below.
  Uint8List? _existingPhotoBytes;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      final rawBlockData = extra?['blockData'];
      final sessionRunId = extra?['sessionRunId'] as String?;
      setState(() {
        _sessionRunId = sessionRunId;
        _blockId = extra?['blockId'] as String?;
        _blockData = rawBlockData is Map
            ? Map<String, dynamic>.from(rawBlockData)
            : <String, dynamic>{};
        final existingPhotoBase64 = _blockData['photoBase64'] as String?;
        if (existingPhotoBase64 != null && existingPhotoBase64.isNotEmpty) {
          try {
            _existingPhotoBytes = base64Decode(existingPhotoBase64);
          } catch (_) {}
        }
      });
      // Pre-fill with any notes already collected upstream (e.g. outdoor
      // cardio's own finished-summary form) so this screen edits/extends
      // rather than silently hiding them — see _handleNext's doc comment
      // for how leaving this field untouched avoids a redundant write.
      final existingNotes = _blockData['notes'] as String?;
      if (existingNotes != null && existingNotes.isNotEmpty) {
        _notesController.text = existingNotes;
      }

      final uid = AuthService().getCurrentUser()?.uid;
      if (uid == null || sessionRunId == null) return;
      final data =
          await FirestoreService().getInProgressSession(uid, sessionRunId);
      if (!mounted || data == null) return;
      setState(() {
        _planId = data['planId'] as String?;
        _dayIndex = (data['dayIndex'] as num?)?.toInt();
      });
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // Same 50m-floor + MM:SS/km convention already used throughout this app
  // (outdoor_cardio_screen.dart's _paceLabel, activity_detail_screen.dart's
  // _avgPaceLabel) — null below that floor or when duration/distance
  // aren't both available, rather than a noisy/nonsensical pace.
  String? _avgPaceLabel(double? distanceMeters, int? durationSeconds) {
    if (distanceMeters == null || durationSeconds == null) return null;
    if (distanceMeters < 50 || durationSeconds <= 0) return null;
    final secondsPerKm = durationSeconds / (distanceMeters / 1000);
    if (!secondsPerKm.isFinite) return null;
    final mins = secondsPerKm ~/ 60;
    final secs = (secondsPerKm % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} /km';
  }

  // ── Photo picker ─────────────────────────────────────────────────────
  // Same pattern as outdoor_cardio_screen.dart's own
  // _pickPhoto/_choosePhotoSource/_buildPhotoSourceSheet/
  // _encodeImageForSession (camera-vs-gallery choice sheet, then
  // downscale-to-480px-wide-JPEG-then-base64 via the `image` package).
  // Duplicated rather than shared since those are private instance methods
  // on a different State class — no new image pipeline introduced.

  Future<void> _pickPhoto() async {
    final source = await _choosePhotoSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _pickedPhoto = File(picked.path));
  }

  Future<ImageSource?> _choosePhotoSource() async {
    if (!mounted) return null;
    return showModalBottomSheet<ImageSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: _buildPhotoSourceSheet,
    );
  }

  Widget _buildPhotoSourceSheet(BuildContext sheetContext) {
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

  // Same mm:ss/h:mm:ss convention as outdoor_cardio_screen.dart's and
  // cardio_session_screen.dart's own _fmtTime — reused here rather than
  // inventing a new format.
  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<String?> _encodePhoto(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(decoded, width: 480);
      final jpegBytes = img.encodeJpg(resized, quality: 75);
      final encoded = base64Encode(jpegBytes);
      if (encoded.length > _kMaxImageBase64Bytes) return null;
      return encoded;
    } catch (_) {
      return null;
    }
  }

  // ── Next ─────────────────────────────────────────────────────────────
  // Only writes a second time if the user actually entered something new
  // here (notes and/or a photo) — otherwise this is a deliberate no-op, so
  // a block whose notes/photo were already collected upstream (outdoor
  // cardio's own finished-summary form, written in the finish handler
  // before this screen was ever reached) isn't redundantly rewritten with
  // the exact same data. When it does write, it merges into the ORIGINAL
  // blockData (received via extra — exactly what the finish handler
  // already wrote) rather than sending just {notes, photoBase64} alone:
  // updateInProgressSessionBlock replaces the whole block rather than
  // merging server-side, so a partial map here would silently wipe out
  // the stats (distance, calories, etc.) already written for this block.
  Future<void> _handleNext() async {
    final sessionRunId = _sessionRunId;
    final blockId = _blockId;
    final trimmedNotes = _notesController.text.trim();
    final photo = _pickedPhoto;
    final hasNewData = trimmedNotes.isNotEmpty || photo != null;

    if (sessionRunId != null && blockId != null && hasNewData) {
      setState(() => _isSaving = true);
      final uid = AuthService().getCurrentUser()?.uid;
      if (uid != null) {
        String? photoBase64;
        if (photo != null) photoBase64 = await _encodePhoto(photo);
        final mergedBlockData = <String, dynamic>{
          ..._blockData,
          if (trimmedNotes.isNotEmpty) 'notes': trimmedNotes,
          'photoBase64': ?photoBase64,
        };
        await FirestoreService().updateInProgressSessionBlock(
            uid, sessionRunId, blockId, mergedBlockData);
      }
      if (!mounted) return;
      setState(() => _isSaving = false);
    }

    if (!mounted) return;
    // Returns to gym_session_screen.dart via context.go() rather than
    // popping back through the stack — the previous approach assumed an
    // exact stack depth (gym_session -> cardio_setup -> this screen) that
    // broke for any plan whose block order/screen path differed from the
    // one case it was built against. context.go() instead reaches
    // gym_session_screen.dart fresh, with sessionRunId in extra so
    // _loadPlanSession() (see its own doc comment) hydrates the exercise
    // list and every block/set's done state directly from Firestore —
    // correct regardless of how this screen was reached or what's
    // currently on the navigation stack.
    //
    // 'forceRefresh' — sessionRunId/planId/dayIndex are all identical on
    // every "Next" tap within the same session (set once at session start,
    // never touched again), so router.dart's identity-based key-caching
    // (added to stop an unrelated push-on-top from tearing down a live gym
    // session — see that route's own doc comment) would otherwise treat
    // every "Next" after the first as a cache hit and reuse the already-
    // mounted GymSessionScreen instance, silently skipping the rehydrate
    // this call was specifically written to guarantee. A fresh value here
    // on every tap forces router.dart's identity string to differ each
    // time, guaranteeing a cache miss (and therefore a genuinely fresh
    // instance/rehydrate) regardless of how many times "Next" is tapped
    // within the same unchanging session.
    context.go(Routes.gymSession, extra: {
      'planId': _planId,
      'dayIndex': _dayIndex,
      'sessionRunId': _sessionRunId,
      'forceRefresh': DateTime.now().microsecondsSinceEpoch.toString(),
    });
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: Icon(Icons.check_circle_rounded,
                          size: 44, color: WW.primary),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Block complete',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: WW.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'More of today’s session is still ahead.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: WW.textSec),
                    ),
                    const SizedBox(height: 20),
                    _buildStatsCard(),
                    const SizedBox(height: 20),
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
                        controller: _notesController,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 14, color: WW.text),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                          hintText: "How'd it go?",
                          hintStyle:
                              TextStyle(fontSize: 14, color: WW.textSec),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _pickPhoto,
                      child: _pickedPhoto == null && _existingPhotoBytes == null
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
                                  // maxHeight caps how tall this gets
                                  // without cropping the photo —
                                  // BoxFit.contain shows the whole image
                                  // (letterboxed against WW.elevated when
                                  // its aspect ratio doesn't fill the box),
                                  // instead of the previous fixed
                                  // height: 160 + BoxFit.cover, which
                                  // cropped whatever didn't fit a
                                  // 160px-tall strip regardless of the
                                  // photo's real shape.
                                  Container(
                                    width: double.infinity,
                                    constraints:
                                        const BoxConstraints(maxHeight: 220),
                                    color: WW.elevated,
                                    child: _pickedPhoto != null
                                        ? Image.file(
                                            _pickedPhoto!,
                                            width: double.infinity,
                                            fit: BoxFit.contain,
                                          )
                                        : Image.memory(
                                            _existingPhotoBytes!,
                                            width: double.infinity,
                                            fit: BoxFit.contain,
                                          ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _pickedPhoto = null;
                                        _existingPhotoBytes = null;
                                      }),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.5),
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
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GestureDetector(
                onTap: _isSaving ? null : _handleNext,
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Next',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Flat WW.cardDecoration box, no icon chips/gradients — matches this
  // app's established flat design language (activity_detail_screen.dart's
  // stats row; this task's own instruction to start matching it here).
  // Rows for distance/avg pace/avg heart rate are included only when the
  // underlying value is actually present — no placeholders for data this
  // particular block didn't produce (e.g. indoor cardio has no distance at
  // all; outdoor cardio doesn't currently compute avg heart rate).
  Widget _buildStatsCard() {
    final distanceMeters = (_blockData['distanceMeters'] as num?)?.toDouble();
    final durationSeconds = (_blockData['durationSeconds'] as num?)?.toInt();
    final avgHeartRate = (_blockData['avgHeartRate'] as num?)?.toDouble();
    final paceLabel = _avgPaceLabel(distanceMeters, durationSeconds);

    // Duration first — the one stat guaranteed to exist for both indoor
    // (no distance) and outdoor cardio, so this card is never left empty.
    final rows = <(String, String)>[
      if (durationSeconds != null && durationSeconds > 0)
        ('Duration', _fmtDuration(durationSeconds)),
      if (distanceMeters != null)
        ('Distance', '${(distanceMeters / 1000).toStringAsFixed(2)} km'),
      if (paceLabel != null) ('Avg Pace', paceLabel),
      if (avgHeartRate != null)
        ('Avg Heart Rate', '${avgHeartRate.round()} bpm'),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 10),
              Container(height: 0.5, color: WW.border),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  rows[i].$1,
                  style: const TextStyle(fontSize: 13, color: WW.textSec),
                ),
                Text(
                  rows[i].$2,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: WW.text,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
