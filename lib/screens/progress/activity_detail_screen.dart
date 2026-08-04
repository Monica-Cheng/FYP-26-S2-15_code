// lib/screens/progress/activity_detail_screen.dart

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../core/share_card_gradients.dart';
import '../../utils/image_encode.dart';
import '../../utils/widget_capture.dart';
import '../../widgets/photo_background_share_card.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../widgets/session_share_cards.dart';
import '../../widgets/share_card_picker.dart';

// Same OpenFreeMap style URL used in outdoor_cardio_screen.dart — duplicated
// here (not imported) since that file's own constant is library-private and
// this task's scope doesn't include modifying that file to export it.
const String _kMapStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  bool _exercisesExpanded = true;
  bool _wiseCoachExpanded = false;
  bool _deleteDialogOpen = false;
  // Share flow state — same shape as post_session_summary_screen.dart's
  // own _isSharing/_selectedGradientColors, reused via
  // buildSessionShareCardOptions() (lib/widgets/session_share_cards.dart)
  // rather than duplicating the card-building logic here. This screen
  // only wires up Share (native OS share) — no Post to Feed button,
  // that's still post_session_summary_screen.dart-only, right after a
  // session finishes.
  bool _isSharing = false;
  List<Color> _selectedGradientColors = ShareCardGradients.presets.first.colors;
  // Captured in _onCardioMapCreated, acted on in _onCardioStyleLoaded —
  // onStyleLoadedCallback's signature takes no controller argument (see
  // maplibre_gl's own typedef OnStyleLoadedCallback = void Function()),
  // so the controller has to be stashed here to be usable once the style
  // is actually ready to accept annotations.
  MapLibreMapController? _cardioMapController;

  // Whether the full-screen map view (opened by tapping the small preview
  // in _buildCardioMapSection()) is currently showing. Pure local UI
  // state, same pattern as outdoor_cardio_screen.dart's own
  // _statsExpanded/_buildExpandedStatsView() full-screen toggle — this
  // codebase has no dedicated photo/image-viewer route or dialog anywhere
  // (confirmed by search), so this in-place state-driven overlay is the
  // closest existing "expand to full screen" precedent to follow rather
  // than inventing a new route/dialog pattern.
  bool _cardioMapFullScreen = false;
  // Separate controller for the full-screen map's own MapLibreMap
  // instance — a completely independent widget/controller from
  // _cardioMapController above, not a reused one. Safe to do here (unlike
  // outdoor_cardio_screen.dart's live-tracking map, which had to stay
  // mounted across its own full-screen toggle to avoid losing
  // incrementally-recorded state) since _routePoints is fixed, already-
  // saved data — the full-screen map just redraws the exact same static
  // route from scratch, so there's nothing to lose by letting the small
  // preview's map mount/unmount independently of this one.
  MapLibreMapController? _cardioMapFullScreenController;

  // At most one cardio block's map is ever a live, interactive MapLibreMap
  // at a time — see _updateActiveCardioMap()'s doc comment for why (avoids
  // N simultaneous native GL platform views/tile-fetch contention). One
  // GlobalKey per cardioBlocks[] index, created on first build of that
  // card, used to read each card's on-screen position. _cardioBlockHasMap
  // records which indices are even eligible to become active (outdoor +
  // has route points) — indoor/no-route blocks are never candidates.
  // _activeCardioMapIndex is whichever eligible, currently-on-screen block
  // is closest to the viewport's vertical center; every other eligible
  // block renders its saved mapSnapshotBase64 as a static preview instead.
  final Map<int, GlobalKey> _cardioBlockKeys = {};
  final Map<int, bool> _cardioBlockHasMap = {};
  int? _activeCardioMapIndex;

  Map<String, dynamic> get _session =>
      GoRouterState.of(context).extra as Map<String, dynamic>? ?? {};

  bool get _isGym => _session['type'] == 'gym';
  bool get _isManual => _session['isManuallyLogged'] == true;
  // A plan-linked session containing both gym and cardio blocks — see
  // finalizeInProgressSession() (firestore_service.dart), which is the only
  // place that ever writes type:'combined'. Must be excluded from _isCardio
  // below: before this, a combined session fell through into the "cardio"
  // branch (since it isn't literally type=='gym'), which reads top-level
  // fields (session['activity'], session['distanceMeters'], etc.) that
  // finalizeInProgressSession never populates for combined sessions — those
  // are only promoted to the top level for a PURE 'cardio' session. Combined
  // sessions instead carry their gym data in exercises[] (same as 'gym') and
  // every cardio block preserved as its own entry in cardioBlocks[] — see
  // _buildCardioBlocksSection().
  bool get _isCombined => _session['type'] == 'combined';
  // Cardio here means "not gym, not manual, not combined" — matches how the
  // rest of this screen already branches (everything left over falls into
  // the cardio stats-row branch below), so indoor and outdoor cardio both
  // still count, while combined sessions now correctly fall out of this
  // getter into their own dedicated rendering path instead.
  bool get _isCardio => !_isGym && !_isManual && !_isCombined;

  String get _title =>
      _session['sessionName'] as String? ??
      _session['activityName'] as String? ??
      'Activity';

  // Matches the exact Run/Walk/Cycle icon-selection logic added to the
  // Activities list (_ActivityCard._iconData in progress_screen.dart) —
  // duplicated here for the same library-privacy reason as _kMapStyleUrl.
  IconData get _headerIcon {
    if (_isManual) return Icons.edit_note_rounded;
    if (_isGym) return Icons.fitness_center_rounded;
    switch (_session['activity'] as String?) {
      case 'Walk':
        return Icons.directions_walk_rounded;
      case 'Cycle':
        return Icons.directions_bike_rounded;
      default:
        return Icons.directions_run_rounded;
    }
  }

  // Only outdoor cardio ever writes a route (see outdoor_cardio_screen.dart's
  // _downsampleRoute/_saveActivity) — gating on the data itself rather than
  // on mode == 'outdoor' alone means a hypothetical outdoor session that
  // captured zero points correctly shows no map instead of an empty one.
  // Checked against _routePoints (the parsed/filtered list actually used
  // for rendering), not the raw stored list — if every raw entry happened
  // to be malformed, the raw list would still be non-empty while
  // _routePoints ends up empty, and _buildCardioMapSection() calls
  // .first on it; gating on the parsed list keeps that always safe.
  bool get _hasRoute => _routePoints.isNotEmpty;

  // Converts the stored {lat, lng} map list into maplibre_gl LatLng points —
  // the exact conversion shape confirmed against saveCardioSession()'s
  // 'route': List<Map<String, double>> write in firestore_service.dart.
  //
  // `late final` rather than a plain getter: this used to be recomputed
  // independently on every access (the map's initial camera target, the
  // line draw, and the bounds fit each re-parsed the same underlying data
  // separately) — the underlying _session data is fixed for this screen's
  // whole lifetime (the route `extra` never changes after this screen is
  // pushed), so a getter was pure waste, not a correctness concern. A
  // `late final` field initializer runs its expression exactly once, on
  // first access, and caches the result from then on — simpler than
  // moving this into initState(), since context (needed by the `_session`
  // getter this depends on) isn't guaranteed ready that early, whereas
  // every actual call site here already runs during/after build.
  //
  // Per-point conversion is wrapped individually so one malformed entry
  // (missing/non-numeric lat/lng — this is runtime GPS data, not a
  // compile-time-guaranteed shape) is skipped rather than throwing an
  // uncaught TypeError that would crash the whole screen's build.
  late final List<LatLng> _routePoints =
      _parseRoutePoints(_session['route'] as List<dynamic>? ?? []);

  // Parameterized (not tied to the top-level session['route'] field) so
  // _buildCardioBlockCard() can reuse this same conversion for a given
  // cardioBlocks[] entry's own 'route' field.
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

  // Same 50m-floor + MM:SS/km formatting convention already used in
  // outdoor_cardio_screen.dart's own pace label and progress_screen.dart's
  // Activities list — returns null below that floor rather than a
  // nonsensical/noisy pace.
  String? _avgPaceLabel(double distanceMeters, int durationSeconds) {
    if (distanceMeters < 50 || durationSeconds <= 0) return null;
    final secondsPerKm = durationSeconds / (distanceMeters / 1000);
    if (!secondsPerKm.isFinite) return null;
    final mins = secondsPerKm ~/ 60;
    final secs = (secondsPerKm % 60).round();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} /km';
  }

  // ── Share flow ─────────────────────────────────────────────────────────
  // Same shape as post_session_summary_screen.dart's own
  // _startCardFlow/_pickPhotoThenContinue/_showCardPickerAndContinue/
  // _shareCard (share-only — this screen has no Post to Feed button, so
  // the forPost branching from that screen's version isn't needed here),
  // pointed at this screen's own _session/_routePoints/_isCardio instead
  // of duplicating the card-building logic itself, which now lives in
  // buildSessionShareCardOptions() (lib/widgets/session_share_cards.dart).

  String? get _reusablePhotoBase64 =>
      PhotoBackgroundShareCard.reusablePhotoBase64(_session);

  Future<void> _startShareFlow() async {
    if (_isSharing) return;

    final existingPhoto = _reusablePhotoBase64;
    if (existingPhoto != null) {
      await _showCardPickerAndShare(photoBase64: existingPhoto);
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
        onTap: () => _pickPhotoThenContinue(ImageSource.camera),
      ),
      QuickAddOption(
        icon: Icons.photo_library_rounded,
        iconColor: WW.teal,
        iconBg: WW.tealBg,
        title: 'Choose from Gallery',
        subtitle: 'Pick an existing photo',
        onTap: () => _pickPhotoThenContinue(ImageSource.gallery),
      ),
      QuickAddOption(
        icon: Icons.arrow_forward_rounded,
        iconColor: WW.textSec,
        iconBg: WW.elevated,
        title: 'Skip Photo',
        subtitle: 'Only offer the Map/Color card designs',
        onTap: () => _showCardPickerAndShare(photoBase64: null),
      ),
    ]);
  }

  Future<void> _pickPhotoThenContinue(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    String? encoded;
    if (picked != null) {
      encoded = await encodeImageBase64(File(picked.path));
    }
    await _showCardPickerAndShare(photoBase64: encoded);
  }

  Future<void> _showCardPickerAndShare({required String? photoBase64}) async {
    if (!mounted) return;
    _selectedGradientColors = ShareCardGradients.presets.first.colors;
    final cards = buildSessionShareCardOptions(
      session: _session,
      isCardio: _isCardio,
      routePoints: _routePoints,
      selectedGradientColors: _selectedGradientColors,
      photoBase64: photoBase64,
    );
    final chosenIndex = await showShareCardPicker(
      context,
      cards: cards,
      confirmLabel: 'Share This Design',
      onGradientChanged: (colors) => _selectedGradientColors = colors,
    );
    if (chosenIndex == null || !mounted) return;
    await _shareCard(cards[chosenIndex]);
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
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate share card.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final tempDir = Directory.systemTemp;
      final file = File(
          '${tempDir.path}/wiseworkout_session_'
          '${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Just crushed a session on WiseWorkout! 💪',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not share: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // Zero-new-dependency substitute for a VisibilityDetector package (not
  // already a pubspec.yaml dependency — confirmed in an earlier phase) —
  // combined with the NotificationListener<ScrollNotification> below and an
  // initial post-frame call from build(), this recomputes, on every scroll
  // and once on initial layout, which single eligible (outdoor + has route)
  // cardio block card is closest to the viewport's vertical center among
  // whichever are currently on screen at all, and makes that one the live
  // MapLibreMap — every other eligible block falls back to its static
  // mapSnapshotBase64 preview (see _buildCardioBlockCard). This caps the
  // number of simultaneous native GL platform views/tile-fetch requests at
  // exactly one, regardless of how many outdoor blocks a combined session
  // has. A simple screen-bounds overlap check (not exact scrollview-
  // viewport clipping) is deliberately enough here, matching this file's
  // existing precedent — the goal is picking a reasonable "most prominent"
  // block, not pixel-perfect viewport math. If no eligible block is
  // currently on screen (e.g. scrolled past the whole cardio section),
  // the previous active index is left as-is rather than cleared — nothing
  // is visibly showing anyway, and clearing it would just force an
  // unnecessary rebuild.
  void _updateActiveCardioMap() {
    if (!mounted) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final viewportCenter = screenHeight / 2;
    int? bestIndex;
    double? bestDistance;
    for (final entry in _cardioBlockKeys.entries) {
      final index = entry.key;
      if (_cardioBlockHasMap[index] != true) continue;
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final position = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      final isOnScreen =
          position.dy < screenHeight && (position.dy + size.height) > 0;
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
      // The previously-active block's MapLibreMap widget is about to be
      // replaced by a static Image.memory preview in the tree — its own
      // State.dispose() (confirmed in an earlier phase by reading the
      // installed maplibre_gl source directly) already tears down the
      // underlying controller/platform view once that widget leaves the
      // tree, so this is only dropping our own now-stale map reference,
      // not a manual controller.dispose() call.
      if (previousIndex != null) {
        _cardioBlockMapControllers.remove(previousIndex);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // TEMPORARY DEBUG — remove once the post-always-fresh-key regression is
    // confirmed fixed. No safe initState() equivalent exists in this file
    // (_session depends on GoRouterState.of(context).extra, which isn't
    // readable that early — see _session's own getter) so this logs on
    // every build() pass instead, same as this file's other diagnostics.
    final debugSession = _session;
    final debugCardioBlocks = debugSession['cardioBlocks'];
    print('DEBUG_REGRESSION: ActivityDetailScreen.build() session '
        'type=${debugSession['type']} '
        'sessionName=${debugSession['sessionName']} '
        'exercises.length=${(debugSession['exercises'] as List?)?.length ?? 'absent'} '
        'cardioBlocks.length=${debugCardioBlocks is List ? debugCardioBlocks.length : 'null/absent'}');

    final hasNotes = (_session['notes'] as String?)?.isNotEmpty == true;
    final photoWidget = _isCardio ? _buildPhotoWidget() : null;

    // Catches the initial active map choice without any scrolling (e.g. a
    // single outdoor block already on screen at load) — the scroll-
    // notification listener below only fires once the user actually
    // scrolls.
    if (_isCombined) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _updateActiveCardioMap());
    }

    return Scaffold(
      backgroundColor: WW.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (_isCombined) _updateActiveCardioMap();
                    return false;
                  },
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: 12),
                        _buildStatsRow(),
                        const SizedBox(height: 12),
                        _buildWiseCoachCard(),
                        const SizedBox(height: 12),
                        ..._xpCardWidgets(),
                        if (_isCardio && _hasRoute) ...[
                          _buildCardioMapSection(),
                          const SizedBox(height: 12),
                        ],
                        if (_isGym || _isCombined) ...[
                          _buildExercisesSection(),
                          const SizedBox(height: 12),
                        ],
                        if (_isCombined) ..._buildCardioBlocksSection(),
                        if (_isManual) ...[
                          _buildNotesSection(),
                          const SizedBox(height: 12),
                          _buildDeleteButton(),
                        ],
                        if (_isCardio && hasNotes) ...[
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
            ],
          ),
          if (_deleteDialogOpen) _buildDeleteDialog(),
          if (_cardioMapFullScreen) _buildCardioMapFullScreen(),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: WW.card,
          border: Border(bottom: BorderSide(color: WW.border, width: 0.5)),
          boxShadow: WW.shadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16, color: WW.primaryDark),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: _startShareFlow,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.share_rounded, size: 18, color: WW.primaryDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  // Flat — no gradient hero, no per-type color coding. Icon sits in a
  // neutral WW.elevated circle; the only remaining color signal is the
  // small "Manual" label, which stays intentionally neutral (informational,
  // not decorative) rather than reintroducing a distinct accent color.

  Widget _buildHeaderCard() {
    final duration = _formatDuration();
    final subtitleParts = <String>[_formatDate(_session['date'])];
    if (duration.isNotEmpty) subtitleParts.add(duration);
    final subtitle = subtitleParts.join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: WW.elevated,
            shape: BoxShape.circle,
          ),
          child: Icon(_headerIcon, color: WW.text, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 3),
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
        if (_isManual)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: WW.elevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Manual',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: WW.textSec,
              ),
            ),
          ),
      ],
    );
  }

  // ── Stats row ──────────────────────────────────────────────────────────────
  // Flat WW.elevated fill, no border/shadow — matches the treatment already
  // used for Progress's own stat-cards row (_buildStatCardsRow) rather than
  // the bordered/shadowed WW.cardDecoration this used before.

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
        // Real route data (outdoor cardio) — swap the generic Duration/
        // Calories/"Type: Cardio" row for the actually-relevant numbers.
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

  // ── WiseCoach summary card (collapsible) ───────────────────────────────────
  // WW.primary left-accent-stripe treatment, matching Progress's own
  // Charts-tab WiseCoach card exactly — this used a distinct lavender
  // tint/fill before, which was the odd one out rather than an
  // intentionally different accent.

  Widget _buildWiseCoachCard() {
    final summary = _session['wiseCoachSummary'] as String?;
    final hasContent = summary != null && summary.isNotEmpty;

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
            Text(
              hasContent
                  ? summary
                  : 'Complete more sessions to unlock AI insights.',
              style: TextStyle(
                fontSize: 13,
                color: hasContent ? WW.text : WW.textSec,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── XP card ────────────────────────────────────────────────────────────────

  List<Widget> _xpCardWidgets() {
    final xp = (_session['xpEarned'] as num?)?.toInt() ?? 0;
    if (xp <= 0) return [];
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: WW.tealBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, color: WW.teal, size: 22),
            const SizedBox(width: 10),
            const Text(
              'XP earned',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WW.teal),
            ),
            const Spacer(),
            Text(
              '+$xp XP',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: WW.teal,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  // ── Outdoor cardio map section ─────────────────────────────────────────────
  // Small preview: still a real, live-rendering MapLibreMap underneath (same
  // style URL, line color/width, and bounds-fitting approach as
  // outdoor_cardio_screen.dart's live tracking map/_fitCameraToRoute, just
  // fitted once on load instead of live-updated) — kept live rather than
  // swapped for a static image so it still shows the genuine map/route with
  // no extra snapshot-decoding step. Its own pan/zoom/rotate/tilt gesture
  // recognizers are explicitly disabled below — an opaque GestureDetector
  // sitting on top of a MapLibreMap with those still enabled (the previous
  // state of this code) is a genuine, unresolved gesture-arena race against
  // the native platform view's own recognizers (confirmed via maplibre_gl's
  // own source: all of rotate/scroll/zoom/tilt/dragEnabled default to true),
  // not just a hit-test-ordering matter — HitTestBehavior.opaque alone only
  // makes the overlay reachable in Flutter's own hit-test, it doesn't defeat
  // a separately-registered native recognizer underneath. Disabling those
  // flags here removes the native recognizer from the arena entirely, so
  // the overlay's tap has nothing left to race against. All real
  // interaction now happens in _buildCardioMapFullScreen() instead, which
  // keeps every one of these gestures enabled (its default, unchanged).

  Widget _buildCardioMapSection() {
    final points = _routePoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: Stack(
              children: [
                MapLibreMap(
                  styleString: _kMapStyleUrl,
                  initialCameraPosition: CameraPosition(
                    target: points.first,
                    zoom: 14,
                  ),
                  onMapCreated: _onCardioMapCreated,
                  onStyleLoadedCallback: _onCardioStyleLoaded,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  dragEnabled: false,
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _cardioMapFullScreen = true),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // The downsampled route only stores {lat, lng} per point (see
        // outdoor_cardio_screen.dart's _downsampleRoute) — no per-point
        // timestamps are kept, so an accurate per-kilometer split
        // breakdown isn't computable from this data. Only the overall
        // average pace (already shown in the stats row above) is
        // available — showing fabricated/approximated splits here would
        // be misleading, so this is intentionally omitted rather than
        // guessed at.
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

  // Fires once the style/sources/layers have genuinely finished loading —
  // confirmed via maplibre_gl's own installed source (maplibre_map.dart):
  // its doc comment says annotations should only be added after this
  // callback, not onMapCreated, which only confirms the native view/
  // controller exists. Drawing the line from onMapCreated (the previous
  // approach) risked running addLine() before the style was ready, which
  // fails silently and — since the camera-fit was sequenced after it in
  // the same try/catch — also skipped the bounds-fit in the same failure.
  void _onCardioStyleLoaded() {
    final controller = _cardioMapController;
    if (controller == null) return;
    _drawRouteLine(controller, _routePoints);
    _fitCameraToRouteBounds(controller, _routePoints);
  }

  // ── Full-screen cardio map (opened by tapping the small preview) ───────────
  // Entirely independent MapLibreMap/controller from the small preview's —
  // see _cardioMapFullScreenController's field doc for why that's safe here.
  // Reuses _drawRouteLine/_fitCameraToRouteBounds as-is (both already take
  // an explicit controller + points, exactly for this kind of reuse).

  void _onCardioMapFullScreenCreated(MapLibreMapController controller) {
    _cardioMapFullScreenController = controller;
  }

  void _onCardioMapFullScreenStyleLoaded() {
    final controller = _cardioMapFullScreenController;
    if (controller == null) return;
    _drawRouteLine(controller, _routePoints);
    _fitCameraToRouteBounds(controller, _routePoints);
  }

  // Full-screen, fully-interactive (no restrictions applied) MapLibreMap —
  // same opaque-Container-over-the-whole-screen + close-button pattern as
  // outdoor_cardio_screen.dart's own _buildExpandedStatsView(), the closest
  // existing full-screen-toggle precedent in this codebase (no dedicated
  // photo/image-viewer route or dialog exists anywhere to reuse instead —
  // confirmed by search). Dismissing just flips _cardioMapFullScreen back to
  // false; the controller field is left to be naturally replaced next time
  // this view is reopened (MapLibreMap's own State.dispose() already tears
  // down the underlying platform view when this widget leaves the tree, per
  // the same precedent already relied on elsewhere in this file — see
  // _updateActiveCardioMap()'s doc comment).
  Widget _buildCardioMapFullScreen() {
    final points = _routePoints;
    return Positioned.fill(
      child: Container(
        color: WW.bg,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Route',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: WW.text,
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _cardioMapFullScreen = false),
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
              Expanded(
                child: points.isEmpty
                    ? const SizedBox.shrink()
                    : MapLibreMap(
                        styleString: _kMapStyleUrl,
                        initialCameraPosition: CameraPosition(
                          target: points.first,
                          zoom: 14,
                        ),
                        onMapCreated: _onCardioMapFullScreenCreated,
                        onStyleLoadedCallback:
                            _onCardioMapFullScreenStyleLoaded,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // One controller per cardioBlocks[] entry — a combined session can have
  // more than one outdoor block, each needing its own independent map (see
  // _buildCardioBlockCard()), unlike the single _cardioMapController above
  // which only ever needs to track one pure-cardio session's map. Keyed by
  // the block's position in cardioBlocks[].
  final Map<int, MapLibreMapController> _cardioBlockMapControllers = {};

  void _onCardioBlockMapCreated(int index, MapLibreMapController controller) {
    _cardioBlockMapControllers[index] = controller;
  }

  void _onCardioBlockStyleLoaded(int index, List<LatLng> points) {
    final controller = _cardioBlockMapControllers[index];
    if (controller == null) return;
    _drawRouteLine(controller, points);
    _fitCameraToRouteBounds(controller, points);
  }

  // Independent try/catch from _fitCameraToRouteBounds — a failure here
  // no longer prevents the camera from still fitting to the route. Takes
  // `points` explicitly (rather than always reading _routePoints) so both
  // the pure-cardio path (passing _routePoints) and each cardio block's own
  // map (passing that block's own parsed route) can share this same method.
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
      debugPrint(
        'ActivityDetailScreen: route line drawn (${points.length} points).',
      );
    } catch (e) {
      debugPrint('ActivityDetailScreen: route line draw failed — $e');
    }
  }

  // Independent try/catch from _drawRouteLine — a failure here no longer
  // depends on (or blocks) whether the line itself was drawn. Same
  // explicit-`points` reasoning as _drawRouteLine above.
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
      debugPrint('ActivityDetailScreen: camera fitted to route bounds.');
    } catch (e) {
      debugPrint('ActivityDetailScreen: camera bounds-fit failed — $e');
    }
  }

  // ── Photo (cardio only) ─────────────────────────────────────────────────

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

  // ── Exercises section (gym only, collapsible) ──────────────────────────────

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
                          ? const BorderSide(
                              color: WW.border, width: 0.5)
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
                          final s =
                              completedSets[si] as Map<String, dynamic>;
                          final weight = s['kg'] ??
                              s['weight'] ??
                              s['weightKg'] ??
                              s['w'] ??
                              0;
                          final reps = s['reps'] ?? s['r'] ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                    color: WW.border, width: 0.5),
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
                                    child: Text('$reps',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: WW.text))),
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

  // ── Cardio blocks section (combined sessions only) ─────────────────────────
  // One card per entry in cardioBlocks[] — see finalizeInProgressSession()'s
  // cardioFieldKeys (firestore_service.dart) for the exact set of fields that
  // survive onto each entry: activity, mode, distanceMeters, durationSeconds,
  // caloriesBurned, avgHeartRate, maxHeartRate, route, elevationGainMeters,
  // photoBase64, mapSnapshotBase64, notes, name (only when present on the
  // original block — durationSeconds/caloriesBurned were added to this
  // whitelist in an earlier fix, so both are reliably present now). 'mode' —
  // written as 'outdoor' by outdoor_cardio_screen.dart's _saveActivity() and
  // 'indoor' by cardio_session_screen.dart's _finishSession() — is the
  // reliable indoor/outdoor signal, checked here rather than route/
  // mapSnapshotBase64 presence alone (a genuinely outdoor block that
  // captured zero GPS points would still be mode:'outdoor' with no route,
  // same reasoning as this file's own _hasRoute doc comment above).

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

    // Only outdoor blocks with at least one real route point are eligible
    // for a map section at all — same _hasRoute-style gating this file's
    // pure-cardio path already uses (a genuinely outdoor block that
    // captured zero GPS points still correctly shows no map, exactly like
    // before). Recorded in _cardioBlockHasMap so _updateActiveCardioMap()
    // knows which indices are real candidates for the single live map.
    final hasMapCandidate = isOutdoor && routePoints.isNotEmpty;
    _cardioBlockHasMap[index] = hasMapCandidate;
    // Only the single active index (closest to viewport center among
    // currently-visible eligible blocks — see _updateActiveCardioMap())
    // ever gets the live, interactive MapLibreMap; every other eligible
    // block falls back to its saved mapSnapshotBase64 static preview
    // instead, sized/rounded to match so the layout doesn't jump when a
    // block becomes/stops being active.
    final isActiveMap = hasMapCandidate && index == _activeCardioMapIndex;
    final mapSnapshotBase64 = block['mapSnapshotBase64'] as String?;
    // Only decoded when actually needed (not the active index) — per-point
    // 4 of this task's instructions, a missing snapshot on an eligible-but-
    // inactive block simply renders no map section at all, same fail-soft
    // behavior _decodeCardioBlockImage already has elsewhere in this file.
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

  // ── Notes section ─────────────────────────────────────────────────────────

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

  // ── Delete button ──────────────────────────────────────────────────────────

  Widget _buildDeleteButton() {
    return GestureDetector(
      onTap: () => setState(() => _deleteDialogOpen = true),
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text(
            'Delete Activity',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDC2626),
            ),
          ),
        ),
      ),
    );
  }

  // ── Delete confirmation bottom sheet ──────────────────────────────────────

  Widget _buildDeleteDialog() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _deleteDialogOpen = false),
        child: Container(
          color: Colors.black.withValues(alpha:0.5),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: WW.card,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33141D3C),
                      blurRadius: 40,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: WW.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Delete activity?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: WW.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This will permanently remove this manually logged activity and its XP. This cannot be undone.',
                      style: TextStyle(
                          fontSize: 14, color: WW.textSec, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        setState(() => _deleteDialogOpen = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Delete coming soon'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text(
                            'Delete activity',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => setState(() => _deleteDialogOpen = false),
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: WW.elevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: WW.border, width: 1.5),
                        ),
                        child: const Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: WW.text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
