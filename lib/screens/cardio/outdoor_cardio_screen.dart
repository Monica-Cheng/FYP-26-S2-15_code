// lib/screens/cardio/outdoor_cardio_screen.dart
// Outdoor cardio GPS tracking: live map, Start/Pause/Finish controls,
// GPS accuracy filtering and speed-implausibility rejection, elevation
// gain, and route/distance capture. Saves the finished session via
// FirestoreService, either standalone or as a plan-linked block.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/health_service.dart';

// Free, no-API-key vector tile style — see https://openfreemap.org/quick_start/.
const String _kOpenFreeMapLibertyStyle =
    'https://tiles.openfreemap.org/styles/liberty';

// Fixes reported with worse horizontal accuracy than this (meters) are
// treated as GPS noise and skipped — not added to the route or distance
// total.
const double _kMinAcceptableAccuracyMeters = 15;

// If no fix has passed _kMinAcceptableAccuracyMeters for at least this
// long, the next fix is accepted anyway regardless of accuracy — a rough
// point is better than an indefinitely frozen route during a prolonged
// GPS dead zone. 18s: comfortably inside the requested 15-20s range,
// closer to the middle than either edge — long enough that ordinary
// short accuracy dips (the first few fixes after Start, momentary
// multipath in dense areas) still resolve on their own via the primary
// gate without ever reaching this fallback, but short enough that a
// genuinely prolonged dead zone doesn't leave the user staring at a
// frozen route for too long.
const Duration _kStaleAcceptanceThreshold = Duration(seconds: 18);

// Max plausible speed per activity (km/h) — generous buffers above
// realistic max effort (even elite race pace/sprinting/cycling), so this
// only rejects genuine GPS jumps/teleportation, not just a fast segment.
// Falls back to _kFallbackDefaultMaxSpeedKmh for any activity value not in
// this map (e.g. if the extra passed in doesn't match one of these
// exactly).
//
// All 7 constants in this section are now Firestore-configurable, via
// appConfig/gamification's cardioAntiCheat.outdoor{} — see
// FirestoreService().getGamificationConfig()'s own doc comment for the
// overall pattern, and _loadCardioAntiCheatConfig()/_configNum() below for
// how this screen fetches and applies it. Each _kFallback-prefixed const
// below is kept, unchanged, as exactly today's original hardcoded value —
// used only when the config doc is missing, malformed, or unreachable;
// the actual mutable instance field the rest of this class reads from
// (same name, minus the _kFallback prefix) starts at this fallback and is
// overwritten once the config fetch resolves.
const Map<String, double> _kFallbackMaxSpeedKmhByActivity = {
  'Walk': 10,
  'Run': 30,
  'Cycle': 60,
};
const double _kFallbackDefaultMaxSpeedKmh = 30;

// Rolling-average window (seconds) for the active-seconds accrual pause
// gate's implausible-speed check — see _computeAccrualPaused(). Short and
// deliberately NOT single-point instantaneous speed: a single jittery GPS
// point can spike a point-to-point speed reading well past any realistic
// threshold even after the accuracy/per-point speed gates in _onPosition
// already ran, so averaging over a few seconds smooths that out while
// still catching a genuinely sustained implausible-speed stretch. 4s: the
// middle of a 3-5s range — reacts quickly without being noise-prone.
const int _kFallbackSpeedRollingWindowSeconds = 4;

// Window (seconds) + distance threshold (meters) for the active-seconds
// accrual pause gate's stationary-detection check — see
// _computeAccrualPaused(). Deliberately much longer than the speed window:
// a brief stop (traffic light, tying a shoelace) shouldn't immediately
// pause accrual, only a sustained lack of real movement should. 12s / 3m:
// middle of the suggested 10-15s / ~3m ranges — comfortably above
// realistic GPS jitter-while-stationary (a few meters of drift is normal
// even standing still) while still catching genuine idling well within a
// typical rest period.
const int _kFallbackStationaryWindowSeconds = 12;
const double _kFallbackStationaryThresholdMeters = 3.0;

// Hysteresis for the _accrualPaused transition — see _startTimer()'s tick
// callback. The underlying per-tick _computeAccrualPaused() check (and its
// thresholds above) is unchanged; this only smooths how its raw true/false
// result gets applied, since flipping _accrualPaused on every single tick's
// raw result made the warning banner flicker during completely normal
// usage (briefly slowing for stairs, a moment of GPS noise). Deliberately
// asymmetric: pausing (denying calorie/XP credit) requires more sustained
// evidence than resuming (restoring it), since a false pause only costs UX
// while a false resume costs real anti-cheat effectiveness.
//  - _kFallbackAccrualPauseDebounceTicks = 3: the raw "should pause"
//    condition must hold for 3 consecutive 1s ticks (~3s) before
//    _accrualPaused actually flips true — long enough that one momentary
//    blip can't trigger it, in line with the existing
//    _speedRollingWindowSeconds/_stationaryWindowSeconds windows this
//    check is layered on top of.
//  - _kFallbackAccrualResumeDebounceTicks = 2: shorter than the pause
//    threshold — once genuinely resumed, the user shouldn't be kept
//    waiting as long to get credit back — but still more than a single
//    tick, so one lucky good reading during an otherwise-ongoing bad
//    stretch can't immediately flip the banner off and back on.
const int _kFallbackAccrualPauseDebounceTicks = 3;
const int _kFallbackAccrualResumeDebounceTicks = 2;

// Reads a nested numeric field out of a gamification config map (e.g.
// path ['cardioAntiCheat', 'outdoor', 'stationaryThresholdMeters']),
// falling back to `fallback` if any segment of the path is missing, the
// wrong type, or the map itself is empty — mirrors
// FirestoreService()'s own private _configNum() (duplicated here rather
// than shared, since it's a two-line pure function and this screen
// otherwise has no reason to reach into that service's private members).
num _configNum(Map<String, dynamic>? config, List<String> path, num fallback) {
  dynamic current = config;
  for (final key in path) {
    if (current is! Map) return fallback;
    current = current[key];
  }
  return current is num ? current : fallback;
}

// Per-activity fallback applied individually — an admin overriding just
// 'Run' in the config, say, still leaves 'Walk'/'Cycle' correctly falling
// back to their own defaults rather than the whole map being discarded.
Map<String, double> _configMaxSpeedKmhByActivity(Map<String, dynamic>? config) {
  dynamic current = config;
  for (final key in [
    'cardioAntiCheat',
    'outdoor',
    'maxSpeedKmhByActivity',
  ]) {
    if (current is! Map) {
      current = null;
      break;
    }
    current = current[key];
  }
  final raw = current;
  final result = <String, double>{};
  _kFallbackMaxSpeedKmhByActivity.forEach((activity, fallback) {
    final value = raw is Map ? raw[activity] : null;
    result[activity] = value is num ? value.toDouble() : fallback;
  });
  return result;
}

// Below this much recorded distance, pace math is too noisy to be
// meaningful (a few meters of GPS jitter can swing it wildly) — show
// "--:--" instead.
const double _kMinDistanceForPaceMeters = 50;

// Minimum altitude increase (meters) between consecutive accepted points
// to count as real elevation gain — smaller fluctuations are ignored
// entirely (neither added nor subtracted). GPS altitude is noisy even
// on flat ground or standing still; without this gate that per-point
// noise compounds into a large, false elevation-gain total over a long
// session instead of averaging out.
const double _kMinElevationDeltaMeters = 1.5;

// Weight given to the new raw fix in the path-smoothing EMA below —
// closer to 1 tracks the raw signal more tightly (less lag, less
// smoothing); closer to 0 damps jitter harder but adds visible lag
// between the drawn route and where the user actually is. 0.65 favors
// staying responsive while still meaningfully softening small GPS
// zigzag from multipath interference in built-up areas.
const double _kSmoothingAlpha = 0.65;

// SharedPreferences key: set once the user taps "Not now" on the
// background-tracking disclosure, or once a subsequent Always-permission
// request doesn't end up actually granting Always — either way, stop
// showing the disclosure automatically every session. We never treat this
// as the sole source of truth though: _handleStartTap always re-checks
// Geolocator.checkPermission() live first, so if Always is (or becomes)
// genuinely granted we skip the disclosure regardless of this flag, and
// if a user later revokes Always in device Settings, the live check will
// no longer report `always` and — since this flag was never set for a
// "granted" outcome — the disclosure will correctly show up again.
const String _kBackgroundDisclosureDeclinedPrefsKey =
    'outdoor_cardio_background_disclosure_declined';

// The recorded route is downsampled to roughly this many points before
// being saved, to keep the Firestore document comfortably under its 1MB
// limit even for long sessions — see _downsampleRoute.
const int _kMaxSavedRoutePoints = 400;

// Safety net for _encodeImageForSession/_captureMapSnapshot: if an
// encoded image's base64 string comes out larger than this, drop it
// (return null) rather than let the whole session write fail over one
// oversized field — see both methods' doc comments. 500KB is comfortably
// under Firestore's per-document 1MB limit even combined with route
// points and notes.
const int _kMaxImageBase64Bytes = 500 * 1024;

class OutdoorCardioScreen extends StatefulWidget {
  const OutdoorCardioScreen({super.key});

  @override
  State<OutdoorCardioScreen> createState() => _OutdoorCardioScreenState();
}

enum _LocationState { checking, granted, denied }

// notStarted: landed on the map (Strava-style), haven't tapped Start yet.
// tracking: actively recording points and elapsed time.
// paused: position stream subscription stays alive, but new points/time
//         aren't recorded — see _onPosition/_startTimer.
// finished: tracking stopped for good; showing the final-stats placeholder.
enum _TrackingState { notStarted, tracking, paused, finished }

