// lib/screens/cardio/outdoor_cardio_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

// Max plausible speed per activity (km/h) — generous buffers above
// realistic max effort (even elite race pace/sprinting/cycling), so this
// only rejects genuine GPS jumps/teleportation, not just a fast segment.
// Falls back to _kDefaultMaxSpeedKmh for any activity value not in this
// map (e.g. if the extra passed in doesn't match one of these exactly).
const Map<String, double> _kMaxSpeedKmhByActivity = {
  'Walk': 10,
  'Run': 30,
  'Cycle': 60,
};
const double _kDefaultMaxSpeedKmh = 30;

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
  int? _blockIndex;

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
  // Altitude (meters) of the last accepted point in the current segment —
  // reset alongside _lastAcceptedTime on each new segment, for the same
  // reason: an elevation delta spanning a pause gap would be meaningless.
  // Null until the first point of a segment is accepted.
  double? _lastAcceptedAltitude;

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

  // Captured once, at the moment the hold-to-finish gesture completes
  // (see _finishTracking) — must happen before _trackingState flips to
  // finished, since that's what unmounts the MapLibreMap widget (and its
  // controller) per build()'s ternary. Read by _saveActivity() instead of
  // capturing fresh there, which was always too late to find a live map.
  String? _capturedMapSnapshotBase64;

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
      _blockIndex = extra?['blockIndex'] as int?;
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

  // Follows the user's live position (re-centering only, no rotation)
  // while a session is actively being recorded; static everywhere else
  // (before Start, and while paused) so the user can freely look around
  // the map without the camera fighting their input. `tracking` was
  // chosen over `trackingCompass`: compass heading is noisy with the
  // phone in a pocket/armband/bag mid-session, and rotating the whole
  // map on that noisy signal would visually fight the route-line
  // smoothing already in place (_smoothPoint) — a fixed north-up view
  // that just re-centers is the more conservative, less-janky default
  // here. This widget is unmounted entirely once _trackingState reaches
  // finished (see build()'s ternary), so this never overlaps with
  // _fitCameraToRoute()/_captureMapSnapshot() at save-time — those only
  // ever run after Finish, by which point this tracking-mode camera
  // behavior is already gone along with the map widget itself.
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
    final raw = profile?['weight'];
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

  Future<void> _startTracking() async {
    final oldTail = _tailLine;
    setState(() {
      _trackingState = _TrackingState.tracking;
      _segments.add([]);
      _currentLine = null;
      _tailLine = null;
      _lastAcceptedTime = null;
      _lastAcceptedAltitude = null;
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
    // just wait for the next update.
    if (position.accuracy > _kMinAcceptableAccuracyMeters) return;

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
          _kMaxSpeedKmhByActivity[_activity] ?? _kDefaultMaxSpeedKmh;
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

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _activeSeconds++);
    });
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
      _lastAcceptedAltitude = null;
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

    _capturedMapSnapshotBase64 = await _captureMapSnapshot();

    if (!mounted) return;
    setState(() {
      _trackingState = _TrackingState.finished;
      _statsExpanded = false;
    });

    // Plan-linked blocks (sessionRunId present) never show the standalone
    // name/notes/photo form below — see build()'s ternary — so there's no
    // "Save Activity" button tap to wait for. Kick off the same
    // save/branch logic _saveActivity() already runs for this case
    // (updateInProgressSessionBlock -> isInProgressSessionFullyDone ->
    // midPlanCardioComplete or finalize+postSessionSummary) immediately
    // instead. _pickedPhoto/_notesController stay at their untouched
    // defaults here, so blockData naturally carries no notes/photoBase64
    // — that collection happens exclusively on
    // mid_plan_cardio_complete_screen.dart.
    if (_sessionRunId != null) {
      await _saveActivity();
    }
  }

  // ── Derived stats ─────────────────────────────────────────────────────

  double get _distanceKm => _totalDistanceMeters / 1000;

  // Same MET formula/values as cardio_session_screen.dart's own
  // _calories getter, but driven by _activeSeconds (already excludes
  // paused time — see _startTimer/_pauseTracking) rather than a raw
  // wall-clock elapsed counter, consistent with how distance/pace here
  // already exclude paused time.
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
          : _trackingState == _TrackingState.finished
              // Plan-linked runs (sessionRunId present) skip this form
              // entirely — _finishTracking() already kicked off the
              // save/navigate flow automatically, so there's nothing for
              // the user to fill in or tap here; just show a brief
              // transition state while that finishes. Standalone runs
              // (sessionRunId == null) are completely unchanged.
              ? (_sessionRunId != null
                  ? _buildFinishingUpIndicator()
                  : _buildFinishedSummary())
              // Expanded view fully replaces the map+compact-card Stack
              // below (simplest of the two options the task offered —
              // covering the map entirely rather than dimming it — and
              // reads cleanly as "a different view" of the same session).
              : _statsExpanded
                  ? _buildExpandedStatsView()
                  : Stack(
                      children: [
                        MapLibreMap(
                          styleString: _kOpenFreeMapLibertyStyle,
                          initialCameraPosition: const CameraPosition(
                            target: LatLng(0, 0),
                            zoom: 2,
                          ),
                          onMapCreated: _onMapCreated,
                          // Only turn on the native location puck once
                          // permission is actually confirmed granted.
                          myLocationEnabled:
                              _locationState == _LocationState.granted,
                          myLocationTrackingMode: _myLocationTrackingMode,
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _trackingState == _TrackingState.notStarted
                              ? _buildStartOverlay()
                              : _buildLiveStatsAndControls(),
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
          onTap: () => _handleStartTap(),
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
            child: const Center(
              child: Text(
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

  // Full-screen replacement for the map while expanded (see build()'s
  // comment on why "cover" rather than "dim" was chosen): a small Time/
  // Avg Pace/BPM row up top, a hero-sized Distance number in the middle,
  // and the same Pause/Finish controls at the bottom. Pure rearrangement
  // of the same live values — no new state, no new logic.
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
  Future<void> _fitCameraToRoute(
    MapLibreMapController controller,
    List<LatLng> allPoints,
  ) async {
    if (allPoints.length < 2) return;
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
  }

  // Captures a small PNG thumbnail of the completed route via maplibre_gl's
  // MapLibreMapController.takeSnapshot(width:, height:) — confirmed present
  // in the installed maplibre_gl 0.26.2 (controller.dart), works on
  // Android/iOS/Web per its doc comment, and already returns PNG bytes
  // rendered at the requested size, so no separate downscale pass is
  // needed the way the photo picker needs one. Called from
  // _finishTracking(), while the map widget is still mounted — see that
  // method's doc comment. Fails soft: returns null on any error (no
  // controller, missing platform support, a mid-capture exception) rather
  // than blocking Finish. Also fails soft on an oversized result — see
  // _kMaxImageBase64Bytes; takeSnapshot() only ever returns PNG bytes (no
  // JPEG option exposed by maplibre_gl), so unlike the photo picker there
  // isn't a format lever to pull here at all, just the size guard.
  // debugPrint (not print) is used for visibility into which branch ran —
  // this project's analysis_options.yaml pulls in package:flutter_lints,
  // whose avoid_print rule flags print()/Print specifically; debugPrint is
  // the distinct, Flutter-recommended logging call and isn't covered by
  // that lint (confirmed: this file has no debugPrint usage flagged
  // anywhere in prior flutter analyze runs, unlike the literal print()
  // calls already present as baseline debt in firestore_service.dart).
  Future<String?> _captureMapSnapshot() async {
    final controller = _mapController;
    if (controller == null) {
      debugPrint('Outdoor cardio: map snapshot skipped — no map controller.');
      return null;
    }
    try {
      final allPoints = _segments.expand((segment) => segment).toList();
      await _fitCameraToRoute(controller, allPoints);
      final bytes = await controller.takeSnapshot(width: 480, height: 300);
      var encoded = base64Encode(bytes);
      if (encoded.length <= _kMaxImageBase64Bytes) {
        debugPrint(
          'Outdoor cardio: map snapshot captured (${bytes.length} bytes).',
        );
        return encoded;
      }

      // Oversized PNG (takeSnapshot exposes no JPEG/quality option itself)
      // — re-encode via the same img.decodeImage/copyResize/encodeJpg
      // pipeline _encodeImageForSession already uses for the regular
      // photo, rather than dropping the snapshot outright. Up to 3 passes
      // with progressively smaller dimensions/lower quality; only falls
      // back to omitting the map entirely if it's still too big after
      // that.
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint(
          'Outdoor cardio: map snapshot dropped — could not decode PNG '
          'bytes for compression.',
        );
        return null;
      }
      const attempts = [
        (width: 400, quality: 70),
        (width: 320, quality: 55),
        (width: 240, quality: 40),
      ];
      for (final attempt in attempts) {
        final resized = img.copyResize(decoded, width: attempt.width);
        final jpegBytes = img.encodeJpg(resized, quality: attempt.quality);
        encoded = base64Encode(jpegBytes);
        if (encoded.length <= _kMaxImageBase64Bytes) {
          debugPrint(
            'Outdoor cardio: map snapshot compressed to '
            '${jpegBytes.length} bytes (width=${attempt.width}, '
            'quality=${attempt.quality}).',
          );
          return encoded;
        }
      }

      debugPrint(
        'Outdoor cardio: map snapshot dropped — still exceeds the safety '
        'threshold after compression (last attempt: ${encoded.length} '
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
  // sessionRunId/blockIndex through from gym_session_screen.dart) — mirrors
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

      // Captured earlier, at Finish-time — see _finishTracking() and
      // _capturedMapSnapshotBase64's field doc for why capturing here
      // (after the map widget is already unmounted) never worked.
      final mapSnapshotBase64 = _capturedMapSnapshotBase64;

      final allPoints = _segments.expand((segment) => segment).toList();
      final route = _downsampleRoute(allPoints);
      final trimmedName = _nameController.text.trim();
      final trimmedNotes = _notesController.text.trim();
      final caloriesRounded = _calories.round();

      final sessionRunId = _sessionRunId;
      final blockIndex = _blockIndex;
      if (sessionRunId != null && blockIndex != null) {
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
        // TEMPORARY DEBUG — remove once the second-cardio-block bug is
        // confirmed fixed.
        print('DEBUG_BLOCKINDEX: outdoor_cardio_screen finish uid=$uid '
            'sessionRunId=$sessionRunId blockIndex=$blockIndex');
        await FirestoreService().updateInProgressSessionBlock(
            uid, sessionRunId, blockIndex, blockData);

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
            'sessionId': finalSessionId,
          },
        );
        return;
      }

      final sessionId = await FirestoreService().saveCardioSession(
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
                          Image.file(
                            _pickedPhoto!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
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
