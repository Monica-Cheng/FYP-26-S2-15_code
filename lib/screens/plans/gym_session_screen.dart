// lib/screens/plans/gym_session_screen.dart
// Active gym session tracker.
// Full-screen experience: no bottom nav bar.
// Timer counts up while not paused. Rest timer counts down after each done set.
// Five exercises displayed one at a time via progress dots.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Same size-capped downscale-to-480px-JPEG-then-base64 pipeline already used
// by outdoor_cardio_screen.dart's _encodeImageForSession/mid_plan_cardio_
// complete_screen.dart's _encodePhoto — reused here (not imported, since
// those are private instance methods on different State classes) for the
// standalone gym-session finish form's own photo picker.
const int _kFinishPhotoMaxBase64Bytes = 500 * 1024;

// Belt-and-suspenders safety net for the injury-review-dismissed flag,
// alongside the Firestore-persisted injuryReviewDismissed field on the
// inProgressSessions doc (see _hydrateFromInProgressSession's use of it).
// Library-scope (survives every GymSessionScreen State object, including
// the fresh one router.dart's forceRefresh deliberately creates on every
// mid_plan_cardio_complete_screen.dart "Next" tap — see that route's own
// doc comment) so that even if dismissInjuryReview()'s write is still
// retrying/failed when a forceRefresh remount happens moments later, the
// sheet still won't re-show within the same app run. Only ever added to,
// never read as authoritative on its own — the Firestore field is still
// the source of truth checked first; this only fills the gap for a
// session already dismissed once THIS app run whose write hasn't landed
// yet.
final Set<String> _dismissedInjuryReviewSessionRunIds = <String>{};

// ── Exercise library (Add Exercise sheet) ──────────────────────────────────────

const _kGymMuscleFilters = [
  'All', 'Chest', 'Back', 'Shoulders', 'Arms',
  'Legs', 'Core', 'Glutes',
];

// ── Data models ────────────────────────────────────────────────────────────────

enum _SetType { warmup, normal, dropSet }

class _SetData {
  String prev;
  _SetType type;
  bool done;
  String kg;
  String reps;
  // Real wall-clock moment this set last transitioned to done:true — see
  // _markSetDone() for exactly when this is set (fresh, every time) and
  // cleared (on un-done, so a reversed completion never leaves stale/
  // misleading data behind). Null until the set has been marked done at
  // least once. Pure data capture for now, per this task's explicit
  // scope — nothing reads this for plausibility/validation yet; that's a
  // separate future prompt once real captured data exists to pick
  // sensible thresholds from.
  DateTime? completedAt;

  _SetData({
    required this.prev,
    this.type = _SetType.normal,
    this.done = false,
    this.kg = '',
    this.reps = '',
    this.completedAt,
  });
}

class _ExerciseData {
  final String name;
  final String muscle;
  int restTime;
  final List<_SetData> sets;
  final bool isCardio;
  final String cardioActivity;
  final int cardioMinutes;
  List<String> injuryRisk;
  // True for a cardio block whose in-progress session doc already has
  // done:true (see _parseExercises) — i.e. its cardio activity was already
  // completed and synced via updateInProgressSessionBlock before this
  // screen was (re)loaded. Always false for a freshly-parsed plan template
  // (which never defines this field) and for exercises added via the "Add
  // Exercise" sheet. Not meaningful for gym exercises today — completion
  // there is tracked per-set (see _SetData.done), not on the exercise as a
  // whole.
  final bool done;
  // The exact raw map this exercise was parsed from — used by
  // _buildCardioPlaceholderCard to show real synced stats (duration,
  // distance, calories — whatever updateInProgressSessionBlock actually
  // wrote) for an already-completed cardio block, instead of the plan
  // template's static placeholder text. Empty for exercises added via the
  // "Add Exercise" sheet, which don't originate from a parsed block.
  final Map<String, dynamic> rawBlock;
  // This exercise's true, permanent position in the Firestore blocks[]
  // array (the same indexing createInProgressSession() used when it first
  // wrote blocks[] from the raw exercises array) — set exactly once, at
  // parse time (see _parseExercises), and never recalculated afterward.
  // Any write back to that array (see _syncBlockDone,
  // _buildCardioPlaceholderCard's onTap) must use this, not this
  // exercise's current position in whatever in-memory list it happens to
  // sit in right now — _applyInjuryFilter can remove earlier exercises
  // from _exercises, which shifts every later exercise's array position
  // without touching Firestore's blocks[] array at all, so array position
  // and true blocks[] position can silently diverge after that. Defaults
  // to -1 (never a parsed block — e.g. one added via the "Add Exercise"
  // sheet, which has no corresponding blocks[] slot to write to);
  // updateInProgressSessionBlock's own `blockIndex < 0` guard already
  // fails soft on that sentinel, so no extra handling is needed here.
  final int originalIndex;

  _ExerciseData({
    required this.name,
    required this.muscle,
    this.restTime = 90,
    required this.sets,
    this.isCardio = false,
    this.cardioActivity = '',
    this.cardioMinutes = 30,
    this.done = false,
    List<String>? injuryRisk,
    Map<String, dynamic>? rawBlock,
    this.originalIndex = -1,
  })  : injuryRisk = injuryRisk ?? [],
        rawBlock = rawBlock ?? const {};
}

// ── Column header style (module-level const) ──────────────────────────────────

const TextStyle _kColHeader = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  color: WW.textSec,
  letterSpacing: 0.4,
);

// ── Rest timer options (label, seconds) ──────────────────────────────────────

const List<(String, int)> _kRestOptions = [
  ('Off', 0),
  ('5s', 5),
  ('10s', 10),
  ('15s', 15),
  ('20s', 20),
  ('30s', 30),
  ('45s', 45),
  ('1m', 60),
  ('1m 30s', 90),
  ('2m', 120),
  ('2m 30s', 150),
  ('3m', 180),
  ('4m', 240),
  ('5m', 300),
];

