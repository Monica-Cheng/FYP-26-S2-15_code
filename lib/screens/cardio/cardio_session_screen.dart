// lib/screens/cardio/cardio_session_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';

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

// ── Indoor motion-presence accrual gate (accelerometer-based) ──────────────────
// Mirrors outdoor_cardio_screen.dart's GPS-based accrual-pause debounce/
// hysteresis scaffolding exactly — only the underlying detection signal
// differs, since indoor has no GPS/distance signal to check speed or
// displacement against. See _computeIndoorAccrualPaused() for the
// detection logic this feeds.
//
// All 4 constants below are now Firestore-configurable, via
// appConfig/gamification's cardioAntiCheat.indoor{} — see
// FirestoreService().getGamificationConfig()'s own doc comment for the
// overall pattern, and _loadCardioAntiCheatConfig()/_configNum() below for
// how this screen fetches and applies it. Each _kFallback-prefixed const
// below is kept, unchanged, as exactly today's original hardcoded value —
// used only when the config doc is missing, malformed, or unreachable;
// the actual mutable instance field the rest of this class reads from
// (same name, minus the _kFallback prefix) starts at this fallback and is
// overwritten once the config fetch resolves.

// Rolling window (seconds) of accelerometer magnitude samples used to
// judge whether the phone is genuinely still. Within the 3-5s range this
// feature was scoped to — short enough to react quickly once genuine
// motion resumes, long enough that a single brief still moment (adjusting
// grip, a pause between treadmill belt encoder ticks) doesn't register as
// sustained stillness on its own.
const int _kFallbackIndoorStillnessWindowSeconds = 4;

// Variance threshold (m/s²)² for the rolling window's acceleration-
// magnitude readings, below which the phone is judged to be at rest.
// Deliberately lenient, per explicit product priority to avoid false
// positives over maximizing strictness: consumer-phone accelerometer
// noise while genuinely motionless (resting on a surface) typically
// produces variance well under 0.01 (m/s²)² on the linear-acceleration
// magnitude; even mild real motion (phone in a pocket or armband during a
// slow walk, resting on a vibrating treadmill console) readily produces
// variance many times higher. 0.02 sits comfortably above genuine-
// stillness noise while staying well below what even gentle real motion
// produces — a borderline reading defaults to NOT pausing. This is a
// reasoned starting estimate, not measured against real device logs —
// worth tuning against actual on-device data if false positives/
// negatives are reported in testing.
const double _kFallbackIndoorStillnessVarianceThreshold = 0.02;

// Same asymmetric debounce reasoning as outdoor's own accrual pause/resume
// debounce ticks (see that file's doc comment) — pausing (denying
// calorie/XP credit) requires more sustained evidence than resuming,
// since a false pause only costs UX while a false resume costs real
// anti-cheat effectiveness. Mirrored exactly (3 ticks to pause, 2 to
// resume) since the same reasoning applies unchanged to this signal.
const int _kFallbackIndoorAccrualPauseDebounceTicks = 3;
const int _kFallbackIndoorAccrualResumeDebounceTicks = 2;

