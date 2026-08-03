// lib/screens/plans/post_session_summary_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../core/share_card_gradients.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/image_encode.dart';
import '../../utils/widget_capture.dart';
import '../../widgets/caption_sheet.dart';
import '../../widgets/photo_background_share_card.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../widgets/route_map_share_card.dart';
import '../../widgets/route_overlay.dart';
import '../../widgets/share_card_picker.dart';
import '../../widgets/share_card_widget.dart';

// Same OpenFreeMap style URL used in activity_detail_screen.dart/
// outdoor_cardio_screen.dart — duplicated here (not imported, since that's
// library-private in both files) for this screen's own cardio map sections.
const String _kMapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

// ── Screen ─────────────────────────────────────────────────────────────────────

class PostSessionSummaryScreen extends StatefulWidget {
  const PostSessionSummaryScreen({super.key});

  @override
  State<PostSessionSummaryScreen> createState() =>
      _PostSessionSummaryScreenState();
}

class _PostSessionSummaryScreenState extends State<PostSessionSummaryScreen>
    with SingleTickerProviderStateMixin {
  bool _isSharing = false;
  bool _isPosting = false;
  bool _exercisesExpanded = true;
  bool _wiseCoachExpanded = false;
  late AnimationController _entranceCtrl;
  late Animation<double> _checkScale;

  // Fetched real session data — this screen now only requires
  // extra['sessionId'] (see _loadSession()) and renders exclusively from
  // this, never from any other extra field. Null until the fetch resolves;
  // stays null (see _hasSession) if getSession() fails or the id/uid isn't
  // available, in which case build() shows _buildErrorState() instead of
  // crashing.
  bool _loading = true;
  Map<String, dynamic>? _sessionData;
  bool get _hasSession => _sessionData != null;
  Map<String, dynamic> get _session => _sessionData ?? {};

  // Badges checkAndAwardBadges() newly awarded for THIS specific save —
  // not the user's full earned-badge history, just what changed right now.
  // Read from extra['newlyEarnedBadges'] alongside sessionId (see
  // _loadSession()). Every finish path threads this through now
  // (standalone gym in gym_session_screen.dart; plan-linked gym/cardio/
  // combined via finalizeInProgressSession(); standalone cardio via
  // saveCardioSession() — both in firestore_service.dart), so this is only
  // empty when the save genuinely earned no new badge.
  List<Map<String, dynamic>> _newlyEarnedBadges = [];

  String _wiseCoachSummary = '';
  bool _summaryLoading = true;

  // ── Cardio blocks / single-active-map — ported verbatim from
  // activity_detail_screen.dart (see that file's own doc comments for the
  // full reasoning). Genuinely shared logic with that screen — see this
  // task's final report re: shared-widget feasibility.
  MapLibreMapController? _cardioMapController;
  final Map<int, GlobalKey> _cardioBlockKeys = {};
  final Map<int, bool> _cardioBlockHasMap = {};
  int? _activeCardioMapIndex;
  final Map<int, MapLibreMapController> _cardioBlockMapControllers = {};
  // Marks the actual scrollable viewport (the NotificationListener/
  // SingleChildScrollView below _buildActionBar() in the Column) — see
  // _updateActiveCardioMap()'s doc comment for why this screen needs its
  // own real viewport bounds rather than the full device screen height.
  final GlobalKey _scrollViewportKey = GlobalKey();

  bool get _isGym => _session['type'] == 'gym';
  bool get _isManual => _session['isManuallyLogged'] == true;
  bool get _isCombined => _session['type'] == 'combined';
  bool get _isCardio => !_isGym && !_isManual && !_isCombined;

  // Recomputed once the fetch resolves (see _loadSession()) — can't be a
  // `late final` initializer here the way activity_detail_screen.dart's is,
  // since _session is only available asynchronously on this screen.
  List<LatLng> _routePoints = [];
  // >= 2, not isNotEmpty — RouteOverlay itself needs at least 2 points to
  // draw a line (a single point can't form a path; see route_overlay.dart's
  // own `routePoints.length < 2` guard) and silently renders nothing if
  // given fewer. Matching the threshold here means the overlay is never
  // added to the Stack for a session where it would just render blank.
  bool get _hasRoute => _routePoints.length >= 2;

  // Reset per card-picker flow (see _showCardPickerAndContinue) so a
  // previous flow's choice doesn't leak into the next one; read back when
  // building the Color card's builder and updated live via the picker's
  // onGradientChanged as the user taps swatches.
  List<Color> _selectedGradientColors = ShareCardGradients.presets.first.colors;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _checkScale = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSession());
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  // Only extra['sessionId'] is read — every other field previously passed
  // through extra by the finish handlers (isCardio, exercises, etc.) is no
  // longer used at all; this screen renders exclusively from the fetched
  // doc. Fails soft to _buildErrorState() (see build()) rather than
  // crashing if sessionId/uid are missing or the fetch itself fails.
  Future<void> _loadSession() async {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final sessionId = extra?['sessionId'] as String?;
    final uid = AuthService().getCurrentUser()?.uid;
    final rawNewlyEarnedBadges = extra?['newlyEarnedBadges'] as List<dynamic>?;
    final newlyEarnedBadges = rawNewlyEarnedBadges
            ?.whereType<Map>()
            .map((b) => Map<String, dynamic>.from(b))
            .toList() ??
        <Map<String, dynamic>>[];

    if (sessionId == null || uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final data = await FirestoreService().getSession(uid, sessionId);
    if (!mounted) return;
    setState(() {
      _sessionData = data;
      _loading = false;
      _newlyEarnedBadges = newlyEarnedBadges;
      _routePoints =
          _parseRoutePoints((data?['route'] as List<dynamic>?) ?? []);
    });
    if (data != null) {
      _generateWiseCoachSummary();
    }
  }

  // Parameterized (not tied to the top-level session['route'] field) so
  // _buildCardioBlockCard() can reuse this same conversion for a given
  // cardioBlocks[] entry's own 'route' field — ported from
  // activity_detail_screen.dart.
  List<LatLng> _parseRoutePoints(List<dynamic> route) {
    final points = <LatLng>[];
    for (final entry in route) {
      try {
        final m = entry as Map<String, dynamic>;
        final lat = (m['lat'] as num).toDouble();
        final lng = (m['lng'] as num).toDouble();
        points.add(LatLng(lat, lng));
      } catch (_) {
        // Skip just this point — a handful of malformed entries shouldn't
        // blank out an otherwise-good route.
      }
    }
    return points;
  }

  // ── Formatting helpers — ported verbatim from activity_detail_screen.dart ──

  String _formatDate(dynamic ts) {
    DateTime date;
    if (ts is Timestamp) {
      date = ts.toDate();
    } else {
      return 'Unknown date';
    }
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDuration() {
    if (_isManual) {
      final mins = _session['durationMinutes'];
      return mins != null ? '$mins min' : '';
    }
    final secs = _session['durationSeconds'] as int?;
    if (secs == null) return '';
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _formatVolume(int v) {
    if (v >= 1000) return '${v ~/ 1000},${(v % 1000).toString().padLeft(3, '0')}';
    return '$v';
  }

  String? _avgPaceLabel(double distanceMeters, int durationSeconds) {
    if (distanceMeters < 50 || durationSeconds <= 0) return null;
    final secondsPerKm = durationSeconds / (distanceMeters / 1000);
    if (!secondsPerKm.isFinite) return null;
    final mins = secondsPerKm ~/ 60;
    final secs = (secondsPerKm % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} /km';
  }

  // ── OpenAI summary ────────────────────────────────────────────────────────

  Future<void> _generateWiseCoachSummary() async {
    final sessionName = _session['sessionName'] as String? ?? 'Session';
    final elapsedSeconds = (_session['durationSeconds'] as num?)?.toInt() ?? 0;
    final durationMins = elapsedSeconds ~/ 60;

    final String prompt;
    if (_isCombined) {
      final cardioBlocks = _session['cardioBlocks'] as List<dynamic>? ?? [];
      final exercises = _session['exercises'] as List<dynamic>? ?? [];
      final totalSets = (_session['totalSets'] as num?)?.toInt() ?? 0;
      final cals = (_session['caloriesBurned'] as num?)?.toInt() ?? 0;
      prompt = 'You are WiseCoach, an AI fitness coach. Generate a 2-3 '
          'sentence post-workout summary for this combined gym + cardio '
          'session. Be encouraging and specific.\n'
          'Session: $sessionName\n'
          'Duration: $durationMins minutes\n'
          'Gym sets completed: $totalSets across ${exercises.length} exercises\n'
          'Cardio blocks completed: ${cardioBlocks.length}\n'
          'Calories burned: $cals kcal\n'
          'Keep it under 60 words. Plain text only, no markdown.';
    } else if (_isCardio) {
      final activity = _session['activity'] as String? ?? 'cardio';
      final cals = (_session['caloriesBurned'] as num?)?.toInt() ?? 0;
      prompt = 'Give a 2-sentence motivational summary for someone who '
          'just completed a $activity session lasting $durationMins '
          'minutes and burned $cals calories. Be encouraging and specific. '
          'Under 50 words.';
    } else {
      final exercises = _session['exercises'] as List<dynamic>? ?? [];
      final totalSets = (_session['totalSets'] as num?)?.toInt() ?? 0;
      final totalVolume = (_session['totalVolume'] as num?)?.toDouble() ?? 0;
      final cals = (_session['caloriesBurned'] as num?)?.toInt() ?? 0;
      prompt = 'You are WiseCoach, an AI fitness coach. Generate a 2-3 '
          'sentence post-workout summary for this gym session. Be '
          'encouraging and specific.\n'
          'Session: $sessionName\n'
          'Duration: $durationMins minutes\n'
          'Sets completed: $totalSets across ${exercises.length} exercises\n'
          'Total volume: ${totalVolume.round()} kg\n'
          'Calories burned: $cals kcal\n'
          'Keep it under 60 words. Plain text only, no markdown.';
    }

    // Relays through the callWiseCoachOpenAI Cloud Function instead of
    // calling OpenAI directly — the API key now lives server-side as a
    // Cloud Functions secret, never in the app bundle. Same prompt, same
    // model/max_tokens/temperature as before; only WHERE the OpenAI call
    // happens has changed.
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('callWiseCoachOpenAI');
      final result = await callable.call<Map<String, dynamic>>({
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'maxTokens': 150,
        'temperature': 0.7,
      });
      if (!mounted) return;
      final text = result.data['content'] as String?;
      if (text != null) {
        final trimmedSummary = text.trim();
        setState(() {
          _wiseCoachSummary = trimmedSummary;
          _summaryLoading = false;
        });

        // Persist to the actual session document so activity_detail_screen
        // .dart can show it later — best-effort only, in its own try/catch,
        // so a write failure here never affects the local display above,
        // which has already succeeded. Only ever called with a genuinely
        // AI-generated summary, never the catch-block fallback string below.
        final sessionId = _session['id'] as String?;
        final uid = AuthService().getCurrentUser()?.uid;
        if (sessionId != null && uid != null) {
          try {
            await FirestoreService()
                .updateSessionSummary(uid, sessionId, trimmedSummary);
          } catch (_) {}
        }
      } else {
        throw Exception('WiseCoach function returned no content');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _wiseCoachSummary = 'Great session! Keep up the consistency.';
        _summaryLoading = false;
      });
    }
  }

  // ── Share ─────────────────────────────────────────────────────────────────

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );

  // ── Shareable card flow (shared by Share and Post to Feed) ──────────────
  // Both entry points funnel through the same card-picker: resolve/prompt
  // for a photo once, build whichever card designs are actually available
  // for this session, let the user swipe/pick one (share_card_picker.dart),
  // then either render+share it or render+post it.

  String? get _reusablePhotoBase64 =>
      PhotoBackgroundShareCard.reusablePhotoBase64(_session);

  Future<void> _startCardFlow({required bool forPost}) async {
    if (forPost ? _isPosting : _isSharing) return;

    final existingPhoto = _reusablePhotoBase64;
    if (existingPhoto != null) {
      await _showCardPickerAndContinue(
          photoBase64: existingPhoto, forPost: forPost);
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
        onTap: () => _pickPhotoThenContinue(ImageSource.camera, forPost: forPost),
      ),
      QuickAddOption(
        icon: Icons.photo_library_rounded,
        iconColor: WW.teal,
        iconBg: WW.tealBg,
        title: 'Choose from Gallery',
        subtitle: 'Pick an existing photo',
        onTap: () => _pickPhotoThenContinue(ImageSource.gallery, forPost: forPost),
      ),
      QuickAddOption(
        icon: Icons.arrow_forward_rounded,
        iconColor: WW.textSec,
        iconBg: WW.elevated,
        title: 'Skip Photo',
        subtitle: 'Only offer the Map/Color card designs',
        onTap: () => _showCardPickerAndContinue(photoBase64: null, forPost: forPost),
      ),
    ]);
  }

  Future<void> _pickPhotoThenContinue(ImageSource source, {required bool forPost}) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    String? encoded;
    if (picked != null) {
      encoded = await _encodeImageForPost(File(picked.path));
    }
    await _showCardPickerAndContinue(photoBase64: encoded, forPost: forPost);
  }

  Future<void> _showCardPickerAndContinue({
    required String? photoBase64,
    required bool forPost,
  }) async {
    if (!mounted) return;
    _selectedGradientColors = ShareCardGradients.presets.first.colors;
    final cards = _buildCardOptions(photoBase64: photoBase64);
    final chosenIndex = await showShareCardPicker(
      context,
      cards: cards,
      confirmLabel: forPost ? 'Use This Design' : 'Share This Design',
      onGradientChanged: (colors) => _selectedGradientColors = colors,
    );
    if (chosenIndex == null || !mounted) return;
    final chosen = cards[chosenIndex];
    if (forPost) {
      await _promptCaptionAndPostCard(chosen);
    } else {
      await _shareCard(chosen);
    }
  }

  String _fmtStatDuration(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // Builds whichever of the 3 card designs are actually available for
  // this session — Map only for a pure-cardio session with a route or
  // snapshot (RouteMapShareCard.isAvailable — always false for combined
  // sessions, since _isCardio is false there and route/snapshot data
  // lives nested per-block instead, out of this feature's scope per
  // Part 1), Photo only if photoBase64 was resolved (reused or picked),
  // Color always (the universal fallback).
  List<ShareCardOption> _buildCardOptions({required String? photoBase64}) {
    final sessionName = _session['sessionName'] as String? ?? 'Workout';
    final elapsedSeconds = (_session['durationSeconds'] as num?)?.toInt() ?? 0;
    final date = (_session['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final totalSets = (_session['totalSets'] as num?)?.toInt() ?? 0;
    final totalVolume = (_session['totalVolume'] as num?)?.toDouble() ?? 0;
    final caloriesBurned = (_session['caloriesBurned'] as num?)?.toInt() ?? 0;
    final cardioActivity = _session['activity'] as String? ?? '';
    final activityLabel = cardioActivity.isNotEmpty ? cardioActivity : 'Cardio';
    final distanceMeters = (_session['distanceMeters'] as num?)?.toDouble() ?? 0;
    final mapSnapshotBase64 = _session['mapSnapshotBase64'] as String?;

    debugPrint('[RouteOverlay] _routePoints.length=${_routePoints.length}'
        '${_routePoints.isNotEmpty ? ' first=${_routePoints.first.latitude},${_routePoints.first.longitude} last=${_routePoints.last.latitude},${_routePoints.last.longitude}' : ''}'
        ' hasSnapshot=${mapSnapshotBase64?.isNotEmpty ?? false} isCardio=$_isCardio');

    final cards = <ShareCardOption>[];

    if (_isCardio &&
        RouteMapShareCard.isAvailable(
          mapSnapshotBase64: mapSnapshotBase64,
          routePoints: _routePoints,
        )) {
      cards.add(ShareCardOption(
        label: 'Map',
        builder: (_) => RouteMapShareCard(
          mapSnapshotBase64: mapSnapshotBase64,
          routePoints: _routePoints,
          sessionName: sessionName,
          activityLabel: activityLabel,
          distanceMeters: distanceMeters,
          durationSeconds: elapsedSeconds,
          calories: caloriesBurned,
          paceLabel: _avgPaceLabel(distanceMeters, elapsedSeconds),
          date: date,
        ),
      ));
    }

    if (photoBase64 != null) {
      final stats = _isCardio
          ? [
              (_fmtStatDuration(elapsedSeconds), 'Duration'),
              ('$caloriesBurned', 'Calories'),
              (_avgPaceLabel(distanceMeters, elapsedSeconds) ?? '--:--', 'Pace'),
            ]
          : [
              (_fmtStatDuration(elapsedSeconds), 'Duration'),
              ('$caloriesBurned', 'Calories'),
              ('$totalSets', 'Sets'),
            ];
      cards.add(ShareCardOption(
        label: 'Photo',
        builder: (_) => SizedBox(
          width: RouteMapShareCard.width,
          height: RouteMapShareCard.height,
          child: Stack(
            children: [
              PhotoBackgroundShareCard(
                photoBase64: photoBase64,
                title: sessionName,
                badgeLabel: _isCardio ? activityLabel : 'Gym',
                stats: stats,
                date: date,
              ),
              if (_hasRoute)
                Positioned.fill(child: RouteOverlay(routePoints: _routePoints)),
            ],
          ),
        ),
      ));
    }

    cards.add(ShareCardOption(
      label: 'Color',
      supportsColorPicker: true,
      builder: (_) => SizedBox(
        width: RouteMapShareCard.width,
        height: RouteMapShareCard.height,
        child: Stack(
          children: [
            ShareCardWidget(
              sessionName: sessionName,
              isCardio: _isCardio,
              cardioActivity: cardioActivity,
              elapsedSeconds: elapsedSeconds,
              calories: caloriesBurned,
              totalSets: totalSets,
              volume: totalVolume,
              // Not stored on the finalized session doc anywhere (it was
              // always just cardio_session_screen.dart's own local,
              // ephemeral "+5 min" goal state) — 0 matches the "no goal
              // set" display elsewhere.
              goalMinutes: 0,
              date: date,
              gradientColors: _selectedGradientColors,
            ),
            if (_hasRoute)
              Positioned.fill(child: RouteOverlay(routePoints: _routePoints)),
          ],
        ),
      ),
    ));

    return cards;
  }

  Future<void> _shareCard(ShareCardOption card) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      if (!mounted) return;
      final bytes = await captureWidgetAsPngBytes(
        context,
        card.builder(context),
        size: const Size(360, 640),
      );
      debugPrint('[ShareCard] label=${card.label} captured bytes=${bytes?.length}');
      if (bytes == null) {
        _snack('Could not generate share card.');
        return;
      }
      // Use dart:io Directory.systemTemp to avoid JNI issues
      // on Android emulator. Works on both real devices and
      // emulators without needing platform channels.
      final Directory tempDir = Directory.systemTemp;
      final file = File(
          '${tempDir.path}/wiseworkout_session_'
          '${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Just crushed a session on WiseWorkout! 💪',
      );
    } catch (e, stack) {
      debugPrint('Share error: $e');
      debugPrint('Stack: $stack');
      _snack('Could not share. Please try again.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // Adapted from activity_detail_screen.dart's _updateActiveCardioMap() —
  // that screen has no fixed bottom bar below its scrollview, so the full
  // device screen height IS its visible viewport. This screen pins
  // _buildActionBar() below the scrollable content (see build()), so the
  // true visible/scrollable viewport is shorter than the device screen —
  // using the raw screen height here let a card that had actually scrolled
  // out of view (clipped behind the real viewport boundary, hidden beneath
  // where the action bar sits) still register as "on screen," so the
  // genuinely-visible card could go forever un-selected as
  // _activeCardioMapIndex. The user would then only ever see that visible
  // card's static mapSnapshotBase64 preview — which still shows the route
  // line baked in from capture time, but is just a picture — instead of a
  // live, pannable map, exactly matching "route renders but doesn't pan."
  // Fixed by measuring the real scrollable viewport's own RenderBox (see
  // _scrollViewportKey) instead of assuming it spans the whole screen.
  void _updateActiveCardioMap() {
    if (!mounted) return;
    final viewportBox = _scrollViewportKey.currentContext?.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.attached) return;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    final viewportCenter = (viewportTop + viewportBottom) / 2;
    int? bestIndex;
    double? bestDistance;
    for (final entry in _cardioBlockKeys.entries) {
      final index = entry.key;
      if (_cardioBlockHasMap[index] != true) continue;
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final position = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      final isOnScreen = position.dy < viewportBottom &&
          (position.dy + size.height) > viewportTop;
      if (!isOnScreen) continue;
      final cardCenter = position.dy + size.height / 2;
      final distance = (cardCenter - viewportCenter).abs();
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
    if (bestIndex != null && bestIndex != _activeCardioMapIndex) {
      final previousIndex = _activeCardioMapIndex;
      setState(() => _activeCardioMapIndex = bestIndex);
      if (previousIndex != null) {
        _cardioBlockMapControllers.remove(previousIndex);
      }
    }
  }

  // ── Post to Feed ──────────────────────────────────────────────────────────
  // Posts the session to the real, shared Club "Feed" tab — separate from
  // _captureAndShare (native OS share sheet). Mirrors nutrition_scan_screen's
  // _postToFeed pattern, including its optional photo attachment.

  // Downscales a photo to a small PNG before base64-encoding — identical to
  // nutrition_scan_screen.dart's _encodeImageForPost, kept well under
  // Firestore's 1MB document limit. Returns null (post goes out without a
  // photo) rather than failing the whole post if anything goes wrong.
  Future<String?> _encodeImageForPost(File file) async {
    try {
      final exists = await file.exists();
      debugPrint('[PostToFeed] _encodeImageForPost: file.exists()=$exists path=${file.path}');
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

  // Lets the user type an optional caption before the chosen card is
  // posted. Dismissing without tapping "Post" cancels the whole post — it
  // does not fall back to posting with no caption.
  Future<void> _promptCaptionAndPostCard(ShareCardOption card) async {
    if (!mounted) return;
    final result = await showCaptionSheet(context, fallbackLabel: 'your session name');
    if (result == null) return;
    await _postCardToFeed(card, caption: result.isEmpty ? null : result);
  }

  Future<void> _postCardToFeed(ShareCardOption card, {String? caption}) async {
    if (_isPosting) return;
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isPosting = true);
    try {
      final sessionName = _session['sessionName'] as String? ?? 'Workout';
      final elapsedSeconds = _session['durationSeconds'] as int? ?? 0;
      final caloriesBurned = _session['caloriesBurned'] as int? ?? 0;
      final totalSets = _session['totalSets'] as int? ?? 0;
      final volume = (_session['totalVolume'] as num?)?.toDouble() ?? 0;
      final cardioActivity = _session['activity'] as String? ?? '';

      final profile = await FirestoreService().getUserProfile(uid);
      final rawName = (profile?['displayName'] as String?)?.trim();
      final authorName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Someone';
      final authorPhotoBase64 = profile?['photoBase64'] as String?;

      if (!mounted) return;
      final pngBytes = await captureWidgetAsPngBytes(
        context,
        card.builder(context),
        size: const Size(360, 640),
      );
      debugPrint('[PostToFeed] label=${card.label} captured bytes=${pngBytes?.length}');
      // Downscaled before base64-encoding for Firestore specifically — the
      // raw capture is full-resolution (1080x1920 real pixels @
      // pixelRatio 3.0) PNG, and PNG compresses photographic/map content
      // poorly enough that a Map/Photo card's full-res capture can exceed
      // Firestore's ~1 MiB per-document limit once base64-encoded
      // (verified via test/capture_size_test.dart — a worst-case captured
      // background landed at ~8.8MB base64; only got safely under the
      // limit once downscaled). This is exactly what was causing the
      // "posting to Feed" invalid-argument regression once the async-
      // image capture race (see widget_capture.dart) was fixed and these
      // cards started actually capturing real image content instead of a
      // blank canvas. Share (native OS share sheet) has no such
      // constraint and stays full-resolution — only this Post-to-Feed
      // path downscales.
      final imageBase64 = pngBytes != null
          ? await encodeImageBytesBase64(pngBytes)
          : null;
      debugPrint('[PostToFeed] label=${card.label} downscaled imageBase64 '
          'length=${imageBase64?.length}');

      await FirestoreService().createFeedPost(
        uid: uid,
        authorName: authorName,
        authorPhotoBase64: authorPhotoBase64,
        type: 'workout',
        calories: caloriesBurned,
        sessionName: sessionName,
        isCardio: _isCardio,
        cardioActivity: cardioActivity,
        elapsedSeconds: elapsedSeconds,
        totalSets: totalSets,
        volume: volume,
        imageBase64: imageBase64,
        caption: caption,
      );

      if (!mounted) return;
      _snack('Posted to your Club feed!');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not post: $e');
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: WW.bg,
        body: Center(child: CircularProgressIndicator(color: WW.primary)),
      );
    }

    if (!_hasSession) {
      return _buildErrorState();
    }

    final hasNotes = (_session['notes'] as String?)?.isNotEmpty == true;
    // Top-level photoBase64 is only ever written for pure gym or pure
    // cardio sessions (saveGymSession/saveCardioSession) — a combined
    // session's photos live per-block inside cardioBlocks[] instead (see
    // _buildCardioBlockCard()), and finalizeInProgressSession() never
    // writes a top-level photoBase64 for type:'combined'.
    final photoWidget = (_isGym || _isCardio) ? _buildPhotoWidget() : null;

    if (_isCombined) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _updateActiveCardioMap());
    }

    return Scaffold(
      backgroundColor: WW.bg,
      // top:true (the default) — the header's own content ("Great
      // session!" etc.) previously sat flush against the very top of the
      // screen with only a fixed 8px gap, so it rendered underneath the
      // status bar/notch on any device with real top insets. bottom:false
      // since _buildActionBar() already adds MediaQuery.of(context).padding
      // .bottom itself — double-applying it here would just add extra
      // empty space above the action bar.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                key: _scrollViewportKey,
                onNotification: (notification) {
                  if (_isCombined) _updateActiveCardioMap();
                  return false;
                },
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildHeaderCard(),
                      const SizedBox(height: 16),
                      _buildStatsRow(),
                      const SizedBox(height: 12),
                      _buildWiseCoachCard(),
                      const SizedBox(height: 12),
                      if (_isGym || _isCombined) ...[
                        ..._xpCardWidgets(),
                        const SizedBox(height: 12),
                      ],
                      // Badges are earned for ANY session type (gym,
                      // plan-linked gym, cardio, combined) — this must NOT
                      // share the XP card's gym/combined-only gate above.
                      // _buildBadgesCard() itself renders nothing
                      // (SizedBox.shrink()) when _newlyEarnedBadges is
                      // empty, so it's safe to always include unconditionally
                      // here regardless of session type.
                      _buildBadgesCard(),
                      const SizedBox(height: 12),
                      if (_isCardio && _hasRoute) ...[
                        _buildCardioMapSection(),
                        const SizedBox(height: 12),
                      ],
                      if (_isGym || _isCombined) ...[
                        _buildFlaggedSetsBanner(),
                        _buildExercisesSection(),
                        const SizedBox(height: 12),
                      ],
                      if (_isCombined) ..._buildCardioBlocksSection(),
                      if (hasNotes) ...[
                        _buildNotesSection(),
                        const SizedBox(height: 12),
                      ],
                      if (photoWidget != null) ...[
                        photoWidget,
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _buildActionBar(context),
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────
  // Same Icon/title/subtitle/button empty-state pattern already used
  // elsewhere in this app (gym_session_screen.dart's "No active plan
  // found", plan_detail_screen.dart's "Plan not found") — shown whenever
  // extra['sessionId']/the current uid are missing, or getSession() itself
  // fails or returns null, rather than crashing.

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 48, color: WW.textSec),
                const SizedBox(height: 16),
                const Text(
                  'Could not load this session',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "It may not have saved properly, or something went wrong.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: WW.textSec),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => context.go(Routes.home),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Go Home',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header — flat, celebratory ───────────────────────────────────────────
  // Same icon-circle/title/subtitle layout and spacing/typography family as
  // activity_detail_screen.dart's _buildHeaderCard() — no gradient, no
  // confetti — but scaled up and given a soft tinted glow (the same
  // color.withValues(alpha:)+blurRadius+offset BoxShadow pattern already
  // used throughout this app for celebratory/CTA elements, e.g. this same
  // file's own _buildActionBar() Done button) so the moment still reads as
  // "grand" without reintroducing a gradient background. WW.tealBg/WW.teal
  // is this app's established "done"/success color (e.g.
  // gym_session_screen.dart's completed-cardio-card checkmark).

  Widget _buildHeaderCard() {
    final duration = _formatDuration();
    final subtitleParts = <String>[_formatDate(_session['date'])];
    if (duration.isNotEmpty) subtitleParts.add(duration);
    final subtitle = subtitleParts.join(' · ');
    final sessionName = _session['sessionName'] as String? ?? 'Session';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _checkScale,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: WW.tealBg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: WW.teal.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, color: WW.teal, size: 34),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Great session!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sessionName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WW.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Stats row — ported verbatim from
  // activity_detail_screen.dart's _buildStatsRow()/_statCell(). ─────────────

  Widget _buildStatsRow() {
    final List<({String label, String value})> stats;

    if (_isGym || _isCombined) {
      final sets = _session['totalSets'] as int? ?? 0;
      final volume =
          ((_session['totalVolume'] as num?)?.toDouble() ?? 0).round();
      final cals = _session['caloriesBurned'] as int? ?? 0;
      stats = [
        (label: 'Sets', value: '$sets'),
        (label: 'Volume', value: '${_formatVolume(volume)} kg'),
        (label: 'Calories', value: '$cals kcal'),
      ];
    } else if (_isManual) {
      final mins = _session['durationMinutes'] as int? ?? 0;
      final cals = _session['caloriesBurned'] as int? ?? 0;
      final intensity =
          _capitalize(_session['intensity'] as String? ?? 'moderate');
      stats = [
        (label: 'Duration', value: '$mins min'),
        (label: 'Calories', value: '$cals kcal'),
        (label: 'Intensity', value: intensity),
      ];
    } else {
      final dur = _formatDuration();
      final cals = _session['caloriesBurned'] as int? ?? 0;
      final distanceMeters = (_session['distanceMeters'] as num?)?.toDouble();
      final elevationGain =
          (_session['elevationGainMeters'] as num?)?.toDouble();
      final durationSeconds = _session['durationSeconds'] as int? ?? 0;

      if (distanceMeters != null && distanceMeters > 0) {
        final pace = _avgPaceLabel(distanceMeters, durationSeconds);
        stats = [
          (label: 'Duration', value: dur.isEmpty ? '—' : dur),
          (label: 'Distance', value: '${(distanceMeters / 1000).toStringAsFixed(2)} km'),
          (label: 'Avg Pace', value: pace ?? '--:-- /km'),
          (label: 'Calories', value: '$cals kcal'),
          if (elevationGain != null)
            (label: 'Elevation', value: '${elevationGain.round()} m'),
        ];
      } else {
        stats = [
          (label: 'Duration', value: dur.isEmpty ? '—' : dur),
          (label: 'Calories', value: '$cals kcal'),
          (label: 'Type', value: 'Cardio'),
        ];
      }
    }

    final rows = <List<({String label, String value})>>[];
    for (var i = 0; i < stats.length; i += 3) {
      final end = i + 3 <= stats.length ? i + 3 : stats.length;
      rows.add(stats.sublist(i, end));
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) ...[
              const SizedBox(height: 12),
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: WW.border,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                for (final stat in rows[r])
                  Expanded(child: _statCell(stat.label, stat.value)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCell(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: WW.textSec,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── WiseCoach card — ported verbatim from
  // activity_detail_screen.dart's _buildWiseCoachCard() (WW.primary
  // left-accent-stripe, collapsible). This screen previously used a
  // distinct lavenderBg-filled, non-collapsible treatment — the odd one
  // out, not an intentionally different style; now aligned.

  Widget _buildWiseCoachCard() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: WW.primary, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                setState(() => _wiseCoachExpanded = !_wiseCoachExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: WW.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 14),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'WISECOACH SUMMARY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _wiseCoachExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: WW.textSec, size: 20),
                ),
              ],
            ),
          ),
          if (_wiseCoachExpanded) ...[
            const SizedBox(height: 10),
            if (_summaryLoading)
              const _WiseCoachTypingDots()
            else
              Text(
                _wiseCoachSummary,
                style: const TextStyle(
                  fontSize: 13,
                  color: WW.text,
                  height: 1.6,
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── XP banner ─────────────────────────────────────────────────────────────
  // Hardcoded progress bar/level text unchanged (out of scope) — xp itself
  // is real, now sourced from the finalized doc's own xpEarned field
  // instead of being recomputed locally.

  List<Widget> _xpCardWidgets() {
    final xp = (_session['xpEarned'] as num?)?.toInt() ?? 0;
    if (xp <= 0) return [];
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: WW.tealBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WW.teal.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_rounded, color: WW.teal, size: 20),
                const SizedBox(width: 6),
                Text(
                  '+$xp XP earned!',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: WW.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 0.72,
                minHeight: 7,
                backgroundColor: WW.teal.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(WW.teal),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Level 4 — 720 / 1000 XP to next level',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: WW.teal,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  // ── Badges — real, from checkAndAwardBadges()'s result for this specific
  // session save (see _loadSession()), not a persisted/refetched list.
  // Renders nothing at all (not an empty card) when no badge was newly
  // earned this session. ─────────────────────────────────────────────────

  Widget _buildBadgesCard() {
    if (_newlyEarnedBadges.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You unlocked a new badge!',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _newlyEarnedBadges.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildBadgeRow(_newlyEarnedBadges[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildBadgeRow(Map<String, dynamic> badge) {
    final imageUrl = badge['imageUrl'] as String? ?? '';
    final name = badge['name'] as String? ?? 'Badge';
    final description = badge['description'] as String? ?? '';
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: WW.chipBg,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.hardEdge,
          child: imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.emoji_events_rounded, color: WW.gold, size: 22),
                  ),
                )
              : const Center(
                  child: Icon(Icons.emoji_events_rounded, color: WW.gold, size: 22),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Pure-cardio map section — ported verbatim from
  // activity_detail_screen.dart's _buildCardioMapSection()/
  // _onCardioMapCreated()/_onCardioStyleLoaded(). ─────────────────────────

  Widget _buildCardioMapSection() {
    final points = _routePoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: MapLibreMap(
              styleString: _kMapStyleUrl,
              initialCameraPosition: CameraPosition(
                target: points.first,
                zoom: 14,
              ),
              onMapCreated: _onCardioMapCreated,
              onStyleLoadedCallback: _onCardioStyleLoaded,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Per-km splits aren't available — outdoor sessions only store "
          'overall average pace today, not per-point timing.',
          style: TextStyle(fontSize: 11, color: WW.textSec, height: 1.4),
        ),
      ],
    );
  }

  void _onCardioMapCreated(MapLibreMapController controller) {
    _cardioMapController = controller;
  }

  void _onCardioStyleLoaded() {
    final controller = _cardioMapController;
    if (controller == null) return;
    _drawRouteLine(controller, _routePoints);
    _fitCameraToRouteBounds(controller, _routePoints);
  }

  void _onCardioBlockMapCreated(int index, MapLibreMapController controller) {
    _cardioBlockMapControllers[index] = controller;
  }

  void _onCardioBlockStyleLoaded(int index, List<LatLng> points) {
    final controller = _cardioBlockMapControllers[index];
    if (controller == null) return;
    _drawRouteLine(controller, points);
    _fitCameraToRouteBounds(controller, points);
  }

  Future<void> _drawRouteLine(
    MapLibreMapController controller,
    List<LatLng> points,
  ) async {
    if (points.isEmpty) return;
    try {
      await controller.addLine(
        LineOptions(
          geometry: points,
          lineColor: WW.primary.toHexStringRGB(),
          lineWidth: 4,
        ),
      );
    } catch (e) {
      debugPrint('PostSessionSummaryScreen: route line draw failed — $e');
    }
  }

  Future<void> _fitCameraToRouteBounds(
    MapLibreMapController controller,
    List<LatLng> points,
  ) async {
    if (points.length < 2) return;
    try {
      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;
      for (final p in points) {
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
          left: 30,
          top: 30,
          right: 30,
          bottom: 30,
        ),
      );
    } catch (e) {
      debugPrint('PostSessionSummaryScreen: camera bounds-fit failed — $e');
    }
  }

  // ── Photo (gym or pure cardio) — ported verbatim from
  // activity_detail_screen.dart's _buildPhotoWidget(). ─────────────────────

  Widget? _buildPhotoWidget() =>
      _buildPhotoPreview(_session['photoBase64'] as String?);

  // Shared by the top-level session photo above and each cardio block's own
  // photo (see _buildCardioBlockCard) — deliberately NOT shared with
  // _decodeCardioBlockImage below, which renders that same block's map
  // snapshot: a map thumbnail is fine cropped at a small fixed size (same
  // reasoning as progress_screen.dart's Activities list map thumbnail), but
  // the user's own attached photo should always show the whole thing they
  // actually took, not a crop. Container+maxHeight+BoxFit.contain (instead
  // of the previous fixed height + BoxFit.cover) shows the full image,
  // letterboxed against WW.elevated when its aspect ratio doesn't fill the
  // box, capped at 220 so a very elongated photo still can't take over the
  // screen. A decode/render failure falls back to nothing rather than
  // breaking the page.
  Widget? _buildPhotoPreview(String? raw, {double borderRadius = 16}) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          color: WW.elevated,
          child: Image.memory(
            bytes,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Flagged-sets banner ────────────────────────────────────────────────────
  // Shown when saveGymSession()/finalizeInProgressSession() excluded one or
  // more sets from totalSets/totalVolume/xpEarned via the completedAt-gap
  // timing check or the exercise-bounds check (see firestore_service.dart's
  // _computeTimingFlaggedIndices()/_isBoundsFlagged()) — those sets are
  // still recorded and shown exactly as entered in the exercises list below
  // (see the flaggedTiming/flaggedBounds marker in _buildExercisesSection),
  // they just didn't count toward credit. Purely explanatory: non-blocking,
  // no dismiss action, nothing to tap. Same amber warning pill style as
  // outdoor_cardio_screen.dart's _buildAccrualPausedBanner() (identical
  // color pair) rather than inventing a new warning style for this screen.
  Widget _buildFlaggedSetsBanner() {
    final flaggedCount = (_session['flaggedSetCount'] as num?)?.toInt() ?? 0;
    if (flaggedCount <= 0) return const SizedBox.shrink();
    final message = flaggedCount == 1
        ? "1 set wasn't counted toward XP/calories due to a reliability "
            'check — you can see which one below.'
        : "$flaggedCount sets weren't counted toward XP/calories due to a "
            'reliability check — you can see which ones below.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: Color(0xFFD97706),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD97706),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Exercises section (gym or combined) — ported verbatim from
  // activity_detail_screen.dart's _buildExercisesSection(). ────────────────

  Widget _buildExercisesSection() {
    final exercises = _session['exercises'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _exercisesExpanded = !_exercisesExpanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
            child: Row(
              children: [
                const Icon(Icons.fitness_center_rounded,
                    size: 18, color: WW.primary),
                const SizedBox(width: 8),
                Text(
                  'Exercises (${exercises.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _exercisesExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: WW.textSec, size: 20),
                ),
              ],
            ),
          ),
        ),
        if (_exercisesExpanded) ...[
          Container(height: 0.5, color: WW.border),
          if (exercises.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Text('No exercises recorded.',
                  style: TextStyle(fontSize: 13, color: WW.textSec)),
            )
          else
            ...List.generate(exercises.length, (ei) {
              final ex = exercises[ei] as Map<String, dynamic>;
              final sets = ex['sets'] as List<dynamic>? ?? [];
              final completedSets = sets.where((s) {
                final m = s as Map<String, dynamic>;
                return m['done'] == true || m['completed'] == true;
              }).toList();
              final muscle = ex['muscle'] as String? ??
                  ex['muscleGroup'] as String? ??
                  '';
              final exName = ex['name'] as String? ??
                  ex['exerciseName'] as String? ??
                  'Exercise';

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: ei > 0
                        ? const BorderSide(color: WW.border, width: 0.5)
                        : BorderSide.none,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            exName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: WW.primaryDark,
                            ),
                          ),
                        ),
                        if (muscle.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: WW.elevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              muscle,
                              style: const TextStyle(
                                  fontSize: 11, color: WW.textSec),
                            ),
                          ),
                      ],
                    ),
                    if (completedSets.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: const [
                          Expanded(
                              flex: 1,
                              child: Text('Set',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: WW.textSec))),
                          Expanded(
                              flex: 2,
                              child: Text('kg',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: WW.textSec))),
                          Expanded(
                              flex: 2,
                              child: Text('Reps',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: WW.textSec))),
                        ],
                      ),
                      const SizedBox(height: 2),
                      ...List.generate(completedSets.length, (si) {
                        final s = completedSets[si] as Map<String, dynamic>;
                        final weight = s['kg'] ??
                            s['weight'] ??
                            s['weightKg'] ??
                            s['w'] ??
                            0;
                        final reps = s['reps'] ?? s['r'] ?? 0;
                        // Real kg/reps the user entered are shown exactly as
                        // recorded either way (see firestore_service.dart's
                        // cleaning loops) — this only adds a visual marker,
                        // it never hides or changes a flagged set's numbers.
                        final isFlagged = s['flaggedTiming'] == true ||
                            s['flaggedBounds'] == true;
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: WW.border, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                  flex: 1,
                                  child: Text('${si + 1}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: WW.textSec))),
                              Expanded(
                                  flex: 2,
                                  child: Text('$weight',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: WW.text))),
                              Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Text('$reps',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: WW.text)),
                                      if (isFlagged) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          size: 12,
                                          color: Color(0xFFD97706),
                                        ),
                                      ],
                                    ],
                                  )),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              );
            }),
        ],
      ],
    );
  }

  // ── Cardio blocks section (combined only) — ported verbatim from
  // activity_detail_screen.dart's _buildCardioBlocksSection()/
  // _buildCardioBlockCard() (including the single-active-map mechanism). ───

  List<Widget> _buildCardioBlocksSection() {
    final rawBlocks = _session['cardioBlocks'] as List<dynamic>? ?? [];
    if (rawBlocks.isEmpty) return [];

    final widgets = <Widget>[
      Row(
        children: [
          const Icon(Icons.directions_run_rounded, size: 18, color: WW.primary),
          const SizedBox(width: 8),
          Text(
            'Cardio (${rawBlocks.length})',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
    ];
    for (var i = 0; i < rawBlocks.length; i++) {
      widgets.add(_buildCardioBlockCard(i, rawBlocks[i] as Map<String, dynamic>));
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  IconData _cardioBlockActivityIcon(String activity) {
    switch (activity) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  String _fmtBlockDuration(int seconds) {
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

  // Map-snapshot preview only now (see _buildPhotoPreview's doc comment for
  // why the per-block photo moved there instead) — BoxFit.cover at a small
  // fixed height stays correct here since cropping a map thumbnail is
  // expected/harmless, unlike cropping the user's own photo.
  Widget? _decodeCardioBlockImage(String? raw, {double height = 160}) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildCardioBlockCard(int index, Map<String, dynamic> block) {
    final isOutdoor = block['mode'] == 'outdoor';
    final activity = block['activity'] as String? ?? 'Cardio';
    final distanceMeters = (block['distanceMeters'] as num?)?.toDouble();
    final avgHeartRate = (block['avgHeartRate'] as num?)?.toDouble();
    final elevationGainMeters =
        (block['elevationGainMeters'] as num?)?.toDouble();
    final durationSeconds = (block['durationSeconds'] as num?)?.toInt();
    final caloriesBurned = (block['caloriesBurned'] as num?)?.toInt();
    final routePoints =
        _parseRoutePoints(block['route'] as List<dynamic>? ?? []);
    final notes = block['notes'] as String?;
    final photoBase64 = block['photoBase64'] as String?;
    final paceLabel = (distanceMeters != null && durationSeconds != null)
        ? _avgPaceLabel(distanceMeters, durationSeconds)
        : null;

    final stats = <({String label, String value})>[
      if (durationSeconds != null && durationSeconds > 0)
        (label: 'Duration', value: _fmtBlockDuration(durationSeconds)),
      if (isOutdoor && distanceMeters != null && distanceMeters > 0)
        (
          label: 'Distance',
          value: '${(distanceMeters / 1000).toStringAsFixed(2)} km'
        ),
      if (isOutdoor && paceLabel != null) (label: 'Avg Pace', value: paceLabel),
      if (caloriesBurned != null && caloriesBurned > 0)
        (label: 'Calories', value: '$caloriesBurned kcal'),
      if (isOutdoor && elevationGainMeters != null && elevationGainMeters > 0)
        (label: 'Elevation', value: '${elevationGainMeters.round()} m'),
      if (!isOutdoor && avgHeartRate != null && avgHeartRate > 0)
        (label: 'Avg Heart Rate', value: '${avgHeartRate.round()} bpm'),
    ];

    final hasMapCandidate = isOutdoor && routePoints.isNotEmpty;
    _cardioBlockHasMap[index] = hasMapCandidate;
    final isActiveMap = hasMapCandidate && index == _activeCardioMapIndex;
    final mapSnapshotBase64 = block['mapSnapshotBase64'] as String?;
    final mapPreviewWidget = hasMapCandidate && !isActiveMap
        ? _decodeCardioBlockImage(mapSnapshotBase64, height: 180)
        : null;
    final photoWidget = _buildPhotoPreview(photoBase64, borderRadius: 12);

    return Container(
      key: _cardioBlockKeys.putIfAbsent(index, () => GlobalKey()),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _cardioBlockActivityIcon(activity),
                size: 18,
                color: WW.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activity,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: WW.chipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isOutdoor ? 'Outdoor' : 'Indoor',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: WW.primary,
                  ),
                ),
              ),
            ],
          ),
          if (hasMapCandidate && isActiveMap) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 180,
                child: MapLibreMap(
                  styleString: _kMapStyleUrl,
                  initialCameraPosition: CameraPosition(
                    target: routePoints.first,
                    zoom: 14,
                  ),
                  onMapCreated: (controller) =>
                      _onCardioBlockMapCreated(index, controller),
                  onStyleLoadedCallback: () =>
                      _onCardioBlockStyleLoaded(index, routePoints),
                ),
              ),
            ),
          ] else if (mapPreviewWidget != null) ...[
            const SizedBox(height: 10),
            mapPreviewWidget,
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final stat in stats)
                  Expanded(child: _statCell(stat.label, stat.value)),
              ],
            ),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              notes,
              style: const TextStyle(fontSize: 13, color: WW.text, height: 1.4),
            ),
          ],
          if (photoWidget != null) ...[
            const SizedBox(height: 10),
            photoWidget,
          ],
        ],
      ),
    );
  }

  // ── Notes section — ported verbatim from
  // activity_detail_screen.dart's _buildNotesSection(). ────────────────────

  Widget _buildNotesSection() {
    final notes = _session['notes'] as String?;
    final hasNotes = notes != null && notes.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NOTES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: WW.textSec,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasNotes ? notes : 'No notes added.',
          style: TextStyle(
            fontSize: 14,
            color: hasNotes ? WW.text : WW.textSec,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ── Action bar ────────────────────────────────────────────────────────────

  Widget _buildActionBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: WW.elevated, width: 1)),
      ),
      // Stacked rather than one 3-wide Row — "Post to Feed" doesn't fit in
      // an equal-thirds Expanded slot on narrower phones (RenderFlex
      // overflow). Done is the primary action (full-width, filled) below
      // the two secondary actions (Share/Post to Feed, outlined, sharing
      // the row evenly) — matches the visual-weight split already used
      // elsewhere in this app's action bars.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _isSharing ? null : () => _startCardFlow(forPost: false),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isSharing ? WW.border : WW.primary,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: _isSharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: WW.primary,
                                strokeWidth: 2,
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.ios_share_rounded,
                                    color: WW.primary, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Share',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: WW.primary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _isPosting ? null : () => _startCardFlow(forPost: true),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isPosting ? WW.border : WW.primary,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: _isPosting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: WW.primary,
                                strokeWidth: 2,
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.dynamic_feed_rounded,
                                    color: WW.primary, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Post to Feed',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: WW.primary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              if (_isGym || _isCombined) {
                final uid = AuthService().getCurrentUser()?.uid;
                final pid = _session['planId'] as String?;
                if (uid != null && pid != null && pid.isNotEmpty) {
                  FirestoreService().markSessionComplete(uid, pid);
                }
              }
              context.go(Routes.home);
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(14),
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
                  'Done',
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
    );
  }
}

// ── WiseCoach typing dots ─────────────────────────────────────────────────────

class _WiseCoachTypingDots extends StatefulWidget {
  const _WiseCoachTypingDots();

  @override
  State<_WiseCoachTypingDots> createState() => _WiseCoachTypingDotsState();
}

class _WiseCoachTypingDotsState extends State<_WiseCoachTypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final phase =
                ((_ctrl.value * 1400 - i * 160) % 1400) / 1400;
            final t =
                phase < 0.5 ? phase * 2 : (1.0 - phase) * 2;
            final scale = 0.8 + 0.2 * t;
            final opacity = 0.2 + 0.8 * t;
            return Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : 5),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: WW.lavender.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.diagonal3Values(scale, scale, 1),
              transformAlignment: Alignment.center,
            );
          },
        );
      }),
    );
  }
}