String _fmtRestTime(int secs) {
  if (secs == 0) return 'Off';
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  final s = secs % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class GymSessionScreen extends StatefulWidget {
  final bool readOnly;
  const GymSessionScreen({super.key, this.readOnly = false});

  @override
  State<GymSessionScreen> createState() => _GymSessionState();
}

class _GymSessionState extends State<GymSessionScreen> {
  late bool _readOnly;
  String _creatorName = '';
  bool _isCustomPlan = false;
  // The plan's own sport/category field (plan['sport'] falling back to
  // plan['type'] — e.g. 'Running'/'Gym', same field explore_screen.dart's
  // plan cards already use) — populated identically to _isCustomPlan on
  // all three load paths below. Used only to decide which "+ Add" sheet(s)
  // to offer mid-session (see _handleAddTap()) — not for any per-exercise
  // cardio inference (that approach was tried and reverted; this is a
  // different, plan-level-only use).
  String? _planSport;
  int _elapsed = 0;
  bool _paused = false;
  bool _showRest = false;
  int _restSecs = 90;
  bool _isSaving = false;
  bool _isLoadingSession = true;
  // Standalone-finish-form fields (sessionRunId == null only — see
  // _showStandaloneFinishForm()/_saveAndNavigate()). Never read/shown for a
  // plan-linked session, which finishes via _saveAndNavigate()'s early
  // return with no form at all, per earlier design decisions for the
  // mid-plan flow.
  final _finishNameController = TextEditingController();
  final _finishNotesController = TextEditingController();
  File? _finishPickedPhoto;
  bool _isCompressed = false;
  bool _isRestDay = false;
  String _sessionName = 'Workout';
  String _planId = '';
  // Set once createInProgressSession() succeeds (see _createInProgressSession,
  // called from _loadPlanSession) — threaded into the cardio screens via
  // _buildCardioPlaceholderCard so a cardio block launched mid-session can
  // report its completion back to the same in-progress session doc. Null
  // until that write resolves, or forever if it fails (fails soft).
  String? _sessionRunId;
  // The Future returned by _createInProgressSession() — awaited by
  // _buildCardioPlaceholderCard's tap handler before reading _sessionRunId
  // into the extra map, so a fast tap (before the fire-and-forget write in
  // _loadPlanSession has resolved) doesn't race and push a cardio screen
  // with sessionRunId still null.
  Future<void>? _sessionInitFuture;

  bool _injuryFilteringEnabled = false;
  List<Map<String, dynamic>> _userInjuries = [];
  List<Map<String, dynamic>> _flaggedExercises = [];
  bool _injuryReviewPending = false;
  bool _isInjuryFiltered = false;
  // Set from _hydrateFromInProgressSession()'s own already-in-scope read of
  // the inProgressSessions doc (no second Firestore read needed) when
  // resuming an existing sessionRunId whose injury review was already
  // completed in an earlier mount of this screen — checked by initState()'s
  // postFrameCallback chain to skip re-running
  // _enrichExercisesWithInjuryRisk()/_checkExercisesForInjuries() and
  // re-showing the sheet on this resume. Stays at its default false for a
  // fresh-start session (no sessionRunId yet, or one just created this
  // load), which correctly always runs the check once, as intended.
  bool _injuryReviewAlreadyDismissed = false;

  Timer? _elapsedTimer;
  Timer? _restTimer;

  List<_ExerciseData> _exercises = [];

  @override
  void initState() {
    super.initState();
    _readOnly = widget.readOnly;
    // _loadPlanSession() reads GoRouterState.of(context).extra as one of
    // its first steps (added when the Firestore-hydrated resume path was
    // introduced) — an InheritedWidget lookup, which throws a Flutter
    // framework assertion if made synchronously from initState(), before
    // this widget's element is fully activated in the dependency graph.
    // Every other screen in this codebase that reads GoRouterState.of
    // (context).extra (cardio_setup_screen.dart's _readExtra,
    // cardio_session_screen.dart's own initState,
    // outdoor_cardio_screen.dart's _readActivityExtra,
    // mid_plan_cardio_complete_screen.dart's initState) defers that read
    // via addPostFrameCallback for exactly this reason — wrapping the
    // existing call here the same way, unchanged otherwise, matches that
    // same pattern instead of being the one exception to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPlanSession().then((_) async {
        await _loadPreviousSessionData();
        // Skipped entirely on a resume whose injury review was already
        // dismissed in an earlier mount (see _injuryReviewAlreadyDismissed's
        // field doc) — nothing left to enrich/check/prompt for, since the
        // user already made their keep/remove choices for this sessionRunId
        // and any removed exercises were already persisted out of blocks[]
        // by dismissInjuryReview() (see _applyInjuryFilter()).
        if (!_injuryReviewAlreadyDismissed) {
          await _enrichExercisesWithInjuryRisk();
          await _loadInjuryData();
          if (_injuryReviewPending && mounted) {
            await _showInjuryReviewSheet();
          }
        }
      });
    });
    if (!_readOnly) _startElapsedTimer();
  }

  Future<void> _loadPlanSession() async {
    // TEMPORARY DEBUG — remove once the post-always-fresh-key regression is
    // confirmed fixed.
    print('DEBUG_REGRESSION: _loadPlanSession() called at '
        '${DateTime.now().toIso8601String()}');
    try {
      final uid = AuthService().getCurrentUser()?.uid;
      if (uid == null) {
        if (mounted) setState(() => _isLoadingSession = false);
        return;
      }

      // Resume path: if this screen was reached with a sessionRunId (see
      // mid_plan_cardio_complete_screen.dart's "Next" button, which routes
      // back here via context.go(Routes.gymSession, extra: {...}) instead
      // of an assumed-depth pop), hydrate directly from the in-progress
      // session doc instead of re-parsing the static plan template below —
      // that doc already reflects true current tick state (done
      // blocks/sets), which a fresh parse would otherwise silently reset.
      // Falls through to the unchanged fresh-start logic below if
      // sessionRunId is absent, or the read comes back null/failed — see
      // _hydrateFromInProgressSession's own doc comment.
      final routeExtra =
          GoRouterState.of(context).extra as Map<String, dynamic>?;
      final extraSessionRunId = routeExtra?['sessionRunId'] as String?;
      // TEMPORARY DEBUG — remove once the post-always-fresh-key regression
      // is confirmed fixed.
      print('DEBUG_REGRESSION: _loadPlanSession branch check '
          'extraSessionRunId=${extraSessionRunId ?? 'null'}');
      if (extraSessionRunId != null) {
        final hydrated = await _hydrateFromInProgressSession(
            uid, extraSessionRunId, routeExtra);
        // TEMPORARY DEBUG — remove once the post-always-fresh-key
        // regression is confirmed fixed.
        print('DEBUG_REGRESSION: _loadPlanSession HYDRATE branch '
            'sessionRunId=$extraSessionRunId hydrated=$hydrated');
        if (hydrated) return;
      }

      // Check user doc for a one-time plan+day override
      // (set by Start button on any day card in All Plans)
      final userDoc = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(uid)
          .get();
      final userData = userDoc.data();
      final overridePlanId = userData?['overridePlanId'] as String?;
      final overrideDay =
          (userData?['overrideDayIndex'] as num?)?.toInt();

      // Determine which plan to load
      Map<String, dynamic>? plan;
      String planId;
      int effectiveDayIndex;

      if (overridePlanId != null &&
          overridePlanId.isNotEmpty &&
          overrideDay != null) {
        // FREE SESSION: load the specific plan and day from Start button
        // Clear the override immediately (fire and forget)
        FirestoreService().clearOverrideDayIndex(uid, overridePlanId);

        // Fetch the override plan directly
        final planDoc = await FirebaseFirestore.instance
            .collection(Collections.plans)
            .doc(overridePlanId)
            .get();
        if (!planDoc.exists) {
          if (mounted) setState(() => _isLoadingSession = false);
          return;
        }
        plan = {'id': planDoc.id, ...planDoc.data()!};
        planId = overridePlanId;
        effectiveDayIndex = overrideDay;
        _planId = planId;
        // No compression check for free sessions

        // Defense-in-depth: the schedule screens already hide/disable the
        // tap target for a completed day (isCompleted/_statusOf checks in
        // plan_detail_screen.dart / plan_schedule_screen.dart), but that's
        // UI-layer only — nothing below re-checked it before this point.
        // Re-verify against the authoritative lifetime completedDayIndices
        // ledger here so a stale/racy UI gate can't still start a session
        // for an already-completed day (see _extractCompletedDayIndices).
        final overrideProgress =
            await FirestoreService().getPlanProgress(uid, planId);
        if (_extractCompletedDayIndices(overrideProgress)
            .contains(effectiveDayIndex)) {
          if (mounted) setState(() => _isLoadingSession = false);
          await _blockAlreadyCompletedDay();
          return;
        }
      } else {
        // TRACKED SESSION: existing logic
        plan = await FirestoreService().getTrackedPlan(uid);
        if (plan == null) {
          if (mounted) setState(() => _isLoadingSession = false);
          return;
        }
        planId = plan['id'] as String? ?? '';
        _planId = planId;

        final progress = planId.isNotEmpty
            ? await FirestoreService().getPlanProgress(uid, planId)
            : null;
        final currentDayIndex =
            (progress?['currentDayIndex'] as num?)?.toInt() ?? 1;
        effectiveDayIndex = currentDayIndex;

        // Defense-in-depth — same authoritative ledger re-check as the
        // override branch above, for the Home/Plans-tab tracked-card entry
        // point (see that branch's doc comment for why this exists).
        // `progress` is already fetched above, so no extra read needed.
        if (_extractCompletedDayIndices(progress)
            .contains(effectiveDayIndex)) {
          if (mounted) setState(() => _isLoadingSession = false);
          await _blockAlreadyCompletedDay();
          return;
        }

        final sessions = (plan['sessions'] as List<dynamic>?) ?? [];
        final total = sessions.length;
        if (sessions.isEmpty) {
          if (mounted) setState(() => _isLoadingSession = false);
          return;
        }

        final sessionIdx = (effectiveDayIndex - 1) % total;
        final session = sessions[sessionIdx] as Map<String, dynamic>;
        final isRest = session['isRestDay'] == true;

        if (isRest) {
          if (mounted) {
            setState(() {
              _isRestDay = true;
              _sessionName = session['name'] as String? ?? 'Rest';
              _isLoadingSession = false;
            });
          }
          return;
        }

        List<dynamic> rawExercises =
            (session['exercises'] as List<dynamic>?) ?? [];

        bool isCompressed = false;
        final compressedDaysList = progress?['compressedDays'];
        if (compressedDaysList is List) {
          final compressedDays =
              compressedDaysList.map((d) => (d as num).toInt()).toSet();
          if (compressedDays.contains(effectiveDayIndex)) {
            rawExercises = rawExercises.where((e) {
              final tag =
                  (e as Map<String, dynamic>)['tag'] as String? ?? '';
              return tag != 'Accessory';
            }).toList();
            isCompressed = true;
          }
        }

        final exercises = _parseExercises(rawExercises,
            isListSets: null, debugSource: 'FRESH_START_TRACKED');
        final designedBy = plan['designedBy'] as Map<String, dynamic>?;
        final isCustom = plan['isCustom'] as bool? ?? false;
        final creatorName = isCustom
            ? 'Custom Routine'
            : (designedBy?['name'] as String? ?? 'WiseWorkout Coach');
        // Not awaited here — see _createInProgressSession's doc comment —
        // but the Future is cached so _buildCardioPlaceholderCard's tap
        // handler can await it (fixes the sessionRunId race condition).
        // TEMPORARY DEBUG — remove once the post-always-fresh-key
        // regression is confirmed fixed.
        print('DEBUG_REGRESSION: _loadPlanSession FRESH_START_TRACKED '
            'branch — creating new in-progress session planId=$planId '
            'dayIndex=$effectiveDayIndex');
        _sessionInitFuture =
            _createInProgressSession(uid, planId, effectiveDayIndex, rawExercises);
        if (mounted) {
          setState(() {
            _exercises = exercises;
            _isCompressed = isCompressed;
            _sessionName = session['name'] as String? ?? 'Workout';
            _isLoadingSession = false;
            _creatorName = creatorName;
            _isCustomPlan = isCustom;
            _planSport = plan?['sport'] as String? ?? plan?['type'] as String?;
          });
        }
        return;
      }

      // FREE SESSION path continues here
      final sessions = (plan['sessions'] as List<dynamic>?) ?? [];
      final total = sessions.length;
      if (sessions.isEmpty) {
        if (mounted) setState(() => _isLoadingSession = false);
        return;
      }

      final sessionIdx = (effectiveDayIndex - 1) % total;
      final session = sessions[sessionIdx] as Map<String, dynamic>;
      final isRest = session['isRestDay'] == true;

      if (isRest) {
        if (mounted) {
          setState(() {
            _isRestDay = true;
            _sessionName = session['name'] as String? ?? 'Rest';
            _isLoadingSession = false;
          });
        }
        return;
      }

      final rawExercises =
          (session['exercises'] as List<dynamic>?) ?? [];
      final exercises = _parseExercises(rawExercises,
          isListSets: null, debugSource: 'FRESH_START_FREE_SESSION');
      final designedBy = plan['designedBy'] as Map<String, dynamic>?;
      final isCustom = plan['isCustom'] as bool? ?? false;
      final creatorName = isCustom
          ? 'Custom Routine'
          : (designedBy?['name'] as String? ?? 'WiseWorkout Coach');
      // Not awaited here — see _createInProgressSession's doc comment —
      // but the Future is cached so _buildCardioPlaceholderCard's tap
      // handler can await it (fixes the sessionRunId race condition).
      // TEMPORARY DEBUG — remove once the post-always-fresh-key regression
      // is confirmed fixed.
      print('DEBUG_REGRESSION: _loadPlanSession FRESH_START_FREE_SESSION '
          'branch — creating new in-progress session planId=$planId '
          'dayIndex=$effectiveDayIndex');
      _sessionInitFuture =
          _createInProgressSession(uid, planId, effectiveDayIndex, rawExercises);

      if (mounted) {
        setState(() {
          _exercises = exercises;
          _isCompressed = false;
          _sessionName = session['name'] as String? ?? 'Workout';
          _isLoadingSession = false;
          _creatorName = creatorName;
          _isCustomPlan = isCustom;
          _planSport = plan?['sport'] as String? ?? plan?['type'] as String?;
        });
      }
    } catch (e) {
      // Logged (matching this file's print()-based convention elsewhere —
      // see _createInProgressSession/_saveAndNavigate) so a genuine error
      // here is visible instead of silently presenting as "no active plan
      // found" — this is exactly the failure mode the initState timing bug
      // above produced. Behavior is unchanged: still fails soft to the
      // same empty-_exercises/not-loading state either way.
      print('_loadPlanSession error: $e');
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  // Shared by both defense-in-depth checks in _loadPlanSession() above.
  Set<int> _extractCompletedDayIndices(Map<String, dynamic>? progress) {
    final raw = progress?['completedDayIndices'];
    if (raw is! List) return {};
    return raw.map((d) => (d as num).toInt()).toSet();
  }

  // Shown when _loadPlanSession()'s data-layer completion guard catches an
  // already-completed day slipping past the UI-layer gate. Navigates to
  // Routes.home rather than context.pop() for the same reason
  // _handleLeaveSession() does (see its own doc comment above) — this
  // screen can be reached via context.push() or context.go() depending on
  // entry point, and Routes.home is reachable either way.
  Future<void> _blockAlreadyCompletedDay() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                'Day already completed',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This day is already completed. Use Restart Program if you want to redo it.',
                style: TextStyle(
                  fontSize: 13,
                  color: WW.textSec,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WW.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    context.go(Routes.home);
  }

  // Attempts to hydrate _exercises/_sessionRunId/tick-state directly from
  // an existing inProgressSessions doc, for the resume path (see
  // _loadPlanSession's own doc comment). Returns true if hydration
  // succeeded (caller should stop, not fall through to the fresh-start
  // path) or false if it should fall back to exactly today's fresh-start
  // behavior — which happens whenever the read comes back null (missing
  // doc, or any Firestore error: getInProgressSession fails soft
  // internally and returns null either way) or the doc's `blocks` field
  // isn't a List.
  //
  // planId/dayIndex are read from `extra` if the caller supplied them
  // (mid_plan_cardio_complete_screen.dart does), else fall back to the
  // same fields stored directly on the in-progress session doc itself
  // (createInProgressSession always writes both there) — either source is
  // fine since they should always agree.
  //
  // Does NOT call createInProgressSession() — the doc already exists;
  // creating a second one for the same resumed session would orphan the
  // original and its already-recorded progress.
  Future<bool> _hydrateFromInProgressSession(
    String uid,
    String sessionRunId,
    Map<String, dynamic>? extra,
  ) async {
    final data = await FirestoreService().getInProgressSession(uid, sessionRunId);
    if (data == null) return false;

    // TEMPORARY DEBUG — remove once the second-cardio-block bug is
    // confirmed fixed.
    final debugRawBlocks = data['blocks'];
    print('DEBUG_BLOCKINDEX: _hydrateFromInProgressSession read back '
        'sessionRunId=$sessionRunId blocks.length='
        '${debugRawBlocks is List ? debugRawBlocks.length : 'N/A'}');
    if (debugRawBlocks is List) {
      for (var i = 0; i < debugRawBlocks.length; i++) {
        final b = debugRawBlocks[i];
        if (b is Map) {
          print('DEBUG_BLOCKINDEX:   [$i] name=${b['name']} '
              'isCardio=${b['isCardio']} done=${b['done']}');
        }
      }
    }

    final rawBlocks = data['blocks'];
    if (rawBlocks is! List) return false;

    final planId = extra?['planId'] as String? ??
        data['planId'] as String? ??
        '';
    final dayIndex = extra?['dayIndex'] as int? ??
        (data['dayIndex'] as num?)?.toInt() ??
        1;

    final blocks =
        rawBlocks.map((b) => Map<String, dynamic>.from(b as Map)).toList();
    final exercises =
        _parseExercises(blocks, isListSets: null, debugSource: 'HYDRATE');

    // Best-effort plan-metadata lookup for display (session name, creator)
    // — in its own try/catch so a failure here doesn't throw away the
    // (more important) exercise/tick-state hydration above; sensible
    // defaults stand in if it fails.
    String sessionName = 'Workout';
    String creatorName = '';
    bool isCustom = false;
    String? sport;
    if (planId.isNotEmpty) {
      try {
        final plan = await FirestoreService().getPlan(planId);
        if (plan != null) {
          final sessions = (plan['sessions'] as List<dynamic>?) ?? [];
          if (sessions.isNotEmpty) {
            final sessionIdx = (dayIndex - 1) % sessions.length;
            final session = sessions[sessionIdx] as Map<String, dynamic>;
            sessionName = session['name'] as String? ?? 'Workout';
          }
          final designedBy = plan['designedBy'] as Map<String, dynamic>?;
          isCustom = plan['isCustom'] as bool? ?? false;
          creatorName = isCustom
              ? 'Custom Routine'
              : (designedBy?['name'] as String? ?? 'WiseWorkout Coach');
          sport = plan['sport'] as String? ?? plan['type'] as String?;
        }
      } catch (_) {}
    }

    if (!mounted) return true;
    setState(() {
      _planId = planId;
      _sessionRunId = sessionRunId;
      _exercises = exercises;
      _sessionName = sessionName;
      _creatorName = creatorName;
      _isCustomPlan = isCustom;
      _planSport = sport;
      _isLoadingSession = false;
      // Reused from this same already-fetched `data` — no second Firestore
      // read needed. See _injuryReviewAlreadyDismissed's field doc. Falls
      // back to the in-memory _dismissedInjuryReviewSessionRunIds set (see
      // its own doc comment) so a dismissal whose Firestore write is still
      // in flight/retrying still isn't re-shown on this same-app-run
      // forceRefresh remount, even though the doc field itself isn't true
      // yet.
      _injuryReviewAlreadyDismissed = data['injuryReviewDismissed'] == true ||
          _dismissedInjuryReviewSessionRunIds.contains(sessionRunId);
    });
    return true;
  }

  // Creates the inProgressSessions doc for this plan day so a cardio block
  // launched mid-session (see _buildCardioPlaceholderCard) can report its
  // completion back to it later. Wrapped in its own try/catch — matching
  // _saveAndNavigate()'s try/catch+print convention, the only other place
  // in this file that logs and continues past a failed Firestore call —
  // rather than letting a failure here fall into _loadPlanSession()'s own
  // outer catch, which would abort loading the whole session and block the
  // user from working out at all over what should be a non-critical side
  // write. Not awaited by either call site above (fire-and-forget): the
  // user's exercise list is already fully ready via that call's own
  // setState, and _sessionRunId just populates a moment later once this
  // write resolves — there's nothing on the critical path that needs it
  // synchronously yet (see this task's own scope: threading only, no
  // consumption until the next phase).
  Future<void> _createInProgressSession(
    String uid,
    String planId,
    int dayIndex,
    List<dynamic> rawExercises,
  ) async {
    try {
      final blocks = rawExercises
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final sessionRunId = await FirestoreService()
          .createInProgressSession(uid, planId, dayIndex, blocks);
      if (mounted) setState(() => _sessionRunId = sessionRunId);
    } catch (e) {
      print('createInProgressSession error: $e');
    }
  }

  Future<void> _loadPreviousSessionData() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      for (final ex in _exercises) {
        if (ex.isCardio) continue;
        final prevSets = await FirestoreService()
            .getLastSessionForExercise(uid, ex.name);
        if (prevSets.isEmpty) continue;
        for (int i = 0; i < ex.sets.length; i++) {
          // Never overwrite a set that's already done — matters for the
          // hydrate-from-Firestore resume path (see
          // _hydrateFromInProgressSession), where a set's real kg/reps was
          // already restored from the in-progress session doc; a no-op for
          // the fresh-start path, where nothing is done yet at this point.
          if (ex.sets[i].done) continue;
          final prevSet = i < prevSets.length
              ? prevSets[i]
              : prevSets.last;
          final kg = prevSet['kg'];
          final reps = prevSet['reps'];
          final kgStr = kg != null
              ? (kg is double && kg == kg.roundToDouble()
                  ? kg.toInt().toString()
                  : kg.toString())
              : '';
          final repsStr = reps?.toString() ?? '';
          if (mounted) {
            setState(() {
              ex.sets[i].prev =
                  kgStr.isNotEmpty && repsStr.isNotEmpty
                      ? '$kgStr kg × $repsStr'
                      : '—';
              ex.sets[i].kg = kgStr;
              ex.sets[i].reps = repsStr;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _enrichExercisesWithInjuryRisk() async {
    try {
      final names = _exercises
          .where((e) => !e.isCardio)
          .map((e) => e.name)
          .toList();
      if (names.isEmpty) return;
      final riskMap = await FirestoreService()
          .getInjuryRisksForExercises(names);
      if (riskMap.isEmpty) return;
      if (mounted) {
        setState(() {
          for (final ex in _exercises) {
            if (riskMap.containsKey(ex.name)) {
              ex.injuryRisk.clear();
              ex.injuryRisk.addAll(riskMap[ex.name]!);
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadInjuryData() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final data = await FirestoreService().getUserInjuryData(uid);
      final enabled = data['injuryFilteringEnabled'] as bool? ?? false;
      final injuries =
          List<Map<String, dynamic>>.from(data['injuries'] as List? ?? []);
      if (!enabled || injuries.isEmpty) return;
      if (mounted) {
        setState(() {
          _injuryFilteringEnabled = true;
          _userInjuries = injuries;
        });
      }
      _checkExercisesForInjuries();
    } catch (e) {
      debugPrint('GymSessionScreen: injury data load failed — $e');
    }
  }

  void _checkExercisesForInjuries() {
    final flagged = <Map<String, dynamic>>[];
    for (int i = 0; i < _exercises.length; i++) {
      final ex = _exercises[i];
      if (ex.isCardio) continue;
      final exMap = {
        'name': ex.name,
        'muscle': ex.muscle,
        'injuryRisk': ex.injuryRisk,
      };
      final match =
          FirestoreService().checkExerciseInjuryRisk(exMap, _userInjuries);
      if (match != null) {
        flagged.add({'index': i, 'name': ex.name, 'injuryName': match, 'remove': true});
      }
    }
    if (flagged.isNotEmpty && mounted) {
      setState(() {
        _flaggedExercises = flagged;
        _injuryReviewPending = true;
      });
    }
  }

  // Returns whether the dismissal was actually persisted to Firestore (or
  // there was nothing to persist to, e.g. a standalone session) — false
  // only when a real sessionRunId exists but every write attempt failed,
  // so the caller (the sheet's "Confirm & Start" button) can surface that
  // to the user instead of assuming it silently worked, as before.
  Future<bool> _applyInjuryFilter() async {
    final toRemove = _flaggedExercises
        .where((f) => f['remove'] == true)
        .map((f) => f['index'] as int)
        .toSet();
    // Stable Firestore-bound slots for whichever exercises are actually
    // being removed — ex.originalIndex, not their transient _exercises
    // array position, matching how every other Firestore-bound write in
    // this file (_syncBlockDone, _buildCardioPlaceholderCard) already
    // distinguishes the two. Collected regardless of which branch below
    // runs, since the "keep everything" case still needs to report an
    // empty removal list to dismissInjuryReview() below.
    final removedOriginalIndices = <int>[];
    if (toRemove.isNotEmpty) {
      final newExercises = <_ExerciseData>[];
      for (int i = 0; i < _exercises.length; i++) {
        if (toRemove.contains(i)) {
          removedOriginalIndices.add(_exercises[i].originalIndex);
        } else {
          newExercises.add(_exercises[i]);
        }
      }
      if (mounted) {
        setState(() {
          _exercises = newExercises;
          _isInjuryFiltered = true;
          _injuryReviewPending = false;
        });
      }
    } else {
      if (mounted) setState(() => _injuryReviewPending = false);
    }

    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return true;

    // _sessionRunId is populated by _createInProgressSession()'s own
    // fire-and-forget write (see that field's doc comment) — awaiting the
    // already-cached _sessionInitFuture here, instead of bailing out on a
    // still-null _sessionRunId the way this used to, closes the race
    // where a fast dismiss beat session creation and the persist below
    // was silently skipped entirely.
    if (_sessionRunId == null && _sessionInitFuture != null) {
      try {
        await _sessionInitFuture;
      } catch (_) {
        // _createInProgressSession already logs its own failure — handled
        // below by sessionRunId still being null.
      }
    }

    final sessionRunId = _sessionRunId;
    if (sessionRunId == null) {
      // Standalone session, or createInProgressSession itself failed —
      // nothing to persist to either way; the in-memory removal above is
      // already the whole story, same as before this change.
      return true;
    }

    // Persists the dismissal — and whichever exercises were actually
    // removed, by stable originalIndex — so a later resume of this same
    // sessionRunId (the mid-plan-cardio return trip, or a full
    // app-kill-and-reopen) doesn't re-prompt for the same exercises and
    // doesn't silently reintroduce ones the user already chose to remove.
    // Awaited (not fire-and-forget) with one retry on failure — a dropped
    // write here used to mean router.dart's forceRefresh remounts would
    // re-show this same sheet on every subsequent cardio-block return
    // trip for the rest of the session.
    const maxAttempts = 2;
    var persisted = false;
    for (var attempt = 1; attempt <= maxAttempts && !persisted; attempt++) {
      persisted = await FirestoreService()
          .dismissInjuryReview(uid, sessionRunId, removedOriginalIndices);
      if (!persisted && attempt < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    // Added regardless of whether the Firestore write ultimately
    // succeeded — see _dismissedInjuryReviewSessionRunIds' own doc
    // comment — so a still-failing write doesn't re-show this sheet again
    // this app run even though the doc field itself never became true.
    _dismissedInjuryReviewSessionRunIds.add(sessionRunId);

    if (!persisted) {
      print('_applyInjuryFilter: dismissInjuryReview failed after '
          '$maxAttempts attempts for sessionRunId=$sessionRunId — '
          'dismissal may not survive an app restart.');
    }
    return persisted;
  }

  // Blocks "Confirm & Start" when every flagged exercise is still on
  // "Remove" and there are no cardio blocks in this session to fall back
  // on — i.e. confirming right now would leave _exercises completely
  // empty (a pure-gym day where an injury happened to flag everything).
  // Cardio blocks are never eligible for removal here (see
  // _checkExercisesForInjuries()'s `if (ex.isCardio) continue;`), so this
  // can only ever trip when the session has zero of them. Reuses
  // _blockAlreadyCompletedDay()'s exact single-button warning Dialog
  // shape rather than inventing a new style — the only difference is this
  // one doesn't navigate anywhere afterward: the review sheet underneath
  // is still open, and the user just needs to go back and keep at least
  // one exercise before confirming again.
  Future<void> _showInjuryFilterEmptyWarning(BuildContext dialogParentCtx) {
    return showDialog<void>(
      context: dialogParentCtx,
      builder: (dialogCtx) => Dialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                'Keep at least one exercise',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Every exercise is currently set to be removed, which would '
                'leave this session with nothing to do. Keep at least one '
                'to continue.',
                style: TextStyle(
                  fontSize: 13,
                  color: WW.textSec,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WW.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInjuryReviewSheet() async {
    // Tracks the brief window where "Confirm & Start" is awaiting
    // _applyInjuryFilter()'s now-awaited persist-with-retry (see that
    // method's own doc comment) — disables the button and swaps its label
    // for a spinner instead of popping the sheet immediately, so the user
    // can't double-tap while a retry is in flight and always gets a
    // truthful "did this save" outcome rather than the old fire-and-forget
    // instant-close.
    var isConfirming = false;
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.healing_rounded, color: WW.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Injury Review',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: WW.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'These exercises may conflict with an injury you\'ve logged. Choose whether to keep or remove each one for this session.',
                      style: TextStyle(
                        fontSize: 13,
                        color: WW.textSec,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _flaggedExercises.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 20, color: WW.border),
                        itemBuilder: (_, i) {
                          final item = _flaggedExercises[i];
                          final remove = item['remove'] == true;
                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] as String? ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: WW.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'May affect: ${item['injuryName']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: WW.textSec,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setSheetState(() => item['remove'] = false);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: !remove ? WW.tealBg : WW.elevated,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: !remove ? WW.teal : WW.border,
                                    ),
                                  ),
                                  child: Text(
                                    'Keep',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: !remove ? WW.teal : WW.textSec,
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setSheetState(() => item['remove'] = true);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: remove
                                        ? const Color(0xFFFEE2E2)
                                        : WW.elevated,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: remove
                                          ? const Color(0xFFDC2626)
                                          : WW.border,
                                    ),
                                  ),
                                  child: Text(
                                    'Remove',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: remove
                                          ? const Color(0xFFDC2626)
                                          : WW.textSec,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WW.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isConfirming
                            ? null
                            : () async {
                                // Same toRemove computation _applyInjuryFilter()
                                // itself does internally — checked here first
                                // so a would-be-empty result blocks the confirm
                                // action instead of silently applying it (see
                                // _showInjuryFilterEmptyWarning's own doc
                                // comment for why this can only ever trip on a
                                // pure-gym day).
                                final toRemove = _flaggedExercises
                                    .where((f) => f['remove'] == true)
                                    .map((f) => f['index'] as int)
                                    .toSet();
                                if (_exercises.length - toRemove.length <= 0) {
                                  await _showInjuryFilterEmptyWarning(ctx);
                                  return;
                                }
                                setSheetState(() => isConfirming = true);
                                final persisted = await _applyInjuryFilter();
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                if (!persisted && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Your injury review choice may not "
                                        "have saved — it could re-prompt "
                                        "later in this session.",
                                      ),
                                    ),
                                  );
                                }
                              },
                        child: isConfirming
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation(
                                      Colors.white),
                                ),
                              )
                            : const Text(
                                'Confirm & Start',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
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
      },
    );
  }

  // Shared by both the fresh-start path (plan template exercises — never
  // carry a `done` field, so the `?? false` fallback below is a no-op for
  // that case) and the hydrate-from-Firestore resume path (blocks[] from
  // an in-progress session, which DO carry real done/kg/reps from prior
  // ticks). The `activity`/`cardioActivity` fallback chain and the `name`
  // fallback chain are similarly additive: template blocks always define
  // `cardioActivity`/`name` directly, so those cases are unaffected; a
  // cardio block that's already been synced via updateInProgressSessionBlock
  // (see cardio_session_screen.dart/outdoor_cardio_screen.dart's finish
  // handlers) only has `activity` (its blockData never sets
  // `cardioActivity` or `name`), so without this fallback a resumed,
  // already-done cardio block would show the generic 'Exercise'/'Run'
  // placeholders instead of its real activity.
  List<_ExerciseData> _parseExercises(
      List<dynamic> rawExercises,
      {required bool? isListSets, String debugSource = ''}) {
    return rawExercises.asMap().entries.map((exEntry) {
      final blockPosition = exEntry.key;
      final e = exEntry.value;
      final exMap = e as Map<String, dynamic>;
      final restTime = (exMap['restTime'] as num?)?.toInt() ?? 90;
      final rawSets = exMap['sets'];
      final wasListSets = rawSets is List;
      final parsedSets = FirestoreService.parseExerciseSets(rawSets, 3);
      final List<_SetData> sets =
          parsedSets.asMap().entries.map((entry) {
        final i = entry.key;
        final s = entry.value;
        final typeStr = s['type'] as String? ?? 'N';
        final _SetType type;
        if (!wasListSets) {
          type = i == 0 ? _SetType.warmup : _SetType.normal;
        } else {
          type = typeStr == 'W'
              ? _SetType.warmup
              : typeStr == 'D'
                  ? _SetType.dropSet
                  : _SetType.normal;
        }
        // s['completedAt'] round-trips through Firestore as a Timestamp
        // (the HYDRATE path reads it straight back from
        // inProgressSessions/{sessionRunId}) — never a raw DateTime at
        // this point, since nothing in this file writes it any other way.
        final rawCompletedAt = wasListSets ? s['completedAt'] : null;
        return _SetData(
          prev: '—',
          type: type,
          done: wasListSets ? (s['done'] as bool? ?? false) : false,
          kg: wasListSets ? s['kg']?.toString() ?? '' : '',
          reps: wasListSets ? s['reps']?.toString() ?? '' : '',
          completedAt:
              rawCompletedAt is Timestamp ? rawCompletedAt.toDate() : null,
        );
      }).toList();
      final isCardio = exMap['isCardio'] as bool? ?? false;
      final cardioActivity = exMap['cardioActivity'] as String? ??
          exMap['activity'] as String? ??
          'Run';
      final cardioMinutes = (exMap['cardioMinutes'] as num?)?.toInt() ?? 30;
      final parsedEx = _ExerciseData(
        name: exMap['name'] as String? ??
            (isCardio ? cardioActivity : null) ??
            'Exercise',
        muscle: exMap['muscle'] as String? ?? '',
        restTime: restTime,
        sets: sets,
        isCardio: isCardio,
        cardioActivity: cardioActivity,
        cardioMinutes: cardioMinutes,
        done: exMap['done'] as bool? ?? false,
        rawBlock: exMap,
        originalIndex: blockPosition,
        injuryRisk: (exMap['injuryRisk'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
      // TEMPORARY DEBUG — remove once the second-cardio-block bug is
      // confirmed fixed.
      print('DEBUG_BLOCKINDEX: _parseExercises[$debugSource] '
          'name=${parsedEx.name} isCardio=${parsedEx.isCardio} '
          'originalIndex=${parsedEx.originalIndex} done=${parsedEx.done}');
      return parsedEx;
    }).toList();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _restTimer?.cancel();
    _finishNameController.dispose();
    _finishNotesController.dispose();
    super.dispose();
  }

  // ── Timers ──────────────────────────────────────────────────────────────────

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_paused && mounted) setState(() => _elapsed++);
    });
  }

  void _startRestTimer() {
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_restSecs <= 1) {
          _showRest = false;
          _restSecs = 90;
          _restTimer?.cancel();
        } else {
          _restSecs--;
        }
      });
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _togglePause() => setState(() => _paused = !_paused);

  void _startSession() {
    setState(() => _readOnly = false);
    _startElapsedTimer();
    // Fire-and-forget "recently used" tracking — the single central point
    // every entry point (Home, Plans tab, Plan Detail preview, Plan
    // Schedule) funnels through once the user actually starts (not just
    // previews) a plan-linked session. Guarded on _planId being non-empty:
    // a genuinely standalone session (no tracked plan at all — see
    // _loadPlanSession's early-return when getTrackedPlan() finds nothing)
    // leaves _planId at its default '', with nothing to record.
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid != null && _planId.isNotEmpty) {
      FirestoreService().recordPlanAccess(uid, _planId);
    }
  }

  void _cycleType(int exIndex, int si) {
    final set = _exercises[exIndex].sets[si];
    if (set.done) return;
    setState(() {
      set.type = _SetType.values[(set.type.index + 1) % _SetType.values.length];
    });
  }

  void _markSetDone(int exIndex, int si, String kg, String reps) {
    final set = _exercises[exIndex].sets[si];
    if (!set.done) {
      if (kg.trim().isEmpty || reps.trim().isEmpty) return;
      final restTime = _exercises[exIndex].restTime;
      setState(() {
        set.kg = kg;
        set.reps = reps;
        set.done = true;
        // Captured fresh on every false->true transition (including a
        // re-tick after an earlier un-tick) — never reused from a prior
        // completion. See _SetData.completedAt's own doc comment.
        set.completedAt = DateTime.now();
        if (restTime > 0) {
          _showRest = true;
          _restSecs = restTime;
        }
      });
      if (restTime > 0) _startRestTimer();
      // Block-level granularity, not per-set: the in-progress session's
      // blocks[] entries mirror the plan's exercises array 1:1 (one entry
      // per exercise, each with its own nested sets[]), so "this block is
      // done" only becomes true once every one of its sets is — writing on
      // every single set tick would just mean this always fires last with
      // the same final data, one write short of every set completing.
      if (_exercises[exIndex].sets.every((s) => s.done)) {
        _syncBlockDone(exIndex);
      }
    } else {
      setState(() {
        set.done = false;
        // Cleared, not left stale — a set with done:false but a leftover
        // completedAt from a previous (reversed) completion would be
        // misleading data for the future plausibility check this is prep
        // for. Re-ticking the same set fills it in fresh again above.
        set.completedAt = null;
      });
      // Un-ticking also needs to sync — otherwise the Firestore in-progress
      // doc keeps reporting this block (and potentially the whole session,
      // via isInProgressSessionFullyDone) as done even after the user
      // reverses a completed set. Safe to call unconditionally now:
      // updateInProgressSessionBlock (firestore_service.dart) derives
      // `done` from whether every set in blockData['sets'] is actually
      // done, rather than always forcing true, specifically so this call
      // correctly writes done:false when appropriate.
      _syncBlockDone(exIndex);
    }
  }

  // Fires whenever a set is toggled done or un-done — writes that block's
  // current name/muscle/restTime/sets back to the in-progress session doc
  // so isInProgressSessionFullyDone()/finalizeInProgressSession() (see
  // cardio_session_screen.dart/outdoor_cardio_screen.dart's finish
  // handlers) always reflect true current local state, whichever direction
  // the toggle went — see updateInProgressSessionBlock's own doc comment
  // for how `done` is derived from the sets rather than forced. Guarded on
  // _sessionRunId being set (null if createInProgressSession hasn't
  // resolved yet, or failed outright — in either case there's nothing to
  // write to). Not awaited: fire it off and move on —
  // updateInProgressSessionBlock() already logs its own failures internally
  // (added in the prior phase), so there's nothing more to add here without
  // duplicating that logging.
  void _syncBlockDone(int exIndex) {
    final sessionRunId = _sessionRunId;
    final uid = AuthService().getCurrentUser()?.uid;
    if (sessionRunId == null || uid == null) return;
    // exIndex is only used to look up the exercise in the current
    // in-memory _exercises list — a real array position, as it must be
    // for local list access. The Firestore-bound write below uses
    // ex.originalIndex instead, since exIndex itself is not a reliable
    // Firestore blocks[] position once injury filtering has removed any
    // earlier exercise (see ex.originalIndex's own field doc).
    final ex = _exercises[exIndex];
    final blockData = {
      'name': ex.name,
      'muscle': ex.muscle,
      'restTime': ex.restTime,
      'sets': ex.sets
          .map((s) => {
                'kg': s.kg,
                'reps': s.reps,
                'done': s.done,
                // Timestamp.fromDate (this codebase's existing convention
                // for a client-captured specific moment — see
                // saveManualActivity()'s 'date' field in
                // firestore_service.dart), not FieldValue.serverTimestamp():
                // that sentinel only resolves to "now, at write time" and
                // isn't supported inside array elements at all, so it's
                // never correct for a per-set moment captured earlier.
                'completedAt': s.completedAt != null
                    ? Timestamp.fromDate(s.completedAt!)
                    : null,
              })
          .toList(),
    };
    FirestoreService().updateInProgressSessionBlock(
        uid, sessionRunId, ex.originalIndex, blockData);
  }

  void _addSet(int exIndex) {
    final ex = _exercises[exIndex];
    final last = ex.sets.isNotEmpty ? ex.sets.last : null;
    setState(() {
      ex.sets.add(_SetData(prev: last?.prev ?? '—'));
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    setState(() {
      _showRest = false;
      _restSecs = 90;
    });
  }

  Future<void> _saveAndNavigate() async {
    if (!mounted) return;
    setState(() => _isSaving = true);

    final sessionData = {
      'sessionName': _sessionName,
      'elapsedSeconds': _elapsed,
      'planId': _planId,
      'exercises': _exercises
          .map((e) => {
                'name': e.name,
                'muscle': e.muscle,
                'sets': e.sets
                    .map((s) => {
                          'kg': s.kg,
                          'reps': s.reps,
                          'done': s.done,
                          'completedAt': s.completedAt,
                        })
                    .toList(),
              })
          .toList(),
    };

    final sessionRunId = _sessionRunId;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Plan-linked session ending on a gym exercise rather than a cardio
    // block — previously this fell straight through to the legacy
    // standalone saveGymSession() path below regardless of sessionRunId,
    // silently orphaning the in-progress session and losing any already-
    // completed cardio blocks' data instead of finalizing into the real
    // combined/gym+cardio doc the way outdoor_cardio_screen.dart's and
    // cardio_session_screen.dart's own finish handlers already do when
    // THEY happen to be the last block done. sessionRunId == null (a
    // genuinely standalone gym session, never part of a plan's in-progress
    // mechanism) skips this block entirely and falls straight to the
    // unchanged standalone path below.
    if (sessionRunId != null && uid != null) {
      try {
        // Sync every gym exercise's current sets/done state before
        // finalizing — _syncBlockDone() (fired on every set toggle)
        // already writes this, but fire-and-forget, so a toggle made
        // immediately before tapping Finish Session could still be in
        // flight; awaiting a fresh write here for every exercise
        // guarantees finalizeInProgressSession below reads true current
        // state rather than racing a pending write.
        for (final ex in _exercises) {
          if (ex.isCardio) continue;
          final blockData = {
            'name': ex.name,
            'muscle': ex.muscle,
            'restTime': ex.restTime,
            'sets': ex.sets
                .map((s) => {
                      'kg': s.kg,
                      'reps': s.reps,
                      'done': s.done,
                      'completedAt': s.completedAt != null
                          ? Timestamp.fromDate(s.completedAt!)
                          : null,
                    })
                .toList(),
          };
          await FirestoreService().updateInProgressSessionBlock(
              uid, sessionRunId, ex.originalIndex, blockData);
        }

        // finalizeInProgressSession() now finalizes whatever's actually
        // done regardless of whether every planned block was completed —
        // tapping Finish Session before finishing every block is the
        // common case, not a rare edge case, so there's no
        // isInProgressSessionFullyDone() gate here anymore. That check
        // remains unchanged and still correct for the cardio finish
        // handlers' own, different use: deciding whether to return to the
        // plan for more blocks vs. show the real summary.
        final finalizeResult = await FirestoreService()
            .finalizeInProgressSession(uid, sessionRunId);
        sessionData['sessionId'] = finalizeResult.sessionId;
        if (finalizeResult.newlyEarnedBadges.isNotEmpty) {
          sessionData['newlyEarnedBadges'] = finalizeResult.newlyEarnedBadges;
        }
        if (!mounted) return;
        setState(() => _isSaving = false);
        context.go(Routes.postSessionSummary, extra: sessionData);
        return;
      } catch (e) {
        print('_saveAndNavigate: plan-linked finalize path failed — $e. '
            'Falling back to standalone saveGymSession().');
      }
    }

    // Standalone path — the plan-linked branch above always returns before
    // reaching here, so sessionData is untouched by any of this for a
    // plan-linked session. Optional name/notes/photo collected via the
    // finish form shown just before _saveAndNavigate() was called (see
    // _showStandaloneFinishForm()) — all optional, so a value only
    // overrides sessionData's existing field when actually provided.
    final trimmedFinishName = _finishNameController.text.trim();
    final trimmedFinishNotes = _finishNotesController.text.trim();
    if (trimmedFinishName.isNotEmpty) {
      sessionData['sessionName'] = trimmedFinishName;
    }
    if (trimmedFinishNotes.isNotEmpty) {
      sessionData['notes'] = trimmedFinishNotes;
    }
    final finishPhoto = _finishPickedPhoto;
    if (finishPhoto != null) {
      final photoBase64 = await _encodeFinishPhotoForSession(finishPhoto);
      if (photoBase64 != null) {
        sessionData['photoBase64'] = photoBase64;
      }
    }

    String? sessionId;
    List<Map<String, dynamic>> newlyEarnedBadges = [];
    try {
      print('Saving session for uid: $uid');
      print('Session data: $sessionData');
      if (uid != null) {
        sessionId = await FirestoreService().saveGymSession(uid, sessionData);
        final totalCompletedSets = _exercises
            .expand((e) => e.sets)
            .where((s) => s.done)
            .length;
        await FirestoreService().addXpToUser(uid, totalCompletedSets * 15);
        await FirestoreService().saveXpEvent(uid, {
          'amount': totalCompletedSets * 15,
          'reason': 'Completed ${sessionData['sessionName']} · $totalCompletedSets sets',
          'type': 'gym',
        });
        // Checked right after addXpToUser() — level/XP/session-count/
        // volume are only current as of that write, so this must run
        // after it, not before.
        newlyEarnedBadges = await FirestoreService().checkAndAwardBadges(uid);
      } else {
        print('saveGymSession skipped: no authenticated user');
      }
    } catch (e) {
      print('saveGymSession error: $e');
    }

    if (sessionId != null) sessionData['sessionId'] = sessionId;
    if (newlyEarnedBadges.isNotEmpty) {
      sessionData['newlyEarnedBadges'] = newlyEarnedBadges;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    context.go(Routes.postSessionSummary, extra: sessionData);
  }

  // Confirms, then leaves an active (non-_readOnly) session mid-way without
  // finalizing it — distinct from _showFinishDialog()'s "End Session",
  // which finalizes/saves-to-sessions-collection. The inProgressSessions
  // doc is left exactly as-is: _syncBlockDone() (fired on every set
  // toggle, see _markSetDone) already keeps it current, but that write is
  // fire-and-forget, so — mirroring _saveAndNavigate()'s own identical
  // precaution before finalizing — this re-syncs every gym exercise's
  // current state and awaits it, guaranteeing a toggle made just before
  // tapping Leave isn't still in flight when the user navigates away.
  // Nothing here calls finalizeInProgressSession() or writes to
  // sessions/{id} — the doc simply stays in inProgressSessions, ready for
  // the Resume/Start Over flow (session_resume_prompt.dart) the next time
  // this plan/day is started.
  //
  // Standalone sessions (_sessionRunId == null — no plan was ever
  // involved) have no inProgressSessions doc to sync in the first place;
  // the sync loop below naturally no-ops for that case via its own guard,
  // and leaving just discards the in-memory progress, same as it always
  // has (standalone sessions were never resumable, before or after this
  // feature).
  //
  // Navigates to Routes.home rather than context.pop(): this screen can be
  // reached via context.push() (Home/Plan Schedule/Plan Detail/Plans tab's
  // fresh-start paths) or context.go() (the Resume path in
  // session_resume_prompt.dart, and mid_plan_cardio_complete_screen.dart's
  // "Next" button) — a go()-originated instance may have nothing on the
  // stack to pop back to. Routes.home is a destination that's always
  // reachable regardless of how this screen was entered, and it's where
  // the Today's Plan card (itself now Resume-aware) naturally surfaces
  // this same session again.
  Future<void> _handleLeaveSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                'Leave workout?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your progress is saved — you can resume this session later.',
                style: TextStyle(
                  fontSize: 13,
                  color: WW.textSec,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: WW.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Keep Going',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: WW.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dialogCtx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WW.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Leave',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final sessionRunId = _sessionRunId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (sessionRunId != null && uid != null) {
      setState(() => _isSaving = true);
      for (final ex in _exercises) {
        if (ex.isCardio) continue;
        final blockData = {
          'name': ex.name,
          'muscle': ex.muscle,
          'restTime': ex.restTime,
          'sets': ex.sets
              .map((s) => {
                    'kg': s.kg,
                    'reps': s.reps,
                    'done': s.done,
                    'completedAt': s.completedAt != null
                        ? Timestamp.fromDate(s.completedAt!)
                        : null,
                  })
              .toList(),
        };
        await FirestoreService().updateInProgressSessionBlock(
            uid, sessionRunId, ex.originalIndex, blockData);
      }
      if (!mounted) return;
      setState(() => _isSaving = false);
    }

    if (!mounted) return;
    context.go(Routes.home);
  }

  void _showFinishDialog() {
    final incomplete = _exercises
        .expand((e) => e.sets)
        .where((s) => !s.done)
        .length;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
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
                'End session?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                incomplete > 0
                    ? '$incomplete sets remaining. Your completed sets will still be logged.'
                    : 'All sets complete. Great work!',
                style: const TextStyle(
                  fontSize: 13,
                  color: WW.textSec,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: WW.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Keep Going',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: WW.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        // Only a genuinely standalone session (never part of
                        // a plan's in-progress mechanism) gets the name/
                        // notes/photo finish form — a plan-linked session
                        // goes straight to _saveAndNavigate(), unchanged,
                        // per earlier design decisions for the mid-plan
                        // flow (see _saveAndNavigate()'s own doc comment).
                        if (_sessionRunId == null) {
                          _showStandaloneFinishForm();
                        } else {
                          _saveAndNavigate();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      child: const Text(
                        'End Session',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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

  // ── Standalone finish form (name/notes/photo) ─────────────────────────────
  // Only ever shown for a genuinely standalone (non-plan-linked) gym
  // session — see _showFinishDialog()'s "End Session" button, the only call
  // site. Same flat WW Title/Notes/photo-picker pattern as
  // outdoor_cardio_screen.dart's own _buildFinishedSummary() form, reused
  // here as a bottom sheet since this screen (unlike outdoor cardio) has no
  // dedicated "finished" body state to swap into — matches this file's own
  // existing bottom-sheet convention (_showRestTimerPicker,
  // _showAddExerciseSheet).

  void _showStandaloneFinishForm() {
    _finishNameController.text = _sessionName;
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
    // parent GymSessionScreen State (which _finishPickedPhoto also lives
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
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(14),
                      hintText: 'Session name',
                      hintStyle: TextStyle(fontSize: 14, color: WW.textSec),
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
                    _saveAndNavigate();
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
  // outdoor_cardio_screen.dart's _encodeImageForSession — see that method's
  // doc comment for why JPEG (via the `image` package) rather than
  // dart:ui's PNG-only encoder, and why a safety cap is checked afterward
  // regardless.
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
          'Gym session: finish photo dropped — encoded size '
          '${encoded.length} bytes exceeds the safety threshold.',
        );
        return null;
      }
      return encoded;
    } catch (_) {
      return null;
    }
  }

  void _showRestTimerPicker(int exIndex) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RestTimerPicker(
        currentSecs: _exercises[exIndex].restTime,
        onSet: (secs) => setState(() => _exercises[exIndex].restTime = secs),
      ),
    );
  }

  // ── "+ Add" button routing ─────────────────────────────────────────────────
  // Replaces the old always-_showAddExerciseSheet() onTap. Branches on plan
  // type (see _isCustomPlan/_planSport's own field docs):
  //  - Custom-built routine: either block type is plausible, so show a
  //    small chooser first.
  //  - A plan categorized 'Running' (not custom): only cardio makes sense,
  //    so skip the chooser and go straight to Add Cardio.
  //  - Everything else (coach-authored gym plans, or anything not
  //    identified as custom or running): unchanged from today — straight
  //    to the existing gym exercise search sheet.
  void _handleAddTap() {
    if (_isCustomPlan) {
      _showAddChoiceSheet();
    } else if ((_planSport ?? '').toLowerCase() == 'running') {
      _showAddCardioSheet();
    } else {
      _showAddExerciseSheet();
    }
  }

  // Same icon-circle/title/two-stacked-rows pattern already used by this
  // file's own _buildFinishPhotoSourceSheet() (camera vs. gallery) for
  // exactly this "pick one of two options" bottom-sheet shape —
  // build_routine_screen.dart's own Add Exercise/Add Cardio choice is
  // presented as two permanently-visible side-by-side footer buttons
  // instead (no chooser sheet at all, since it always has room for both),
  // which doesn't fit this screen's single "+ Add" button — this reuses
  // the closest existing in-file precedent for a 2-option chooser rather
  // than inventing a new shape.
  void _showAddChoiceSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: _buildAddChoiceSheet,
    );
  }

  Widget _buildAddChoiceSheet(BuildContext sheetContext) {
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
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 14),
          const Text(
            'Add to session',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Navigator.of(sheetContext).pop();
              _showAddExerciseSheet();
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
                  'Add Exercise',
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
            onTap: () {
              Navigator.of(sheetContext).pop();
              _showAddCardioSheet();
            },
            child: Container(
              width: double.infinity,
              height: 50,
              alignment: Alignment.center,
              child: const Text(
                'Add Cardio',
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

  // Ported directly from build_routine_screen.dart's _showCardioSheet() —
  // same Run/Walk/Cycle picker + minutes CupertinoPicker, same local
  // StatefulBuilder state. On confirm, appends a new cardio _ExerciseData
  // to _exercises the same way _showAddExerciseSheet()'s onAdd already
  // appends a plain gym _ExerciseData — see _addCardioExercise().
  void _showAddCardioSheet() {
    String selectedActivity = 'Run';
    int selectedMinutes = 30;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Cardio Block',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Indoor/outdoor choice is made when starting the block.',
                style: TextStyle(fontSize: 12, color: WW.textSec),
              ),
              const SizedBox(height: 16),
              Row(
                children: ['Run', 'Walk', 'Cycle'].map((activity) {
                  final isSelected = selectedActivity == activity;
                  final icon = activity == 'Run'
                      ? Icons.directions_run_rounded
                      : activity == 'Walk'
                          ? Icons.directions_walk_rounded
                          : Icons.directions_bike_rounded;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setModal(() => selectedActivity = activity),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? WW.primary : WW.elevated,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(icon,
                                color:
                                    isSelected ? Colors.white : WW.textSec,
                                size: 22),
                            const SizedBox(height: 4),
                            Text(
                              activity,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    isSelected ? Colors.white : WW.textSec,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Duration (minutes)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CupertinoPicker(
                  itemExtent: 36,
                  scrollController: FixedExtentScrollController(
                    initialItem: selectedMinutes - 1,
                  ),
                  onSelectedItemChanged: (index) {
                    setModal(() => selectedMinutes = index + 1);
                  },
                  children: List.generate(
                    120,
                    (i) => Center(
                      child: Text(
                        '${i + 1} min',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: WW.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.of(ctx).pop();
                  _addCardioExercise(selectedActivity, selectedMinutes);
                },
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: WW.teal,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Center(
                    child: Text(
                      'Add Cardio Block',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Gives a mid-session-added block (gym or cardio, via either "+ Add"
  // sheet) a REAL Firestore blocks[] slot instead of the originalIndex: -1
  // sentinel every such block got before this fix (which meant
  // _syncBlockDone()/_buildCardioPlaceholderCard's onTap always silently
  // no-op'd via updateInProgressSessionBlock's own out-of-range guard —
  // for a cardio block specifically, this meant tapping "Start <Activity>"
  // did nothing visibly wrong, just never synced). Only relevant for a
  // plan-linked session (_sessionRunId != null) — a standalone session has
  // no in-progress doc to append to at all, so this returns -1 immediately
  // with no Firestore call, leaving that case completely unchanged from
  // today. Also fails soft to -1 if the append call itself fails
  // (appendInProgressSessionBlock's own fail-soft return of null) — an add
  // should never block the user from continuing their workout, just accept
  // that this one block won't sync, same degraded fallback as today.
  // Awaited by both call sites BEFORE the setState that actually adds the
  // block to _exercises, so no tappable "Start <Activity>"/set row for it
  // can ever render before its real index (or the -1 fallback) is decided
  // — no race where a fast tap targets a not-yet-resolved index.
  Future<int> _appendBlockIfMidSession(Map<String, dynamic> blockData) async {
    final sessionRunId = _sessionRunId;
    final uid = AuthService().getCurrentUser()?.uid;
    if (sessionRunId == null || uid == null) return -1;
    final index = await FirestoreService()
        .appendInProgressSessionBlock(uid, sessionRunId, blockData);
    return index ?? -1;
  }

  // Mirrors _addCardioBlock()'s shape in build_routine_screen.dart (name
  // baked as "$activity ${minutes}min", muscle:'Cardio', a single fake
  // set carrying minutes as its reps — matches this app's other
  // isCardio:true block convention) but builds a typed _ExerciseData for
  // this screen's own in-memory model instead of a raw Firestore map.
  Future<void> _addCardioExercise(String activity, int minutes) async {
    final originalIndex = await _appendBlockIfMidSession({
      'isCardio': true,
      'cardioActivity': activity,
      'cardioMinutes': minutes,
      'name': '$activity ${minutes}min',
      'muscle': 'Cardio',
      'restTime': 0,
      'sets': [
        {'id': '1', 'type': 'N', 'kg': '', 'reps': '$minutes'},
      ],
    });
    if (!mounted) return;
    setState(() {
      _exercises.add(_ExerciseData(
        name: '$activity ${minutes}min',
        muscle: 'Cardio',
        restTime: 0,
        sets: [_SetData(prev: '—', type: _SetType.normal, reps: '$minutes')],
        isCardio: true,
        cardioActivity: activity,
        cardioMinutes: minutes,
        injuryRisk: [],
        originalIndex: originalIndex,
      ));
    });
  }

  void _showAddExerciseSheet() {
    final currentNames = _exercises.map((e) => e.name).toSet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _GymExerciseSearchSheet(
        alreadyAdded: currentNames,
        onAdd: (name, muscle) async {
          Navigator.of(ctx).pop();
          final sets = [
            _SetData(prev: '—', type: _SetType.warmup),
            _SetData(prev: '—', type: _SetType.normal),
            _SetData(prev: '—', type: _SetType.normal),
          ];
          final originalIndex = await _appendBlockIfMidSession({
            'name': name,
            'muscle': muscle,
            'restTime': 90,
            'sets': sets
                .map((s) => {
                      'kg': s.kg,
                      'reps': s.reps,
                      'done': s.done,
                      // Always null here — these sets were just created,
                      // not yet completed — but included for shape
                      // consistency with every other blockData['sets']
                      // write site.
                      'completedAt': s.completedAt,
                    })
                .toList(),
          });
          if (!mounted) return;
          setState(() {
            _exercises.add(_ExerciseData(
              name: name,
              muscle: muscle,
              restTime: 90,
              sets: sets,
              injuryRisk: [],
              originalIndex: originalIndex,
            ));
          });
          _loadPreviousSessionData();
        },
      ),
    );
  }

  String _fmtElapsed() {
    final h = _elapsed ~/ 3600;
    final m = (_elapsed % 3600) ~/ 60;
    final s = _elapsed % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  Widget _buildRestDayScreen() {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💤', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              const Text(
                'Rest Day',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Today is a scheduled rest day. Take it easy and recover!',
                style: TextStyle(
                  fontSize: 14,
                  color: WW.textSec,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              GestureDetector(
                onTap: () => context.push(Routes.manualActivityLog),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: WW.primary.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'Log Manual Activity',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                // context.go(Routes.home), not context.pop(): this rest-day
                // screen can be reached via context.push() OR context.go()
                // depending on entry point (see session_resume_prompt.dart's
                // Resume flow / mid_plan_cardio_complete_screen.dart's
                // "Next" button, both of which use context.go() and replace
                // the whole navigation stack) — same reasoning as
                // _blockAlreadyCompletedDay()/_handleLeaveSession() above.
                // Routes.home is reachable regardless of how this screen was
                // entered; context.pop() is not.
                onTap: () => context.go(Routes.home),
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WW.border, width: 1.5),
                  ),
                  child: const Center(
                    child: Text(
                      'Back to Plans',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: WW.textSec,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSession) {
      return Scaffold(
        backgroundColor: WW.primaryDark,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_isRestDay) return _buildRestDayScreen();

    if (_exercises.isEmpty) {
      return Scaffold(
        backgroundColor: WW.bg,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fitness_center_rounded,
                    size: 48, color: WW.textSec),
                const SizedBox(height: 16),
                const Text(
                  'No active plan found',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Track a plan from the Plans tab to get started.',
                  style: TextStyle(fontSize: 13, color: WW.textSec),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  // context.go(Routes.home), not context.pop() — same
                  // reasoning as the rest-day screen's "Back to Plans"
                  // button above and _blockAlreadyCompletedDay()/
                  // _handleLeaveSession() elsewhere in this file: this
                  // empty-state screen (reached whenever _exercises is
                  // empty, including via the injury filter — see
                  // _applyInjuryFilter()) can be reached via a stack-
                  // replacing context.go() (session_resume_prompt.dart's
                  // Resume flow, mid_plan_cardio_complete_screen.dart's
                  // "Next" button), which leaves nothing for context.pop()
                  // to pop back to. Routes.home is always reachable
                  // regardless of entry point.
                  onTap: () => context.go(Routes.home),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: WW.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Go Back',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: WW.bg,
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                // Top bar extends to status bar edge.
                Container(
                  color: WW.primaryDark,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: MediaQuery.of(context).padding.top),
                      _buildTopBar(),
                      if (_showRest) _buildRestBar(),
                    ],
                  ),
                ),
                if (_isCompressed) _buildCompressedBanner(),
                if (_isInjuryFiltered) _buildInjuryFilteredBanner(),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ListView.builder(
                          padding: _readOnly
                              ? const EdgeInsets.fromLTRB(16, 12, 16, 32)
                              : const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _exercises.length + (_readOnly ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_readOnly && index == 0) {
                              return _buildReadOnlyHeader();
                            }
                            final actualIndex = _readOnly ? index - 1 : index;
                            final ex = _exercises[actualIndex];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              // actualIndex is only a valid Firestore blocks[]
                              // position when nothing has ever been removed
                              // from _exercises ahead of it — not guaranteed
                              // once injury filtering has run (see
                              // ex.originalIndex's own field doc). Only
                              // _buildExerciseCard still needs actualIndex —
                              // that's local _exercises list access (sets,
                              // notes, rest timer), which must stay a real
                              // array position; _buildCardioPlaceholderCard's
                              // blockIndex, by contrast, is Firestore-bound
                              // and must use the stable ex.originalIndex.
                              child: ex.isCardio
                                  ? _buildCardioPlaceholderCard(
                                      ex, ex.originalIndex)
                                  : _buildExerciseCard(actualIndex),
                            );
                          },
                        ),
                      ),
                      if (!_readOnly)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: _buildStickyBottomBar(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isSaving)
          const ColoredBox(
            color: Color(0x66000000),
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16))),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: WW.primary),
                      SizedBox(height: 14),
                      Text(
                        'Saving session…',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WW.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Section 0 — Read-only header ─────────────────────────────────────────

  Widget _buildReadOnlyHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WW.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: WW.chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_rounded,
                    color: WW.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Created by',
                      style: TextStyle(
                          fontSize: 11, color: WW.textSec),
                    ),
                    Text(
                      _creatorName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _startSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: WW.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text(
                'Start Session',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 1 — Top bar ───────────────────────────────────────────────────

  Widget _buildTopBar() {
    if (_readOnly) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            _TopBarButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => context.pop(),
            ),
            const Spacer(),
            Text(
              _sessionName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          // Leave (not Finish) — see _handleLeaveSession()'s own doc
          // comment. Same arrow_back_rounded icon as the _readOnly
          // branch's own back-chevron above, for the same "leave this
          // screen" meaning in either state.
          _TopBarButton(
            icon: Icons.arrow_back_rounded,
            onTap: _handleLeaveSession,
          ),
          const SizedBox(width: 8),
          // Elapsed timer
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _paused ? WW.textSec : WW.teal,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _fmtElapsed(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          // Session name
          Text(
            _sessionName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          // Controls
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TopBarButton(
                  icon: _paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  onTap: _togglePause,
                ),
                const SizedBox(width: 8),
                _TopBarButton(
                  icon: Icons.arrow_forward_rounded,
                  onTap: _showFinishDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2 — Rest timer bar ────────────────────────────────────────────

  Widget _buildRestBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REST',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white60,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '${_restSecs ~/ 60}:${(_restSecs % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          _RestButton(
            label: '+30s',
            onTap: () => setState(() => _restSecs += 30),
          ),
          const SizedBox(width: 6),
          _RestButton(label: 'Skip', onTap: _skipRest),
        ],
      ),
    );
  }

  // ── Section 2b — Compressed session banner ───────────────────────────────

  Widget _buildCompressedBanner() {
    return Container(
      width: double.infinity,
      color: WW.lavenderBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.bolt_rounded, color: WW.lavender, size: 14),
          SizedBox(width: 6),
          Text(
            'Compressed session · Primary exercises only',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WW.lavender,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInjuryFilteredBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF3C7),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.healing_rounded, color: Color(0xFFD97706), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Injury filtering active — ${_injuryFilteringEnabled ? "some exercises removed." : "no conflicts found."}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 4 — Exercise card ─────────────────────────────────────────────

  Widget _buildExerciseCard(int exIndex) {
    final ex = _exercises[exIndex];
    final completedSets = ex.sets.where((s) => s.done).length;
    final totalSets = ex.sets.length;

    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Exercise number badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: WW.chipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${exIndex + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '$completedSets/$totalSets sets',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: WW.border,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: WW.chipBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              ex.muscle,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: WW.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Rest timer pill
                      GestureDetector(
                        onTap: _readOnly
                            ? null
                            : () => _showRestTimerPicker(exIndex),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: WW.elevated,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined,
                                  size: 12, color: WW.textSec),
                              const SizedBox(width: 4),
                              Text(
                                'Rest: ${_fmtRestTime(ex.restTime)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: WW.textSec,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Info button
                GestureDetector(
                  onTap: () => context.push(
                    Routes.exerciseDetail,
                    extra: {'name': ex.name, 'muscle': ex.muscle},
                  ),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: WW.elevated,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.info_outline,
                          color: WW.primary, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Set table
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                const Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text('Set', style: _kColHeader),
                    ),
                    SizedBox(width: 5),
                    SizedBox(
                      width: 32,
                      child: Text('Type', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text('Previous', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    SizedBox(
                      width: 50,
                      child: Text('kg', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    SizedBox(
                      width: 44,
                      child: Text('Reps', style: _kColHeader,
                          textAlign: TextAlign.center),
                    ),
                    SizedBox(width: 5),
                    SizedBox(width: 30),
                  ],
                ),
                const SizedBox(height: 4),
                // Set rows
                ...List.generate(ex.sets.length, (si) {
                  final set = ex.sets[si];
                  final canDelete = ex.sets.length > 1;
                  return Dismissible(
                    key: ObjectKey(set),
                    direction: canDelete
                        ? DismissDirection.endToStart
                        : DismissDirection.none,
                    onDismissed: (_) {
                      setState(() => ex.sets.remove(set));
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    child: _SetRow(
                      key: ObjectKey(set),
                      setIndex: si,
                      data: set,
                      readOnly: _readOnly,
                      onTypeChanged: () => _cycleType(exIndex, si),
                      onToggleDone: (kg, reps) =>
                          _markSetDone(exIndex, si, kg, reps),
                      onKgStored: (v) => set.kg = v,
                      onRepsStored: (v) => set.reps = v,
                    ),
                  );
                }),
                // Add set
                if (!_readOnly)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () => _addSet(exIndex),
                      child: const Text(
                        '+ Add Set',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: WW.primary,
                        ),
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

  // ── Section 4b — Cardio placeholder card ─────────────────────────────────

  Widget _buildCardioPlaceholderCard(_ExerciseData ex, int blockIndex) {
    final icon = ex.cardioActivity == 'Run'
        ? Icons.directions_run_rounded
        : ex.cardioActivity == 'Walk'
            ? Icons.directions_walk_rounded
            : Icons.directions_bike_rounded;
    final color = ex.cardioActivity == 'Run'
        ? WW.teal
        : ex.cardioActivity == 'Walk'
            ? const Color(0xFF22C55E)
            : WW.lavender;

    if (ex.done) {
      return _buildCompletedCardioCard(ex, icon, color);
    }

    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: WW.elevated,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                        ),
                      ),
                      Text(
                        '${ex.cardioActivity} · '
                        '${ex.cardioMinutes} min · Indoor/Outdoor',
                        style: const TextStyle(
                          fontSize: 12,
                          color: WW.textSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Start button — gated behind _readOnly exactly like every other
          // gym control in this file (rest timer pill, _SetRow's type/kg/
          // reps/checkmark, add-set, notes), which this one was missing
          // entirely before. The muted/no-shadow look while _readOnly is
          // true reuses _buildCompletedCardioCard's own existing
          // WW.elevated-background, no-shadow treatment for this exact
          // button shape/role (rather than inventing a new disabled style)
          // — WW.textSec for the label matches this file's established
          // muted/secondary text color elsewhere (rest timer text, etc.).
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: _readOnly
                  ? null
                  : () async {
                      // Guards against the race where the user taps Start
                      // faster than _loadPlanSession()'s fire-and-forget
                      // createInProgressSession() write resolves — without
                      // this, _sessionRunId below could still be null even
                      // though a write is genuinely in flight (see
                      // _sessionInitFuture's field doc).
                      final initFuture = _sessionInitFuture;
                      if (initFuture != null) await initFuture;
                      if (!mounted) return;
                      // TEMPORARY DEBUG — remove once the second-cardio-block
                      // bug is confirmed fixed.
                      print(
                          'DEBUG_BLOCKINDEX: _buildCardioPlaceholderCard onTap '
                          'name=${ex.name} originalIndex=${ex.originalIndex} '
                          'blockIndex=$blockIndex sessionRunId=$_sessionRunId');
                      context.push(
                        Routes.cardioSetup,
                        extra: {
                          'fromPlan': true,
                          'planActivity': ex.cardioActivity,
                          'planMinutes': ex.cardioMinutes,
                          'sessionRunId': _sessionRunId,
                          'blockIndex': blockIndex,
                        },
                      );
                    },
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: _readOnly ? WW.elevated : color,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: _readOnly
                      ? null
                      : [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: Text(
                    'Start ${ex.cardioActivity}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _readOnly ? WW.textSec : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Info note
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Complete your cardio session, then come back '
              'and tap Next to continue.',
              style: const TextStyle(
                fontSize: 12,
                color: WW.textSec,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // Completed state for a cardio block whose done flag (hydrated from the
  // in-progress session doc — see ex.done's own field doc) is already
  // true. There's no existing "whole card is done" pattern elsewhere in
  // this file to match: gym exercises only ever show per-set completion
  // (the teal checkmark in _SetRow), never a whole-card treatment — so
  // this uses a simple flat WW-style treatment consistent with the rest of
  // this card (same icon chip, same WW.cardDecoration shell), reusing
  // WW.teal for the checkmark since that's this file's own existing
  // "done" color (see _SetRow's done-state fill). No GestureDetector
  // anywhere in this widget — unlike the active-state card above, tapping
  // it does nothing at all, since the activity is already finished.
  Widget _buildCompletedCardioCard(
    _ExerciseData ex,
    IconData icon,
    Color color,
  ) {
    final durationSeconds = (ex.rawBlock['durationSeconds'] as num?)?.toInt();
    final distanceMeters = (ex.rawBlock['distanceMeters'] as num?)?.toDouble();
    final caloriesBurned = (ex.rawBlock['caloriesBurned'] as num?)?.toInt();

    // Real synced data (whatever updateInProgressSessionBlock actually
    // wrote for this block) instead of the plan's static "cardioMinutes
    // min · Indoor/Outdoor" placeholder text.
    final subtitleParts = <String>[ex.cardioActivity];
    if (durationSeconds != null && durationSeconds > 0) {
      subtitleParts.add('${(durationSeconds / 60).round()} min');
    }
    if (distanceMeters != null && distanceMeters > 0) {
      subtitleParts.add('${(distanceMeters / 1000).toStringAsFixed(2)} km');
    }
    if (caloriesBurned != null && caloriesBurned > 0) {
      subtitleParts.add('$caloriesBurned kcal');
    }

    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: WW.elevated,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: WW.text,
                        ),
                      ),
                      Text(
                        subtitleParts.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: WW.textSec,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: WW.teal, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Completed',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: WW.teal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 5 — Sticky bottom bar ────────────────────────────────────────

  Widget _buildStickyBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: WW.border, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _handleAddTap,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: WW.primary, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.add_rounded, color: WW.primary, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Add',
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
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _showFinishDialog,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: WW.teal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Finish Session',
                    style: TextStyle(
                      fontSize: 14,
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
    );
  }
}

// ── Top bar icon button ───────────────────────────────────────────────────────

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ── Rest timer button ─────────────────────────────────────────────────────────

class _RestButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RestButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Set row ───────────────────────────────────────────────────────────────────
// Owns kg and reps TextEditingControllers.
// Calls onKgStored/onRepsStored (no setState) to persist values in parent.
// Calls onToggleDone with current controller text when checkmark is tapped.

class _SetRow extends StatefulWidget {
  final int setIndex;
  final _SetData data;
  final VoidCallback onTypeChanged;
  final void Function(String kg, String reps) onToggleDone;
  final ValueChanged<String> onKgStored;
  final ValueChanged<String> onRepsStored;
  final bool readOnly;

  const _SetRow({
    required super.key,
    required this.setIndex,
    required this.data,
    required this.onTypeChanged,
    required this.onToggleDone,
    required this.onKgStored,
    required this.onRepsStored,
    this.readOnly = false,
  });

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _kg;
  late final TextEditingController _reps;
  bool _userEdited = false;

  @override
  void initState() {
    super.initState();
    _kg = TextEditingController(text: widget.data.kg);
    _reps = TextEditingController(text: widget.data.reps);
  }

  @override
  void didUpdateWidget(_SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.kg != widget.data.kg &&
        _kg.text.isEmpty) {
      _kg.text = widget.data.kg;
    }
    if (oldWidget.data.reps != widget.data.reps &&
        _reps.text.isEmpty) {
      _reps.text = widget.data.reps;
    }
  }

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.data.done;
    final st = widget.data.type;

    // Set type visual properties.
    final Color typeColor;
    final Color typeBg;
    final String typeLabel;
    switch (st) {
      case _SetType.warmup:
        typeColor = WW.textSec;
        typeBg = WW.elevated;
        typeLabel = 'W';
      case _SetType.normal:
        typeColor = WW.primary;
        typeBg = WW.chipBg;
        typeLabel = 'N';
      case _SetType.dropSet:
        typeColor = WW.gold;
        typeBg = Color.alphaBlend(
          WW.gold.withValues(alpha: 0.15),
          WW.card,
        );
        typeLabel = 'D';
    }

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(
        color: done ? WW.tealBg : WW.border,
        width: 1.5,
      ),
    );

    final inputDecoration = InputDecoration(
      hintText: '—',
      hintStyle: const TextStyle(fontSize: 13, color: WW.border),
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      isDense: true,
      filled: true,
      fillColor: done ? WW.tealBg : WW.card,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: WW.primary, width: 1.5),
      ),
      disabledBorder: inputBorder,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: done ? WW.teal.withValues(alpha: 0.05) : Colors.transparent,
        border: const Border(
          bottom: BorderSide(color: WW.elevated),
        ),
      ),
      child: Row(
        children: [
          // Set number
          SizedBox(
            width: 24,
            child: Text(
              '${widget.setIndex + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: done ? WW.teal : WW.text,
              ),
            ),
          ),
          const SizedBox(width: 5),
          // Type button
          GestureDetector(
            onTap: (done || widget.readOnly) ? null : widget.onTypeChanged,
            child: Container(
              width: 32,
              height: 22,
              decoration: BoxDecoration(
                color: typeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: typeColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          // Previous
          Expanded(
            child: Text(
              widget.data.prev,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: WW.textSec.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(width: 5),
          // kg input
          SizedBox(
            width: 50,
            child: TextField(
              controller: _kg,
              enabled: !done && !widget.readOnly,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: done
                    ? WW.teal
                    : (widget.data.kg.isNotEmpty && !_userEdited
                        ? WW.textSec
                        : WW.text),
              ),
              decoration: inputDecoration,
              onChanged: (v) {
                setState(() => _userEdited = true);
                widget.onKgStored(v);
              },
            ),
          ),
          const SizedBox(width: 5),
          // Reps input
          SizedBox(
            width: 44,
            child: TextField(
              controller: _reps,
              enabled: !done && !widget.readOnly,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: done
                    ? WW.teal
                    : (widget.data.reps.isNotEmpty && !_userEdited
                        ? WW.textSec
                        : WW.text),
              ),
              decoration: inputDecoration,
              onChanged: (v) {
                setState(() => _userEdited = true);
                widget.onRepsStored(v);
              },
            ),
          ),
          const SizedBox(width: 5),
          // Checkmark button
          GestureDetector(
            onTap: widget.readOnly
                ? null
                : () => widget.onToggleDone(_kg.text, _reps.text),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: done ? WW.teal : WW.chipBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: done ? WW.teal : WW.border,
                  width: 1.5,
                ),
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: WW.border,
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

// ── Rest timer bottom-sheet picker ────────────────────────────────────────────

class _RestTimerPicker extends StatefulWidget {
  final int currentSecs;
  final ValueChanged<int> onSet;

  const _RestTimerPicker({required this.currentSecs, required this.onSet});

  @override
  State<_RestTimerPicker> createState() => _RestTimerPickerState();
}

class _RestTimerPickerState extends State<_RestTimerPicker> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    // Snap to the nearest matching option.
    final found = _kRestOptions.any((o) => o.$2 == widget.currentSecs);
    _selected = found ? widget.currentSecs : 90;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: WW.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 15, color: WW.textSec),
                ),
              ),
              const Expanded(
                child: Text(
                  'Rest Timer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  widget.onSet(_selected);
                  Navigator.pop(context);
                },
                child: const Text(
                  'Set',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: WW.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: WW.elevated),
        // Options list
        SizedBox(
          height: 280,
          child: ListView.builder(
            itemCount: _kRestOptions.length,
            itemBuilder: (_, i) {
              final (label, secs) = _kRestOptions[i];
              final isSelected = secs == _selected;
              return ListTile(
                dense: true,
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected ? WW.primary : WW.text,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: WW.primary, size: 18)
                    : null,
                onTap: () => setState(() => _selected = secs),
              );
            },
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    );
  }
}

// ── Gym exercise search bottom sheet ────────────────────────────────────────────

class _GymExerciseSearchSheet extends StatefulWidget {
  final Set<String> alreadyAdded;
  final void Function(String name, String muscle) onAdd;

  const _GymExerciseSearchSheet({
    required this.alreadyAdded,
    required this.onAdd,
  });

  @override
  State<_GymExerciseSearchSheet> createState() =>
      _GymExerciseSearchSheetState();
}

class _GymExerciseSearchSheetState
    extends State<_GymExerciseSearchSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _muscleFilter = 'All';

  // Fetched once when the sheet opens (see _loadExercises) rather than
  // re-querying Firestore on every chip/search keystroke — _results below
  // filters this in-memory list client-side. Used to filter the hardcoded
  // _kGymExerciseLibrary const directly; that const has since been removed
  // now that this Firestore-backed fetch is confirmed working.
  List<Map<String, dynamic>> _allExercises = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final exercises = await FirestoreService().getAllExercises();
      if (!mounted) return;
      setState(() {
        _allExercises = exercises;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // muscle ?? 'Other' — some real exercise documents may lack a muscle
  // field (see getAllExercises()'s own doc comment on incomplete
  // documents); falling back to 'Other' here rather than an empty string
  // keeps both the muscle-chip filter and the row's muscle label sensible
  // instead of silently matching nothing / displaying blank.
  List<Map<String, dynamic>> get _results {
    return _allExercises.where((e) {
      final name = (e['name'] as String?) ?? '';
      final muscle = (e['muscle'] as String?) ?? 'Other';
      final nameMatch = _query.isEmpty ||
          name.toLowerCase().contains(_query.toLowerCase());
      final muscleMatch = _muscleFilter == 'All' || muscle == _muscleFilter;
      return nameMatch && muscleMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              decoration: BoxDecoration(
                color: WW.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Text(
              'Add Exercise',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: WW.border, width: 0.5),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(Icons.search_rounded,
                        size: 16, color: WW.textSec),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search exercises...',
                        hintStyle: TextStyle(
                            fontSize: 13, color: WW.textSec),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          fontSize: 13, color: WW.text),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: WW.textSec),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: _kGymMuscleFilters.map((m) {
                final active = _muscleFilter == m;
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _muscleFilter = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? WW.chipBg : WW.elevated,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              active ? WW.primary : WW.border,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color:
                              active ? WW.primary : WW.textSec,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: WW.border),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: WW.primary),
                  )
                : _hasError
                    ? _buildErrorState()
                    : results.isEmpty
                        ? const Center(
                            child: Text(
                              'No exercises found',
                              style: TextStyle(
                                  fontSize: 13, color: WW.textSec),
                            ),
                          )
                        : ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    itemCount: results.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: WW.border),
                    itemBuilder: (_, i) {
                      final e = results[i];
                      final name = (e['name'] as String?) ?? '';
                      final muscle = (e['muscle'] as String?) ?? 'Other';
                      final added =
                          widget.alreadyAdded.contains(name);
                      return InkWell(
                        onTap: added
                            ? null
                            : () => widget.onAdd(name, muscle),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: WW.chipBg,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.fitness_center_rounded,
                                  color: WW.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: WW.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      muscle,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: WW.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              added
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                      color: WW.teal)
                                  : const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: WW.textSec),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: WW.textSec),
          const SizedBox(height: 10),
          const Text(
            "Couldn't load exercises",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _loadExercises,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