class _OutdoorCardioScreenState extends State<OutdoorCardioScreen>
    with SingleTickerProviderStateMixin {
  _LocationState _locationState = _LocationState.checking;
  _TrackingState _trackingState = _TrackingState.notStarted;

  MapLibreMapController? _mapController;
  // Signals the next MapLibreMap.onMapIdle firing — completed exactly
  // once each time an idle callback arrives while this is non-null/
  // pending, then cleared. Used by _captureMapSnapshot() below as a real
  // "tiles finished loading" event instead of a blind delay — see that
  // method's own doc comment for why the package's own
  // waitUntilMapTilesAreLoaded() can't be used for this (confirmed via
  // its source: a literal no-op on native platforms). onMapIdle's own
  // doc comment (maplibre_map.dart) explicitly guarantees "All currently
  // requested tiles have loaded" among its firing conditions, which is
  // exactly the signal needed here.
  Completer<void>? _mapIdleCompleter;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;

  // Which activity this session is for (Walk/Run/Cycle), read from the
  // route's `extra` — see _readActivityExtra. Drives the max-plausible-
  // speed threshold in _onPosition. Defaults to 'Run' both because that's
  // cardio_setup_screen.dart's own default and because the temporary
  // Routes.outdoorCardioTest route (router.dart) doesn't pass any extra
  // at all when reached directly.
  String _activity = 'Run';

  // Which in-progress plan session (and which cardio block within it) this
  // session belongs to, if reached via a plan's cardio block — see
  // cardio_setup_screen.dart's _handleStart(). Read alongside _activity in
  // _readActivityExtra(). Not yet used for anything (see this task's
  // scope: threading only); both stay null when this screen is reached
  // standalone (including via the temporary Routes.outdoorCardioTest
  // route, which doesn't pass any extra at all).
  String? _sessionRunId;
  String? _blockId;

  // Injury Alert banner — same fields/data source as
  // cardio_session_screen.dart's own _showInjuryWarning/_activeInjuries/
  // _injuryWarningDismissed (that screen didn't have this at all before;
  // ported here for indoor/outdoor parity). Screen-local State, not
  // persisted — this route is a plain GoRoute with no keep-alive
  // wrapper, so a fresh session (indoor or outdoor) always gets a fresh
  // widget instance and these reset to their defaults automatically; no
  // extra plumbing needed for "dismiss lasts only this session."
  bool _showInjuryWarning = false;
  List<Map<String, dynamic>> _activeInjuries = [];
  bool _injuryWarningDismissed = false;

  // ── Accrual-pause anti-cheat config — Firestore-configurable, see
  // _loadCardioAntiCheatConfig() and the _kFallback-prefixed consts above.
  // Each starts at its own fallback and is overwritten once the config
  // fetch resolves. _startTracking() awaits _cardioAntiCheatConfigFuture
  // before tracking actually begins (see that method), so — unlike when
  // this was first added — these are guaranteed resolved (or safely
  // fallen back via timeout) by the time any real accrual decision is
  // ever made; they're never read while still mid-fetch.
  Map<String, double> _maxSpeedKmhByActivity = _kFallbackMaxSpeedKmhByActivity;
  double _defaultMaxSpeedKmh = _kFallbackDefaultMaxSpeedKmh;
  int _speedRollingWindowSeconds = _kFallbackSpeedRollingWindowSeconds;
  int _stationaryWindowSeconds = _kFallbackStationaryWindowSeconds;
  double _stationaryThresholdMeters = _kFallbackStationaryThresholdMeters;
  int _accrualPauseDebounceTicks = _kFallbackAccrualPauseDebounceTicks;
  int _accrualResumeDebounceTicks = _kFallbackAccrualResumeDebounceTicks;
  Future<void>? _cardioAntiCheatConfigFuture;
  // True while _startTracking() is awaiting the config load/timeout —
  // gates the Start button to a spinner for this (normally imperceptible)
  // window rather than allowing a double-tap or silently doing nothing.
  bool _isPreparingToStart = false;

  // Each inner list is one continuously-recorded stretch of the route — a
  // new one starts on Resume (see _resumeTracking) so the pause gap isn't
  // drawn as a straight line or counted as distance covered.
  final List<List<LatLng>> _segments = [];
  // The map Line for whichever segment is currently being recorded; reset
  // to null at the start of each new segment (see _currentLine's usage in
  // _drawCurrentSegment) so we know whether to addLine or updateLine.
  Line? _currentLine;
  // Short, visually distinct line from the last accepted route point to
  // the current raw GPS position — see _updateLiveTail. Keeps the drawn
  // route from visibly lagging behind the native blue dot while noisy
  // fixes are being rejected. Never counted toward distance/route.
  Line? _tailLine;
  // Timestamp of the last accepted (not filtered out) point in the
  // current segment — reset alongside _currentLine on each new segment.
  // Used to compute implied speed for the plausibility check.
  DateTime? _lastAcceptedTime;
  // Wall-clock time this tracking segment began (Start or Resume) — the
  // reference point for the stale-GPS fallback in _onPosition() when
  // _lastAcceptedTime is still null (no fix has been accepted yet this
  // segment), so a long stretch of poor-accuracy fixes right after
  // Start/Resume still eventually gets a fallback acceptance instead of
  // waiting forever for _lastAcceptedTime to exist. Reset alongside
  // _lastAcceptedTime on each new segment.
  DateTime? _segmentStartTime;
  // Altitude (meters) of the last accepted point in the current segment —
  // reset alongside _lastAcceptedTime on each new segment, for the same
  // reason: an elevation delta spanning a pause gap would be meaningless.
  // Null until the first point of a segment is accepted.
  double? _lastAcceptedAltitude;

  // Recently-accepted points (including any stale-fallback-accepted ones —
  // both flow through the same acceptance path in _onPosition, so neither
  // is special-cased here), each paired with its own fix timestamp. Used
  // by _computeAccrualPaused() to compute rolling average speed and
  // stationary detection for the active-seconds accrual gate. Bounded to
  // the longer of the two windows (_kStationaryWindowSeconds) by trimming
  // stale entries every time _computeAccrualPaused() runs; reset alongside
  // the rest of this session's per-segment state on Start/Resume.
  final List<({LatLng point, DateTime time})> _recentAcceptedPoints = [];
  // True while active-seconds accrual (and therefore calories/pace/XP) is
  // paused — see _computeAccrualPaused()'s own doc comment for exactly
  // what the underlying per-tick check looks at, and _startTimer()'s tick
  // callback for the debounce that sits on top of it before this flag
  // actually flips (see _kAccrualPauseDebounceTicks/
  // _kAccrualResumeDebounceTicks). Purely a display/gating flag; never
  // affects route/tail line drawing, which reads _segments directly and is
  // untouched by this.
  bool _accrualPaused = false;
  // Consecutive-tick streak counters feeding the debounce in _startTimer()
  // — incrementing one always resets the other, since each tick's raw
  // _computeAccrualPaused() result is one or the other, never both. Reset
  // alongside _accrualPaused on Start/Resume.
  int _consecutivePauseConditionTicks = 0;
  int _consecutiveClearConditionTicks = 0;

  double _totalDistanceMeters = 0;
  double _elevationGainMeters = 0;
  int _activeSeconds = 0;
  Timer? _timer;

  // Same live-BPM pattern as cardio_session_screen.dart's
  // _initHealthKit()/_heartRateTimer: poll every 5s once HealthKit
  // permission is granted (iOS only — HealthService always returns
  // false/null on other platforms), "--" shown until a reading arrives.
  double? _liveHeartRate;
  Timer? _heartRateTimer;

  // User's body weight for the MET calorie formula — same
  // FirestoreService().getUserProfile() lookup as
  // cardio_session_screen.dart's _loadUserWeight(), same 70kg fallback.
  double _weightKg = 70.0;
  String? _uid;

  // Pure UI toggle — same live values, just rearranged into a Strava-
  // style full-screen layout when true. See _buildExpandedStatsView.
  bool _statsExpanded = false;

  // Hold-to-finish: GestureDetector's built-in onLongPress* doesn't expose
  // a configurable duration, so this uses the task's offered alternative —
  // a manual AnimationController driven by onTapDown/onTapUp/onTapCancel
  // instead. A plain tap recognizer has no time limit on its own (it only
  // cancels on movement, not elapsed time), so forward() safely keeps
  // running for the full hold regardless of how long the finger stays
  // down, and reverse() on early release snaps the fill back to empty.
  late final AnimationController _finishHoldController;

  // Save form (shown once _trackingState reaches finished) — see
  // _buildFinishedSummary/_saveActivity.
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  File? _pickedPhoto;
  bool _isSaving = false;

  // Resolved value of _pendingSnapshotFuture, once it completes — see that
  // field's doc. Kept as a plain fallback for _saveActivity() in case
  // _pendingSnapshotFuture is somehow null when it runs; in practice
  // _finishTracking() always sets _pendingSnapshotFuture before either
  // save path (plan-linked or standalone) can reach _saveActivity().
  String? _capturedMapSnapshotBase64;

  // Kicked off fire-and-forget by _finishTracking() the moment Finish
  // completes, so the map-snapshot's animateCamera/
  // waitUntilMapTilesAreLoaded/takeSnapshot chain (which can
  // intermittently take several seconds on a slow network or a large
  // route) never blocks the user from immediately seeing the finished/
  // success screen. _saveActivity() awaits this directly (rather than
  // reading _capturedMapSnapshotBase64 synchronously) so the snapshot is
  // never silently dropped if a save happens before the capture resolves.
  Future<String?>? _pendingSnapshotFuture;

  // True from the moment Finish is tapped until _pendingSnapshotFuture
  // resolves — keeps the MapLibreMap widget (and its controller) mounted
  // just long enough for the background snapshot capture to actually have
  // a live controller to call, even though _trackingState has already
  // flipped to finished and the UI has moved on to the finished/success
  // screen. See build()'s showMap computation.
  bool _mapNeededForSnapshot = false;

  @override
  void initState() {
    super.initState();
    _uid = AuthService().getCurrentUser()?.uid;
    _finishHoldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finishHoldController.reset();
        _finishTracking();
      }
    });
    _requestLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readActivityExtra());
    // Started immediately (well before the user can possibly reach the
    // Start button — _requestLocation()'s own permission flow and
    // _handleStartTap()'s background-tracking disclosure both take real
    // user interaction time first) so that by the time _startTracking()
    // below actually awaits it, it has almost always already resolved —
    // in practice, closing the race window below adds no perceptible
    // delay to a normal session start. The Future itself is stored (not
    // just fired) so _startTracking() can await this exact call rather
    // than kicking off a second, redundant fetch.
    _cardioAntiCheatConfigFuture = _loadCardioAntiCheatConfig();
    _loadInjuryWarning();
  }

  // Same getUserInjuryData() call cardio_session_screen.dart's own
  // _loadInjuryWarning() already uses — reused directly, not
  // reimplemented, per this port's own scope.
  Future<void> _loadInjuryWarning() async {
    if (_uid == null) return;
    try {
      final data = await FirestoreService().getUserInjuryData(_uid!);
      final enabled = data['injuryFilteringEnabled'] as bool? ?? false;
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

  Future<void> _loadCardioAntiCheatConfig() async {
    final config = await FirestoreService().getGamificationConfig();
    if (!mounted) return;
    _maxSpeedKmhByActivity = _configMaxSpeedKmhByActivity(config);
    _defaultMaxSpeedKmh = _configNum(config,
            ['cardioAntiCheat', 'outdoor', 'defaultMaxSpeedKmh'],
            _kFallbackDefaultMaxSpeedKmh)
        .toDouble();
    _speedRollingWindowSeconds = _configNum(
            config,
            ['cardioAntiCheat', 'outdoor', 'speedRollingWindowSeconds'],
            _kFallbackSpeedRollingWindowSeconds)
        .toInt();
    _stationaryWindowSeconds = _configNum(
            config,
            ['cardioAntiCheat', 'outdoor', 'stationaryWindowSeconds'],
            _kFallbackStationaryWindowSeconds)
        .toInt();
    _stationaryThresholdMeters = _configNum(
            config,
            ['cardioAntiCheat', 'outdoor', 'stationaryThresholdMeters'],
            _kFallbackStationaryThresholdMeters)
        .toDouble();
    _accrualPauseDebounceTicks = _configNum(
            config,
            ['cardioAntiCheat', 'outdoor', 'accrualPauseDebounceTicks'],
            _kFallbackAccrualPauseDebounceTicks)
        .toInt();
    _accrualResumeDebounceTicks = _configNum(
            config,
            ['cardioAntiCheat', 'outdoor', 'accrualResumeDebounceTicks'],
            _kFallbackAccrualResumeDebounceTicks)
        .toInt();
  }

  // Mirrors cardio_setup_screen.dart's own _readExtra() pattern — reads
  // this route's `extra` map directly via GoRouterState rather than
  // needing router.dart's GoRoute builder to forward it as a constructor
  // parameter (Routes.outdoorCardioTest's builder currently ignores
  // `extra` entirely, and that's temporary scaffolding out of this
  // screen's scope to change).
  void _readActivityExtra() {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final activity = extra?['activity'] as String?;
    setState(() {
      if (activity != null && activity.isNotEmpty) _activity = activity;
      _sessionRunId = extra?['sessionRunId'] as String?;
      _blockId = extra?['blockId'] as String?;
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _timer?.cancel();
    _heartRateTimer?.cancel();
    _finishHoldController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Permission / initial position ────────────────────────────────────

  Future<void> _requestLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (!granted) {
      if (mounted) setState(() => _locationState = _LocationState.denied);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _locationState = _LocationState.granted;
      });
      _centerMapOnCurrentPosition();
    } catch (_) {
      if (mounted) setState(() => _locationState = _LocationState.denied);
    }
  }

  void _centerMapOnCurrentPosition() {
    final controller = _mapController;
    final position = _currentPosition;
    if (controller == null || position == null) return;
    controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        16,
      ),
    );
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    // The map may finish loading before the location request resolves (or
    // vice versa) — centering runs from both places and no-ops if either
    // piece isn't ready yet.
    _centerMapOnCurrentPosition();
  }

  // Fires on every idle settle (live tracking, user panning, etc.), not
  // just the one _captureMapSnapshot() cares about — _mapIdleCompleter is
  // only non-null while that method is actively awaiting one, so this is
  // a no-op the rest of the time.
  void _onMapIdle() {
    final completer = _mapIdleCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  // Follows the user's live position (re-centering only, no rotation)
  // while a session is actively being recorded; static everywhere else
  // (before Start, and while paused) so the user can freely look around
  // the map without the camera fighting their input. `tracking` was
  // chosen over `trackingCompass`: compass heading is noisy with the
  // phone in a pocket/armband/bag mid-session, and rotating the whole
  // map on that noisy signal would visually fight the route-line
  // smoothing already in place (_smoothPoint) — a fixed north-up view
  // that just re-centers is the more conservative, less-janky default
  // here. This property alone wasn't reliably engaging the native follow
  // behavior on-device, so _onPosition() also does an explicit
  // moveCamera() on every accepted fix as a guaranteed backstop — see
  // _followCameraOnAcceptedPoint(). The map widget itself now stays
  // mounted through _trackingState reaching finished (see build()'s
  // showMap) for as long as _mapNeededForSnapshot needs it for the
  // background snapshot capture, but this getter still correctly returns
  // `none` by then since _trackingState is no longer `tracking`.
  MyLocationTrackingMode get _myLocationTrackingMode =>
      _trackingState == _TrackingState.tracking
          ? MyLocationTrackingMode.tracking
          : MyLocationTrackingMode.none;

  // ── Heart rate / calories ────────────────────────────────────────────
  // Both copied to match cardio_session_screen.dart's own
  // _loadUserWeight()/_initHealthKit() exactly, per this task's
  // instruction — only kicked off once a session actually starts (see
  // _startTracking), not at screen-open, since outdoor's map-first-then-
  // Start flow means those two moments aren't the same here the way they
  // are on the indoor screen.

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
      final parsed = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (parsed != null) setState(() => _weightKg = parsed);
    }
  }

  Future<void> _initHealthKit() async {
    final granted = await HealthService().requestPermissions();
    if (!mounted || !granted) return;
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

  // ── Background-tracking disclosure ──────────────────────────────────

  // Runs when the user taps Start. Only shows the disclosure when it's
  // actually relevant (not already Always, not previously declined) —
  // otherwise goes straight to _startTracking() exactly as before this
  // task. Either disclosure choice ends up calling _startTracking(); the
  // only difference is whether we ask the OS for Always first.
  Future<void> _handleStartTap() async {
    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.always) {
      _startTracking();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final declinedBefore =
        prefs.getBool(_kBackgroundDisclosureDeclinedPrefsKey) ?? false;
    if (declinedBefore) {
      _startTracking();
      return;
    }

    if (!mounted) return;
    final wantsBackground = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: _buildBackgroundDisclosureSheet,
    );

    if (wantsBackground == true) {
      await _requestAlwaysPermission(prefs);
    } else {
      await prefs.setBool(_kBackgroundDisclosureDeclinedPrefsKey, true);
    }

    if (mounted) _startTracking();
  }

  Widget _buildBackgroundDisclosureSheet(BuildContext sheetContext) {
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
              Icons.lock_clock_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Keep tracking while your phone is locked',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'WiseWorkout can keep recording your route, distance, and pace '
            'even if you lock your phone or switch apps during an outdoor '
            'run, walk, or ride. Doing that needs "Always" location access, '
            'instead of just "while using the app."',
            style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.4),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.of(sheetContext).pop(true),
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Center(
                child: Text(
                  'Allow Background Tracking',
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
            onTap: () => Navigator.of(sheetContext).pop(false),
            child: Container(
              width: double.infinity,
              height: 50,
              alignment: Alignment.center,
              child: const Text(
                'Not now — foreground only',
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

  // Requests the OS "Always" upgrade. Info.plist (iOS) and the Android
  // manifest now declare what's needed for this to actually succeed (see
  // _buildLocationSettings for how a granted Always permission is used).
  // Still wrapped in try/catch: the user can decline the OS prompt, and
  // on some OS versions the second-step "upgrade to Always" prompt isn't
  // guaranteed to appear synchronously within this call at all — iOS
  // controls whether/when that native dialog shows, so `result` can
  // silently stay `whileInUse` even when the user fully intends to grant
  // background access. On iOS only, that case now gets a follow-up sheet
  // pointing the user to Settings instead of silently treating it like a
  // decline (see _showManualAlwaysSettingsDialog). Android's
  // ACCESS_BACKGROUND_LOCATION request already surfaces its own
  // system-level grant/deny prompt directly from this same call, so it
  // keeps the original decline-only behavior — no changed evidence here
  // that it needs the same treatment.
  Future<void> _requestAlwaysPermission(SharedPreferences prefs) async {
    try {
      final result = await Geolocator.requestPermission();
      if (result == LocationPermission.always) return;

      if (Platform.isIOS && mounted) {
        final openedSettings = await _showManualAlwaysSettingsDialog();
        if (!openedSettings) {
          await prefs.setBool(_kBackgroundDisclosureDeclinedPrefsKey, true);
        }
        return;
      }

      await prefs.setBool(_kBackgroundDisclosureDeclinedPrefsKey, true);
    } catch (_) {
      await prefs.setBool(_kBackgroundDisclosureDeclinedPrefsKey, true);
    }
  }

  // Shows the iOS-only manual-Settings follow-up sheet and returns whether
  // the user tapped "Open Settings" (true) or "Not now" (false). Mirrors
  // _buildBackgroundDisclosureSheet's exact visual pattern (icon circle,
  // title, body copy, primary button, plain-text secondary button) so it
  // reads as part of the same flow rather than a different dialog style.
  Future<bool> _showManualAlwaysSettingsDialog() async {
    final openedSettings = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: _buildManualAlwaysSettingsSheet,
    );
    return openedSettings ?? false;
  }

  Widget _buildManualAlwaysSettingsSheet(BuildContext sheetContext) {
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
              Icons.settings_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Background tracking needs one more step',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "iOS didn't grant full background access automatically. To keep "
            'tracking your route while your phone is locked, open Settings '
            'and change Location Access for WiseWorkout to "Always".',
            style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.4),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Geolocator.openAppSettings();
              Navigator.of(sheetContext).pop(true);
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Center(
                child: Text(
                  'Open Settings',
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
            onTap: () => Navigator.of(sheetContext).pop(false),
            child: Container(
              width: double.infinity,
              height: 50,
              alignment: Alignment.center,
              child: const Text(
                'Not now',
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

  // ── Tracking lifecycle ────────────────────────────────────────────────

  // Tracking must not begin until the anti-cheat config load has resolved
  // (or safely fallen back) — per product decision, closing the earlier
  // race window where _startTimer() could fire in parallel with a
  // still-in-flight config fetch, briefly running on fallback defaults
  // until the real values arrived mid-session. In practice this await
  // resolves near-instantly: the fetch was already kicked off back in
  // initState(), well before the user could possibly reach this point
  // (location-permission checks and _handleStartTap()'s own background-
  // tracking disclosure both take real interaction time first), so a
  // normal Firestore read has almost always already completed by now.
  //
  // The .timeout() below is a belt-and-suspenders safety net, not the
  // primary fallback mechanism: _loadCardioAntiCheatConfig() already can't
  // hang or throw on its own (FirestoreService().getGamificationConfig()
  // fails soft to {} on any error, per its own doc comment, and every
  // field extracted from it already falls back to today's hardcoded
  // default individually). This timeout exists purely to guarantee Start
  // can never get stuck waiting in some unforeseen scenario, without
  // needing to touch firestore_service.dart.
  Future<void> _startTracking() async {
    setState(() => _isPreparingToStart = true);
    try {
      await (_cardioAntiCheatConfigFuture ?? _loadCardioAntiCheatConfig())
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {
      // Fields already sit at their hardcoded fallback defaults — nothing
      // further to do, just proceed.
    }
    if (!mounted) return;
    setState(() => _isPreparingToStart = false);

    final oldTail = _tailLine;
    setState(() {
      _trackingState = _TrackingState.tracking;
      _segments.add([]);
      _currentLine = null;
      _tailLine = null;
      _lastAcceptedTime = null;
      _segmentStartTime = DateTime.now();
      _lastAcceptedAltitude = null;
      _recentAcceptedPoints.clear();
      _accrualPaused = false;
      _consecutivePauseConditionTicks = 0;
      _consecutiveClearConditionTicks = 0;
    });
    if (oldTail != null) _removeLine(oldTail);
    _startTimer();
    // Only fired once per session (not on Resume) — matches
    // cardio_session_screen.dart kicking these off exactly once, at the
    // point tracking actually begins.
    _loadUserWeight();
    _initHealthKit();

    // Only use the platform-specific background-capable settings when the
    // user actually has Always permission — background config existing
    // isn't the same as the user having opted in (see the disclosure
    // sheet in _handleStartTap). Absent that, this stays byte-for-byte
    // the same plain LocationSettings as before this task.
    final hasAlways =
        await Geolocator.checkPermission() == LocationPermission.always;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(hasAlways),
    ).listen(
      _onPosition,
      onError: (_) {
        // Transient GPS errors (momentary signal loss, provider hiccups) —
        // swallow and keep listening rather than tearing the subscription
        // down; the next good fix just picks up where we left off.
      },
      cancelOnError: false,
    );
  }

  LocationSettings _buildLocationSettings(bool hasAlways) {
    const accuracy = LocationAccuracy.high;
    // Only emit roughly every 5m moved — keeps the route reasonably
    // smooth for run/walk/cycle without flooding updates/battery. Left
    // unchanged across all branches below per this task's explicit
    // instruction not to touch the distance filter.
    const distanceFilter = 5;

    if (!hasAlways) {
      return const LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
    }

    if (Platform.isIOS) {
      // AppleSettings.allowBackgroundLocationUpdates already defaults to
      // true — set explicitly here so the intent is visible rather than
      // relying on the default. Needs
      // NSLocationAlwaysAndWhenInUseUsageDescription + UIBackgroundModes
      // containing "location" in Info.plist (added alongside this
      // change). ActivityType.fitness tunes iOS's location manager for
      // exactly this kind of walk/run/cycle tracking.
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: true,
        // Honest UX — keeps the OS's blue "location in use" indicator
        // visible while genuinely tracking in the background, rather
        // than hiding that it's happening.
        showBackgroundLocationIndicator: true,
      );
    }

    if (Platform.isAndroid) {
      // Providing foregroundNotificationConfig is what makes geolocator
      // run the location updates as an actual Android foreground service
      // (required for continuous updates once the app is backgrounded) —
      // needs ACCESS_BACKGROUND_LOCATION / FOREGROUND_SERVICE /
      // FOREGROUND_SERVICE_LOCATION in the manifest (added alongside
      // this change). setOngoing: true matches how other fitness-tracker
      // apps make the "recording" notification non-dismissable while a
      // session is active, since swiping it away would kill the service.
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'WiseWorkout',
          notificationText: 'WiseWorkout is tracking your outdoor $_activity',
          notificationChannelName: 'Outdoor Tracking',
          setOngoing: true,
        ),
      );
    }

    // Other platforms (web, desktop) — background tracking isn't
    // relevant here for this app; fall back to the plain settings.
    return const LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  void _onPosition(Position position) {
    _currentPosition = position;

    // Paused: keep the stream/subscription alive (per the task's chosen
    // approach) but don't record anything while frozen.
    if (_trackingState != _TrackingState.tracking) return;

    // Live tail: always reflects the raw current position relative to
    // the last accepted route point, even for fixes that go on to fail
    // the filters below — this is what keeps the drawn route from
    // visibly lagging behind the native blue dot while a burst of noisy
    // fixes gets rejected. Never touches the route or distance total.
    _updateLiveTail(position);

    // Low-quality fix — don't let GPS noise inflate the route/distance;
    // just wait for the next update. UNLESS no accepted fix has landed
    // for at least _kStaleAcceptanceThreshold — then accept this one
    // anyway (falling through to the normal acceptance path below,
    // rather than returning) so a prolonged GPS dead zone doesn't leave
    // the route looking frozen indefinitely. The stored/used accuracy
    // value itself is never faked — this just lets a real, lower-accuracy
    // point through as-is.
    if (position.accuracy > _kMinAcceptableAccuracyMeters) {
      final referenceTime =
          _lastAcceptedTime ?? _segmentStartTime ?? position.timestamp;
      final staleness = DateTime.now().difference(referenceTime);
      if (staleness <= _kStaleAcceptanceThreshold) return;
      // Falls through to the normal acceptance path below — same
      // distance calc/segment.add/_lastAcceptedTime update as an
      // ordinary accurate fix. Setting _lastAcceptedTime there is what
      // prevents this from cascading: the next poor fix must wait out
      // the full threshold again from this new timestamp.
    }

    final rawPoint = LatLng(position.latitude, position.longitude);
    final segment = _segments.last;

    if (segment.isNotEmpty) {
      final distanceMeters = Geolocator.distanceBetween(
        segment.last.latitude,
        segment.last.longitude,
        rawPoint.latitude,
        rawPoint.longitude,
      );

      final elapsedSeconds =
          position.timestamp.difference(_lastAcceptedTime!).inMilliseconds /
              1000;
      // Can't judge plausibility without a positive time delta, and a
      // ~zero-time jump with real distance is itself implausible either
      // way — drop it rather than risk a divide-by-near-zero speed spike.
      if (elapsedSeconds <= 0) return;

      final impliedSpeedKmh = (distanceMeters / elapsedSeconds) * 3.6;
      final maxSpeedKmh =
          _maxSpeedKmhByActivity[_activity] ?? _defaultMaxSpeedKmh;
      // Implausible jump for this activity — genuine GPS glitch, not a
      // fast segment. Judged against the RAW fix, before any smoothing
      // below, so smoothing can never make an implausible jump look
      // acceptable — it only softens points that already passed this
      // check. Drop silently, same as the accuracy filter.
      if (impliedSpeedKmh > maxSpeedKmh) return;

      _totalDistanceMeters += distanceMeters;
    }

    // Smooth only now that the point has passed both filters above — see
    // _smoothPoint's doc comment for the approach.
    final acceptedPoint =
        segment.isEmpty ? rawPoint : _smoothPoint(segment.last, rawPoint);
    segment.add(acceptedPoint);
    _lastAcceptedTime = position.timestamp;
    // Feeds _computeAccrualPaused()'s rolling speed/stationary checks —
    // see that method's own doc comment.
    _recentAcceptedPoints.add((point: acceptedPoint, time: position.timestamp));
    _followCameraOnAcceptedPoint(acceptedPoint);

    // Elevation gain: only count increases, matching how most fitness
    // apps report "gain" rather than net elevation change. Position
    // .altitude is a non-nullable double in the installed geolocator
    // version (not double?), so a literal null can't occur here — a
    // non-finite reading (NaN/Infinity, which can happen before a fix
    // has a full 3D lock) is the practical equivalent of "unavailable"
    // and is skipped the same way the task asked for a null altitude to
    // be skipped.
    if (position.altitude.isFinite) {
      final previousAltitude = _lastAcceptedAltitude;
      if (previousAltitude != null) {
        final delta = position.altitude - previousAltitude;
        // Below _kMinElevationDeltaMeters, treat as GPS altitude noise
        // rather than real climb — ignored entirely, not even as a small
        // contribution, so flat-ground noise can't compound over time.
        if (delta > _kMinElevationDeltaMeters) _elevationGainMeters += delta;
      }
      _lastAcceptedAltitude = position.altitude;
    }

    if (mounted) setState(() {});
    _drawCurrentSegment();
  }

  // Explicit backstop for the native myLocationTrackingMode follow
  // behavior (see that getter's doc) — called on every accepted fix while
  // tracking, so the camera reliably re-centers on the user regardless of
  // whether the platform's own tracking-mode property is behaving
  // correctly. moveCamera (an instant snap) rather than animateCamera:
  // this fires as often as every ~5m of movement
  // (_buildLocationSettings' distanceFilter), and stacking animateCamera
  // calls faster than each one's own implicit fly-to animation finishes
  // fights itself into visible stutter — an instant snap at this cadence
  // reads smoother in practice than competing animations.
  void _followCameraOnAcceptedPoint(LatLng point) {
    _mapController?.moveCamera(CameraUpdate.newLatLng(point));
  }

  // Simple exponential moving average: blends the new raw fix with the
  // last accepted point (which was itself already smoothed), weighted
  // toward the new fix via _kSmoothingAlpha. Deliberately lightweight —
  // this is not a Douglas-Peucker simplification pass, just enough to
  // soften small zigzag jitter. Because each accepted point is blended
  // against the previous (already-smoothed) one, the damping compounds
  // gently across a noisy stretch rather than only softening one step at
  // a time, without needing to keep a longer point history around.
  LatLng _smoothPoint(LatLng previousAccepted, LatLng raw) {
    return LatLng(
      _kSmoothingAlpha * raw.latitude +
          (1 - _kSmoothingAlpha) * previousAccepted.latitude,
      _kSmoothingAlpha * raw.longitude +
          (1 - _kSmoothingAlpha) * previousAccepted.longitude,
    );
  }

  // Draws/updates the short line from the last accepted route point to
  // the current raw GPS position — see _tailLine's field doc. Runs on
  // every position update regardless of whether it passes the accuracy/
  // speed filters, since its whole point is to show where the raw signal
  // currently is relative to the last officially-recorded point.
  Future<void> _updateLiveTail(Position position) async {
    final controller = _mapController;
    if (controller == null) return;
    if (_segments.isEmpty) return;
    final segment = _segments.last;
    if (segment.isEmpty) return;

    final tailGeometry = [
      segment.last,
      LatLng(position.latitude, position.longitude),
    ];

    try {
      if (_tailLine == null) {
        _tailLine = await controller.addLine(
          LineOptions(
            geometry: tailGeometry,
            lineColor: WW.primary.toHexStringRGB(),
            // Thinner and more transparent than the main route line
            // (width 4, full opacity) so it reads as "live/unconfirmed"
            // rather than part of the official recorded route.
            lineWidth: 2,
            lineOpacity: 0.45,
          ),
        );
      } else {
        await controller.updateLine(
          _tailLine!,
          LineOptions(geometry: tailGeometry),
        );
      }
    } catch (_) {
      // Same transient-failure handling as _drawCurrentSegment — skip
      // this draw, the next update retries.
    }
  }

  // Best-effort removal of a previously-drawn Line — used when starting a
  // fresh segment (Start/Resume) or finishing, so a stale tail/route line
  // from before doesn't linger on the map pointing at the wrong place.
  Future<void> _removeLine(Line line) async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.removeLine(line);
    } catch (_) {
      // Nothing to clean up if this fails — the line manager may already
      // be gone (e.g. screen disposed mid-call).
    }
  }

  Future<void> _drawCurrentSegment() async {
    final controller = _mapController;
    if (controller == null) return;
    final segment = _segments.last;
    if (segment.length < 2) return;

    try {
      if (_currentLine == null) {
        _currentLine = await controller.addLine(
          LineOptions(
            geometry: segment,
            lineColor: WW.primary.toHexStringRGB(),
            lineWidth: 4,
          ),
        );
      } else {
        await controller.updateLine(
          _currentLine!,
          LineOptions(geometry: segment),
        );
      }
    } catch (_) {
      // Style/line-manager not ready yet, or a transient platform-channel
      // hiccup — skip this draw, the next point's update will retry.
    }
  }

  // Ticks every second regardless of accrual state — this is also the only
  // place _accrualPaused is (re)computed, not just where it's consumed,
  // since a genuinely stationary user may not generate any new GPS fixes
  // at all (the OS's distanceFilter means nothing fires below ~5m of
  // movement), so the pause gate can't rely solely on _onPosition running.
  // _activeSeconds only increments when the DEBOUNCED _accrualPaused says
  // the user is genuinely, plausibly moving — calories/pace/XP all derive
  // from _activeSeconds/_totalDistanceMeters, so pausing accrual here is
  // sufficient to keep all three honest without touching those getters.
  //
  // The raw per-tick _computeAccrualPaused() result is NOT applied to
  // _accrualPaused directly — doing that flipped the warning banner on
  // every single tick's result, which flickered during completely normal
  // usage (briefly slowing for stairs, a moment of GPS noise). Instead,
  // each raw result only extends a same-direction streak counter (see
  // _consecutivePauseConditionTicks/_consecutiveClearConditionTicks —
  // incrementing one always resets the other, so a flip in the raw result
  // restarts whichever streak from zero), and _accrualPaused only
  // transitions once one streak has held for its own debounce threshold
  // (_kAccrualPauseDebounceTicks / _kAccrualResumeDebounceTicks — see
  // those constants' own doc comment for the asymmetric reasoning). This
  // is purely a smoothing layer on top of _computeAccrualPaused()'s
  // existing thresholds — that method, and what it checks, is unchanged.
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final rawShouldPause = _computeAccrualPaused();
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
    });
  }

  // True when active-seconds accrual should be paused this tick — either
  // the user is effectively stationary (near-zero real movement over the
  // last _kStationaryWindowSeconds) or recent accepted points imply an
  // unrealistic sustained speed for this activity (a rolling average over
  // _kSpeedRollingWindowSeconds, not a single-point spike — see that
  // constant's own doc comment). Route/tail line drawing is entirely
  // unaffected — this only ever gates _activeSeconds, never _segments.
  // Coexists with the 18s stale-fallback without any special-casing: a
  // stale-fallback-accepted point flows through the exact same
  // segment.add/_recentAcceptedPoints.add path as a normal one in
  // _onPosition, so it's naturally included in both checks below.
  bool _computeAccrualPaused() {
    final now = DateTime.now();

    // Stationary check: sums cumulative path distance (consecutive-pair
    // distances — the same method _totalDistanceMeters itself uses, robust
    // against back-and-forth jitter since it doesn't rely on net
    // displacement alone) among accepted points from the last
    // _kStationaryWindowSeconds. Fewer than 2 such points — including none
    // at all, e.g. no fix has landed recently — is treated as stationary
    // too: a deliberately conservative default, since unverified time
    // shouldn't accrue calories/XP just because there's no data either way.
    final stationaryWindowStart =
        now.subtract(Duration(seconds: _stationaryWindowSeconds));
    _recentAcceptedPoints.removeWhere((p) => p.time.isBefore(stationaryWindowStart));
    double stationaryDistance = 0;
    for (var i = 1; i < _recentAcceptedPoints.length; i++) {
      stationaryDistance += Geolocator.distanceBetween(
        _recentAcceptedPoints[i - 1].point.latitude,
        _recentAcceptedPoints[i - 1].point.longitude,
        _recentAcceptedPoints[i].point.latitude,
        _recentAcceptedPoints[i].point.longitude,
      );
    }
    final isStationary = _recentAcceptedPoints.length < 2 ||
        stationaryDistance < _stationaryThresholdMeters;

    // Speed check: rolling average over a much shorter window than the
    // stationary one — skipped (never triggers a pause on its own) when
    // there's insufficient recent data, since the stationary check above
    // already owns the "no data" conservative case.
    final speedWindowStart =
        now.subtract(Duration(seconds: _speedRollingWindowSeconds));
    final speedWindowPoints = _recentAcceptedPoints
        .where((p) => p.time.isAfter(speedWindowStart))
        .toList();
    var isImplausiblySpeedy = false;
    if (speedWindowPoints.length >= 2) {
      double windowDistance = 0;
      for (var i = 1; i < speedWindowPoints.length; i++) {
        windowDistance += Geolocator.distanceBetween(
          speedWindowPoints[i - 1].point.latitude,
          speedWindowPoints[i - 1].point.longitude,
          speedWindowPoints[i].point.latitude,
          speedWindowPoints[i].point.longitude,
        );
      }
      final windowSeconds = speedWindowPoints.last.time
              .difference(speedWindowPoints.first.time)
              .inMilliseconds /
          1000;
      if (windowSeconds > 0) {
        final windowSpeedKmh = (windowDistance / windowSeconds) * 3.6;
        final maxSpeedKmh =
            _maxSpeedKmhByActivity[_activity] ?? _defaultMaxSpeedKmh;
        isImplausiblySpeedy = windowSpeedKmh > maxSpeedKmh;
      }
    }

    return isStationary || isImplausiblySpeedy;
  }

  void _pauseTracking() {
    _timer?.cancel();
    setState(() => _trackingState = _TrackingState.paused);
  }

  void _resumeTracking() {
    final oldTail = _tailLine;
    setState(() {
      _trackingState = _TrackingState.tracking;
      // Fresh segment so the map doesn't draw a straight line across
      // wherever the user was standing during the pause.
      _segments.add([]);
      _currentLine = null;
      _tailLine = null;
      _lastAcceptedTime = null;
      _segmentStartTime = DateTime.now();
      _lastAcceptedAltitude = null;
      _recentAcceptedPoints.clear();
      _accrualPaused = false;
      _consecutivePauseConditionTicks = 0;
      _consecutiveClearConditionTicks = 0;
    });
    if (oldTail != null) _removeLine(oldTail);
    _startTimer();
  }

  // Async now (was sync) so the map snapshot can be captured — and
  // awaited — before _trackingState flips to finished below. That flip is
  // what unmounts the MapLibreMap widget (see build()'s ternary), so
  // capturing any later (e.g. inside _saveActivity(), the old approach)
  // was always operating on an already-gone map and silently produced
  // nothing. The AnimationController status listener that calls this
  // (see _finishHoldController) can't itself be async, so it just fires
  // this and doesn't await it — fine here since nothing after that call
  // site depends on this method's completion.
  Future<void> _finishTracking() async {
    _timer?.cancel();
    _heartRateTimer?.cancel();
    _positionSub?.cancel();
    _positionSub = null;
    final oldTail = _tailLine;
    _tailLine = null;
    if (oldTail != null) _removeLine(oldTail);

    // UI transitions immediately — the map-snapshot capture below (whose
    // animateCamera/waitUntilMapTilesAreLoaded/takeSnapshot chain can
    // intermittently take several seconds on a slow network or a large
    // route) is no longer on the critical path for Finish. The map widget
    // stays mounted behind the finished-state UI for as long as
    // _mapNeededForSnapshot is true (see build()'s showMap), so the
    // capture below still has a live controller to call.
    if (!mounted) return;
    setState(() {
      _trackingState = _TrackingState.finished;
      _statsExpanded = false;
      _mapNeededForSnapshot = true;
    });

    // Fire-and-forget from this method's point of view — _saveActivity()
    // (below, and the standalone "Save Activity" button tap) awaits this
    // same future directly rather than reading _capturedMapSnapshotBase64
    // synchronously, so the snapshot is never silently dropped if a save
    // happens before the capture resolves.
    final snapshotFuture = _captureMapSnapshot();
    _pendingSnapshotFuture = snapshotFuture;
    unawaited(snapshotFuture.then((snapshot) {
      _capturedMapSnapshotBase64 = snapshot;
      if (mounted) setState(() => _mapNeededForSnapshot = false);
    }));

    // Plan-linked blocks (sessionRunId present) never show the standalone
    // name/notes/photo form below — see build()'s ternary — so there's no
    // "Save Activity" button tap to wait for. Kick off the same
    // save/branch logic _saveActivity() already runs for this case
    // (updateInProgressSessionBlock -> isInProgressSessionFullyDone ->
    // midPlanCardioComplete or finalize+postSessionSummary) immediately
    // instead. _pickedPhoto/_notesController stay at their untouched
    // defaults here, so blockData naturally carries no notes/photoBase64
    // — that collection happens exclusively on
    // mid_plan_cardio_complete_screen.dart. _saveActivity() itself awaits
    // _pendingSnapshotFuture before reading the snapshot, so this doesn't
    // race the capture kicked off above.
    if (_sessionRunId != null) {
      await _saveActivity();
    }
  }

  // ── Derived stats ─────────────────────────────────────────────────────

  double get _distanceKm => _totalDistanceMeters / 1000;

  // True once tracking has started but no fix has yet passed
  // _kMinAcceptableAccuracyMeters in _onPosition — i.e. every segment
  // (including a fresh one just started via Resume) is still empty, so
  // the route hasn't started drawing yet. Cleared automatically the
  // moment the first point is accepted.
  bool get _isWaitingForGpsFix =>
      _trackingState == _TrackingState.tracking &&
      _segments.every((segment) => segment.isEmpty);

  // Same MET formula/values as cardio_session_screen.dart's own
  // _calories getter, but driven by _activeSeconds (already excludes
  // paused time — see _startTimer/_pauseTracking) rather than a raw
  // wall-clock elapsed counter, consistent with how distance/pace here
  // already exclude paused time. This also means it automatically excludes
  // any stretch _computeAccrualPaused() has gated out (implausible speed /
  // stationary) — no separate logic needed here, since _activeSeconds
  // itself simply doesn't increment during those stretches (see
  // _startTimer). _paceLabel below gets the same benefit for the same
  // reason. _totalDistanceMeters is a narrower case: sustained implausible
  // speed is already blocked point-by-point by _onPosition's own
  // pre-existing per-point speed gate, but small GPS jitter while
  // genuinely stationary isn't independently re-gated by
  // _computeAccrualPaused() — that drift is bounded/negligible in
  // practice and pre-existing to this change, not introduced by it.
  double get _calories {
    final met = _activity == 'Run'
        ? 9.0
        : _activity == 'Walk'
            ? 3.5
            : 6.0;
    return met * _weightKg * (_activeSeconds / 3600);
  }

  String get _paceLabel {
    if (_totalDistanceMeters < _kMinDistanceForPaceMeters ||
        _activeSeconds == 0) {
      return '--:--';
    }
    final secondsPerKm = _activeSeconds / _distanceKm;
    if (!secondsPerKm.isFinite) return '--:--';
    final mins = secondsPerKm ~/ 60;
    final secs = (secondsPerKm % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _fmtTime(int seconds) {
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

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isFinished = _trackingState == _TrackingState.finished;
    // The map now stays mounted continuously from before Start all the
    // way through a brief window after Finish — never unmounted just
    // because _statsExpanded toggles (that was the maximize/minimize bug:
    // a remount meant a brand-new controller while _currentLine/_tailLine
    // still pointed at the old, disposed one, so the route line could
    // never be re-added) — and kept alive past _trackingState reaching
    // finished for as long as _mapNeededForSnapshot needs it, so the
    // background snapshot capture kicked off by _finishTracking() still
    // has a live controller to call.
    final showMap = !isFinished || _mapNeededForSnapshot;

    return Scaffold(
      backgroundColor: WW.bg,
      appBar: AppBar(
        backgroundColor: WW.card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: WW.primaryDark),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Outdoor Cardio',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
          ),
        ),
      ),
      body: _locationState == _LocationState.denied
          ? _buildPermissionDeniedMessage()
          : Stack(
              children: [
                if (showMap)
                  MapLibreMap(
                    styleString: _kOpenFreeMapLibertyStyle,
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(0, 0),
                      zoom: 2,
                    ),
                    onMapCreated: _onMapCreated,
                    onMapIdle: _onMapIdle,
                    // Only turn on the native location puck once
                    // permission is actually confirmed granted.
                    myLocationEnabled:
                        _locationState == _LocationState.granted,
                    myLocationTrackingMode: _myLocationTrackingMode,
                  ),
                if (isFinished)
                  // Opaque full-size cover — the map may still be mounted
                  // underneath (see showMap) while its background
                  // snapshot capture finishes, so this must fully hide it
                  // rather than relying on either finished-state widget
                  // having its own background.
                  Positioned.fill(
                    child: Container(
                      color: WW.bg,
                      // Plan-linked runs (sessionRunId present) skip this
                      // form entirely — _finishTracking() already kicked
                      // off the save/navigate flow automatically, so
                      // there's nothing for the user to fill in or tap
                      // here; just show a brief transition state while
                      // that finishes. Standalone runs (sessionRunId ==
                      // null) are completely unchanged.
                      child: _sessionRunId != null
                          ? _buildFinishingUpIndicator()
                          : _buildFinishedSummary(),
                    ),
                  )
                else if (_statsExpanded)
                  // Covers the still-mounted map entirely (simplest of
                  // the two options the task offered — covering rather
                  // than dimming — and reads cleanly as "a different
                  // view" of the same session) without unmounting it,
                  // unlike before this fix.
                  Positioned.fill(child: _buildExpandedStatsView())
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _trackingState == _TrackingState.notStarted
                        ? _buildStartOverlay()
                        : _buildLiveStatsAndControls(),
                  ),
                if (!isFinished)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildInjuryWarningBanner(),
                  ),
              ],
            ),
    );
  }

  Widget _buildStartOverlay() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: GestureDetector(
          onTap: _isPreparingToStart ? null : () => _handleStartTap(),
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: WW.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: WW.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: _isPreparingToStart
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Start',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveStatsAndControls() {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isWaitingForGpsFix)
            _buildGpsWaitingBanner()
          else if (_accrualPaused)
            _buildAccrualPausedBanner(),
          _buildStatsCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(child: _buildPauseResumeButton()),
                const SizedBox(width: 12),
                Expanded(child: _buildHoldToFinishButton()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Shown only while tracking has started but no fix has yet passed the
  // accuracy gate in _onPosition (see _isWaitingForGpsFix) — i.e. before
  // the route has actually started drawing, so the user isn't left
  // wondering why nothing's appearing on the map yet. Same flat
  // icon+text pill style as cardio_setup_screen.dart's own "Suggested
  // duration" info row (WW.chipBg background, WW.primary icon/text).
  Widget _buildGpsWaitingBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: WW.primary,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Waiting for GPS signal…',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WW.primary,
            ),
          ),
        ],
      ),
    );
  }

  // Same visual style/copy as cardio_session_screen.dart's own
  // _buildInjuryWarningBanner() ("Injury Alert" + safety disclaimer +
  // dismiss X), ported here for indoor/outdoor parity. One difference
  // from that screen's version: no manual
  // MediaQuery.of(context).padding.top offset in the padding here — this
  // screen already has a Scaffold-level AppBar (unlike
  // cardio_session_screen.dart, which has none), so the Positioned
  // banner below already sits under the status bar/notch without needing
  // to self-manage that inset. Positioned as a top-level Stack sibling
  // (see build()'s body: Stack(...) — this screen already had one, no
  // Column→Stack conversion needed the way cardio_session_screen.dart's
  // fix required), gated on !isFinished so it doesn't linger over the
  // post-session summary.
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
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
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

  // Shown while _accrualPaused (the DEBOUNCED flag — see _startTimer()'s
  // tick callback) has paused active-seconds accrual (implausible
  // sustained speed, or effectively stationary), never the raw per-tick
  // _computeAccrualPaused() result directly — so this can't flicker on a
  // single momentary blip the same way the underlying check alone would.
  // Mutually exclusive with the GPS-waiting banner above (before any fix
  // has landed at all, _isWaitingForGpsFix already covers the relevant
  // status, and _accrualPaused would independently also end up true there
  // since the stationary check treats "no recent points" as paused —
  // showing both at once would be redundant). Non-blocking: no dismiss
  // action, doesn't stop the session/freeze any controls, and clears
  // itself automatically once the resume-side debounce threshold is met.
  // Amber warning styling matches gym_session_screen.dart's own
  // _buildInjuryFilteredBanner() (same color pair), distinct from the
  // neutral WW.chipBg/WW.primary info style used for the GPS-waiting
  // banner above, since this is a warning rather than a status update.
  Widget _buildAccrualPausedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
              "Pace doesn't look right — pausing tracking until this "
              'clears up.',
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

  // Single card, 2-row/6-stat grid (Time/Avg Pace/Distance on top,
  // BPM/Calories/Elevation below, divided by a horizontal rule matching
  // the vertical dividers already used between columns) — replaces the
  // two separately-boxed cards from before this task. The expand icon
  // (top-right, Strava's arrows-pointing-outward concept) switches to
  // _buildExpandedStatsView(); nothing about the underlying values
  // changes, this only rearranges how they're displayed.
  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: WW.shadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _statsExpanded = true),
                child: const Icon(
                  Icons.open_in_full_rounded,
                  size: 18,
                  color: WW.textSec,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _statColumn('Time', _fmtTime(_activeSeconds))),
              Container(width: 1, height: 32, color: WW.border),
              Expanded(
                child: _statColumn(
                  'Avg Pace',
                  _paceLabel == '--:--' ? _paceLabel : '$_paceLabel /km',
                ),
              ),
              Container(width: 1, height: 32, color: WW.border),
              Expanded(
                child: _statColumn(
                  'Distance',
                  '${_distanceKm.toStringAsFixed(2)} km',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: WW.border),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statColumn(
                  'BPM',
                  _liveHeartRate != null
                      ? '${_liveHeartRate!.round()}'
                      : '--',
                ),
              ),
              Container(width: 1, height: 32, color: WW.border),
              Expanded(
                child: _statColumn('Calories', '${_calories.round()} kcal'),
              ),
              Container(width: 1, height: 32, color: WW.border),
              Expanded(
                child: _statColumn(
                  'Elevation',
                  '${_elevationGainMeters.round()} m',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Full-screen opaque cover over the still-mounted map while expanded
  // (see build()'s comment on why "cover" rather than "dim" was chosen,
  // and why this no longer unmounts the map): a small Time/Avg Pace/BPM
  // row up top, a hero-sized Distance number in the middle, and the same
  // Pause/Finish controls at the bottom. Pure rearrangement of the same
  // live values — no new state, no new logic.
  Widget _buildExpandedStatsView() {
    return Container(
      color: WW.bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _statsExpanded = false),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: WW.elevated,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.close_fullscreen_rounded,
                          size: 16,
                          color: WW.textSec,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _statColumn(
                      'Time',
                      _fmtTime(_activeSeconds),
                      valueFontSize: 30,
                      labelFontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: _statColumn(
                      'Avg Pace',
                      _paceLabel == '--:--' ? _paceLabel : '$_paceLabel /km',
                      valueFontSize: 30,
                      labelFontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: _statColumn(
                      'BPM',
                      _liveHeartRate != null
                          ? '${_liveHeartRate!.round()}'
                          : '--',
                      valueFontSize: 30,
                      labelFontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // FittedBox as a safety net for unusually long
                    // sessions (e.g. 100+ km) on narrower phones — a
                    // no-op for the vast majority of real distances,
                    // which comfortably fit 96px at full size.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _distanceKm.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 96,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                          letterSpacing: -3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'km',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: WW.textSec,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(child: _buildPauseResumeButton()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildHoldToFinishButton()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fully pill-shaped (radius == half of height) and filled with
  // WW.primary — this app's equivalent of Strava's orange Pause pill.
  Widget _buildPauseResumeButton() {
    final isTracking = _trackingState == _TrackingState.tracking;
    return GestureDetector(
      onTap: isTracking ? _pauseTracking : _resumeTracking,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: WW.primary,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Center(
          child: Text(
            isTracking ? 'Pause' : 'Resume',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // Hold ~3.5s to actually finish (see _finishHoldController's field doc
  // for why this uses onTapDown/onTapUp/onTapCancel rather than
  // onLongPress*). Pill-shaped like Pause, but styled the opposite way —
  // a white card with a WW.primary outline and WW.primary text — so the
  // two are easy to tell apart at rest. Holding fills it with WW.primary
  // left-to-right, and the text flips to white once the fill passes the
  // midpoint so it stays readable against either background. A quick tap
  // forwards then immediately reverses before the fill is visible, so it
  // reads as doing nothing, per the task's requirement.
  Widget _buildHoldToFinishButton() {
    return GestureDetector(
      onTapDown: (_) => _finishHoldController.forward(),
      onTapUp: (_) => _finishHoldController.reverse(),
      onTapCancel: () => _finishHoldController.reverse(),
      child: AnimatedBuilder(
        animation: _finishHoldController,
        builder: (context, child) {
          final progress = _finishHoldController.value;
          return Container(
            height: 56,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: WW.card,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: WW.primary, width: 1.5),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    heightFactor: 1,
                    child: Container(color: WW.primary),
                  ),
                ),
                Text(
                  progress > 0.02 ? 'Hold to finish…' : 'Finish',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: progress > 0.5 ? Colors.white : WW.primary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // valueFontSize/labelFontSize default to the compact-card/finished-
  // summary sizing (17/11) — the expanded view's top row passes larger
  // overrides (see _buildExpandedStatsView) instead of duplicating this
  // whole widget just to change two numbers. The value is wrapped in a
  // FittedBox so a long string at a large override size (e.g. "01:23:45"
  // for a multi-hour session, or "12:34 /km" for pace) shrinks to fit its
  // column instead of overflowing/clipping — a no-op at the default sizes,
  // which already comfortably fit.
  Widget _statColumn(
    String label,
    String value, {
    double valueFontSize = 17,
    double labelFontSize = 11,
  }) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w800,
              color: WW.text,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: labelFontSize, color: WW.textSec),
        ),
      ],
    );
  }

  // Downsamples the full recorded route to roughly _kMaxSavedRoutePoints
  // points before it's persisted, so a long session's document stays
  // comfortably under Firestore's 1MB limit. Pause-boundary segmentation
  // (see _segments) isn't preserved in storage — the flattened, evenly-
  // strided point list is an intentional simplification, acceptable since
  // nothing currently renders a saved route back with segment gaps.
  List<Map<String, double>> _downsampleRoute(List<LatLng> allPoints) {
    final stride = allPoints.length > _kMaxSavedRoutePoints
        ? (allPoints.length / _kMaxSavedRoutePoints).ceil()
        : 1;
    final sampled = <Map<String, double>>[];
    for (var i = 0; i < allPoints.length; i += stride) {
      sampled.add({
        'lat': allPoints[i].latitude,
        'lng': allPoints[i].longitude,
      });
    }
    return sampled;
  }

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

  // Camera-vs-gallery choice sheet — mirrors the exact visual pattern
  // already used by _buildBackgroundDisclosureSheet/
  // _buildManualAlwaysSettingsSheet in this same file (icon circle,
  // title, primary filled button, plain-text secondary button), so it
  // reads as part of the same design language rather than a new style.
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
            onTap: () =>
                Navigator.of(sheetContext).pop(ImageSource.camera),
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
            onTap: () =>
                Navigator.of(sheetContext).pop(ImageSource.gallery),
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

  // Downscale-to-480px-wide-JPEG-then-base64, via the `image` package
  // (pubspec.yaml) — dart:ui's ui.ImageByteFormat only offers raw formats
  // or lossless PNG, no JPEG, and PNG compresses photographic content far
  // worse than JPEG at the same pixel width, risking an oversized field
  // on write. quality: 75 balances visible quality against payload size
  // for a thumbnail-sized session photo. _kMaxImageBase64Bytes below is
  // still checked afterward as a safety net — a genuinely huge/complex
  // source photo could in principle still encode past the threshold even
  // as JPEG, and this keeps the fail-soft behavior (drop the photo rather
  // than risk a Firestore write failure) regardless.
  Future<String?> _encodeImageForSession(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(decoded, width: 480);
      final jpegBytes = img.encodeJpg(resized, quality: 75);
      final encoded = base64Encode(jpegBytes);
      if (encoded.length > _kMaxImageBase64Bytes) {
        debugPrint(
          'Outdoor cardio: photo dropped — encoded size '
          '${encoded.length} bytes exceeds the safety threshold.',
        );
        return null;
      }
      return encoded;
    } catch (_) {
      return null;
    }
  }

  // Fits the map camera to the full recorded route (with padding) so the
  // snapshot actually shows the whole path, rather than whichever camera
  // position live tracking last left the map at. No-ops (leaves the camera
  // wherever it already is) if there aren't at least 2 points to bound.
  // Never races with the live _myLocationTrackingMode follow-camera: this
  // is only ever called from _saveActivity(), which is only reachable
  // once _trackingState is already finished — by then the MapLibreMap
  // widget (and its tracking-mode setting) has already been unmounted by
  // build()'s ternary, so there's no active "follow user" behavior left
  // to fight with this one-off bounds-fit.
  // Returns the computed bounding box (null if there weren't enough points
  // to bound) so _captureMapSnapshot() can reuse the exact same bounds as
  // the reference frame for projecting the route onto the captured image
  // — see _drawRouteOnSnapshot()'s doc comment for why this is a
  // deliberate approximation rather than the live camera's actual
  // rendered viewport.
  Future<({double minLat, double maxLat, double minLng, double maxLng})?>
      _fitCameraToRoute(
    MapLibreMapController controller,
    List<LatLng> allPoints,
  ) async {
    if (allPoints.length < 2) return null;
    var minLat = allPoints.first.latitude;
    var maxLat = allPoints.first.latitude;
    var minLng = allPoints.first.longitude;
    var maxLng = allPoints.first.longitude;
    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 40,
        top: 40,
        right: 40,
        bottom: 40,
      ),
    );
    // No-op on native platforms today (only meaningful on web), but this
    // is exactly the call maplibre_gl's own doc comment recommends before
    // taking a screenshot, so it's included for correctness if that ever
    // changes.
    await controller.waitUntilMapTilesAreLoaded();
    return (minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
  }

  // Captures a small thumbnail of the completed route via maplibre_gl's
  // MapLibreMapController.takeSnapshot(width:, height:) — confirmed
  // present in the installed maplibre_gl 0.26.2 (controller.dart), works
  // on Android/iOS/Web per its doc comment. That call only ever renders
  // the bare base map (see _drawRouteOnSnapshot's doc comment for why),
  // so this always decodes the result and composites the route line onto
  // it before re-encoding as JPEG — unlike the very first version of this
  // method, which could sometimes return takeSnapshot()'s raw PNG bytes
  // unmodified; that fast path no longer applies now that every result
  // needs the line drawn on first. Called from _finishTracking(), while
  // the map widget is still mounted — see that method's doc comment.
  // Fails soft throughout: returns null on any error (no controller,
  // missing platform support, a mid-capture exception, or still oversized
  // after every compression attempt) rather than blocking Finish.
  // debugPrint (not print) is used for visibility into which branch ran —
  // this project's analysis_options.yaml pulls in package:flutter_lints,
  // whose avoid_print rule flags print()/Print specifically; debugPrint is
  // the distinct, Flutter-recommended logging call and isn't covered by
  // that lint (confirmed: this file has no debugPrint usage flagged
  // anywhere in prior flutter analyze runs, unlike the literal print()
  // calls already present as baseline debt in firestore_service.dart).
  // Defensively (re)draws the full accumulated route — spanning every
  // segment, not just the currently-recording one — onto _currentLine
  // right before the snapshot is fitted/captured. Normally already up to
  // date via _drawCurrentSegment()'s per-fix calls, but this makes the
  // snapshot immune to any leftover staleness (e.g. an in-flight
  // _drawCurrentSegment() call that hadn't resolved yet at the exact
  // moment Finish was tapped) rather than relying purely on incremental
  // state. Best-effort: a snapshot missing the line is still better than
  // no snapshot at all, which _captureMapSnapshot's own try/catch already
  // covers.
  Future<void> _ensureFullRouteDrawnForSnapshot(
    MapLibreMapController controller,
    List<LatLng> allPoints,
  ) async {
    if (allPoints.length < 2) return;
    try {
      if (_currentLine == null) {
        _currentLine = await controller.addLine(
          LineOptions(
            geometry: allPoints,
            lineColor: WW.primary.toHexStringRGB(),
            lineWidth: 4,
          ),
        );
      } else {
        await controller.updateLine(
          _currentLine!,
          LineOptions(geometry: allPoints),
        );
      }
    } catch (_) {
      // Nothing more to do — see this method's own doc comment.
    }
  }

  // Draws the route polyline directly onto the decoded snapshot image —
  // confirmed via maplibre_gl's native source (both MLNMapSnapshotter on
  // iOS and MapSnapshotter on Android) that controller.takeSnapshot()
  // renders through a wholly separate off-screen snapshotter with no
  // knowledge of the live map's addLine() annotations, so the purple
  // route line can only ever end up in the saved image if drawn onto it
  // ourselves — the same approach Strava-style apps use for route
  // thumbnails.
  //
  // Projection: standard Web Mercator, exactly like every slippy map
  // (including this one) renders with — linear in longitude, and the
  // canonical ln(tan(pi/4 + lat/2)) transform for latitude. `bounds` is
  // the same bounding box _fitCameraToRoute() already computed and asked
  // the live camera to fit to.
  //
  // This is a practical approximation, not a pixel-perfect registration
  // against the live map's own camera/zoom: the snapshotter renders at
  // whatever center/zoom the live camera settled on for ITS OWN view size
  // (_fitCameraToRoute's fit-to-bounds call is sized for the live
  // on-screen map, not this 480x300 canvas), which isn't recoverable from
  // the Dart side. Projecting against our own bounds (with matching edge
  // padding) instead gives a route that's correctly shaped and
  // proportioned within the frame — the actual goal of a route thumbnail
  // — even if it isn't pixel-registered against the base map's roads
  // underneath.
  //
  // Uses a SINGLE uniform scale for both axes (previously: two independent
  // scale factors, lngSpan->width and mercYSpan->height, computed
  // separately). That independent-axis version stretched the route
  // anisotropically whenever the route's true geographic bounding-box
  // aspect ratio didn't match this canvas's fixed 480x300 shape — which is
  // most of the time — visibly warping the drawn line relative to its real
  // shape. A real map camera (including the live MapLibreMap the activity
  // detail screen renders, which looks correct) only ever has one zoom
  // level applied identically to both axes; this now matches that by
  // taking the smaller of the two axis-fit ratios as the one shared scale,
  // then centering the route within whichever axis ends up with leftover
  // room — the same idea as BoxFit.contain, not BoxFit.fill.
  void _drawRouteOnSnapshot(
    img.Image image,
    List<LatLng> allPoints,
    ({double minLat, double maxLat, double minLng, double maxLng}) bounds,
  ) {
    double mercatorY(double latDegrees) {
      final latRad = latDegrees * (math.pi / 180);
      return math.log(math.tan((math.pi / 4) + (latRad / 2)));
    }

    final mercMinY = mercatorY(bounds.minLat);
    final mercMaxY = mercatorY(bounds.maxLat);
    final lngSpan = bounds.maxLng - bounds.minLng;
    final mercYSpan = mercMaxY - mercMinY;

    // Guard against a degenerate (near-zero-area) bounding box — e.g. a
    // route with barely any real movement — which would otherwise divide
    // by ~0 below.
    if (lngSpan.abs() < 1e-9 || mercYSpan.abs() < 1e-9) return;

    // Same breathing room as the live camera's own newLatLngBounds
    // padding (40px there), expressed as a fraction of this image's much
    // smaller canvas so the route doesn't touch the frame edges.
    const paddingFraction = 0.12;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final drawableW = w * (1 - 2 * paddingFraction);
    final drawableH = h * (1 - 2 * paddingFraction);

    // The smaller of the two axis-fit ratios is the binding constraint —
    // scaling by the larger one would overflow the other axis. Whichever
    // axis isn't the binding one ends up with unused space, split evenly
    // as a centering offset (letterboxing) rather than stretched to fill it.
    final scale = math.min(drawableW / lngSpan, drawableH / mercYSpan);
    final offsetX = (w - lngSpan * scale) / 2;
    final offsetY = (h - mercYSpan * scale) / 2;

    ({double x, double y}) project(LatLng point) {
      // North (higher lat, larger mercatorY) maps to the TOP of the image
      // (smaller y) — hence maxY-minus-current, not the other way round.
      final x = offsetX + (point.longitude - bounds.minLng) * scale;
      final y = offsetY + (mercMaxY - mercatorY(point.latitude)) * scale;
      return (x: x, y: y);
    }

    // Scaled relative to this image's own width rather than reusing the
    // live map's LineOptions(lineWidth: 4) verbatim — that value is in
    // the live MapLibre view's own rendering units, which don't
    // correspond 1:1 to this canvas's pixel size. 1.2% of width, clamped
    // to a sane range, reads clearly at both this method's ~480px base
    // resolution and the smaller fallback widths used if the image is
    // resized further for the size cap below.
    final thickness = (w * 0.012).clamp(3.0, 6.0);

    // Mirrors WW.primary exactly — the same source of truth already used
    // for the live route line's color via WW.primary.toHexStringRGB() —
    // rather than hardcoding a duplicate RGB literal that could drift out
    // of sync with it.
    final lineColor = img.ColorRgb8(
      (WW.primary.r * 255).round(),
      (WW.primary.g * 255).round(),
      (WW.primary.b * 255).round(),
    );

    var previous = project(allPoints.first);
    for (var i = 1; i < allPoints.length; i++) {
      final current = project(allPoints[i]);
      img.drawLine(
        image,
        x1: previous.x.round(),
        y1: previous.y.round(),
        x2: current.x.round(),
        y2: current.y.round(),
        color: lineColor,
        thickness: thickness,
        antialias: true,
      );
      previous = current;
    }
  }

  Future<String?> _captureMapSnapshot() async {
    final controller = _mapController;
    if (controller == null) {
      debugPrint('Outdoor cardio: map snapshot skipped — no map controller.');
      return null;
    }
    try {
      final allPoints = _segments.expand((segment) => segment).toList();
      await _ensureFullRouteDrawnForSnapshot(controller, allPoints);

      // Real "tiles finished loading" signal instead of a blind delay —
      // confirmed via maplibre_gl 0.26.2's own source
      // (method_channel_maplibre_gl.dart) that
      // waitUntilMapTilesAreLoaded() (called inside _fitCameraToRoute()
      // below) is a literal no-op on native platforms, so it can never be
      // trusted here. MapLibreMap's onMapIdle callback (wired to
      // _onMapIdle()/_mapIdleCompleter above) is a real, native-
      // functional event whose own doc comment explicitly guarantees "All
      // currently requested tiles have loaded" among its firing
      // conditions — set up BEFORE the camera jump so an idle event
      // firing unusually fast can't be missed. A previous version of this
      // method used a blind 500ms delay as a stopgap, which real-device
      // testing showed was insufficient after a large camera jump over a
      // real network connection (a stretched, low-tile-count share-card
      // background). 3s timeout fallback so a session with a genuinely
      // slow/unreachable tile server still finishes instead of hanging
      // Finish indefinitely.
      final idleCompleter = Completer<void>();
      _mapIdleCompleter = idleCompleter;
      final bounds = await _fitCameraToRoute(controller, allPoints);
      await idleCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('Outdoor cardio: onMapIdle did not fire within 3s of '
              'the post-tracking camera jump — capturing the snapshot '
              'with whatever tiles had loaded by then instead of '
              'blocking Finish indefinitely.');
        },
      );
      _mapIdleCompleter = null;
      final bytes = await controller.takeSnapshot(width: 480, height: 300);

      // takeSnapshot() only ever returns a bare base map (see
      // _drawRouteOnSnapshot's doc comment) — decode it so the route line
      // can be composited on before saving. A decode failure falls back
      // to the plain undecorated bytes rather than losing the snapshot
      // entirely (edge case #5: fewer than 2 points, or bounds missing,
      // also just skips drawing and keeps the plain map — no error).
      final composited = img.decodeImage(bytes);
      if (composited == null) {
        final encoded = base64Encode(bytes);
        if (encoded.length <= _kMaxImageBase64Bytes) {
          debugPrint(
            'Outdoor cardio: map snapshot captured without route line — '
            'image decode failed (${bytes.length} bytes).',
          );
          return encoded;
        }
        debugPrint(
          'Outdoor cardio: map snapshot dropped — could not decode PNG '
          'bytes and raw bytes exceed the safety threshold.',
        );
        return null;
      }

      if (allPoints.length >= 2 && bounds != null) {
        _drawRouteOnSnapshot(composited, allPoints, bounds);
      }

      // Re-encode as JPEG at progressively smaller sizes until the result
      // fits the safety threshold — same compress-until-under-threshold
      // approach as before this task, now applied unconditionally (rather
      // than only on an oversized PNG) since baking the route line in
      // means the original raw-PNG fast path no longer applies: every
      // result now goes through this same img.copyResize/encodeJpg
      // pipeline _encodeImageForSession already uses for the regular
      // photo.
      const attempts = [
        (width: 480, quality: 75),
        (width: 400, quality: 70),
        (width: 320, quality: 55),
        (width: 240, quality: 40),
      ];
      var lastEncodedLength = 0;
      for (final attempt in attempts) {
        final resized = img.copyResize(composited, width: attempt.width);
        final jpegBytes = img.encodeJpg(resized, quality: attempt.quality);
        final encoded = base64Encode(jpegBytes);
        lastEncodedLength = encoded.length;
        if (encoded.length <= _kMaxImageBase64Bytes) {
          debugPrint(
            'Outdoor cardio: map snapshot captured with route line, '
            '${jpegBytes.length} bytes (width=${attempt.width}, '
            'quality=${attempt.quality}).',
          );
          return encoded;
        }
      }

      debugPrint(
        'Outdoor cardio: map snapshot dropped — still exceeds the safety '
        'threshold after compression (last attempt: $lastEncodedLength '
        'bytes).',
      );
      return null;
    } catch (e) {
      debugPrint('Outdoor cardio: map snapshot failed — $e');
      return null;
    }
  }

  // Branches on whether this session was launched from a plan's cardio
  // block (see cardio_setup_screen.dart's _handleStart(), which forwards
  // sessionRunId/blockId through from gym_session_screen.dart) — mirrors
  // cardio_session_screen.dart's own _finishSession() branch. If not (both
  // null), everything is byte-for-byte the original standalone behavior —
  // untouched. If launched from a plan, this block's result is persisted
  // through the in-progress-session flow instead of creating a separate
  // standalone saveCardioSession() doc.
  Future<void> _saveActivity() async {
    if (_isSaving) return;
    final uid = _uid;
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      String? photoBase64;
      final photo = _pickedPhoto;
      if (photo != null) {
        photoBase64 = await _encodeImageForSession(photo);
      }

      // Awaits the same background capture _finishTracking() kicked off
      // (fire-and-forget) right after Finish — this is what prevents the
      // snapshot from being silently dropped if a save happens before the
      // capture resolves, whether that's a plan-linked run's automatic
      // save (called directly from _finishTracking()) or a standalone
      // user tapping "Save Activity" quickly. Falls back to whatever's
      // already in _capturedMapSnapshotBase64 in the (practically
      // unreachable) case this runs with no pending future at all.
      final mapSnapshotBase64 = _pendingSnapshotFuture != null
          ? await _pendingSnapshotFuture!
          : _capturedMapSnapshotBase64;

      final allPoints = _segments.expand((segment) => segment).toList();
      final route = _downsampleRoute(allPoints);
      final trimmedName = _nameController.text.trim();
      final trimmedNotes = _notesController.text.trim();
      final caloriesRounded = _calories.round();

      final sessionRunId = _sessionRunId;
      final blockId = _blockId;
      if (sessionRunId != null && blockId != null) {
        // isCardio: true must be included — updateInProgressSessionBlock
        // replaces the whole block rather than merging, and
        // finalizeInProgressSession's gym-vs-cardio composition check keys
        // off this field, so leaving it out would silently reclassify
        // this block as a gym exercise with no valid sets data.
        final blockData = <String, dynamic>{
          'isCardio': true,
          'activity': _activity,
          'mode': 'outdoor',
          'durationSeconds': _activeSeconds,
          'caloriesBurned': caloriesRounded,
          'distanceMeters': _totalDistanceMeters,
          if (route.isNotEmpty) 'route': route,
          'elevationGainMeters': _elevationGainMeters,
          if (trimmedName.isNotEmpty) 'name': trimmedName,
          if (trimmedNotes.isNotEmpty) 'notes': trimmedNotes,
          'photoBase64': ?photoBase64,
          'mapSnapshotBase64': ?mapSnapshotBase64,
        };
        await FirestoreService().updateInProgressSessionBlock(
            uid, sessionRunId, blockId, blockData);

        if (!mounted) return;

        // Always shows the block-completion summary, even when this
        // happens to be the last remaining incomplete block in the
        // session — isInProgressSessionFullyDone() must NOT be used here
        // to skip straight to finalizing/postSessionSummary. The session
        // should only ever end via an explicit Finish/End Session tap on
        // the main gym_session_screen.dart (see that screen's own Finish
        // Session flow for the real finalizeInProgressSession() call),
        // never auto-detected just because every planned block happens to
        // be done.
        context.pushReplacement(Routes.midPlanCardioComplete, extra: {
          'sessionRunId': sessionRunId,
          'blockId': blockId,
          'blockData': blockData,
        });
        return;
      }

      final saveResult = await FirestoreService().saveCardioSession(
        uid: uid,
        activity: _activity,
        durationSeconds: _activeSeconds,
        caloriesBurned: caloriesRounded,
        mode: 'outdoor',
        distanceMeters: _totalDistanceMeters,
        route: route,
        elevationGainMeters: _elevationGainMeters,
        name: trimmedName,
        notes: trimmedNotes.isEmpty ? null : trimmedNotes,
        photoBase64: photoBase64,
        mapSnapshotBase64: mapSnapshotBase64,
      );
      final sessionId = saveResult.sessionId;

      if (!mounted) return;
      // Matches cardio_session_screen.dart's own post-save navigation
      // target/payload shape so both indoor and outdoor cardio land on
      // the same celebratory summary flow.
      context.pushReplacement(
        Routes.postSessionSummary,
        extra: {
          'sessionName':
              trimmedName.isEmpty ? '$_activity · Outdoor' : trimmedName,
          'elapsedSeconds': _activeSeconds,
          'date': DateTime.now(),
          'exercises': [],
          'isCardio': true,
          'cardioActivity': _activity,
          'cardioCalories': caloriesRounded,
          'goalMinutes': 0,
          'sessionId': sessionId,
          if (saveResult.newlyEarnedBadges.isNotEmpty)
            'newlyEarnedBadges': saveResult.newlyEarnedBadges,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save activity: $e')),
      );
    }
  }

  // Lightweight transition shown only for plan-linked runs while
  // _finishTracking()'s automatic _saveActivity() call is in flight — see
  // build()'s ternary. Standalone runs never see this; they show
  // _buildFinishedSummary() instead.
  Widget _buildFinishingUpIndicator() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: WW.primary),
          SizedBox(height: 16),
          Text(
            'Saving...',
            style: TextStyle(fontSize: 14, color: WW.textSec),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedSummary() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Icon(Icons.flag_rounded, size: 44, color: WW.primary),
            ),
            const SizedBox(height: 12),
            const Text(
              'Session complete',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: WW.cardDecoration,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statColumn('Time', _fmtTime(_activeSeconds)),
                  _statColumn(
                    'Avg Pace',
                    _paceLabel == '--:--' ? _paceLabel : '$_paceLabel /km',
                  ),
                  _statColumn(
                    'Distance',
                    '${_distanceKm.toStringAsFixed(2)} km',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
                controller: _nameController,
                style: const TextStyle(fontSize: 14, color: WW.text),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                  hintText: 'Morning $_activity',
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
                controller: _notesController,
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
              onTap: _pickPhoto,
              child: _pickedPhoto == null
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
                          // cropping the photo — BoxFit.contain shows the
                          // whole image (letterboxed against WW.elevated
                          // when its aspect ratio doesn't fill the box),
                          // instead of the previous fixed height: 160 +
                          // BoxFit.cover, which cropped whatever didn't
                          // fit a 160px-tall strip regardless of the
                          // photo's real shape.
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 220),
                            color: WW.elevated,
                            child: Image.file(
                              _pickedPhoto!,
                              width: double.infinity,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _pickedPhoto = null),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
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
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _isSaving ? null : _saveActivity,
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
                          'Save Activity',
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
  }

  Widget _buildPermissionDeniedMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_off_rounded,
              size: 48,
              color: WW.textSec,
            ),
            const SizedBox(height: 16),
            const Text(
              'Location access needed',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'WiseWorkout needs your location to track outdoor routes. '
              'Enable location access in Settings to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: WW.textSec, height: 1.4),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Geolocator.openAppSettings(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