// Reads a nested numeric field out of a gamification config map (e.g.
// path ['cardioAntiCheat', 'indoor', 'stillnessVarianceThreshold']),
// falling back to `fallback` if any segment of the path is missing, the
// wrong type, or the map itself is empty — mirrors
// FirestoreService()'s own private _configNum() (duplicated here rather
// than shared, matching outdoor_cardio_screen.dart's own identical local
// copy for the same reason).
num _configNum(Map<String, dynamic>? config, List<String> path, num fallback) {
  dynamic current = config;
  for (final key in path) {
    if (current is! Map) return fallback;
    current = current[key];
  }
  return current is num ? current : fallback;
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class CardioSessionScreen extends StatefulWidget {
  const CardioSessionScreen({super.key});

  @override
  State<CardioSessionScreen> createState() => _CardioSessionScreenState();
}

class _CardioSessionScreenState extends State<CardioSessionScreen> {
  // True from mount until the gamification config load (or its timeout/
  // fallback) resolves — tracking must not begin before this clears, so
  // the anti-cheat thresholds it feeds are never briefly stale mid-session
  // (see _prepareAndStartSession()). Gates build() below to a simple
  // loading view for this short window.
  bool _isPreparingSession = true;
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

  // ── Indoor motion-presence accrual gate — see the module-level constants
  // and _computeIndoorAccrualPaused()/_initMotionSensing() doc comments
  // for the full reasoning. _activeSeconds is the gated counter calories/
  // persisted duration actually derive from (see _calories/_finishSession)
  // — kept separate from _elapsedSeconds, which stays wall-clock (used for
  // the on-screen timer/goal countdown/auto-finish), exactly mirroring how
  // outdoor_cardio_screen.dart separates _activeSeconds from real elapsed
  // time via its own debounce/hysteresis gate.
  int _activeSeconds = 0;
  bool _accrualPaused = false;
  int _consecutivePauseConditionTicks = 0;
  int _consecutiveClearConditionTicks = 0;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  final List<(DateTime, double)> _recentAccelMagnitudes = [];
  // True once accelerometer sensing has failed/proven unavailable (see
  // _initMotionSensing()) — _computeIndoorAccrualPaused() always returns
  // false while this is true, i.e. accrual is never paused, falling back
  // to today's uncapped-accrual behavior rather than breaking the session
  // over a missing/failed sensor.
  bool _motionSensingUnavailable = false;
  // Firestore-configurable — see _loadCardioAntiCheatConfig() and the
  // _kFallback-prefixed consts above. Each starts at its own fallback and
  // is overwritten once the config fetch resolves.
  int _stillnessWindowSeconds = _kFallbackIndoorStillnessWindowSeconds;
  double _stillnessVarianceThreshold = _kFallbackIndoorStillnessVarianceThreshold;
  int _accrualPauseDebounceTicks = _kFallbackIndoorAccrualPauseDebounceTicks;
  int _accrualResumeDebounceTicks = _kFallbackIndoorAccrualResumeDebounceTicks;
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
      // Started immediately (unaffected by the config gate below) so the
      // rolling magnitude buffer already has samples by the time tracking
      // actually begins.
      _initMotionSensing();
      _prepareAndStartSession();
    });
  }

  // Tracking must not begin until the anti-cheat config load has resolved
  // (or safely fallen back) — per product decision, closing the earlier
  // race window where _startTimer() could fire in parallel with a
  // still-in-flight config fetch, briefly running on fallback defaults
  // until the real values arrived mid-session. _isPreparingSession gates
  // build() to a simple loading view for this window (see build()'s own
  // early-return) — in practice this resolves near-instantly on a healthy
  // connection, since the fetch starts the moment the screen mounts and a
  // normal Firestore read completes well under a second.
  //
  // The .timeout() below is a belt-and-suspenders safety net, not the
  // primary fallback mechanism: _loadCardioAntiCheatConfig() already can't
  // hang or throw on its own (FirestoreService().getGamificationConfig()
  // fails soft to {} on any error, per its own doc comment, and every
  // field extracted from it already falls back to today's hardcoded
  // default individually). This timeout exists purely to guarantee this
  // screen itself can never get stuck on the preparing view even in some
  // unforeseen scenario, without needing to touch firestore_service.dart.
  Future<void> _prepareAndStartSession() async {
    try {
      await _loadCardioAntiCheatConfig()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {
      // Fields already sit at their hardcoded fallback defaults — nothing
      // further to do, just proceed.
    }
    if (!mounted) return;
    setState(() => _isPreparingSession = false);
    _startTimer();
    _sessionStartTime = DateTime.now();
    _initHealthKit();
  }

  Future<void> _loadCardioAntiCheatConfig() async {
    final config = await FirestoreService().getGamificationConfig();
    if (!mounted) return;
    _stillnessWindowSeconds = _configNum(
            config,
            ['cardioAntiCheat', 'indoor', 'stillnessWindowSeconds'],
            _kFallbackIndoorStillnessWindowSeconds)
        .toInt();
    _stillnessVarianceThreshold = _configNum(
            config,
            ['cardioAntiCheat', 'indoor', 'stillnessVarianceThreshold'],
            _kFallbackIndoorStillnessVarianceThreshold)
        .toDouble();
    _accrualPauseDebounceTicks = _configNum(
            config,
            ['cardioAntiCheat', 'indoor', 'accrualPauseDebounceTicks'],
            _kFallbackIndoorAccrualPauseDebounceTicks)
        .toInt();
    _accrualResumeDebounceTicks = _configNum(
            config,
            ['cardioAntiCheat', 'indoor', 'accrualResumeDebounceTicks'],
            _kFallbackIndoorAccrualResumeDebounceTicks)
        .toInt();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heartRateTimer?.cancel();
    _accelSub?.cancel();
    _finishNameController.dispose();
    _finishNotesController.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadUserWeight() async {
    if (_uid == null) return;
    final profile = await FirestoreService().getUserProfile(_uid!);
    if (!mounted) return;
    // Field name fixed to match what onboarding/Health Profile actually
    // write (weightKg, already in kg — no unit conversion needed here).
    // The previous 'weight' key was never written anywhere, so this always
    // silently fell back to the 70.0 default below.
    final raw = profile?['weightKg'];
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

  // Driven by _activeSeconds (already excludes any stretch
  // _computeIndoorAccrualPaused() has gated out as motionless), not raw
  // _elapsedSeconds — mirrors outdoor_cardio_screen.dart's own _calories
  // getter exactly.
  double get _calories {
    final met = _activity == 'Run'
        ? 9.0
        : _activity == 'Walk'
            ? 3.5
            : 6.0;
    return met * _weightKg * (_activeSeconds / 3600);
  }

  Future<void> _initHealthKit() async {
    final granted = await HealthService().requestPermissions();
    if (!mounted) return;
    setState(() => _healthPermissionGranted = granted);
    if (granted) {
      // Manage App screen's Heart Rate toggle (default true) — see
      // FirestoreService.isHealthCategoryEnabled()'s own doc comment.
      final uid = _uid;
      final heartRateEnabled = uid == null
          ? true
          : await FirestoreService().isHealthCategoryEnabled(uid, 'heartRate');
      if (!mounted || !heartRateEnabled) return;
      _heartRateTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        final hr = await HealthService().getLatestHeartRate();
        if (!mounted) return;
        setState(() => _liveHeartRate = hr);
      });
    }
  }

  // ── Motion-presence accrual gate (indoor, accelerometer-based) ──────────────

  // Starts listening for accelerometer data for the duration of the active
  // session — mirrors _initHealthKit() immediately above (best-effort,
  // silently disables the feature rather than blocking the session if
  // sensing isn't available). Uses userAccelerometerEventStream() (linear
  // acceleration, gravity already removed by the platform) rather than the
  // raw accelerometerEventStream() — raw acceleration's gravity component
  // varies with device orientation/tilt, so a fixed ~9.8 subtraction would
  // be unreliable unless orientation were also tracked; linear
  // acceleration avoids that confound entirely.
  //
  // Unlike HealthService().requestPermissions(), there is no explicit
  // permission-request API for this in sensors_plus — confirmed: raw/
  // linear accelerometer streaming via CoreMotion's CMMotionManager (what
  // this package wraps on iOS) doesn't require NSMotionUsageDescription or
  // any runtime permission at all; that's only required for
  // CMPedometer/CMMotionActivityManager (step counting / activity
  // classification), neither of which this uses or needs. If the stream
  // errors anyway (e.g. no accelerometer hardware present, or some other
  // platform failure), _motionSensingUnavailable disables the gate
  // entirely and _computeIndoorAccrualPaused() always returns false —
  // falling back to today's uncapped-accrual behavior rather than
  // breaking the session.
  void _initMotionSensing() {
    try {
      _accelSub = userAccelerometerEventStream().listen(
        (event) {
          final magnitude = sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z);
          final now = DateTime.now();
          _recentAccelMagnitudes.add((now, magnitude));
          final windowStart =
              now.subtract(Duration(seconds: _stillnessWindowSeconds));
          _recentAccelMagnitudes
              .removeWhere((sample) => sample.$1.isBefore(windowStart));
        },
        onError: (_) {
          _motionSensingUnavailable = true;
        },
        cancelOnError: true,
      );
    } catch (_) {
      _motionSensingUnavailable = true;
    }
  }

  // Analogous to outdoor_cardio_screen.dart's _computeAccrualPaused() —
  // same role (a per-tick "should accrual be paused right now" signal fed
  // into the shared debounce/hysteresis block in _startTimer() below),
  // different underlying signal (accelerometer motion-presence instead of
  // GPS speed/displacement, since indoor has neither). See the module-
  // level _kFallbackIndoorStillnessWindowSeconds/
  // _kFallbackIndoorStillnessVarianceThreshold doc comments for the
  // detection reasoning/threshold (Firestore-configurable — see
  // _loadCardioAntiCheatConfig()).
  bool _computeIndoorAccrualPaused() {
    if (_motionSensingUnavailable) return false;

    final now = DateTime.now();
    final windowStart =
        now.subtract(Duration(seconds: _stillnessWindowSeconds));
    _recentAccelMagnitudes
        .removeWhere((sample) => sample.$1.isBefore(windowStart));

    // Fewer than 2 samples in the window (e.g. the first tick or two right
    // after Start, before any accelerometer events have landed yet) is
    // treated as "can't verify, don't award credit yet" — the same
    // deliberately conservative default outdoor's own stationary check
    // uses for its own "no recent data" case.
    if (_recentAccelMagnitudes.length < 2) return true;

    final magnitudes = _recentAccelMagnitudes.map((s) => s.$2).toList();
    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final variance = magnitudes
            .map((m) => (m - mean) * (m - mean))
            .reduce((a, b) => a + b) /
        magnitudes.length;

    return variance < _stillnessVarianceThreshold;
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  // _elapsedSeconds stays wall-clock (goal countdown/auto-finish below,
  // and the on-screen timer, both intentionally keep ticking through a
  // motion-pause — a stillness pause is a credit/anti-cheat concern, not
  // a reason to extend how long the user's stated time goal takes in the
  // real world). _activeSeconds is the separate, gated counter — see its
  // own field doc comment — computed via the exact same debounce/
  // hysteresis pattern as outdoor_cardio_screen.dart's own _startTimer()
  // tick callback, just fed by _computeIndoorAccrualPaused() instead of
  // that file's GPS-based _computeAccrualPaused().
  void _startTimer() {
    _timer?.cancel();
    _isRunning = true;
    _isPaused = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;

        final rawShouldPause = _computeIndoorAccrualPaused();
        if (rawShouldPause) {
          _consecutivePauseConditionTicks++;
          _consecutiveClearConditionTicks = 0;
        } else {
          _consecutiveClearConditionTicks++;
          _consecutivePauseConditionTicks = 0;
        }

        if (!_accrualPaused &&
            _consecutivePauseConditionTicks >= _accrualPauseDebounceTicks) {
          _accrualPaused = true;
        } else if (_accrualPaused &&
            _consecutiveClearConditionTicks >= _accrualResumeDebounceTicks) {
          _accrualPaused = false;
        }

        if (!_accrualPaused) _activeSeconds++;
      });
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
        // Clean restart of the hysteresis state on manual resume —
        // mirrors outdoor_cardio_screen.dart's own _resumeTracking(),
        // which resets _accrualPaused/both streak counters the same way,
        // so a stale streak from before the manual pause can't combine
        // with post-resume ticks to flip state prematurely.
        _accrualPaused = false;
        _consecutivePauseConditionTicks = 0;
        _consecutiveClearConditionTicks = 0;
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
                              // maxHeight caps how tall this gets without
                              // cropping the photo — BoxFit.contain shows
                              // the whole image (letterboxed against
                              // WW.elevated when its aspect ratio doesn't
                              // fill the box), instead of the previous
                              // fixed height: 160 + BoxFit.cover, which
                              // cropped whatever didn't fit a 160px-tall
                              // strip regardless of the photo's real shape.
                              Container(
                                width: double.infinity,
                                constraints:
                                    const BoxConstraints(maxHeight: 220),
                                color: WW.elevated,
                                child: Image.file(
                                  _finishPickedPhoto!,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                ),
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
        // Manage App screen's Heart Rate toggle (default true) — see
        // FirestoreService.isHealthCategoryEnabled()'s own doc comment.
        final heartRateEnabled =
            await FirestoreService().isHealthCategoryEnabled(uid, 'heartRate');
        if (_sessionStartTime != null && heartRateEnabled) {
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
        // _activeSeconds (gated), not raw _elapsedSeconds — mirrors
        // outdoor_cardio_screen.dart's own persisted durationSeconds.
        'durationSeconds': _activeSeconds,
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
      List<Map<String, dynamic>> newlyEarnedBadges = [];
      try {
        final finalizeResult = await FirestoreService()
            .finalizeInProgressSession(uid, sessionRunId);
        finalSessionId = finalizeResult.sessionId;
        newlyEarnedBadges = finalizeResult.newlyEarnedBadges;
      } catch (_) {}

      if (!mounted) return;
      context.pushReplacement(Routes.postSessionSummary, extra: {
        'planId': null,
        'sessionName': '$_activity · Indoor',
        // _activeSeconds (gated) — mirrors outdoor's own postSessionSummary
        // payload, which uses _activeSeconds for this same field.
        'elapsedSeconds': _activeSeconds,
        'date': DateTime.now(),
        'exercises': <dynamic>[],
        'isCardio': true,
        'cardioActivity': _activity,
        'cardioCalories': _calories.round(),
        'goalMinutes': _goalMinutes,
        'sessionId': finalSessionId,
        if (newlyEarnedBadges.isNotEmpty)
          'newlyEarnedBadges': newlyEarnedBadges,
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
    List<Map<String, dynamic>> newlyEarnedBadges = [];
    if (uid != null) {
      try {
        double? avgHR;
        double? maxHR;
        // Manage App screen's Heart Rate toggle (default true) — see
        // FirestoreService.isHealthCategoryEnabled()'s own doc comment.
        final heartRateEnabled =
            await FirestoreService().isHealthCategoryEnabled(uid, 'heartRate');
        if (_sessionStartTime != null && heartRateEnabled) {
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
        final saveResult = await FirestoreService().saveCardioSession(
          uid: uid,
          activity: _activity,
          // _activeSeconds (gated) — mirrors outdoor's own
          // saveCardioSession() call, which passes _activeSeconds here.
          durationSeconds: _activeSeconds,
          caloriesBurned: _calories.round(),
          mode: 'indoor',
          avgHeartRate: avgHR,
          maxHeartRate: maxHR,
          name: trimmedFinishName.isEmpty ? null : trimmedFinishName,
          notes: trimmedFinishNotes.isEmpty ? null : trimmedFinishNotes,
          photoBase64: photoBase64,
        );
        sessionId = saveResult.sessionId;
        newlyEarnedBadges = saveResult.newlyEarnedBadges;
      } catch (_) {}
    }
    if (!mounted) return;
    context.pushReplacement(Routes.postSessionSummary, extra: {
      'planId': null,
      'sessionName': finishSessionName,
      // _activeSeconds (gated) — mirrors outdoor's own postSessionSummary
      // payload for this same field.
      'elapsedSeconds': _activeSeconds,
      'date': DateTime.now(),
      'exercises': <dynamic>[],
      'isCardio': true,
      'cardioActivity': _activity,
      'cardioCalories': _calories.round(),
      'goalMinutes': _goalMinutes,
      'sessionId': sessionId,
      if (newlyEarnedBadges.isNotEmpty)
        'newlyEarnedBadges': newlyEarnedBadges,
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

  // Same amber warning pill styling as outdoor_cardio_screen.dart's own
  // _buildAccrualPausedBanner() (identical color pair/icon/padding/
  // border-radius) — only the wording differs, since indoor's pause
  // signal is stillness rather than GPS speed/displacement. Only ever
  // called from build() when _accrualPaused is true (see that call site),
  // matching outdoor's own call-site-gated convention rather than an
  // internal early-return guard.
  Widget _buildIndoorAccrualPausedBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            size: 16,
            color: Color(0xFFD97706),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'No movement detected — pausing tracking until this clears up.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFD97706),
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
    if (_isPreparingSession) {
      return const Scaffold(
        backgroundColor: WW.primaryDark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Preparing session...',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

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

                    if (_accrualPaused) ...[
                      _buildIndoorAccrualPausedBanner(),
                      const SizedBox(height: 12),
                    ],

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
