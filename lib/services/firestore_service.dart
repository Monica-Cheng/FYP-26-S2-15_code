// lib/services/firestore_service.dart
// Handles ALL Firestore reads and writes for WiseWorkout.
// NEVER import cloud_firestore directly in a screen or widget — always go through this service.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _planProgress = 'planProgress';
  static const _inProgressSessions = 'inProgressSessions';
  // One doc per calendar day (doc id = yyyy-MM-dd, same convention as
  // weightLogs/{date}), recording whether that day was a scheduled rest
  // day for the user's tracked plan at the time — written by
  // home_screen.dart's _loadTodaySession() the moment that's known, so
  // calculateStreak() can later treat a rest day as not breaking the
  // streak. Only exists going forward from whenever this write was first
  // added — see calculateStreak()'s own doc comment for why retroactive
  // backfill isn't possible.
  static const _dailyActivityLog = 'dailyActivityLog';
  // Admin-managed badge definitions (top-level, read-only from the app —
  // same convention as challengeCategories/exercises) and each user's own
  // persisted earned-badge record (users/{uid}/earnedBadges/{badgeId}).
  // See getBadgeDefinitions()/checkAndAwardBadges() below.
  static const _badges = 'badges';
  static const _earnedBadges = 'earnedBadges';
  // Mirror of a pending friend request on the SENDER's own side —
  // users/{fromUid}/sentFriendRequests/{toUid} — written alongside the
  // recipient-side users/{toUid}/friendRequests/{fromUid} doc. Exists so
  // hasSentFriendRequest() can check "did I already send this?" as a
  // self-scoped read (fromUid == the caller) instead of reading the
  // RECIPIENT's private inbox, which owner-only rules correctly deny to
  // anyone but the recipient themself.
  static const _sentFriendRequests = 'sentFriendRequests';
  // Denormalized leaderboard-safe mirror of a subset of users/{uid}
  // (displayName, username, weeklyXp, level, leaderboardVisible,
  // lastWeeklyXpUpdate) — exists so getFriendsLeaderboardStream() can read
  // other users' data once users/{uid} itself is locked to owner-only
  // reads. Kept in sync by every users/{uid} write site that touches any
  // of those fields (see updateUserProfile()/saveOnboardingStep1()/
  // addXpToUser()) — always in the same batch as the users/{uid} write, so
  // the two docs can never be observed out of sync.
  static const _publicProfiles = 'publicProfiles';

  // The subset of users/{uid} fields getFriendsLeaderboardStream() actually
  // reads — the single source of truth for which fields get mirrored into
  // publicProfiles/{uid} by every write site below. weekStartDate is
  // deliberately NOT included: addXpToUser() uses it purely as an internal
  // anchor for its own lazy weekly-reset math and the leaderboard stream
  // never reads it, so mirroring it would just be dead weight on the
  // public doc.
  static const _publicProfileFields = {
    'displayName',
    'username',
    'weeklyXp',
    'level',
    'leaderboardVisible',
    'lastWeeklyXpUpdate',
// Mirrored so a user's photo can eventually be read cross-user (e.g.
    // viewing someone else's profile) without opening up users/{uid}'s
    // owner-only read rule — see user_profile_screen.dart / firestore.rules
    // investigation notes. Not yet consumed cross-user by any call site;
    // this only makes the data available on the next photo write.
    'photoBase64',
    // Mirrored so user_profile_screen.dart can show another user's real
    // Level + XP progress bar (via getPublicProfile()) instead of a fake
    // Lv.1/0 XP default — see that screen's _loadProfile(). NOTE: the
    // actual XP-earning path is addXpToUser(), which writes its own
    // explicit publicProfiles batch rather than going through
    // updateUserProfile() below — that write was updated in the same
    // change to also include totalXp, so this entry alone is not
    // sufficient on its own; see addXpToUser()'s doc comment.
    'totalXp',
  };

  // ---------------------------------------------------------------------------
  // Timing-plausibility constants for the per-set anti-gaming check (see
  // _computeTimingFlaggedIndices(), used by saveGymSession()/
  // finalizeInProgressSession()). restTime is deliberately NOT used for
  // this: it's a live, freely user-editable in-session setting (see
  // gym_session_screen.dart's _RestTimerPicker) with no record kept of
  // what the plan originally specified, so a user could set it to "Off"
  // specifically to defeat a rest-time-based check. completedAt gaps are a
  // real, client-captured wall-clock signal instead, judged against a
  // minimum plausible duration derived purely from that set's own rep
  // count — independent of whatever restTime happens to be configured.
  //
  // _kFallbackMinSetTransitionSeconds: a fixed floor per set-to-set
  // transition, independent of rep count — covers unavoidable overhead
  // between two consecutive completions on the same exercise (re-racking/
  // re-gripping the weight, resetting stance, physically registering the
  // tick) that exists even for a single-rep set.
  // _kFallbackMinSecondsPerRep: an additional floor per rep performed —
  // deliberately conservative (low) so genuinely fast, well-conditioned
  // training is never flagged; it exists only to catch a rep count that's
  // physically impossible in the time actually available, not to judge
  // tempo or form.
  //
  // Both are now Firestore-configurable (see getGamificationConfig()'s own
  // doc comment below) — these two remain in the source as the fallback
  // values used when the config doc is missing/malformed/unreachable,
  // exactly today's original hardcoded values, never deleted.
  // ---------------------------------------------------------------------------
  static const double _kFallbackMinSetTransitionSeconds = 5.0;
  static const double _kFallbackMinSecondsPerRep = 1.5;

  // ---------------------------------------------------------------------------
  // Fallback defaults for the rest of the gamification config — see
  // getGamificationConfig()'s own doc comment. Every one of these is
  // today's exact existing hardcoded value, kept here specifically for use
  // when the corresponding config field is missing, malformed, or the
  // fetch fails outright — never deleted, never silently replaced with 0.
  // ---------------------------------------------------------------------------
  static const int _kFallbackGymXpPerSet = 15;
  static const double _kFallbackCardioXpPerCalorie = 0.5;
  static const int _kFallbackCardioMinXp = 20;
  static const int _kFallbackCardioMaxXp = 500;
  static const double _kFallbackGymCaloriesVolumeCoefficient = 0.06;
  static const double _kFallbackGymCaloriesSetsCoefficient = 0.18;
  static const int _kFallbackGymCaloriesMin = 0;
  static const int _kFallbackGymCaloriesMax = 2000;
  // The exact array _calculateLevel() hardcoded before this change —
  // confirmed by re-reading the method fresh, not carried over from
  // memory (it does NOT match the array this task's own prompt described;
  // this is the real one).
  static const List<num> _kFallbackLevelThresholds = [
    0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000,
  ];

  // ---------------------------------------------------------------------------
  // Gamification/anti-cheat config — Firestore-configurable via
  // appConfig/gamification (admin-edited through the separate React
  // dashboard this app doesn't build, only reads from — same pattern as
  // Collections.exercises' minKg/maxKg/minReps/maxReps bounds). Fetched
  // once and cached for the app's session in a STATIC field, not an
  // instance field — FirestoreService() is constructed fresh at many call
  // sites throughout the app (it's not a singleton), so only a static
  // cache actually persists a "fetch once per session" behavior across
  // all of them. Lazily fetched on first use rather than eagerly at app
  // start: an eager fetch would need to live in app-bootstrap code
  // (main.dart or similar), outside this change's scope — lazy-on-first-
  // use is also simpler and doesn't add latency to app launch for a
  // config that's only actually needed once a session is being saved.
  //
  // Returns the raw fetched map — {} if the doc doesn't exist, is
  // malformed, or the fetch fails for any reason (never throws). Every
  // caller is responsible for its OWN field-level fallback when reading a
  // specific value out of this map (see _configNum() below, and
  // outdoor_cardio_screen.dart/cardio_session_screen.dart's own local
  // equivalents) — deliberately NOT centralizing typed extraction here, so
  // a single missing/malformed field can never take down every other
  // field's ability to fall back correctly on its own.
  //
  // 'appConfig' is referenced as a raw string rather than a Collections.x
  // constant, per this file's own existing precedent for businessPartners
  // — adding it to Collections would require touching constants.dart,
  // outside this change's permitted file scope.
  // ---------------------------------------------------------------------------
  static Map<String, dynamic>? _gamificationConfigCache;

  Future<Map<String, dynamic>> getGamificationConfig() async {
    final cached = _gamificationConfigCache;
    if (cached != null) return cached;
    try {
      final doc = await _db.collection('appConfig').doc('gamification').get();
      _gamificationConfigCache = doc.exists ? (doc.data() ?? {}) : {};
    } catch (_) {
      _gamificationConfigCache = {};
    }
    return _gamificationConfigCache!;
  }

  // Reads a nested numeric field out of a gamification config map (e.g.
  // path ['xp', 'gymPerSet']), falling back to `fallback` if any segment
  // of the path is missing, the wrong type, or the map itself is empty —
  // this is what makes every individual config value fall back
  // independently rather than one missing field invalidating the whole
  // config.
  num _configNum(
    Map<String, dynamic> config,
    List<String> path,
    num fallback,
  ) {
    dynamic current = config;
    for (final key in path) {
      if (current is! Map) return fallback;
      current = current[key];
    }
    return current is num ? current : fallback;
  }

  // Same reasoning/shape as _configNum() above, for a numeric ARRAY field
  // (levelThresholds) instead of a scalar. Falls back to the whole
  // `fallback` list if the field is missing, isn't a List, or contains
  // ANY non-numeric element — a partially-malformed thresholds table
  // (e.g. one entry accidentally saved as a string) is treated as fully
  // invalid rather than silently computing levels off a corrupted list.
  List<num> _configNumList(
    Map<String, dynamic> config,
    List<String> path,
    List<num> fallback,
  ) {
    dynamic current = config;
    for (final key in path) {
      if (current is! Map) return fallback;
      current = current[key];
    }
    if (current is! List) return fallback;
    final result = <num>[];
    for (final value in current) {
      if (value is! num) return fallback;
      result.add(value);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Public wrapper around getGamificationConfig() + _configNumList() for
  // callers that need the actual levelThresholds VALUES (not just a level
  // number already resolved server-side by _calculateLevel()) — a
  // progress-toward-next-level bar needs the real threshold XP values.
  // xp_levels.dart/progress_screen.dart/profile_screen.dart each used to
  // keep their own hardcoded copy of this array, never reading the live
  // Firestore config the way _calculateLevel()/addXpToUser() already do —
  // this is the shared read path all three now go through instead, so an
  // admin-edited threshold value reflects everywhere the first fetch
  // after it changes, not just in the stored level number. Uses
  // getGamificationConfig()'s own existing static-cache — repeat calls
  // from any of the three screens cost nothing beyond the first real
  // fetch anywhere in the app session; no separate cache needed here.
  // [fallback] is the caller's own existing local array, used only if the
  // live config doc is missing/malformed/unreachable — same fail-soft
  // convention as every other _config* read in this file.
  // ---------------------------------------------------------------------------
  Future<List<num>> getLevelThresholds(List<num> fallback) async {
    final config = await getGamificationConfig();
    return _configNumList(config, ['levelThresholds'], fallback);
  }

  // ---------------------------------------------------------------------------
  // Subscription/pricing config — adminSettings/global (admin-edited
  // through Settings.js's "Subscription" panel, via the adminUpdateSettings
  // Cloud Function). Exact same pattern as getGamificationConfig() above:
  // static cache (FirestoreService() isn't a singleton, so only a static
  // field actually persists "fetch once per session" across every call
  // site), lazily fetched on first use, returns {} on missing/malformed/
  // error and never throws — every caller does its own field-level
  // fallback when reading a specific value (see upgrade_screen.dart).
  //
  // adminSettings/global already held premiumPrice/freeTierAIMessages
  // (written correctly by adminUpdateSettings) but had no corresponding
  // client-side read anywhere, and no Firestore rule even permitted one —
  // both fixed alongside this method (see firestore.rules' adminSettings
  // match block).
  // ---------------------------------------------------------------------------
  static Map<String, dynamic>? _subscriptionConfigCache;

  Future<Map<String, dynamic>> getSubscriptionConfig() async {
    final cached = _subscriptionConfigCache;
    if (cached != null) return cached;
    try {
      final doc = await _db.collection('adminSettings').doc('global').get();
      _subscriptionConfigCache = doc.exists ? (doc.data() ?? {}) : {};
    } catch (_) {
      _subscriptionConfigCache = {};
    }
    return _subscriptionConfigCache!;
  }

  // Shared by saveGymSession() and finalizeInProgressSession() — the one
  // place gym XP is now actually computed, collapsing what used to be two
  // separately-hardcoded `totalSets * 15` copies into a single source read
  // from the same cached config both callers already fetch.
  int _computeGymXp(int totalSets, Map<String, dynamic> config) {
    final perSet =
        _configNum(config, ['xp', 'gymPerSet'], _kFallbackGymXpPerSet).toInt();
    return totalSets * perSet;
  }

  // Shared by saveCardioSession() and finalizeInProgressSession() — the
  // one place cardio XP is now actually computed, collapsing what used to
  // be two separately-hardcoded `(caloriesBurned * 0.5).round().clamp(20,
  // 500)` copies into a single source read from the same cached config
  // both callers already fetch.
  int _computeCardioXp(int caloriesBurned, Map<String, dynamic> config) {
    final perCalorie = _configNum(
            config, ['xp', 'cardioPerCalorieRate'], _kFallbackCardioXpPerCalorie)
        .toDouble();
    final minXp =
        _configNum(config, ['xp', 'cardioMinXp'], _kFallbackCardioMinXp).toInt();
    final maxXp =
        _configNum(config, ['xp', 'cardioMaxXp'], _kFallbackCardioMaxXp).toInt();
    return (caloriesBurned * perCalorie).round().clamp(minXp, maxXp);
  }

  // ---------------------------------------------------------------------------
  // Creates or merges a user document at users/{uid}.
  // Safe to call on first sign-up and on subsequent updates — merge:true
  // ensures existing fields are not overwritten by omission.
  // ---------------------------------------------------------------------------
  Future<void> createUserProfile(
    String uid,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Updates specific fields on an existing users/{uid} document.
  // Throws if the document does not exist — call createUserProfile first.
  //
  // This is a generic pass-through used by many screens for many different
  // field sets (settings_screen.dart's leaderboard-visibility toggle,
  // edit_profile_screen.dart's displayName/username, health_profile_screen
  // .dart's body-profile save, plan tracking/goal fields elsewhere, etc.) —
  // rather than chasing every individual caller, this single chokepoint
  // mirrors whichever of _publicProfileFields happen to be present in
  // [data] into publicProfiles/{uid}, in the same batch as the users/{uid}
  // write, so it automatically covers every current AND future caller that
  // touches a leaderboard-relevant field without needing special-casing.
  // ---------------------------------------------------------------------------
  Future<void> updateUserProfile(
    String uid,
    Map<String, dynamic> data,
  ) async {
    final publicUpdates = <String, dynamic>{
      for (final entry in data.entries)
        if (_publicProfileFields.contains(entry.key)) entry.key: entry.value,
    };

    // Diagnostic for the "leaderboard still not showing photos" investigation
    // — this is the single chokepoint every photo upload (profile_screen
    // .dart / edit_profile_screen.dart) goes through, so logging here covers
    // both call sites without duplicating in each screen.
    final touchesPhoto = data.containsKey('photoBase64');
    if (touchesPhoto) {
      debugPrint('[ProfilePhoto] updateUserProfile uid=$uid — data contains '
          'photoBase64 (length=${(data['photoBase64'] as String?)?.length ?? 0}); '
          'will mirror to publicProfiles=${publicUpdates.containsKey('photoBase64')}');
    }

    final batch = _db.batch();
    batch.update(_db.collection(Collections.users).doc(uid), data);
    if (publicUpdates.isNotEmpty) {
      batch.set(
        _db.collection(_publicProfiles).doc(uid),
        publicUpdates,
        SetOptions(merge: true),
      );
    }
    await batch.commit();

    if (touchesPhoto) {
      debugPrint('[ProfilePhoto] updateUserProfile uid=$uid — batch committed. '
          'Wrote users/$uid'
          '${publicUpdates.isNotEmpty ? ' AND publicProfiles/$uid' : ' ONLY — publicUpdates was empty, publicProfiles NOT written'}.');
    }
  }

  // ---------------------------------------------------------------------------
  // Reads users/{uid} and returns the data map, or null if the document
  // does not exist. Use for one-off profile reads — for a live/reactive
  // read of the same document, see getUserProfileStream() right below.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc =
        await _db.collection(Collections.users).doc(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  // ---------------------------------------------------------------------------
  // Same document as getUserProfile() above, as a live stream instead of a
  // one-off read — for screens that need to react to users/{uid} changing
  // (e.g. trackedPlanId, displayName) without a manual re-fetch. Mirrors
  // getPlanStream()/getPlanProgressStream()'s existing shape: null when the
  // document doesn't (or no longer does) exist, otherwise its data map.
  // ---------------------------------------------------------------------------
  Stream<Map<String, dynamic>?> getUserProfileStream(String uid) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
  }

  // ---------------------------------------------------------------------------
  // Whether [uid] wants [category] (one of 'heartRate'/'steps'/
  // 'activeCalories' — see manage_app_screen.dart) used elsewhere in the app.
  // Reads users/{uid}.healthCategoriesEnabled, defaulting to true whenever
  // the map itself or the specific key is missing — matches HealthKit's own
  // existing behavior (all 3 categories requested together, see
  // HealthService._readTypes) so existing users see no change until they
  // actively toggle something off on the new Manage App screen.
  // ---------------------------------------------------------------------------
  Future<bool> isHealthCategoryEnabled(String uid, String category) async {
    final profile = await getUserProfile(uid);
    final categories =
        profile?['healthCategoriesEnabled'] as Map<String, dynamic>?;
    if (categories == null) return true;
    return categories[category] as bool? ?? true;
  }

  // ---------------------------------------------------------------------------
  // Reads publicProfiles/{uid} — the cross-user-readable mirror of
  // _publicProfileFields (displayName/username/weeklyXp/level/
  // leaderboardVisible/lastWeeklyXpUpdate). Use this instead of
  // getUserProfile() whenever the caller needs to read a DIFFERENT
  // user's data — users/{uid} is locked to owner-only reads, so
  // getUserProfile(otherUid) permission-denies for anyone but that user
  // themselves (see acceptCoachRequest()'s own history: it originally
  // called getUserProfile(clientUid) from the coach's session to look up
  // the client's display name, which silently failed every accept with
  // PERMISSION_DENIED since a coach is never that client).
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getPublicProfile(String uid) async {
    final doc = await _db.collection(_publicProfiles).doc(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  // ---------------------------------------------------------------------------
  // Checks whether a username is already taken by another user document.
  // ---------------------------------------------------------------------------
  // Queries publicProfiles rather than users/{uid} — this is a cross-user
  // query (no per-doc uid scoping), which users/{uid}'s owner-only rule
  // cannot satisfy; publicProfiles mirrors username and is readable by any
  // authenticated user (see _publicProfileFields).
  Future<bool> isUsernameTaken(String username) async {
    final snapshot = await _db
        .collection(_publicProfiles)
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Persists onboarding step 1 — body profile fields — into users/{uid}.
  // Expected keys in bodyProfile:
  //   displayName, dob, biologicalSex, heightCm, weightKg,
  //   preferredUnits, healthConnected
  //
  // This is the very first write for a brand-new user — the users/{uid}
  // doc doesn't exist before this (see createUserProfile()'s own doc
  // comment; nothing else creates it first). So this is also the first
  // time publicProfiles/{uid} gets created, seeded with just displayName/
  // username (the only bodyProfile keys that are also in
  // _publicProfileFields) — same batch as the users/{uid} write.
  // ---------------------------------------------------------------------------
  Future<void> saveOnboardingStep1(
    String uid,
    Map<String, dynamic> bodyProfile,
  ) async {
    final publicUpdates = <String, dynamic>{
      for (final entry in bodyProfile.entries)
        if (_publicProfileFields.contains(entry.key)) entry.key: entry.value,
    };

    final batch = _db.batch();
    batch.set(
      _db.collection(Collections.users).doc(uid),
      // 'role' defaults to 'user' here since this is the very first write
      // for a brand-new account (see this method's own doc comment above)
      // — every other read of this field elsewhere falls back to 'user'
      // too (accounts created before this field existed have no role at
      // all), this just makes it explicit going forward. bodyProfile is
      // spread after so it could still override this if a caller ever
      // needed to (none do today).
      //
      // 'isPremium' defaults to false for the same reason — previously
      // absent entirely on a brand-new account (every read already falls
      // back to `?? false`, so this alone was never the cause of a crash;
      // see getCreatedChallengeCount()'s own fix for the actual bug this
      // was investigated alongside). Explicit false here just makes the
      // field's existence match every other account-level flag instead of
      // being undefined until an admin sets it once.
      {'role': 'user', 'isPremium': false, ...bodyProfile},
      SetOptions(merge: true),
    );
    if (publicUpdates.isNotEmpty) {
      batch.set(
        _db.collection(_publicProfiles).doc(uid),
        publicUpdates,
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Persists onboarding step 2 — fitness survey answers — into users/{uid}.
  // Expected keys in surveyAnswers:
  //   primaryGoal, sportPreference, experienceLevel,
  //   equipmentAvailable, daysPerWeek, sessionLength
  // ---------------------------------------------------------------------------
  Future<void> saveOnboardingStep2(
    String uid,
    Map<String, dynamic> surveyAnswers,
  ) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .set(surveyAnswers, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Marks onboarding as complete for users/{uid}.
  // Call after saveOnboardingStep2 succeeds. The router guards check this
  // flag to decide whether to show onboarding or the main app shell.
  // ---------------------------------------------------------------------------
  Future<void> markOnboardingComplete(String uid) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .update({'onboardingComplete': true});
  }

  // ---------------------------------------------------------------------------
  // Estimates gym calories from actual legitimate work done — no duration/
  // elapsed-time term at all (removed; see below), purely totalVolume and
  // totalSets, both of which already exclude flagged sets (timing-
  // implausible or out-of-bounds — see _computeTimingFlaggedIndices()/
  // _isBoundsFlagged()) upstream in saveGymSession()/
  // finalizeInProgressSession(). Two components:
  //  - volumeComponent: 0.06 kcal per kg of totalVolume (kg x reps summed
  //    across every legitimate done set — the same "volume load" metric
  //    this app already surfaces via _formatVolume elsewhere), scaled by
  //    the user's own body weight relative to a 70kg reference — a rough,
  //    deliberately conservative approximation for resistance-training
  //    energy expenditure scaling with both moved load and lifter mass.
  //  - setsComponent: 0.18 kcal/kg per legitimate completed set — a small
  //    flat per-set overhead (bracing, rest, setup) that volume alone
  //    under-counts for lighter-load/bodyweight exercises.
  // A previous duration-based term (1.0 kcal/kg/hour, meant to be a
  // near-resting-rate baseline for the non-barbell parts of a session:
  // setup, walking between stations, holding positions) was removed
  // entirely by product decision: it was driven purely by elapsed time,
  // completely independent of which sets were flagged, so a session made
  // entirely of flagged/fake sets still earned meaningful calories from
  // duration alone even after volume/sets correctly zeroed out. The 0.06/
  // 0.18 coefficients above are scaled up from the prior 0.05/0.15 (same
  // ~60/40 volume/sets split as before) to absorb roughly what the removed
  // duration term used to contribute for a typical session, so a real
  // session's total calorie estimate stays in a comparable real-world
  // range to before this change — see this function's own sanity-check
  // numbers reported alongside this change. Floor dropped from the old
  // formula's 10 to 0: with no duration baseline left to prop up an empty
  // session, a genuinely zero-legitimate-work session (everything flagged,
  // or nothing done at all) should now correctly earn exactly zero,
  // not some artificial display minimum. Ceiling kept at 2000 as a sane
  // per-session sanity cap.
  // ---------------------------------------------------------------------------
  Future<int> _estimateGymCalories({
    required double weightKg,
    required int totalSets,
    required double totalVolume,
  }) async {
    final config = await getGamificationConfig();
    final volumeCoefficient = _configNum(config,
            ['gymCalories', 'volumeCoefficient'], _kFallbackGymCaloriesVolumeCoefficient)
        .toDouble();
    final setsCoefficient = _configNum(
            config, ['gymCalories', 'setsCoefficient'], _kFallbackGymCaloriesSetsCoefficient)
        .toDouble();
    final minCalories =
        _configNum(config, ['gymCalories', 'minCalories'], _kFallbackGymCaloriesMin)
            .toInt();
    final maxCalories =
        _configNum(config, ['gymCalories', 'maxCalories'], _kFallbackGymCaloriesMax)
            .toInt();

    final volumeComponent = volumeCoefficient * totalVolume * (weightKg / 70.0);
    final setsComponent = setsCoefficient * weightKg * totalSets;
    final total = volumeComponent + setsComponent;
    return total.round().clamp(minCalories, maxCalories);
  }

  // ---------------------------------------------------------------------------
  // Normalizes a set's completedAt value into the Timestamp this app's
  // existing convention uses for a client-captured specific moment (see
  // saveManualActivity()'s 'date': Timestamp.fromDate(...) below for the
  // precedent) — FieldValue.serverTimestamp() is never the right choice
  // here: it only resolves "now, at write time" (wrong for a moment
  // captured earlier) and isn't supported inside array elements at all.
  // Accepts either a plain DateTime (saveGymSession()'s sessionData is
  // built directly in Dart, not round-tripped through Firestore first) or
  // an already-deserialized Timestamp (finalizeInProgressSession() reads
  // its data straight back from a doc) — anything else (missing field,
  // legacy data with no completedAt at all) returns null rather than
  // throwing.
  // ---------------------------------------------------------------------------
  Timestamp? _normalizeSetCompletedAt(dynamic raw) {
    if (raw is Timestamp) return raw;
    if (raw is DateTime) return Timestamp.fromDate(raw);
    return null;
  }

  // ---------------------------------------------------------------------------
  // Returns, indexed to match `exercises` (e.g. rawExercises/gymBlocks —
  // result[i] holds the flagged set-indices for exercises[i]'s own `sets`
  // list), the done sets across the WHOLE SESSION whose completedAt gap
  // since the immediately preceding done set — by actual completion time,
  // never by array/exercise position — is below what that set's own rep
  // count could plausibly take (minSetTransitionSeconds/minSecondsPerRep
  // below — Firestore-configurable, see getGamificationConfig(); callers
  // resolve these from cached config before calling in, with
  // _kFallbackMinSetTransitionSeconds/_kFallbackMinSecondsPerRep used if
  // config is unavailable). Replaces an earlier per-exercise version of
  // this check: comparing only within the same exercise meant
  // every exercise's own first set was exempt, so a session with N
  // exercises had N free unflagged sets no matter how implausible. Every
  // done set from every exercise (including a mid-session-added one — its
  // real completedAt values interleave correctly here regardless of where
  // its block happens to sit in the array, since appendInProgressSessionBlock
  // always appends at the end of blocks[] with no chronological meaning —
  // see that method's own doc comment) is gathered into one flat list and
  // sorted by real completedAt before any gap is computed, so only the
  // true first set of the entire session has no preceding set to compare
  // against.
  //
  // sessionStartAnchor covers that one true-first-set case:
  //  - plan-linked sessions: pass the inProgressSessions doc's own
  //    createdAt (a server timestamp captured when the session was first
  //    loaded — finalizeInProgressSession() already has this doc in scope)
  //    so even the very first set is checked against a real reference
  //    point.
  //  - standalone sessions: pass null — no inProgressSessions doc was ever
  //    created for one, and _elapsed (gym_session_screen.dart) is a
  //    pause-aware counter, not a wall-clock value, so it can't be trusted
  //    to reconstruct a start moment. With no anchor, the whole session's
  //    first set is simply never flagged for lack of anything trustworthy
  //    to compare it against — same as every first set always was before
  //    this fix, just now scoped to once per session instead of once per
  //    exercise.
  // A set with no completedAt (legacy data predating this feature) or no
  // parseable positive rep count is skipped for this check (nothing
  // plausible to judge it against), not flagged by default — unchanged
  // from before.
  // ---------------------------------------------------------------------------
  List<Set<int>> _computeSessionTimingFlags(
    List<dynamic> exercises,
    DateTime? sessionStartAnchor, {
    required double minSetTransitionSeconds,
    required double minSecondsPerRep,
  }) {
    // (exerciseIndex, setIndex, the set map itself, its completedAt) for
    // every done set with a parseable completedAt, across every exercise.
    final allDoneSets = <(int, int, Map, DateTime)>[];
    for (var ei = 0; ei < exercises.length; ei++) {
      final e = exercises[ei];
      if (e is! Map) continue;
      final sets = e['sets'];
      if (sets is! List) continue;
      for (var si = 0; si < sets.length; si++) {
        final s = sets[si];
        if (s is! Map || s['done'] != true) continue;
        final ts = _normalizeSetCompletedAt(s['completedAt']);
        if (ts == null) continue;
        allDoneSets.add((ei, si, s, ts.toDate()));
      }
    }
    allDoneSets.sort((a, b) => a.$4.compareTo(b.$4));

    final result = List.generate(exercises.length, (_) => <int>{});
    for (var i = 0; i < allDoneSets.length; i++) {
      final (ei, si, curSet, completedAt) = allDoneSets[i];
      final reps = int.tryParse(curSet['reps']?.toString() ?? '');
      if (reps == null || reps <= 0) continue;

      final prevTime = i > 0 ? allDoneSets[i - 1].$4 : sessionStartAnchor;
      if (prevTime == null) continue; // true first set, no anchor available

      final gapSeconds =
          completedAt.difference(prevTime).inMilliseconds / 1000.0;
      final minPlausibleSeconds =
          minSetTransitionSeconds + reps * minSecondsPerRep;
      if (gapSeconds < minPlausibleSeconds) {
        result[ei].add(si);
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Whether a single set's kg/reps falls outside its exercise's admin-set
  // bounds (see getExerciseBoundsForExercises() — a null/absent bounds map
  // always means "not configured for this exercise", never treated as a
  // 0/0 bound). Only flags a value that's actually present and parseable
  // and genuinely out of range — a null kg/reps (shouldn't normally
  // happen; _markSetDone() in gym_session_screen.dart requires both
  // non-empty before a set can be marked done) is never flagged by this
  // check on its own.
  // ---------------------------------------------------------------------------
  bool _isBoundsFlagged(double? kg, int? reps, Map<String, num>? bounds) {
    if (bounds == null) return false;
    final minKg = bounds['minKg'];
    final maxKg = bounds['maxKg'];
    final minReps = bounds['minReps'];
    final maxReps = bounds['maxReps'];
    if (kg != null) {
      if (minKg != null && kg < minKg) return true;
      if (maxKg != null && kg > maxKg) return true;
    }
    if (reps != null) {
      if (minReps != null && reps < minReps) return true;
      if (maxReps != null && reps > maxReps) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Saves a completed gym session to users/{uid}/sessions/{auto-id}.
  // Calculates totalSets, totalVolume, caloriesBurned, and xpEarned from the
  // exercises list. Uses add() so each call creates a unique document.
  // ---------------------------------------------------------------------------
  Future<String> saveGymSession(
    String uid,
    Map<String, dynamic> sessionData,
  ) async {
    final gamificationConfig = await getGamificationConfig();
    final rawExercises = sessionData['exercises'];
    int totalSets = 0;
    double totalVolume = 0.0;
    int flaggedSetCount = 0;

    // Build a cleaned exercises list: only completed sets, numeric kg/reps.
    final List<Map<String, dynamic>> cleanedExercises = [];

    if (rawExercises is List) {
      // One bulk lookup for every exercise in this session, rather than a
      // separate getExerciseDetail() collection scan per exercise — see
      // getExerciseBoundsForExercises()'s own doc comment.
      final exerciseNames = rawExercises
          .whereType<Map>()
          .map((e) => e['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      final exerciseBounds = await getExerciseBoundsForExercises(exerciseNames);
      // Standalone session — saveGymSession() is only ever reached here for
      // a genuinely standalone session, or as a fallback when the
      // plan-linked finalizeInProgressSession() path throws (see this
      // method's own doc comment) — sessionData never carries a
      // sessionRunId either way, so there's no inProgressSessions doc to
      // read a createdAt anchor from. Passing null means the whole
      // session's true first set is simply never flagged for lack of a
      // trustworthy reference point — see _computeSessionTimingFlags()'s
      // own doc comment for why this is deliberate, not an oversight.
      final timingFlagsByExercise = _computeSessionTimingFlags(
        rawExercises,
        null,
        minSetTransitionSeconds: _configNum(
                gamificationConfig,
                ['gymTiming', 'minSetTransitionSeconds'],
                _kFallbackMinSetTransitionSeconds)
            .toDouble(),
        minSecondsPerRep: _configNum(gamificationConfig,
                ['gymTiming', 'minSecondsPerRep'], _kFallbackMinSecondsPerRep)
            .toDouble(),
      );

      for (var ei = 0; ei < rawExercises.length; ei++) {
        final e = rawExercises[ei];
        if (e is! Map) continue;
        final sets = e['sets'];
        if (sets is! List) continue;
        final bounds = exerciseBounds[e['name'] as String? ?? ''];
        final flaggedTimingIndices = timingFlagsByExercise[ei];

        final List<Map<String, dynamic>> doneSets = [];
        for (var i = 0; i < sets.length; i++) {
          final s = sets[i];
          if (s is! Map || s['done'] != true) continue;
          final kg = double.tryParse(s['kg']?.toString() ?? '');
          final reps = int.tryParse(s['reps']?.toString() ?? '');

          // A flagged set is still recorded exactly as the user entered it
          // (real kg/reps/completedAt, plus its flag) — it just doesn't
          // contribute to totalSets/totalVolume (and therefore xpEarned/
          // caloriesBurned below), rather than being hidden or altered.
          final flaggedTiming = flaggedTimingIndices.contains(i);
          final flaggedBounds = _isBoundsFlagged(kg, reps, bounds);
          if (flaggedTiming || flaggedBounds) {
            flaggedSetCount++;
          } else {
            totalSets++;
            totalVolume += (kg ?? 0) * (reps ?? 0);
          }

          doneSets.add({
            'kg': kg,
            'reps': reps,
            'done': true,
            'completedAt': _normalizeSetCompletedAt(s['completedAt']),
            if (flaggedTiming) 'flaggedTiming': true,
            if (flaggedBounds) 'flaggedBounds': true,
          });
        }

        if (doneSets.isNotEmpty) {
          cleanedExercises.add({
            'name': e['name'],
            'muscle': e['muscle'],
            'sets': doneSets,
          });
        }
      }
    }

    final profile = await getUserProfile(uid);
    final weightKg =
        double.tryParse(profile?['weightKg']?.toString() ?? '70') ?? 70.0;
    final caloriesBurned = await _estimateGymCalories(
      weightKg: weightKg,
      totalSets: totalSets,
      totalVolume: totalVolume,
    );

    // sessionData['planId'] is usually empty for a genuinely standalone
    // session, but gym_session_screen.dart's _saveAndNavigate() also falls
    // back to this method when the plan-linked finalizeInProgressSession()
    // path throws — and _planId there is still set to the real tracked
    // plan's id in that case. So this lookup mirrors
    // finalizeInProgressSession()'s own fail-soft getPlan() pattern rather
    // than assuming planId is always blank here.
    final gymSessionPlanId = sessionData['planId'] as String? ?? '';
    var planIsCustom = false;
    if (gymSessionPlanId.isNotEmpty) {
      try {
        final plan = await getPlan(gymSessionPlanId);
        planIsCustom = plan?['isCustom'] as bool? ?? false;
      } catch (_) {}
    }

    try {
      debugPrint('Writing to Firestore...');
      // notes/photoBase64 are optional — only ever present on sessionData
      // when the standalone gym-session finish form (gym_session_screen
      // .dart's _showStandaloneFinishForm()) actually collected one; a
      // plan-linked session's sessionData never has these keys at all, and
      // this method is never even reached for that path (it finalizes via
      // finalizeInProgressSession() instead) — see _saveAndNavigate()'s own
      // doc comment.
      final notes = sessionData['notes'] as String?;
      final photoBase64 = sessionData['photoBase64'] as String?;
      final ref = await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(Collections.sessions)
          .add({
        'type': 'gym',
        'sessionName': sessionData['sessionName'],
        'planId': sessionData['planId'] ?? '',
        'date': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'durationSeconds': sessionData['elapsedSeconds'],
        'exercises': cleanedExercises,
        'totalSets': totalSets,
        'totalVolume': totalVolume,
        'flaggedSetCount': flaggedSetCount,
        'caloriesBurned': caloriesBurned,
        'xpEarned': _computeGymXp(totalSets, gamificationConfig),
        'isManuallyLogged': false,
        'planIsCustom': planIsCustom,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (photoBase64 != null && photoBase64.isNotEmpty)
          'photoBase64': photoBase64,
      });
      debugPrint('Firestore write successful!');
      return ref.id;
    } catch (e) {
      debugPrint('Firestore write error: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Returns all sessions logged today (since local midnight) for users/{uid}.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getTodaysSessions(String uid) async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(midnight))
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Returns one page of sessions for users/{uid}, newest first — replaces the
  // old getRecentSessions()/getRecentSessionsStream() pair, which had a
  // hardcoded limit and no way to page past it (root cause of
  // less-frequently-logged session types silently aging out of view once
  // enough newer sessions of another type accumulated).
  //
  // type/manualOnly/customOnly filter server-side (not client-side after the
  // fetch) so a filtered page always reflects [pageSize] real matches —
  // filtering the already-limited result client-side would reintroduce the
  // same "looks like there's only a few, but there's actually more on later
  // pages" bug in a new shape. Only one of type/manualOnly/customOnly is
  // ever passed at once by progress_screen.dart's single-select filter
  // chips, matching _filteredSessions' old mutually-exclusive semantics.
  //
  // rangeStart/rangeEnd add an optional INCLUSIVE [rangeStart, rangeEnd]
  // range on the same 'date' field the query already orders by — the
  // caller (progress_screen.dart's _pickActivityDate()/_loadSessionsPage())
  // is responsible for setting rangeEnd to 23:59:59.999 of the selected end
  // day so activities logged later that same day aren't excluded.
  //
  // One-time fetch (not .snapshots()) — a live listener on a
  // startAfterDocument()-paginated page would keep re-firing as new
  // sessions are saved, shifting what "the last item on this page" is and
  // desyncing from a cursor already captured from an earlier snapshot
  // (duplicate/reordered/missing items on the next page). See
  // progress_screen.dart's _loadSessionsPage() for the caller-side paging
  // state (cursor, hasMore, append-on-load-more).
  //
  // Combining an equality filter (type/isManuallyLogged/planIsCustom) with
  // orderBy('date') on a different field requires a composite index — see
  // firestore.indexes.json (type+date, isManuallyLogged+date,
  // planIsCustom+date), deployed via `firebase deploy --only
  // firestore:indexes`. That field/order combination is unaffected by
  // switching the date clause from isLessThan (month-exclusive) to
  // isLessThanOrEqualTo (range-inclusive) — composite indexes key on which
  // fields and their sort order, not the comparison operator a query uses,
  // so no index changes were needed for that switch. The unfiltered ("All")
  // case still needs no composite index since date is the only field
  // involved.
  // ---------------------------------------------------------------------------
  Future<
      ({
        List<Map<String, dynamic>> sessions,
        DocumentSnapshot<Map<String, dynamic>>? lastDoc,
        bool hasMore,
      })> getSessionsPage(
    String uid, {
    int pageSize = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfterDoc,
    String? type,
    bool manualOnly = false,
    bool customOnly = false,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions);

    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }
    if (manualOnly) {
      query = query.where('isManuallyLogged', isEqualTo: true);
    }
    if (customOnly) {
      query = query.where('planIsCustom', isEqualTo: true);
    }
    if (rangeStart != null) {
      query = query.where(
        'date',
        isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart),
      );
    }
    if (rangeEnd != null) {
      query = query.where(
        'date',
        isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd),
      );
    }
    query = query.orderBy('date', descending: true).limit(pageSize);
    if (startAfterDoc != null) {
      query = query.startAfterDocument(startAfterDoc);
    }

    final snapshot = await query.get();
    return (
      sessions:
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList(),
      lastDoc: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  // ---------------------------------------------------------------------------
  // Deletes a single session doc at users/{uid}/sessions/{sessionId}.
  // Firestore rules already restrict this to the owning user. Used by
  // activity_detail_screen.dart to delete manually-logged activities —
  // deliberately no XP/streak/leaderboard reversal here, since manual
  // activities never contributed to any of those in the first place.
  // ---------------------------------------------------------------------------
  Future<void> deleteSession(String uid, String sessionId) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .doc(sessionId)
        .delete();
  }

  // ---------------------------------------------------------------------------
  // Returns lifetime totals across all sessions for users/{uid}: session
  // count, summed gym volume (kg) — both used by the Profile stats row —
  // and totalDistanceMeters, added for badge conditions (see
  // checkAndAwardBadges()). totalDistanceMeters is computed in this SAME
  // full-collection scan rather than as its own separate method/query —
  // this method already reads every session doc for sessionCount/
  // totalVolume, so deriving distance here too is free; a standalone
  // getLifetimeDistanceMeters() would either duplicate the same full scan
  // (wasteful) or just call this method and discard two of its three
  // fields (pointless indirection). Uses the exact same type-aware
  // branching as computeChallengeProgress() (cardio -> distanceMeters
  // directly, combined -> sum cardioBlocks[].distanceMeters, gym -> 0),
  // and excludes manually-logged sessions from the distance sum
  // specifically — badge conditions need validated activity, same
  // reasoning as computeChallengeProgress()/calculateStreak()'s identical
  // exclusion. sessionCount/totalVolume deliberately do NOT gain this same
  // exclusion here — that would silently change this method's pre-existing
  // behavior for every other caller (e.g. profile_screen.dart's lifetime
  // stats row), which is outside this change's scope.
  //
  // gymSessionCount/cardioSessionCount/combinedSessionCount (added for more
  // granular badge conditions) are computed in this same loop for the same
  // "already scanning every doc" reason. Unlike sessionCount, all three
  // exclude manually-logged sessions (same exclusion as totalDistanceMeters
  // above), and each counts ONLY its own pure type — a 'combined' session
  // counts toward combinedSessionCount alone, never toward
  // gymSessionCount/cardioSessionCount too, so the three never overlap and
  // sum to (sessionCount - manually-logged count).
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getLifetimeStats(String uid) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .get();

    int sessionCount = snapshot.docs.length;
    double totalVolume = 0;
    double totalDistanceMeters = 0;
    int gymSessionCount = 0;
    int cardioSessionCount = 0;
    int combinedSessionCount = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final vol = data['totalVolume'];
      if (vol is num) {
        totalVolume += vol.toDouble();
      }

      if (data['isManuallyLogged'] != true) {
        final type = data['type'] as String? ?? '';
        if (type == 'cardio') {
          totalDistanceMeters += (data['distanceMeters'] as num?)?.toDouble() ?? 0;
          cardioSessionCount++;
        } else if (type == 'combined') {
          final blocks = data['cardioBlocks'];
          if (blocks is List) {
            for (final b in blocks) {
              if (b is Map) {
                totalDistanceMeters += (b['distanceMeters'] as num?)?.toDouble() ?? 0;
              }
            }
          }
          combinedSessionCount++;
        } else if (type == 'gym') {
          gymSessionCount++;
        }
      }
    }

    return {
      'sessionCount': sessionCount,
      'totalVolume': totalVolume,
      'totalDistanceMeters': totalDistanceMeters,
      'gymSessionCount': gymSessionCount,
      'cardioSessionCount': cardioSessionCount,
      'combinedSessionCount': combinedSessionCount,
    };
  }

  // ---------------------------------------------------------------------------
  // Returns this-calendar-month-scoped session count + total duration for
  // users/{uid} — same explicit start/end Timestamp range-query shape as
  // getMonthActivity()/computeChallengeProgress(), but returning aggregate
  // sums instead of per-date sets. Added for profile_screen.dart's
  // Sessions/Workout Time stat cards, which used to read getLifetimeStats()
  // (unscoped, lifetime) and produced meaninglessly huge numbers on a
  // long-lived account (e.g. "5,222,977 kg Lifted").
  //
  // sessionCount mirrors getLifetimeStats()'s own definition exactly (every
  // doc in range counts, manually-logged included) — a count of activity,
  // not a validated-only anti-cheat metric.
  //
  // durationSeconds sums every doc's durationSeconds field unfiltered
  // (manually-logged sessions included too, unlike
  // computeChallengeProgress()'s duration metric, which deliberately
  // excludes them for anti-cheat reasons — that exclusion doesn't apply
  // here, this is just "how much time did you spend" across every activity
  // type). gym/cardio/manual/combined sessions all write durationSeconds
  // the same way (see saveGymSession()/finalizeInProgressSession()/the
  // cardio session save paths), so no per-type branching is needed.
  // ---------------------------------------------------------------------------
  Future<Map<String, int>> getMonthlyStats(
    String uid,
    int year,
    int month,
  ) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate))
        .get();

    int durationSeconds = 0;
    for (final doc in snapshot.docs) {
      durationSeconds += (doc.data()['durationSeconds'] as num?)?.toInt() ?? 0;
    }

    return {
      'sessionCount': snapshot.docs.length,
      'durationSeconds': durationSeconds,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BADGES
  // badges/{badgeId} is admin-managed reference data (name, description,
  // imageUrl, conditions[]) — read-only from the app, same convention as
  // challengeCategories/exercises. users/{uid}/earnedBadges/{badgeId} is
  // the persisted record of which badges a user has actually earned —
  // once written, a badge is never re-evaluated or revoked, even if the
  // admin later changes its conditions (see checkAndAwardBadges(), which
  // only ever looks at NOT-yet-earned badges).
  // ═══════════════════════════════════════════════════════════════════════

  /// Fetches all badge definitions. Read-only from the app; admin adds/
  /// edits these directly in Firestore/the dashboard. Same fail-soft
  /// convention as getChallengeCategories()/getInjuryCategories().
  Future<List<Map<String, dynamic>>> getBadgeDefinitions() async {
    try {
      final snapshot = await _db.collection(_badges).get();
      return snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// The set of badge ids [uid] has already earned — used by
  /// profile_screen.dart to render earned vs. locked in the badges grid.
  /// Fail-soft to an empty set (renders everything as locked, never
  /// crashes) rather than throwing.
  Future<Set<String>> getEarnedBadgeIds(String uid) async {
    try {
      final snapshot = await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(_earnedBadges)
          .get();
      return snapshot.docs.map((doc) => doc.id).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Checks every NOT-yet-earned badge definition against [uid]'s current
  /// stats, and persists any newly-qualifying ones into
  /// users/{uid}/earnedBadges/{badgeId}. Returns the full data (not just
  /// ids) of every badge newly earned by THIS call, so a caller (e.g.
  /// post_session_summary_screen.dart) can display a "you unlocked a new
  /// badge" moment for exactly what changed just now — not the user's
  /// full earned-badge history.
  ///
  /// Each badge's conditions[] is a list of {statType, value} pairs,
  /// meaning "this stat >= value" — ALL conditions on a badge must pass
  /// (AND) for it to be earned. statType is one of: 'level', 'totalXp',
  /// 'sessionCount', 'totalVolume', 'totalDistance', 'streak',
  /// 'gymSessionCount', 'cardioSessionCount', 'combinedSessionCount'.
  ///
  /// Only computes the specific stats actually referenced by at least one
  /// unearned badge's conditions — the union of every unearned badge's
  /// statTypes is computed first, and each underlying fetch
  /// (getUserProfile for level/totalXp, getLifetimeStats for
  /// sessionCount/totalVolume/totalDistance/gymSessionCount/
  /// cardioSessionCount/combinedSessionCount, calculateStreak for streak)
  /// only runs if its stat(s) are actually needed. calculateStreak() in
  /// particular is a full, unbounded session-collection scan — skipping it
  /// entirely when nothing needs 'streak' avoids real, avoidable cost on
  /// every single session save.
  Future<List<Map<String, dynamic>>> checkAndAwardBadges(String uid) async {
    final allBadges = await getBadgeDefinitions();
    if (allBadges.isEmpty) return [];

    final earnedIds = await getEarnedBadgeIds(uid);
    final unearned = allBadges
        .where((b) => !earnedIds.contains(b['id'] as String))
        .toList();
    if (unearned.isEmpty) return [];

    final neededStatTypes = <String>{
      for (final badge in unearned)
        for (final cond in (badge['conditions'] as List? ?? const []))
          if (cond is Map && cond['statType'] is String)
            cond['statType'] as String,
    };
    if (neededStatTypes.isEmpty) return [];

    final stats = <String, num>{};

    if (neededStatTypes.contains('level') ||
        neededStatTypes.contains('totalXp')) {
      final profile = await getUserProfile(uid);
      if (neededStatTypes.contains('level')) {
        stats['level'] = (profile?['level'] as num?)?.toInt() ?? 1;
      }
      if (neededStatTypes.contains('totalXp')) {
        stats['totalXp'] = (profile?['totalXp'] as num?)?.toInt() ?? 0;
      }
    }

    if (neededStatTypes.contains('sessionCount') ||
        neededStatTypes.contains('totalVolume') ||
        neededStatTypes.contains('totalDistance') ||
        neededStatTypes.contains('gymSessionCount') ||
        neededStatTypes.contains('cardioSessionCount') ||
        neededStatTypes.contains('combinedSessionCount')) {
      final lifetime = await getLifetimeStats(uid);
      if (neededStatTypes.contains('sessionCount')) {
        stats['sessionCount'] = (lifetime['sessionCount'] as num?)?.toInt() ?? 0;
      }
      if (neededStatTypes.contains('totalVolume')) {
        stats['totalVolume'] = (lifetime['totalVolume'] as num?)?.toDouble() ?? 0;
      }
      if (neededStatTypes.contains('totalDistance')) {
        stats['totalDistance'] =
            (lifetime['totalDistanceMeters'] as num?)?.toDouble() ?? 0;
      }
      if (neededStatTypes.contains('gymSessionCount')) {
        stats['gymSessionCount'] =
            (lifetime['gymSessionCount'] as num?)?.toInt() ?? 0;
      }
      if (neededStatTypes.contains('cardioSessionCount')) {
        stats['cardioSessionCount'] =
            (lifetime['cardioSessionCount'] as num?)?.toInt() ?? 0;
      }
      if (neededStatTypes.contains('combinedSessionCount')) {
        stats['combinedSessionCount'] =
            (lifetime['combinedSessionCount'] as num?)?.toInt() ?? 0;
      }
    }

    if (neededStatTypes.contains('streak')) {
      stats['streak'] = await calculateStreak(uid);
    }

    final batch = _db.batch();
    final newlyEarned = <Map<String, dynamic>>[];

    for (final badge in unearned) {
      final conditions = (badge['conditions'] as List?) ?? const [];
      if (conditions.isEmpty) continue;

      var allConditionsPass = true;
      for (final cond in conditions) {
        if (cond is! Map) {
          allConditionsPass = false;
          break;
        }
        final statType = cond['statType'] as String?;
        final requiredValue = cond['value'];
        if (statType == null || requiredValue is! num) {
          allConditionsPass = false;
          break;
        }
        final actual = stats[statType];
        if (actual == null || actual < requiredValue) {
          allConditionsPass = false;
          break;
        }
      }

      if (allConditionsPass) {
        final badgeId = badge['id'] as String;
        final ref = _db
            .collection(Collections.users)
            .doc(uid)
            .collection(_earnedBadges)
            .doc(badgeId);
        batch.set(ref, {'earnedAt': FieldValue.serverTimestamp()});
        newlyEarned.add(badge);
      }
    }

    if (newlyEarned.isNotEmpty) {
      await batch.commit();
    }
    return newlyEarned;
  }

  /// Returns the most recent set data for a given
  /// exercise name across all of this user's gym
  /// sessions. Returns a list of maps with 'kg' and
  /// 'reps' keys, or empty list if not found.
  Future<List<Map<String, dynamic>>> getLastSessionForExercise(
    String uid,
    String exerciseName,
  ) async {
    try {
      final snapshot = await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(Collections.sessions)
          .orderBy('date', descending: true)
          .limit(20)
          .get();

      for (final doc in snapshot.docs) {
        final type = doc.data()['type'] as String? ?? '';
        if (type != 'gym') continue;
        final exercises =
            doc.data()['exercises'] as List<dynamic>? ?? [];
        for (final ex in exercises) {
          if (ex is! Map) continue;
          final name = ex['name'] as String? ?? '';
          if (name.toLowerCase() == exerciseName.toLowerCase()) {
            final sets = ex['sets'] as List<dynamic>? ?? [];
            return sets
                .whereType<Map>()
                .map((s) => {
                      'kg': s['kg'],
                      'reps': s['reps'],
                    })
                .toList();
          }
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetches a single exercise document by name
  /// (case-insensitive match). Returns null if not found.
  Future<Map<String, dynamic>?> getExerciseDetail(
    String exerciseName,
  ) async {
    try {
      final snapshot = await _db
          .collection(Collections.exercises)
          .get();
      for (final doc in snapshot.docs) {
        final name = doc.data()['name'] as String? ?? '';
        if (name.toLowerCase() == exerciseName.toLowerCase()) {
          return {'id': doc.id, ...doc.data()};
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches injuryRisk arrays for a list of exercise
  /// names from the exercises collection. Returns a
  /// map of exerciseName -> injuryRisk list.
  Future<Map<String, List<String>>> getInjuryRisksForExercises(
    List<String> exerciseNames,
  ) async {
    if (exerciseNames.isEmpty) return {};
    try {
      final snapshot = await _db
          .collection(Collections.exercises)
          .get();
      final result = <String, List<String>>{};
      for (final doc in snapshot.docs) {
        final name = doc.data()['name'] as String? ?? '';
        final injuryRisk =
            (doc.data()['injuryRisk'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final match = exerciseNames.firstWhere(
          (n) => n.toLowerCase() == name.toLowerCase(),
          orElse: () => '',
        );
        if (match.isNotEmpty) {
          result[match] = injuryRisk;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Fetches weight/rep bounds — 'minKg'/'maxKg'/'minReps'/'maxReps', all
  /// optional and admin-set via Firebase Console (no write path exists in
  /// the app, matching this collection's existing read-only convention —
  /// see getExerciseDetail()/getInjuryRisksForExercises() above) — for a
  /// list of exercise names from the exercises collection. Mirrors
  /// getInjuryRisksForExercises()'s bulk-lookup shape (one collection read
  /// total) rather than calling getExerciseDetail() once per exercise,
  /// which would otherwise re-scan the entire collection per exercise in a
  /// session. An exercise with none of the four fields set is simply
  /// absent from the result — callers must treat a missing entry as "no
  /// bounds configured, skip the check", never invent a 0/0 bound.
  Future<Map<String, Map<String, num>>> getExerciseBoundsForExercises(
    List<String> exerciseNames,
  ) async {
    if (exerciseNames.isEmpty) return {};
    try {
      final snapshot = await _db.collection(Collections.exercises).get();
      final result = <String, Map<String, num>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? '';
        final match = exerciseNames.firstWhere(
          (n) => n.toLowerCase() == name.toLowerCase(),
          orElse: () => '',
        );
        if (match.isEmpty) continue;
        final bounds = <String, num>{};
        if (data['minKg'] is num) bounds['minKg'] = data['minKg'] as num;
        if (data['maxKg'] is num) bounds['maxKg'] = data['maxKg'] as num;
        if (data['minReps'] is num) bounds['minReps'] = data['minReps'] as num;
        if (data['maxReps'] is num) bounds['maxReps'] = data['maxReps'] as num;
        if (bounds.isNotEmpty) result[match] = bounds;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Fetches ALL documents from the exercises collection — the "browse/
  /// list" counterpart to getExerciseDetail()'s single name-keyed lookup
  /// and getInjuryRisksForExercises()/getExerciseBoundsForExercises()'s
  /// bulk name-keyed lookups (all three of those only ever fetch this
  /// collection to look up specific already-known names; nothing before
  /// this method ever needed every document at once). Each result is the
  /// raw doc data plus its own 'id' — same lightweight shape as
  /// getExerciseDetail()/getPlan() elsewhere in this file — deliberately
  /// NOT re-typed or defaulted here: some existing exercise documents are
  /// missing some of these fields, and inventing a default at this layer
  /// (e.g. muscle ?? 'Other') would hide that choice from callers who may
  /// want to handle it differently (group under "Other" vs. exclude
  /// entirely) — that's a UI-wiring decision for later, not this method's.
  /// Confirmed real-world fields a document may contain, any of which may
  /// be absent: name, muscle, muscleGroup, equipment, difficulty,
  /// instructions, secondaryMuscles (List), injuryRisk (List), minKg/
  /// maxKg/minReps/maxReps (num).
  ///
  /// muscle — not muscleGroup — is the field filtered on server-side.
  /// Confirmed against a real seeded document (Squat): muscle: "Legs",
  /// muscleGroup: "thighs" — muscle is the coarse category that actually
  /// matches the existing "Add Exercise" sheets' filter chips
  /// (_kMuscleFilters/_kGymMuscleFilters — 'Chest'/'Back'/'Shoulders'/etc.,
  /// 8 coarse categories), while muscleGroup is a finer anatomical
  /// subcategory (e.g. "thighs", "biceps") those chips were never meant to
  /// match. Passing null, empty, or 'All' skips the where() clause and
  /// returns every document — matching the existing filter chips' own
  /// "All" semantics.
  ///
  /// Text search is deliberately NOT done here — Firestore has no native
  /// substring/contains query, so name search stays exactly where it
  /// already is today (client-side, over whatever list this method
  /// returns); only the SOURCE of that list changes, from the hardcoded
  /// _kExerciseLibrary/_kGymExerciseLibrary consts to this real fetch —
  /// the filtering mechanics themselves don't change at all.
  ///
  /// Deliberately does NOT catch/swallow errors here (unlike
  /// getExerciseDetail()/getInjuryRisksForExercises()/
  /// getExerciseBoundsForExercises() above, which fail soft to null/{}
  /// since they're supplementary lookups a caller can reasonably treat as
  /// "nothing found either way"). This method's callers — the "Add
  /// Exercise" search sheets in build_routine_screen.dart/
  /// gym_session_screen.dart — need to tell "the query genuinely
  /// succeeded and found nothing" apart from "the query failed", so they
  /// can show a real error/retry state instead of a misleading "No
  /// exercises found" for a genuine Firestore failure. Swallowing the
  /// error here would make those two outcomes indistinguishable to any
  /// caller. Callers must wrap this in their own try/catch.
  Future<List<Map<String, dynamic>>> getAllExercises({
    String? muscle,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection(Collections.exercises);
    if (muscle != null && muscle.isNotEmpty && muscle != 'All') {
      query = query.where('muscle', isEqualTo: muscle);
    }
    final snapshot = await query.get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  /// Fetches all injury categories from Firestore.
  /// Returns list of maps with id, name, bodyPart,
  /// description fields.
  Future<List<Map<String, dynamic>>> getInjuryCategories() async {
    try {
      final snapshot = await _db
          .collection(Collections.injuryCategories)
          .orderBy('bodyPart')
          .get();
      return snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // HttpsCallableResult.data decodes nested JSON objects as
  // Map<Object?, Object?> on native platforms (not Map<String, dynamic>) —
  // a platform-channel codec quirk, not specific to this app. A shallow
  // Map<String, dynamic>.from(result.data) fixes the top level only;
  // anything nested (e.g. getHealthData()'s injuries list) stays
  // Map<Object?, Object?> and throws the moment a caller force-casts it,
  // e.g. List<Map<String, dynamic>>.from(...). This walks the whole
  // structure at any depth so every caller gets plain
  // Map<String, dynamic>/List<dynamic> the same way a fresh JSON decode
  // would produce.
  // ---------------------------------------------------------------------------
  static dynamic _deepConvertCallableResult(dynamic value) {
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k.toString(), _deepConvertCallableResult(v)),
      );
    }
    if (value is List) {
      return value.map(_deepConvertCallableResult).toList();
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // getHealthData/updateHealthData relay through the getHealthData/
  // updateHealthData Cloud Functions (functions/index.js) instead of
  // reading/writing users/{uid} directly — this session's health-data-
  // encryption migration moved injuries/dob/biologicalSex/heightCm/
  // weightKg/goalWeight/weightGoalActive/dailyCalorieGoal/
  // weeklyCalorieGoal/monthlyCalorieGoal/calorieGoalActive off the
  // plaintext user document into users/{uid}.encryptedHealthData,
  // decryptable only server-side (the key lives only in Secret Manager,
  // mirrors the OPENAI_API_KEY pattern already used for
  // callWiseCoachOpenAI/analyzeNutrition).
  //
  // Neither method catches its own errors — callers that need fail-soft
  // behavior (e.g. getUserInjuryData() below) wrap their own try/catch,
  // exactly as before this migration; callers that need a real error to
  // propagate (e.g. saveUserInjuries() below, so its own callers can show
  // a "Failed to save" message) get exactly that, also unchanged.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getHealthData(String uid) async {
    final callable = FirebaseFunctions.instance.httpsCallable('getHealthData');
    final result = await callable.call<Map<String, dynamic>>({'uid': uid});
    return _deepConvertCallableResult(result.data) as Map<String, dynamic>;
  }

  Future<void> updateHealthData(Map<String, dynamic> updates) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('updateHealthData');
    await callable.call<Map<String, dynamic>>({'updates': updates});
  }

  // ---------------------------------------------------------------------------
  // Relays through the deleteUserAccount Cloud Function (functions/index.js)
  // — deletes this user's own Firestore data (self-scoped to the caller's
  // uid server-side, never a client-supplied one). Does NOT delete the
  // Firebase Auth account itself — see AuthService.deleteAccount(), which
  // must only be called after this succeeds. See the Cloud Function's own
  // doc comment for the exact deletion scope and its documented known
  // limitations (businessPartners, pending coach/friend requests on other
  // users' docs, reverse follow edges, notifications this user sent to
  // others — none of those are touched by this call).
  // ---------------------------------------------------------------------------
  Future<void> deleteUserAccount() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('deleteUserAccount');
    await callable.call<Map<String, dynamic>>();
  }

  /// Saves the user's current injuries and filtering preference. [uid] is
  /// kept for call-site compatibility, but no longer used to target the
  /// write directly — updateHealthData()'s Cloud Function always writes
  /// under the authenticated caller's own uid (request.auth.uid), never a
  /// client-supplied one.
  Future<void> saveUserInjuries(
    String uid, {
    required List<Map<String, dynamic>> injuries,
    required bool filteringEnabled,
  }) async {
    await updateHealthData({
      'injuries': injuries,
      'injuryFilteringEnabled': filteringEnabled,
    });
  }

  /// Reads the user's current injuries and filtering
  /// preference from their user document.
  Future<Map<String, dynamic>> getUserInjuryData(
    String uid,
  ) async {
    try {
      final data = await getHealthData(uid);
      return {
        'injuries': data['injuries'] ?? [],
        'injuryFilteringEnabled': data['injuryFilteringEnabled'] ?? false,
      };
    } catch (_) {
      return {
        'injuries': [],
        'injuryFilteringEnabled': false,
      };
    }
  }

  /// Checks if an exercise should be flagged based on
  /// user injuries. Returns the matching injury name
  /// if flagged, null if safe.
  String? checkExerciseInjuryRisk(
    Map<String, dynamic> exercise,
    List<Map<String, dynamic>> userInjuries,
  ) {
    if (userInjuries.isEmpty) return null;
    final injuryRisk =
        (exercise['injuryRisk'] as List<dynamic>?)
            ?.map((e) => e.toString().trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toList() ??
        [];
    if (injuryRisk.isEmpty) return null;
    for (final injury in userInjuries) {
      final injuryName =
          (injury['name'] as String? ?? '')
              .trim()
              .toLowerCase();
      if (injuryName.isEmpty) continue;
      if (injuryRisk.contains(injuryName)) {
        final rawName = (injury['name'] as String? ?? '').trim();
        return rawName.isNotEmpty ? rawName : null;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Sums caloriesBurned across all sessions logged today (since local midnight)
  // for users/{uid}. Returns 0 if no sessions exist.
  // ---------------------------------------------------------------------------
  Future<int> getTodaysCalories(String uid) async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(midnight))
        .get();

    int total = 0;
    for (final doc in snapshot.docs) {
      total += (doc.data()['caloriesBurned'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // Adds xpEarned to the user's totalXp and weeklyXp, then recalculates and
  // updates their level. Uses merge:true so unrelated fields are untouched.
  //
  // weeklyXp/level/lastWeeklyXpUpdate/totalXp are also mirrored into
  // publicProfiles/{uid} in the same batch (weekStartDate is not — it's
  // purely an internal anchor for this method's own lazy-reset math below,
  // never read by getFriendsLeaderboardStream(), so it has no reason to
  // exist on the public doc). totalXp used to be excluded here too (it
  // isn't one of the fields the leaderboard stream reads), but
  // user_profile_screen.dart now needs it to show another user's real XP
  // progress bar via getPublicProfile() — this method writes its own
  // explicit batch rather than going through updateUserProfile(), so
  // adding 'totalXp' to _publicProfileFields alone wouldn't have covered
  // this, the actual XP-earning path.
  // ---------------------------------------------------------------------------
  Future<void> addXpToUser(String uid, int xpEarned) async {
    final config = await getGamificationConfig();
    final doc = await _db.collection(Collections.users).doc(uid).get();
    final data = doc.data() ?? {};
    final newTotal = ((data['totalXp'] as num?)?.toInt() ?? 0) + xpEarned;

    // Lazy weekly reset: if the stored weekStartDate is missing or before
    // this week's Monday, this event starts the new week's weeklyXp fresh
    // (not added to the old value) rather than continuing to accumulate.
    final currentWeekStart = _currentWeekStart();
    final storedWeekStart = data['weekStartDate'];
    final isNewWeek = storedWeekStart is! Timestamp ||
        storedWeekStart.toDate().isBefore(currentWeekStart);
    final existingWeekly = (data['weeklyXp'] as num?)?.toInt() ?? 0;
    final newWeekly = isNewWeek ? xpEarned : existingWeekly + xpEarned;
    final newLevel = _calculateLevel(newTotal, config);
    // One serverTimestamp() sentinel, used on both docs — both writes
    // commit in the same batch, so they resolve to the identical server
    // commit time on both docs, not two independently-resolved timestamps.
    final now = FieldValue.serverTimestamp();

    final batch = _db.batch();
    batch.set(_db.collection(Collections.users).doc(uid), {
      'totalXp': newTotal,
      'weeklyXp': newWeekly,
      'weekStartDate': Timestamp.fromDate(currentWeekStart),
      'lastWeeklyXpUpdate': now,
      'level': newLevel,
    }, SetOptions(merge: true));
    batch.set(_db.collection(_publicProfiles).doc(uid), {
      'weeklyXp': newWeekly,
      'level': newLevel,
      'lastWeeklyXpUpdate': now,
      'totalXp': newTotal,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  // Most recent Monday at local midnight (device-local time).
  static DateTime _currentWeekStart() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  // Firestore-configurable via appConfig/gamification's levelThresholds
  // field — same pattern as _computeGymXp()/_computeCardioXp() above,
  // reading from the config map the caller already fetched (via the same
  // cached getGamificationConfig(), not a separate fetch) rather than
  // fetching its own copy. Falls back to _kFallbackLevelThresholds (the
  // exact array this method hardcoded before) if the field is missing or
  // malformed.
  int _calculateLevel(int totalXp, Map<String, dynamic> config) {
    final thresholds =
        _configNumList(config, ['levelThresholds'], _kFallbackLevelThresholds);
    int level = 1;
    for (int i = 0; i < thresholds.length; i++) {
      if (totalXp >= thresholds[i]) level = i + 1;
    }
    return level;
  }

  // ---------------------------------------------------------------------------
  // Calculates the current workout streak for users/{uid} — just the
  // count. Delegates to calculateStreakDates() (below) for the actual
  // backward walk so the two never drift out of sync; see that method's
  // doc comment for the full walk semantics (rest-day protection,
  // manually-logged exclusion, the dailyActivityLog pre-history caveat).
  // ---------------------------------------------------------------------------
  Future<int> calculateStreak(String uid) async {
    final dates = await calculateStreakDates(uid);
    return dates.length;
  }

  // ---------------------------------------------------------------------------
  // Same walk as calculateStreak(), but returns the actual Set of
  // 'yyyy-MM-dd' dates the walk counted — not just how many. Added for the
  // month-calendar's fire-icon streak marker (lib/widgets/common/
  // month_calendar.dart via monthActivityProvider).
  //
  // Deliberately NOT scoped to any particular calendar month, even though
  // its only caller besides calculateStreak() feeds a month-at-a-time
  // widget: the currently active streak is one global fact anchored at
  // today, not a per-month one, and it can span across a month boundary
  // (e.g. a 10-day streak with only 6 days elapsed in the currently
  // viewed month means the other 4 streak days are in the previous
  // month). Scoping this walk to a single month's own fetched data would
  // silently clip the streak at day 1 of that month and under-render the
  // fire icon on those early days. So this always re-walks from today
  // regardless of which month the caller is displaying; the caller
  // intersects this global Set against whichever month's dates it needs.
  //
  // Counts consecutive days (going back from today) that either have at
  // least one real (non-manually-logged) session, OR were recorded as a
  // scheduled rest day via recordDailyActivityLog() — a rest day doesn't
  // break the streak, but only for dates that have a dailyActivityLog
  // entry at all. If today has neither yet, yesterday is checked first —
  // streak still counts (today may still get logged/marked later).
  //
  // Manually-logged sessions are excluded from "day has activity" entirely
  // (isManuallyLogged == true is skipped when building sessionDates) —
  // same reasoning as computeChallengeProgress()'s identical exclusion:
  // contributions must come from validated, anti-cheat-checked data only.
  //
  // dailyActivityLog only exists going forward from whenever
  // recordDailyActivityLog() was first added — there is no retroactive
  // reconstruction of past rest days. Plan-day progression
  // (checkAndAdvanceDay()) is completion-driven, not calendar-anchored,
  // and keeps no history of which plan/day was active on a given past
  // date, so there is no reliable way to derive "was date X a rest day"
  // after the fact — confirmed during investigation, deliberately out of
  // scope. Past dates before this log exists simply get no rest-day
  // benefit and behave exactly as before this change (both here and in
  // getMonthActivity()'s protectedRestDates below).
  //
  // A user who has never tracked a plan (or is between tracked plans)
  // never gets a dailyActivityLog entry at all for those days (see
  // home_screen.dart's _loadTodaySession(), which only calls
  // recordDailyActivityLog() once it has a real tracked plan/session to
  // read isRestDay from) — such days correctly still require real
  // activity to keep the streak alive, with no special-casing needed here.
  // ---------------------------------------------------------------------------
  Future<Set<String>> calculateStreakDates(String uid) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .orderBy('date', descending: true)
        .get();

    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final sessionDates = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isManuallyLogged'] == true) continue;
      final ts = data['date'];
      if (ts is Timestamp) {
        sessionDates.add(key(ts.toDate().toLocal()));
      }
    }

    final restDaySnapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_dailyActivityLog)
        .get();
    final restDates = <String>{
      for (final doc in restDaySnapshot.docs)
        if (doc.data()['isRestDay'] == true) doc.id,
    };

    if (sessionDates.isEmpty && restDates.isEmpty) return {};

    bool dayCounts(DateTime d) {
      final k = key(d);
      return sessionDates.contains(k) || restDates.contains(k);
    }

    final now = DateTime.now();
    // If today has neither real activity nor a recorded rest day yet,
    // start counting from yesterday.
    DateTime check = dayCounts(now) ? now : now.subtract(const Duration(days: 1));

    if (!dayCounts(check)) return {};

    final streakDates = <String>{};
    while (dayCounts(check)) {
      streakDates.add(key(check));
      check = check.subtract(const Duration(days: 1));
    }
    return streakDates;
  }

  // ---------------------------------------------------------------------------
  // Returns a Set of date strings ('yyyy-MM-dd') for all sessions logged within
  // the last [days] days for users/{uid}. Used to drive the week calendar strip.
  // ---------------------------------------------------------------------------
  Future<Set<String>> getSessionDates(String uid, {int days = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .get();

    String _key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final dates = <String>{};
    for (final doc in snapshot.docs) {
      final ts = doc.data()['date'];
      if (ts is Timestamp) {
        dates.add(_key(ts.toDate().toLocal()));
      }
    }
    return dates;
  }

  // ---------------------------------------------------------------------------
  // Returns per-date workout/rest-day activity for one calendar month for
  // users/{uid} — the data source for the shared month-calendar widget
  // (lib/widgets/common/month_calendar.dart, via monthActivityProvider),
  // used both by Home's week-strip drill-down modal and Progress > Charts.
  // Same explicit start/end Timestamp range-query shape as
  // getSessionStats() (not a "last N days from now" window like
  // getSessionDates() above), just deriving per-day presence instead of
  // aggregate sums.
  //
  // Returns two plain Sets, not a UI-facing day-state enum — that
  // 3-way classification (workout / protectedRest / neither) is the
  // widget's own vocabulary, derived by the provider from these two Sets;
  // this method stays a plain-data method like getSessionDates() above.
  // Does NOT include streak-membership dates — see
  // calculateStreakDates()'s own doc comment for why that's a deliberately
  // separate, month-independent fetch (a streak can span a month
  // boundary; scoping it to one month's own data would clip it).
  //
  //   'workoutDates': dates with a real (non-manually-logged) session.
  //   'protectedRestDates': dates with a dailyActivityLog/{date} doc where
  //     isRestDay == true. Per calculateStreakDates()'s doc comment, this
  //     collection only has entries from whenever recordDailyActivityLog()
  //     started being called for this user — months (or parts of months)
  //     before that simply won't have any entries here, which is the
  //     correct "falls back to 2-state" behavior for old history, not an
  //     error to special-case.
  // ---------------------------------------------------------------------------
  Future<Map<String, Set<String>>> getMonthActivity(
    String uid,
    int year,
    int month,
  ) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String dateKeyStr(int y, int m, int d) =>
        '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

    final sessionsSnapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate))
        .get();

    final workoutDates = <String>{};
    for (final doc in sessionsSnapshot.docs) {
      final data = doc.data();
      if (data['isManuallyLogged'] == true) continue;
      final ts = data['date'];
      if (ts is Timestamp) {
        workoutDates.add(key(ts.toDate().toLocal()));
      }
    }

    // dailyActivityLog doc ids ARE 'yyyy-MM-dd' date strings, so a
    // documentId range query scopes this to the same month directly —
    // ISO date strings sort identically to chronological order, same
    // trick used nowhere else yet in this file but safe/standard for
    // Firestore doc-id range queries.
    final startKey = dateKeyStr(year, month, 1);
    final nextMonthYear = month == 12 ? year + 1 : year;
    final nextMonth = month == 12 ? 1 : month + 1;
    final endKey = dateKeyStr(nextMonthYear, nextMonth, 1);

    final activityLogSnapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_dailyActivityLog)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThan: endKey)
        .get();

    final protectedRestDates = <String>{
      for (final doc in activityLogSnapshot.docs)
        if (doc.data()['isRestDay'] == true) doc.id,
    };

    return {
      'workoutDates': workoutDates,
      'protectedRestDates': protectedRestDates,
    };
  }

  // ---------------------------------------------------------------------------
  // Saves a manually-logged activity to users/{uid}/sessions/{auto-id}.
  // No XP is awarded for manual logs per the PRD.
  // ---------------------------------------------------------------------------
  Future<void> saveManualActivity(
    String uid, {
    required String activityKey,
    required String activityName,
    required String intensity,
    required int durationMinutes,
    double? distance,
    String? notes,
    required int caloriesBurned,
    required DateTime activityDate,
  }) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .add({
      'type': 'manual',
      'activityKey': activityKey,
      'activityName': activityName,
      'intensity': intensity,
      'durationMinutes': durationMinutes,
      'durationSeconds': durationMinutes * 60,
      'distance': distance,
      'notes': notes,
      'caloriesBurned': caloriesBurned,
      'date': Timestamp.fromDate(activityDate),
      'createdAt': FieldValue.serverTimestamp(),
      'isManuallyLogged': true,
      'xpEarned': 0,
      // No plan is ever involved in a manually-logged activity.
      'planIsCustom': false,
    });
  }

  // ---------------------------------------------------------------------------
  // Returns weekly session statistics for users/{uid}.
  // Covers Mon–Sun of the current local week.
  // caloriesByDay / volumeByDay are indexed 0=Mon … 6=Sun.
  //
  // Extended (Progress-tab metrics expansion) to also compute, from this
  // SAME single query/loop rather than firing additional date-range
  // queries per new chart:
  //  - gym/cardio/combined/manualCountByDay: per-bucket session-type
  //    counts, same indexing as caloriesByBucket/volumeByBucket, for the
  //    session-type-breakdown stacked bar chart. gymSessions/
  //    cardioSessions above were already period TOTALS (not bucketed) —
  //    these are the per-bucket equivalent, plus the two missing types.
  //  - distanceByDay: per-bucket summed distanceMeters, for sessions
  //    where it's present (outdoor cardio, and combined sessions whose
  //    first cardio block had one — see finalizeInProgressSession()'s own
  //    doc comment on why only the first block's fields get promoted to
  //    the top level for a combined session). Never derived from `type`
  //    directly — distanceMeters presence is the actual signal, since a
  //    combined session's top-level type is 'combined', not 'cardio'.
  //  - totalDistanceMeters / totalDistanceDurationSeconds: summed across
  //    the same distance-having sessions, for computing one overall
  //    average pace for the period (not per-bucket — a per-bucket pace
  //    would need per-bucket duration too, which isn't needed for
  //    anything else, so it's kept to the one period-level figure the
  //    distance chart's caption actually shows).
  //  - muscleSetCounts: NOT bucketed by day/week/month like the above —
  //    a single Map<String,int> of setCount per muscle across the whole
  //    period, for the muscle-group distribution chart, which shows
  //    composition for the selected period, not a sub-period trend.
  //    Counts every done set (flagged-timing/flagged-bounds sets
  //    included) — flagging is an anti-cheat signal for XP/calorie
  //    integrity, not a claim the set didn't happen, so it still counts
  //    toward "what did you actually train" here. Exercises with a
  //    missing/null muscle (exercises collection is admin-managed and not
  //    guaranteed complete — see getAllExercises()'s own doc comment)
  //    are counted under the fixed key '_unknownMuscleKey' below rather
  //    than silently dropped.
  // ---------------------------------------------------------------------------
  static const String unknownMuscleKey = 'Unknown';

  Future<Map<String, dynamic>> getSessionStats(
    String uid, {
    required DateTime startDate,
    required DateTime endDate,
    required int bucketCount,
    required String bucketUnit,
  }) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate))
        .get();

    final caloriesByBucket = List<double>.filled(bucketCount, 0);
    final volumeByBucket = List<double>.filled(bucketCount, 0);
    final gymCountByBucket = List<double>.filled(bucketCount, 0);
    final cardioCountByBucket = List<double>.filled(bucketCount, 0);
    final combinedCountByBucket = List<double>.filled(bucketCount, 0);
    final manualCountByBucket = List<double>.filled(bucketCount, 0);
    final distanceByBucket = List<double>.filled(bucketCount, 0);
    int totalCalories = 0;
    double totalVolume = 0;
    int totalSessions = 0;
    int gymSessions = 0;
    int cardioSessions = 0;
    int combinedSessions = 0;
    int manualSessions = 0;
    double totalDistanceMeters = 0;
    int totalDistanceDurationSeconds = 0;
    final muscleSetCounts = <String, int>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final ts = data['date'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate().toLocal();
      final cals =
          (data['caloriesBurned'] as num?)?.toDouble() ?? 0;
      final vol =
          (data['totalVolume'] as num?)?.toDouble() ?? 0;
      final type = data['type'] as String? ?? '';

      int bucketIndex;
      if (bucketUnit == 'day') {
        bucketIndex = date
            .difference(startDate)
            .inDays
            .clamp(0, bucketCount - 1);
      } else if (bucketUnit == 'week') {
        bucketIndex = (date.difference(startDate).inDays ~/ 7)
            .clamp(0, bucketCount - 1);
      } else {
        // Elapsed calendar months since startDate, NOT just
        // date.month - startDate.month — that only worked when the
        // whole range stayed within one calendar year. Now that "This
        // Year" (progress_screen.dart's _loadChartData()) is a rolling
        // 365-day window, it almost always crosses a year boundary
        // (e.g. startDate in August 2025, a date in January 2026 needs
        // to land in a LATER bucket than one in August 2025, not wrap
        // back to a negative/clamped-to-0 index the way the old
        // month-only subtraction would).
        bucketIndex =
            ((date.year - startDate.year) * 12 +
                    (date.month - startDate.month))
                .clamp(0, bucketCount - 1);
      }

      caloriesByBucket[bucketIndex] += cals;
      if (type == 'gym') volumeByBucket[bucketIndex] += vol;
      totalCalories += cals.round();
      totalVolume += vol;
      totalSessions++;
      if (type == 'gym') {
        gymSessions++;
        gymCountByBucket[bucketIndex]++;
      }
      if (type == 'cardio') {
        cardioSessions++;
        cardioCountByBucket[bucketIndex]++;
      }
      if (type == 'combined') {
        combinedSessions++;
        combinedCountByBucket[bucketIndex]++;
      }
      if (type == 'manual') {
        manualSessions++;
        manualCountByBucket[bucketIndex]++;
      }

      // distanceMeters presence (not `type`) is the real signal — a
      // combined session carries type:'combined' but can still have a
      // top-level distanceMeters copied from its first cardio block.
      final distance = data['distanceMeters'] as num?;
      if (distance != null) {
        distanceByBucket[bucketIndex] += distance.toDouble();
        totalDistanceMeters += distance.toDouble();
        totalDistanceDurationSeconds +=
            (data['durationSeconds'] as num?)?.toInt() ?? 0;
      }

      if (type == 'gym') {
        final exercises = data['exercises'] as List<dynamic>? ?? [];
        for (final ex in exercises) {
          if (ex is! Map) continue;
          final muscle = ex['muscle'] as String?;
          final sets = ex['sets'] as List<dynamic>? ?? [];
          final key = (muscle == null || muscle.isEmpty)
              ? unknownMuscleKey
              : muscle;
          muscleSetCounts[key] = (muscleSetCounts[key] ?? 0) + sets.length;
        }
      }
    }

    return {
      'caloriesByDay': caloriesByBucket,
      'volumeByDay': volumeByBucket,
      'totalCalories': totalCalories,
      'totalVolume': totalVolume.round(),
      'totalSessions': totalSessions,
      'gymSessions': gymSessions,
      'cardioSessions': cardioSessions,
      'combinedSessions': combinedSessions,
      'manualSessions': manualSessions,
      'gymCountByDay': gymCountByBucket,
      'cardioCountByDay': cardioCountByBucket,
      'combinedCountByDay': combinedCountByBucket,
      'manualCountByDay': manualCountByBucket,
      'distanceByDay': distanceByBucket,
      'totalDistanceMeters': totalDistanceMeters,
      'totalDistanceDurationSeconds': totalDistanceDurationSeconds,
      'muscleSetCounts': muscleSetCounts,
    };
  }

  /// Convenience wrapper for backward compatibility
  Future<Map<String, dynamic>> getWeeklySessionStats(
      String uid) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart =
        today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    return getSessionStats(
      uid,
      startDate: weekStart,
      endDate: weekEnd,
      bucketCount: 7,
      bucketUnit: 'day',
    );
  }

  // ---------------------------------------------------------------------------
  // Appends an XP event to users/{uid}/xpEvents/{auto-id}.
  // Called immediately after addXpToUser so XP history stays in sync.
  // ---------------------------------------------------------------------------
  Future<void> saveXpEvent(String uid, Map<String, dynamic> eventData) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.xpEvents)
        .add({
      'amount': eventData['amount'],
      'reason': eventData['reason'],
      'type': eventData['type'],
      'date': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Returns the [limit] most recent XP events for users/{uid}, newest first.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getXpEvents(
    String uid, {
    int limit = 20,
  }) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.xpEvents)
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Returns a single plan document by id, or null if it does not exist.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getPlan(String planId) async {
    final doc = await _db.collection(Collections.plans).doc(planId).get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data()!};
  }

  Stream<Map<String, dynamic>?> getPlanStream(String planId) {
    return _db
        .collection(Collections.plans)
        .doc(planId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return {'id': snap.id, ...snap.data()!};
    });
  }

  static List<Map<String, dynamic>> parseExerciseSets(
      dynamic rawSets, int fallbackCount) {
    if (rawSets is List) {
      return rawSets.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }
    final count = (rawSets as num?)?.toInt() ?? fallbackCount;
    return List.generate(
      count,
      (_) => {
        'kg': 0.0,
        'reps': 10,
        'done': false,
        'type': 'normal',
        'restTime': 60,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Returns all documents from the plans collection, each map including
  // the document id as 'id'.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getPlans() async {
    final snapshot = await _db.collection(Collections.plans).get();
    return snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Whether uid already has at least one of their OWN personal custom
  // routines (isCustom:true, createdBy:uid) — coach-authored plans
  // (isCoachPlan:true, saved via the same saveCustomRoutine()) are excluded,
  // since those aren't the user's personal free-tier routine slot. Filters
  // client-side over getPlans()'s full catalog rather than a new server-side
  // query shape, matching plans_screen.dart's own existing "my custom
  // plans" filter (isCustom==true && createdBy==uid) exactly. Used to gate
  // new personal-routine creation on the free tier.
  // ---------------------------------------------------------------------------
  Future<bool> hasExistingCustomRoutine(String uid) async {
    final allPlans = await getPlans();
    return allPlans.any((p) =>
        p['isCustom'] == true &&
        (p['createdBy'] as String?) == uid &&
        p['isCoachPlan'] != true);
  }

  // ---------------------------------------------------------------------------
  // planProgress subcollection helpers — per-plan progress isolation.
  // ---------------------------------------------------------------------------

  // Seeds a brand-new planProgress/{planId} doc with defaults. Guarded by
  // an existence check so this is genuinely idempotent to call more than
  // once for the same uid+planId (e.g. trackPlan() re-tracking a plan
  // that was already tracked before, then untracked, then tracked again —
  // untracking never touches this doc, so it can still hold real progress
  // by the time trackPlan() calls this again). SetOptions(merge:true)
  // alone does NOT provide that safety: every field below is explicitly
  // named in the payload, and merge only protects fields NOT listed in a
  // write — every one of these would still be silently overwritten back
  // to its default on a second call without this guard. Deliberately
  // resetting a plan's progress is a separate, explicit action — see
  // resetPlanProgress(), wired to the "Restart Program" buttons in
  // plan_detail_screen.dart/plan_schedule_screen.dart — tracking must
  // never implicitly do that.
  Future<void> initPlanProgress(String uid, String planId) async {
    final docRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .doc(planId);
    final existing = await docRef.get();
    if (existing.exists) return;
    await docRef.set({
      'planId': planId,
      'currentDayIndex': 1,
      'lastCompletedDate': '',
      'lastCompletedDayIndex': 0,
      // Map of dayIndex (as a string key) -> {removedExercises: [int],
      // cardioOverrides: {exerciseIndex (string key): minutes}} — see
      // plan_schedule_screen.dart's _CompressedDayData for the in-memory
      // shape and _parseCompressedDays() for graceful handling of the
      // older boolean-array format ([dayIndex, ...]) some existing users'
      // docs may still have.
      'compressedDays': {},
      // Lifetime per-day completion ledger — every dayIndex ever marked
      // done via markSessionComplete(), persisting across app sessions
      // until an explicit resetPlanProgress() (or the automatic
      // full-program-wrap clear in checkAndAdvanceDay()). Distinct from
      // lastCompletedDate/lastCompletedDayIndex above, which only ever
      // remember the single most recently completed day — this is what
      // lets plan_detail_screen.dart/plan_schedule_screen.dart correctly
      // show every genuinely-completed day, not just the latest one.
      'completedDayIndices': [],
      'breakModeActive': false,
      'breakStartDate': null,
      'breakEndDate': null,
      'breakDays': 3,
      'trackingStartDate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getPlanProgress(
      String uid, String planId) async {
    final doc = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .doc(planId)
        .get();
    if (doc.exists) return doc.data();
    await initPlanProgress(uid, planId);
    return {
      'planId': planId,
      'currentDayIndex': 1,
      'lastCompletedDate': '',
      'compressedDays': {},
      'completedDayIndices': [],
      'breakModeActive': false,
      'trackingStartDate': null,
    };
  }

  // ---------------------------------------------------------------------------
  // Same read as getPlanProgress() above, but never auto-creates a doc or
  // returns a default map when one doesn't exist — plain null instead, same
  // as a bare .get(). getPlanProgress()'s auto-init-on-missing behavior is
  // right for screens actively driving a plan's progress forward, but wrong
  // for a passive/background check (e.g. home_screen.dart's missed-session
  // check) where silently creating a fresh progress doc as a side effect of
  // a read would be incorrect.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getPlanProgressIfExists(
      String uid, String planId) async {
    final doc = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .doc(planId)
        .get();
    return doc.exists ? doc.data() : null;
  }

  Stream<Map<String, dynamic>?> getPlanProgressStream(
      String uid, String planId) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .doc(planId)
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  Future<void> updatePlanProgress(
      String uid, String planId, Map<String, dynamic> fields) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .doc(planId)
        .set(fields, SetOptions(merge: true));
  }

  // Records that `planId` was actually started (not merely previewed) —
  // called fire-and-forget from gym_session_screen.dart's _startSession(),
  // the single point every entry point (Home, Plans tab, Plan Detail
  // preview, Plan Schedule) funnels through once "Start Session" is
  // tapped. Reuses updatePlanProgress's existing merge:true set, which
  // already creates the planProgress/{planId} doc if this plan was never
  // tracked before — no separate initPlanProgress() call needed.
  Future<void> recordPlanAccess(String uid, String planId) async {
    await updatePlanProgress(uid, planId, {
      'lastAccessedAt': FieldValue.serverTimestamp(),
    });
  }

  // Bulk-reads every planProgress doc for uid in one query, keyed by
  // planId (the Firestore doc id under users/{uid}/planProgress) — for
  // callers that need a field like lastAccessedAt across several plans at
  // once (see plans_screen.dart's Recently Used sort) without issuing one
  // read per plan. This subcollection only ever holds docs for plans this
  // user has tracked/accessed, so it stays small in practice — a single
  // unfiltered .get() is simplest here; no whereIn/chunking needed the way
  // a cross-user query would.
  Future<Map<String, Map<String, dynamic>>> getAllPlanProgress(
      String uid) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()};
  }

  // ---------------------------------------------------------------------------
  // Sets the user's tracked plan. Progress is stored per-plan in the
  // planProgress subcollection; only trackedPlanId/Name live on the user doc.
  //
  // trackedPlanStartedAt is written unconditionally on every call (unlike
  // initPlanProgress()'s other seed fields, which only ever get set once
  // per plan) — it always reflects when the CURRENTLY tracked plan most
  // recently became tracked, including re-tracks/switches, so
  // home_screen.dart's _checkMissedSession() has a reliable anchor for its
  // 24h grace period even when switching onto an old, previously-tracked
  // plan with stale history. Deliberately a separate field from the
  // existing trackingStartDate (set once, inside initPlanProgress, and
  // otherwise unused) to avoid redefining that field's original
  // first-ever-tracked meaning.
  // ---------------------------------------------------------------------------
  Future<void> trackPlan(
    String uid,
    String planId,
    String planName,
  ) async {
    await _db.collection(Collections.users).doc(uid).update({
      'trackedPlanId': planId,
      'trackedPlanName': planName,
      'savedPlanIds': FieldValue.arrayUnion([planId]),
    });
    await initPlanProgress(uid, planId);
    await updatePlanProgress(uid, planId, {
      'trackedPlanStartedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Reads trackedPlanId from users/{uid}, then fetches that plan document.
  // Returns null if the user has no tracked plan or the plan doc is missing.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getTrackedPlan(String uid) async {
    final userDoc =
        await _db.collection(Collections.users).doc(uid).get();
    final trackedPlanId =
        userDoc.data()?['trackedPlanId'] as String?;
    if (trackedPlanId == null || trackedPlanId.isEmpty) return null;
    final planDoc =
        await _db.collection(Collections.plans).doc(trackedPlanId).get();
    if (!planDoc.exists) return null;
    return {'id': planDoc.id, ...planDoc.data()!};
  }

  // ---------------------------------------------------------------------------
  // Records completion of today's session. Saves lastCompletedDate (yyyy-MM-dd)
  // and lastCompletedDayIndex without changing currentDayIndex — the advance
  // happens on the next app open via checkAndAdvanceDay. Also adds
  // currentDayIndex to the lifetime completedDayIndices ledger via
  // arrayUnion, so a repeat completion of the same day (e.g. redoing Day 1
  // before advancing) doesn't create a duplicate entry.
  // ---------------------------------------------------------------------------
  Future<void> markSessionComplete(String uid, String planId) async {
    final progress = await getPlanProgress(uid, planId);
    final currentDayIndex =
        (progress?['currentDayIndex'] as num?)?.toInt() ?? 1;
    final today = DateTime.now().toString().substring(0, 10);
    await updatePlanProgress(uid, planId, {
      'lastCompletedDate': today,
      'lastCompletedDayIndex': currentDayIndex,
      'completedDayIndices': FieldValue.arrayUnion([currentDayIndex]),
    });
  }

  // ---------------------------------------------------------------------------
  // Advances currentDayIndex if the last completed session was on a previous
  // calendar day and the index has not been advanced yet.
  // Returns the effective currentDayIndex (new value or unchanged).
  //
  // newIndex == 1 here specifically means currentDayIndex == totalSessions —
  // i.e. the plan's entire defined day count was just exhausted and this
  // wrapped back to the start of a fresh cycle through the whole program
  // (this is the ONLY place in the codebase currentDayIndex is computed via
  // a wrapping formula — every other write either seeds it to 1 for a new
  // plan or is the explicit resetPlanProgress() restart, neither of which
  // is this kind of automatic wrap). Treated as an implicit "start over"
  // exactly like the explicit Restart Program action, so the lifetime
  // completedDayIndices ledger is cleared here too — otherwise a user who
  // simply keeps going after finishing the whole program (never tapping
  // Restart) would see every day of the new cycle pre-marked complete from
  // the previous one.
  // ---------------------------------------------------------------------------
  Future<int> checkAndAdvanceDay(
      String uid, int totalSessions, String planId) async {
    final progress = await getPlanProgress(uid, planId);
    final data = progress ?? {};
    final currentDayIndex =
        (data['currentDayIndex'] as num?)?.toInt() ?? 1;
    final lastCompletedDate = data['lastCompletedDate'] as String?;
    final lastCompletedDayIndex =
        (data['lastCompletedDayIndex'] as num?)?.toInt();
    final today = DateTime.now().toString().substring(0, 10);

    if (lastCompletedDate != null &&
        lastCompletedDate.isNotEmpty &&
        lastCompletedDate != today &&
        lastCompletedDayIndex == currentDayIndex) {
      final newIndex = (currentDayIndex % totalSessions) + 1;
      final updates = <String, dynamic>{'currentDayIndex': newIndex};
      if (newIndex == 1) updates['completedDayIndices'] = [];
      await updatePlanProgress(uid, planId, updates);
      return newIndex;
    }
    return currentDayIndex;
  }

  // ---------------------------------------------------------------------------
  // Records whether today was a scheduled rest day for [uid]'s tracked plan
  // — called from home_screen.dart's _loadTodaySession() right after that's
  // determined, since that's the one place this information already exists
  // live. Doc id is today's date (yyyy-MM-dd), and the write uses
  // SetOptions(merge:true), so it's naturally idempotent — _loadTodaySession
  // can (and does) call this more than once on the same day (once on
  // initial load, again whenever the plan-progress stream reports a day
  // change) without needing a separate check-then-write guard; repeated
  // identical writes to the same doc id are safe.
  //
  // Deliberately does NOT also record whether the day had real activity —
  // calculateStreak() already scans the full sessions collection anyway to
  // build its own set of active dates, so deriving that signal there is
  // free. Precomputing and caching it here would need an extra query at
  // write time AND risk going stale (e.g. this fires on morning app-open,
  // before an evening workout gets logged later the same day).
  // ---------------------------------------------------------------------------
  Future<void> recordDailyActivityLog(String uid, {required bool isRestDay}) async {
    final today = DateTime.now().toString().substring(0, 10);
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_dailyActivityLog)
        .doc(today)
        .set({'isRestDay': isRestDay}, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Resets a plan's progress back to Day 1 — the shared reset used by both
  // plan_schedule_screen.dart's Restart Plan action and
  // plan_detail_screen.dart's Restart Program action, so the exact set of
  // fields reset can never drift out of sync between the two screens again.
  // Session history (sessions/{id} docs) is untouched — this only resets
  // the planProgress/{planId} tracking doc.
  // ---------------------------------------------------------------------------
  Future<void> resetPlanProgress(String uid, String planId) async {
    await updatePlanProgress(uid, planId, {
      'currentDayIndex': 1,
      'lastCompletedDate': '',
      'lastCompletedDayIndex': 0,
      'compressedDays': {},
      'completedDayIndices': [],
    });
  }

  // ---------------------------------------------------------------------------
  // Saves a custom user-built routine to:
  //   1. users/{uid}/customRoutines/{auto-id}  — private copy
  //   2. plans/{auto-id}                       — discoverable plan entry
  // ---------------------------------------------------------------------------
  // isCoachPlan defaults to false so every existing call site (a normal
  // user, or a coach saving an ordinary PERSONAL plan for themselves via
  // the same screen everyone uses) is completely unaffected — it's only
  // ever true when build_routine_screen.dart was opened from
  // coach_dashboard_screen.dart's "Create a Plan" entry point (see that
  // screen's own extra: {'isCoachPlan': true}). Doesn't change the
  // existing plans-collection create rule at all (isCustom==true &&
  // createdBy==caller already covers this write; isCoachPlan is just an
  // extra field the rule never inspects), so no rules deploy needed for
  // this.
  Future<void> saveCustomRoutine({
    required String uid,
    required String routineName,
    required List<Map<String, dynamic>> sessions,
    required int daysPerWeek,
    bool isCoachPlan = false,
  }) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection('customRoutines')
        .add({
      'name': routineName,
      'createdAt': FieldValue.serverTimestamp(),
      'sessions': sessions,
      'isCustom': true,
      if (isCoachPlan) 'isCoachPlan': true,
    });

    await _db.collection(Collections.plans).add({
      'name': routineName,
      'level': 'Custom',
      // Custom/coach-built routines are intentionally free-form — they may
      // mix strength exercises and cardio blocks on any day — so they're
      // never really "Gym" specifically, regardless of what the user
      // happened to add first. 'Combine' matches how official plans that
      // mix both are already categorized (see explore_screen.dart's
      // _gymPlans/_cardioPlans/_combinePlans sport filters and
      // _accentColor()). This is shared by both a normal personal routine
      // and a coach-authored one (isCoachPlan above) — same builder, same
      // free-form schema, so both get the same type here.
      'type': 'Combine',
      'daysPerWeek': daysPerWeek,
      'description': 'Custom routine created by user',
      'isCustom': true,
      'createdBy': uid,
      'sessions': sessions,
      'createdAt': FieldValue.serverTimestamp(),
      if (isCoachPlan) 'isCoachPlan': true,
    });
  }

  Future<void> updateCustomRoutine({
    required String planId,
    required String routineName,
    required List<Map<String, dynamic>> sessions,
    required int daysPerWeek,
  }) async {
    await _db.collection(Collections.plans).doc(planId).update({
      'name': routineName,
      'sessions': sessions,
      'daysPerWeek': daysPerWeek,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Deletes a custom plan from plans/{planId}, matching customRoutines docs
  // by name, and planProgress/{planId} if it exists.
  //
  // If planId is also the user's currently-tracked plan, clears
  // trackedPlanId/trackedPlanName too (empty string, not FieldValue.delete()
  // — matches getTrackedPlan()'s own null-handling, which treats an empty
  // trackedPlanId the same as a missing one, and matches home_screen.dart's/
  // plans_screen.dart's own "no tracked plan" defaults). Without this,
  // deleting a tracked plan left users/{uid}.trackedPlanId pointing at a
  // now-nonexistent plans/{} doc — Plans tab's getTrackedPlan() correctly
  // returned null and showed "No tracked plan", but Home still had a
  // non-empty trackedPlanName to render a stale "Today's Plan" card with
  // (that field isn't derived from the plan doc at all, so it never
  // reflected the deletion on its own).
  // ---------------------------------------------------------------------------
  Future<void> deleteCustomPlan(
      String uid, String planId, String planName) async {
    final userDoc =
        await _db.collection(Collections.users).doc(uid).get();
    final isTracked = (userDoc.data()?['trackedPlanId'] as String?) == planId;

    await _db.collection(Collections.plans).doc(planId).delete();

    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection('customRoutines')
        .where('name', isEqualTo: planName)
        .get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }

    try {
      await _db
          .collection(Collections.users)
          .doc(uid)
          .collection('planProgress')
          .doc(planId)
          .delete();
    } catch (_) {}

    if (isTracked) {
      await _db.collection(Collections.users).doc(uid).update({
        'trackedPlanId': '',
        'trackedPlanName': '',
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Saves/unsaves an Explore plan to the user's saved plan list.
  // ---------------------------------------------------------------------------
  Future<void> saveExplorePlan(String uid, String planId) async {
    await _db.collection(Collections.users).doc(uid).update({
      'savedPlanIds': FieldValue.arrayUnion([planId]),
    });
  }

  Future<void> unsaveExplorePlan(String uid, String planId) async {
    await _db.collection(Collections.users).doc(uid).update({
      'savedPlanIds': FieldValue.arrayRemove([planId]),
    });
  }

  Future<List<String>> getSavedPlanIds(String uid) async {
    final doc = await _db.collection(Collections.users).doc(uid).get();
    final data = doc.data();
    if (data == null) return [];
    final raw = data['savedPlanIds'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  // ---------------------------------------------------------------------------
  // Sets/clears a one-time override day index in planProgress.
  // Used by Start buttons on day cards to open a specific session day.
  // ---------------------------------------------------------------------------
  Future<void> setOverrideDayIndex(
      String uid, String planId, int dayIndex) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .doc(planId)
        .set({'overrideDayIndex': dayIndex}, SetOptions(merge: true));
    await _db
        .collection(Collections.users)
        .doc(uid)
        .update({
          'overridePlanId': planId,
          'overrideDayIndex': dayIndex,
        });
  }

  Future<void> clearOverrideDayIndex(String uid, String planId) async {
    try {
      await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(_planProgress)
          .doc(planId)
          .update({'overrideDayIndex': FieldValue.delete()});
    } catch (_) {}
    try {
      await _db
          .collection(Collections.users)
          .doc(uid)
          .update({
            'overridePlanId': FieldValue.delete(),
            'overrideDayIndex': FieldValue.delete(),
          });
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Writes a missed session record to users/{uid}/missedSessions/{yesterday}.
  // Uses yesterday's date as the doc id so duplicate checks are O(1).
  // ---------------------------------------------------------------------------
  Future<void> logMissedSession(
      String uid, String planId, int dayIndex, String reason,
      {String? date}) async {
    final targetDate = date ??
        DateTime.now()
            .subtract(const Duration(days: 1))
            .toString()
            .substring(0, 10);
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection('missedSessions')
        .doc(targetDate)
        .set({
      'reason': reason,
      'planId': planId,
      'dayIndex': dayIndex,
      'date': targetDate,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Whether a users/{uid}/missedSessions doc already exists for [date]
  // ('yyyy-MM-dd', same convention as the doc id logMissedSession() writes
  // to). Used by home_screen.dart's missed-workout banner check to avoid
  // double-flagging a day that's already been recorded.
  // ---------------------------------------------------------------------------
  Future<bool> hasMissedSessionForDate(String uid, String date) async {
    final doc = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection('missedSessions')
        .doc(date)
        .get();
    return doc.exists;
  }

  // ---------------------------------------------------------------------------
  // Live stream of users/{uid}/missedSessions docs, newest first — powers
  // progress_screen.dart's check-ins list.
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getMissedSessionsStream(
    String uid, {
    int limit = 50,
  }) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection('missedSessions')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  // ---------------------------------------------------------------------------
  // Count of users/{uid}/missedSessions docs whose 'date' field falls within
  // the inclusive [start, end] range — used by coach_screen.dart's Phase 4
  // referral-nudge trigger (5+ missed sessions in the trailing 7 days).
  // 'date' is a 'yyyy-MM-dd' string (same value as the doc id), so a
  // lexicographic range query works directly, same trick getMonthActivity()
  // already uses for dailyActivityLog doc-id ranges.
  // ---------------------------------------------------------------------------
  Future<int> getMissedSessionCountInRange(
    String uid,
    DateTime start,
    DateTime end,
  ) async {
    String dateKey(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection('missedSessions')
        .where('date', isGreaterThanOrEqualTo: dateKey(start))
        .where('date', isLessThanOrEqualTo: dateKey(end))
        .get();
    return snapshot.docs.length;
  }

  // ---------------------------------------------------------------------------
  // Saves a completed cardio session to users/{uid}/sessions/{auto-id}.
  // XP is awarded at 0.5× calories, clamped to 20–500.
  // ---------------------------------------------------------------------------
  Future<({String sessionId, List<Map<String, dynamic>> newlyEarnedBadges})>
      saveCardioSession({
    required String uid,
    required String activity,
    required int durationSeconds,
    required int caloriesBurned,
    String mode = 'indoor',
    double? avgHeartRate,
    double? maxHeartRate,
    double? distanceMeters,
    List<Map<String, double>>? route,
    double? elevationGainMeters,
    String? name,
    String? notes,
    String? photoBase64,
    String? mapSnapshotBase64,
  }) async {
    final gamificationConfig = await getGamificationConfig();
    final xpEarned = _computeCardioXp(caloriesBurned, gamificationConfig);
    final sessionName = (name != null && name.isNotEmpty)
        ? name
        : '$activity · ${mode == 'indoor' ? 'Indoor' : 'Outdoor'}';
    final ref = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .add({
      'type': 'cardio',
      'sessionName': sessionName,
      'activity': activity,
      'mode': mode,
      'date': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'durationSeconds': durationSeconds,
      'caloriesBurned': caloriesBurned,
      'xpEarned': xpEarned,
      'isManuallyLogged': false,
      'exercises': [],
      'totalSets': 0,
      'totalVolume': 0.0,
      // This method has no planId parameter today, so a real custom-plan
      // lookup isn't possible here yet — known gap, always false until
      // planId plumbing is added separately (out of scope for now).
      'planIsCustom': false,
      'avgHeartRate': ?avgHeartRate,
      'maxHeartRate': ?maxHeartRate,
      'distanceMeters': ?distanceMeters,
      'route': ?route,
      'elevationGainMeters': ?elevationGainMeters,
      'notes': ?notes,
      'photoBase64': ?photoBase64,
      'mapSnapshotBase64': ?mapSnapshotBase64,
    });

    // Previously missing entirely for this session type — xpEarned was
    // computed and stored on the session doc above but never actually
    // credited to the user's totalXp/level (see addXpToUser()'s own doc
    // comment for what it writes), and badges could never be checked after
    // a cardio session either. Matches gym_session_screen.dart's standalone
    // finish flow, which calls both right after its own session write.
    await addXpToUser(uid, xpEarned);
    await saveXpEvent(uid, {
      'amount': xpEarned,
      'reason': 'Completed $sessionName',
      'type': 'cardio',
    });
    final newlyEarnedBadges = await checkAndAwardBadges(uid);
    return (sessionId: ref.id, newlyEarnedBadges: newlyEarnedBadges);
  }

  // ---------------------------------------------------------------------------
  // Updates a session document with a WiseCoach summary generated after the
  // fact (the AI call in post_session_summary_screen.dart is slower than the
  // initial save, so it can't be included in saveGymSession/saveCardioSession
  // itself — this is a follow-up write once the summary is actually ready).
  // ---------------------------------------------------------------------------
  Future<void> updateSessionSummary(
    String uid,
    String sessionId,
    String summary,
  ) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .doc(sessionId)
        .update({'wiseCoachSummary': summary});
  }

  // ---------------------------------------------------------------------------
  // Reads a single finalized session doc (users/{uid}/sessions/{sessionId}).
  // Fails soft (logs, returns null) on a missing doc or any Firestore error —
  // matching this file's existing getPlan()/getInProgressSession() fail-soft
  // convention — rather than throwing, since a lookup failure here shouldn't
  // crash whatever screen is trying to display a past session.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getSession(String uid, String sessionId) async {
    try {
      final doc = await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(Collections.sessions)
          .doc(sessionId)
          .get();
      if (!doc.exists) {
        debugPrint('getSession: no such session $sessionId');
        return null;
      }
      return {'id': doc.id, ...doc.data()!};
    } catch (e) {
      debugPrint('getSession error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // inProgressSessions subcollection helpers — tracks a multi-block plan
  // day (gym exercises + cardio blocks) across navigation away and back
  // (e.g. to a cardio block's own screen) so per-block completion isn't
  // lost the way plain in-memory widget state currently is.
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Generates a stable identity for an inProgressSessions blocks[] entry —
  // the fix for the confirmed root cause of the block-corruption bugs this
  // whole system had: array POSITION was previously the only identity a
  // block ever had, but the array's real shape changes after creation
  // (dismissInjuryReview()'s removeAt() shifts every later position;
  // appendInProgressSessionBlock() grows it) while every already-in-memory
  // reference to a block's old position was never refreshed — causing
  // out-of-range writes, wrong-slot overwrites (a full block replaced with
  // a DIFFERENT exercise's data), and the resulting apparent duplication.
  // Microsecond timestamp + `salt` (the block's own position AT
  // GENERATION TIME, used only as a same-instant tiebreaker, never as an
  // identity itself afterward) — not a uuid package (none is a dependency
  // of this app); mirrors the timestamp-based id patterns already
  // established elsewhere in this codebase (build_routine_screen.dart's
  // counter-based _nextId(), this file's own existing set-id generation,
  // router.dart's ValueKey microsecond suffixes). `static` so it's callable
  // without an instance — gym_session_screen.dart's hydration path also
  // calls this directly for the backward-compatibility backfill (see
  // _hydrateFromInProgressSession's own doc comment there).
  // ---------------------------------------------------------------------------
  static String generateBlockId(int salt) =>
      'block-${DateTime.now().microsecondsSinceEpoch}-$salt';

  // ---------------------------------------------------------------------------
  // Creates a new in-progress session at
  // users/{uid}/inProgressSessions/{auto-id}. `blocks` is the day's raw
  // exercises array (as already stored in customRoutines/plans); each entry
  // is written with `done: false` seeded on regardless of block type, plus
  // a fresh, stable `blockId` (see generateBlockId's own doc comment) — for
  // isCardio entries no other change is made yet (per this task's scope).
  // Returns the new document's id (the sessionRunId used by the other three
  // methods below).
  // ---------------------------------------------------------------------------
  Future<String> createInProgressSession(
    String uid,
    String planId,
    int dayIndex,
    List<Map<String, dynamic>> blocks,
  ) async {
    // Preserves an already-present blockId rather than always generating a
    // fresh one — gym_session_screen.dart's _assignBlockIds() pre-assigns
    // ids to a fresh-start plan template's raw exercises BEFORE calling
    // both this method and _parseExercises() with the same list, so its
    // in-memory _exercises and this seed write agree on identical ids
    // from the start. Only actually generates a new one for a block that
    // somehow still lacks one (defensive — every real call site today
    // already pre-assigns).
    final seededBlocks = blocks.asMap().entries.map((entry) {
      final i = entry.key;
      final b = entry.value;
      final blockId = b['blockId'] as String? ?? generateBlockId(i);
      return {...b, 'done': false, 'blockId': blockId};
    }).toList();
    final ref = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .add({
      'planId': planId,
      'dayIndex': dayIndex,
      'blocks': seededBlocks,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // ---------------------------------------------------------------------------
  // Backward-compatibility helper: persists blockIds freshly assigned by
  // gym_session_screen.dart's _hydrateFromInProgressSession() for a
  // session that predates the stable-blockId migration (see
  // generateBlockId's own doc comment). Fire-and-forget, deliberately not
  // wrapped in a transaction — this only ever runs once per session
  // (every block gets an id the first time it's touched post-migration,
  // and every write from then on already includes it), so the narrow race
  // window against a genuinely concurrent write is an acceptable,
  // low-stakes tradeoff for keeping this one-time backfill simple.
  // ---------------------------------------------------------------------------
  Future<void> backfillInProgressSessionBlocks(
    String uid,
    String sessionRunId,
    List<Map<String, dynamic>> blocks,
  ) async {
    try {
      await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(_inProgressSessions)
          .doc(sessionRunId)
          .update({'blocks': blocks});
    } catch (e) {
      debugPrint('backfillInProgressSessionBlocks error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Marks a single block within an in-progress session done or not-done —
  // looked up by its stable blockId (see generateBlockId's own doc
  // comment for the full root-cause history), NOT by array position. This
  // used to take a raw blockIndex and trust it directly
  // (blocks[blockIndex] = ...), which broke the moment the array's real
  // shape changed after that index was captured (dismissInjuryReview()
  // removing an earlier block shifts every later block's true position,
  // but nothing ever refreshed an already-in-memory reference to the old
  // one) — causing rejected out-of-range writes and, worse, silent
  // wrong-slot overwrites where a stale-but-still-in-range index landed
  // this write on a completely different exercise's slot. Looking the
  // block up by blockId instead is immune to this by construction: a
  // block's id never changes no matter how many times the array around it
  // shrinks, grows, or reorders.
  //
  // Firestore has no in-place array-element update, so the whole `blocks`
  // array is still read, the matched entry is replaced with blockData,
  // and the full array is written back — inside a runTransaction(), not a
  // bare get()+update(). This read-modify-write used to run outside any
  // transaction, which meant two overlapping calls (this is called
  // un-awaited from gym_session_screen.dart's _syncBlockDone() every time
  // an exercise's sets complete — two exercises finishing close together
  // in real time is enough to overlap two calls) could each read a
  // same/stale snapshot and each write back a full array reflecting only
  // its own single-index change, silently losing whichever one committed
  // first. A transaction closes this: if two transactions' reads
  // overlap, Firestore fails whichever one's write attempts to commit
  // second against the now-stale read version and automatically retries
  // it — that retry re-reads the doc (now including the first
  // transaction's committed change) and reapplies its own mutation on top
  // of it, rather than clobbering it. Fails soft (logs, doesn't throw) if
  // the doc is missing or blockId isn't found — a stray/late update after
  // the session was already finalized or abandoned (see
  // finalizeInProgressSession/deleteInProgressSession) shouldn't crash the
  // caller.
  //
  // `done` is derived, not always forced true: if blockData['sets'] is a
  // List (a gym block), done = every one of those sets having done:true —
  // so un-ticking a set correctly writes done:false back, not just the
  // same sets with done forced true regardless of their actual state. A
  // block with no 'sets' list (a cardio block — this app's cardio finish
  // handlers never include one) has no partial-completion concept in this
  // app's UI, so it's always written as done:true, matching every existing
  // cardio call site's actual use (called exactly once, at genuine finish).
  // ---------------------------------------------------------------------------
  Future<void> updateInProgressSessionBlock(
    String uid,
    String sessionRunId,
    String blockId,
    Map<String, dynamic> blockData,
  ) async {
    final docRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .doc(sessionRunId);
    try {
      await _db.runTransaction((transaction) async {
        // transaction.get()/transaction.update(), not docRef.get()/
        // docRef.update() — required for this read and this write to be
        // the ones Firestore actually tracks for conflict detection/retry;
        // a bare docRef.get() inside a transaction callback would silently
        // opt that read out of the transaction's isolation guarantee.
        final doc = await transaction.get(docRef);
        if (!doc.exists) {
          debugPrint('updateInProgressSessionBlock: no such session $sessionRunId');
          return;
        }
        final rawBlocks = doc.data()?['blocks'];
        if (rawBlocks is! List) {
          debugPrint('updateInProgressSessionBlock: no blocks[] for session '
              '$sessionRunId');
          return;
        }
        final blocks = rawBlocks
            .map((b) => Map<String, dynamic>.from(b as Map))
            .toList();
        final index = blocks.indexWhere((b) => b['blockId'] == blockId);
        if (index < 0) {
          debugPrint('updateInProgressSessionBlock: blockId $blockId not found '
              'for session $sessionRunId');
          return;
        }
        final rawSets = blockData['sets'];
        final done = rawSets is List
            ? rawSets.every((s) => s is Map && s['done'] == true)
            : true;
        // blockId explicitly re-included — blockData (built by callers
        // from their own in-memory exercise state) never carries it, and
        // this is a full slot replacement, not a merge, so leaving it out
        // would silently drop the block's own identity on every write.
        blocks[index] = {...blockData, 'done': done, 'blockId': blockId};
        transaction.update(docRef, {'blocks': blocks});
      });
    } catch (e) {
      debugPrint('updateInProgressSessionBlock error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Appends a brand-new block to an in-progress session's blocks[] array and
  // returns its new blockId (see generateBlockId's own doc comment) — for
  // a block added mid-session (gym_session_screen.dart's "+ Add" sheets)
  // that never had a slot from createInProgressSession()'s original
  // seeding at all, unlike updateInProgressSessionBlock(), which only ever
  // replaces an EXISTING slot (looked up by id) and fails soft if that id
  // isn't found rather than growing the array. Previously returned the
  // new array index instead of an id — changed alongside every other
  // identity-bearing call in this system, since a raw index captured here
  // would go stale the moment anything later shifts the array (see
  // updateInProgressSessionBlock's own doc comment for the full history).
  // done:false is always seeded on, same as createInProgressSession() does
  // for every block it originally seeds. Fails soft (logs, returns null)
  // on a missing doc or any error — an add should never be able to block
  // the user from continuing their workout; the caller falls back to
  // blockId: null (no sync) exactly as it already does today when this
  // returns null.
  // ---------------------------------------------------------------------------
  Future<String?> appendInProgressSessionBlock(
    String uid,
    String sessionRunId,
    Map<String, dynamic> blockData,
  ) async {
    final docRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .doc(sessionRunId);
    try {
      final doc = await docRef.get();
      if (!doc.exists) {
        debugPrint('appendInProgressSessionBlock: no such session $sessionRunId');
        return null;
      }
      final rawBlocks = doc.data()?['blocks'];
      final blocks = rawBlocks is List
          ? rawBlocks.map((b) => Map<String, dynamic>.from(b as Map)).toList()
          : <Map<String, dynamic>>[];
      final blockId = generateBlockId(blocks.length);
      blocks.add({...blockData, 'done': false, 'blockId': blockId});
      await docRef.update({'blocks': blocks});
      return blockId;
    } catch (e) {
      debugPrint('appendInProgressSessionBlock error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Marks injury review as dismissed for this in-progress session (so
  // gym_session_screen.dart's initState() postFrameCallback chain doesn't
  // re-run _checkExercisesForInjuries()/re-show the review sheet on a later
  // resume of the same sessionRunId — see that file's
  // _injuryReviewAlreadyDismissed field doc) and, in the same
  // read-modify-write, removes whichever blocks[] entries the user chose to
  // remove during that review — same read-the-whole-array,
  // replace-write-it-back approach as updateInProgressSessionBlock(), since
  // Firestore has no in-place array-element removal either.
  //
  // removedBlockIds are each block's stable blockId, matched and removed
  // via removeWhere() — NOT removeAt(index), which this used to do
  // (highest-index-first, specifically so removing one wouldn't shift the
  // position of another index still queued in the same pass). That
  // safeguard only ever protected against collisions WITHIN one call to
  // this function; it did nothing about every OTHER already-in-memory
  // reference to a surviving block's now-shifted real position — which is
  // exactly what caused the out-of-range-write/wrong-slot-overwrite bugs
  // this whole system had. Removing by id sidesteps the position-shift
  // problem entirely: a block's id is meaningless as a position, so
  // nothing about removal can ever invalidate another block's identity.
  //
  // Returns whether the write actually succeeded (still fails soft — logs,
  // doesn't throw, matching updateInProgressSessionBlock()'s convention
  // that a stray/late call after the session was already
  // finalized/abandoned shouldn't crash the caller) so
  // gym_session_screen.dart's caller can retry on a transient failure
  // instead of silently treating a dropped write as a successful
  // dismissal.
  // ---------------------------------------------------------------------------
  Future<bool> dismissInjuryReview(
    String uid,
    String sessionRunId,
    List<String> removedBlockIds,
  ) async {
    final docRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .doc(sessionRunId);
    try {
      final doc = await docRef.get();
      if (!doc.exists) {
        debugPrint('dismissInjuryReview: no such session $sessionRunId');
        return false;
      }
      final rawBlocks = doc.data()?['blocks'];
      final blocks = rawBlocks is List
          ? rawBlocks.map((b) => Map<String, dynamic>.from(b as Map)).toList()
          : <Map<String, dynamic>>[];
      blocks.removeWhere((b) => removedBlockIds.contains(b['blockId']));
      await docRef.update({
        'blocks': blocks,
        'injuryReviewDismissed': true,
      });
      return true;
    } catch (e) {
      debugPrint('dismissInjuryReview error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Reads inProgressSessions/{sessionRunId} and returns its data, or null if
  // missing or on any read error (fail-soft, logs per this file's
  // convention). Used to resume a plan session's exercise/tick state (see
  // gym_session_screen.dart's _hydrateFromInProgressSession) and to recover
  // planId/dayIndex for a screen further down the flow that wasn't itself
  // threaded them directly (see mid_plan_cardio_complete_screen.dart) —
  // createInProgressSession() already stores both on this same doc.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getInProgressSession(
    String uid,
    String sessionRunId,
  ) async {
    try {
      final doc = await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(_inProgressSessions)
          .doc(sessionRunId)
          .get();
      if (!doc.exists) {
        debugPrint('getInProgressSession: no such session $sessionRunId');
        return null;
      }
      return doc.data();
    } catch (e) {
      debugPrint('getInProgressSession error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Finalizes an in-progress session into a single combined
  // sessions/{auto-id} document (mirroring saveGymSession/saveCardioSession's
  // existing schema), then deletes the inProgressSessions/{sessionRunId}
  // doc. Throws a StateError only if the session doc itself is missing —
  // a genuine precondition violation. Does NOT require every block to be
  // done: finalizes whatever's actually done (see doneBlocks below) and
  // silently drops nothing-yet-done blocks from the output, since tapping
  // "Finish Session"/"Finish" before completing every planned block is the
  // common case, not a rare edge case — the previous "must be fully done or
  // throw" gate meant every completed block's data (and any already-done
  // cardio blocks) got silently dropped by callers falling back to the
  // legacy standalone save path instead, whenever the user didn't finish
  // everything.
  //
  // type is derived from composition: 'gym' (only non-cardio blocks),
  // 'cardio' (only cardio blocks), or 'combined' (both) — sessions/
  // {sessionId} previously had no shape for a session containing both
  // block types, which meant a session with more than one cardio block
  // silently lost every cardio block after the first (only one block's
  // fields could be promoted to the top level). For type:'combined', every
  // cardio block is preserved as its own entry in a new `cardioBlocks`
  // array field instead of being promoted to the top level — none dropped,
  // regardless of how many there are. Pure 'gym' and pure 'cardio' output
  // is unchanged from before this: 'cardio' still promotes the FIRST (only)
  // cardio block's fields to the top level, matching saveCardioSession's
  // own shape.
  //
  // durationSeconds/caloriesBurned are summed across ALL blocks (gym and
  // cardio alike) from whatever each block's blockData happened to contain
  // when marked done via updateInProgressSessionBlock — since no screen yet
  // writes real per-block result data (durationSeconds, caloriesBurned,
  // distanceMeters, etc.) into blockData (wiring is explicitly out of this
  // task's scope), these currently total 0 for any block that was only
  // marked done without that data attached.
  // ---------------------------------------------------------------------------
  Future<({String sessionId, List<Map<String, dynamic>> newlyEarnedBadges})>
      finalizeInProgressSession(
    String uid,
    String sessionRunId,
  ) async {
    final docRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .doc(sessionRunId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError(
          'finalizeInProgressSession: no such session $sessionRunId');
    }
    final gamificationConfig = await getGamificationConfig();
    final data = doc.data() ?? {};
    final rawBlocks = data['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.map((b) => Map<String, dynamic>.from(b as Map)).toList()
        : <Map<String, dynamic>>[];

    // Cardio blocks: completion is genuinely all-or-nothing, so the
    // existing block-level done == true gate is semantically correct here
    // and stays unchanged.
    final cardioBlocks =
        blocks.where((b) => b['isCardio'] == true && b['done'] == true).toList();
    final hasCardio = cardioBlocks.isNotEmpty;

    // Gym blocks: a block's own 'done' flag means "every set on this
    // exercise is done" — partial completion (some sets done, some not) is
    // the normal case, not an edge case. So every gym block is passed
    // through here regardless of its own done flag; the per-set extraction
    // loop below already correctly filters to just the done sets within
    // each exercise and skips an exercise entirely only if doneSets ends up
    // empty. Pre-filtering by block-level done here would silently drop
    // any exercise that isn't 100% complete before that loop ever runs.
    final gymBlocks = blocks.where((b) => b['isCardio'] != true).toList();

    final List<Map<String, dynamic>> cleanedExercises = [];
    int totalSets = 0;
    double totalVolume = 0.0;
    int flaggedSetCount = 0;
    // One bulk lookup for every gym exercise in this session, rather than a
    // separate getExerciseDetail() collection scan per exercise — see
    // getExerciseBoundsForExercises()'s own doc comment.
    final gymExerciseNames = gymBlocks
        .map((b) => b['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final exerciseBounds = await getExerciseBoundsForExercises(gymExerciseNames);
    // Plan-linked session — this doc's own createdAt (a server timestamp
    // written by createInProgressSession() when the session was first
    // loaded) is a real, trustworthy reference point for even the whole
    // session's true first set — see _computeSessionTimingFlags()'s own
    // doc comment. Already deserializes as a Timestamp on read-back
    // (unlike saveGymSession()'s in-memory sessionData, which is never
    // round-tripped through Firestore first).
    final rawCreatedAt = data['createdAt'];
    final sessionStartAnchor =
        rawCreatedAt is Timestamp ? rawCreatedAt.toDate() : null;
    final timingFlagsByExercise = _computeSessionTimingFlags(
      gymBlocks,
      sessionStartAnchor,
      minSetTransitionSeconds: _configNum(
              gamificationConfig,
              ['gymTiming', 'minSetTransitionSeconds'],
              _kFallbackMinSetTransitionSeconds)
          .toDouble(),
      minSecondsPerRep: _configNum(gamificationConfig,
              ['gymTiming', 'minSecondsPerRep'], _kFallbackMinSecondsPerRep)
          .toDouble(),
    );

    for (var ei = 0; ei < gymBlocks.length; ei++) {
      final e = gymBlocks[ei];
      final sets = e['sets'];
      if (sets is! List) continue;
      final bounds = exerciseBounds[e['name'] as String? ?? ''];
      final flaggedTimingIndices = timingFlagsByExercise[ei];

      final List<Map<String, dynamic>> doneSets = [];
      for (var i = 0; i < sets.length; i++) {
        final s = sets[i];
        if (s is! Map || s['done'] != true) continue;
        final kg = double.tryParse(s['kg']?.toString() ?? '');
        final reps = int.tryParse(s['reps']?.toString() ?? '');

        // Same treatment as saveGymSession()'s identical loop — a flagged
        // set is still recorded exactly as entered (real kg/reps/
        // completedAt, plus its flag) but excluded from totalSets/
        // totalVolume (and therefore xpEarned/caloriesBurned below).
        final flaggedTiming = flaggedTimingIndices.contains(i);
        final flaggedBounds = _isBoundsFlagged(kg, reps, bounds);
        if (flaggedTiming || flaggedBounds) {
          flaggedSetCount++;
        } else {
          totalSets++;
          totalVolume += (kg ?? 0) * (reps ?? 0);
        }

        doneSets.add({
          'kg': kg,
          'reps': reps,
          'done': true,
          'completedAt': _normalizeSetCompletedAt(s['completedAt']),
          if (flaggedTiming) 'flaggedTiming': true,
          if (flaggedBounds) 'flaggedBounds': true,
        });
      }
      if (doneSets.isNotEmpty) {
        cleanedExercises.add({
          'name': e['name'],
          'muscle': e['muscle'],
          'sets': doneSets,
        });
      }
    }

    // hasGym reflects whether any exercise actually ended up with a
    // completed set (post per-set extraction) — not the block-level done
    // flag — otherwise a combined session with only partially-done gym
    // exercises would incorrectly resolve to type:'cardio' below.
    final hasGym = cleanedExercises.isNotEmpty;
    // Defaults to 'gym' whenever there's no cardio — including the
    // zero-done-blocks edge case (hasGym and hasCardio both false) —
    // matching saveGymSession()'s own existing precedent, which
    // unconditionally writes type:'gym' even with zero completed sets,
    // rather than rejecting or inventing new handling for that case.
    final type = hasGym && hasCardio
        ? 'combined'
        : (hasCardio ? 'cardio' : 'gym');

    int durationSeconds = 0;
    for (final b in [...gymBlocks, ...cardioBlocks]) {
      durationSeconds += (b['durationSeconds'] as num?)?.toInt() ?? 0;
    }
    // Gym blocks never carry their own caloriesBurned or durationSeconds
    // field (see gym_session_screen.dart's _syncBlockDone blockData shape —
    // only name/muscle/restTime/sets), so the old `caloriesBurned +=
    // b['caloriesBurned']` loop above always added 0 for every gym block —
    // a combined session's total silently excluded the gym portion
    // entirely. Estimated here instead via the same _estimateGymCalories()
    // formula saveGymSession() uses — that formula no longer takes a
    // duration signal at all (see its own doc comment), so the lack of a
    // reliable per-gym-block duration here no longer matters either way.
    // Cardio blocks DO carry their own caloriesBurned (computed
    // client-side by the outdoor/indoor cardio screens before being synced
    // here) — summed as before, unchanged.
    final profile = await getUserProfile(uid);
    final weightKg =
        double.tryParse(profile?['weightKg']?.toString() ?? '70') ?? 70.0;
    final gymCaloriesBurned = hasGym
        ? await _estimateGymCalories(
            weightKg: weightKg,
            totalSets: totalSets,
            totalVolume: totalVolume,
          )
        : 0;
    final cardioCaloriesBurned = cardioBlocks.fold<int>(
      0,
      (acc, b) => acc + ((b['caloriesBurned'] as num?)?.toInt() ?? 0),
    );
    final caloriesBurned = gymCaloriesBurned + cardioCaloriesBurned;
    final xpEarned = _computeGymXp(totalSets, gamificationConfig) +
        cardioBlocks.fold<int>(0, (acc, b) {
          final cals = (b['caloriesBurned'] as num?)?.toInt() ?? 0;
          return acc + _computeCardioXp(cals, gamificationConfig);
        });

    final planId = data['planId'] as String? ?? '';
    final dayIndex = data['dayIndex'];

    // Real routine name (e.g. "Jason babo") instead of the generic
    // placeholder — same getPlan() lookup gym_session_screen.dart's own
    // _hydrateFromInProgressSession() already uses for display. Fails soft:
    // any error, a missing doc, or a missing/empty name field all fall back
    // to today's exact 'Plan Day $dayIndex' string rather than throwing —
    // a cosmetic session-name lookup shouldn't be able to block finalizing
    // an otherwise-complete session.
    var sessionName = 'Plan Day $dayIndex';
    var planIsCustom = false;
    if (planId.isNotEmpty) {
      try {
        final plan = await getPlan(planId);
        final planName = plan?['name'] as String?;
        if (planName != null && planName.isNotEmpty) {
          sessionName = '$planName Day $dayIndex';
        }
        planIsCustom = plan?['isCustom'] as bool? ?? false;
      } catch (_) {}
    }

    final sessionDoc = <String, dynamic>{
      'type': type,
      'sessionName': sessionName,
      'planIsCustom': planIsCustom,
      'planId': planId,
      'date': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'durationSeconds': durationSeconds,
      'caloriesBurned': caloriesBurned,
      'xpEarned': xpEarned,
      'isManuallyLogged': false,
      'exercises': cleanedExercises,
      'totalSets': totalSets,
      'totalVolume': totalVolume,
      'flaggedSetCount': flaggedSetCount,
    };

    if (type == 'combined') {
      // One entry per cardio block, in order — every cardio block is
      // preserved (unlike the pure-'cardio' branch below, which only has
      // room for one cardio block's fields at the top level). Only fields
      // actually present on that block's blockData are copied over —
      // nothing is invented for a field that isn't there.
      const cardioFieldKeys = [
        'activity',
        'mode',
        'distanceMeters',
        'durationSeconds',
        'caloriesBurned',
        'avgHeartRate',
        'maxHeartRate',
        'route',
        'elevationGainMeters',
        'photoBase64',
        'mapSnapshotBase64',
        'notes',
        'name',
      ];
      sessionDoc['cardioBlocks'] = cardioBlocks.map((b) {
        final entry = <String, dynamic>{'done': true};
        for (final key in cardioFieldKeys) {
          if (b.containsKey(key) && b[key] != null) {
            entry[key] = b[key];
          }
        }
        return entry;
      }).toList();
    } else {
      // Pure 'gym' or pure 'cardio' — unchanged from before: promote the
      // FIRST cardio block's fields (if any) to the top level. Only ever
      // relevant for type:'cardio' here, since type:'gym' implies
      // cardioBlocks is empty.
      final firstCardio = cardioBlocks.isNotEmpty ? cardioBlocks.first : null;
      final cardioActivity = firstCardio?['cardioActivity'] as String? ??
          firstCardio?['activity'] as String?;
      final cardioMode = firstCardio?['mode'] as String?;
      final distanceMeters =
          (firstCardio?['distanceMeters'] as num?)?.toDouble();
      final avgHeartRate = (firstCardio?['avgHeartRate'] as num?)?.toDouble();
      final maxHeartRate = (firstCardio?['maxHeartRate'] as num?)?.toDouble();
      final elevationGainMeters =
          (firstCardio?['elevationGainMeters'] as num?)?.toDouble();
      final route = firstCardio?['route'];
      // These two were previously missing from this promotion list, unlike
      // the 'combined' branch above (which copies every cardioFieldKeys
      // entry, including these) — a pure-cardio plan-linked session lost
      // its map snapshot/photo on finalize even though
      // updateInProgressSessionBlock() had already saved them onto the
      // block. Promoted the same way as route/distanceMeters below.
      final photoBase64 = firstCardio?['photoBase64'] as String?;
      final mapSnapshotBase64 = firstCardio?['mapSnapshotBase64'] as String?;

      if (cardioActivity != null) sessionDoc['activity'] = cardioActivity;
      if (cardioMode != null) sessionDoc['mode'] = cardioMode;
      if (distanceMeters != null) {
        sessionDoc['distanceMeters'] = distanceMeters;
      }
      if (avgHeartRate != null) sessionDoc['avgHeartRate'] = avgHeartRate;
      if (maxHeartRate != null) sessionDoc['maxHeartRate'] = maxHeartRate;
      if (elevationGainMeters != null) {
        sessionDoc['elevationGainMeters'] = elevationGainMeters;
      }
      if (route != null) sessionDoc['route'] = route;
      if (photoBase64 != null) sessionDoc['photoBase64'] = photoBase64;
      if (mapSnapshotBase64 != null) {
        sessionDoc['mapSnapshotBase64'] = mapSnapshotBase64;
      }
    }

    final ref = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .add(sessionDoc);

    await docRef.delete();

    // Previously missing entirely for this session type (plan-linked
    // gym/cardio/combined finishes) — xpEarned was computed and stored on
    // the session doc above but never actually credited to the user's
    // totalXp/level (see addXpToUser()'s own doc comment for what it
    // writes), and badges could never be checked after these session types
    // either. Matches gym_session_screen.dart's standalone finish flow,
    // which calls both right after its own session write.
    await addXpToUser(uid, xpEarned);
    await saveXpEvent(uid, {
      'amount': xpEarned,
      'reason': 'Completed $sessionName',
      'type': type,
    });
    final newlyEarnedBadges = await checkAndAwardBadges(uid);
    return (sessionId: ref.id, newlyEarnedBadges: newlyEarnedBadges);
  }

  // ---------------------------------------------------------------------------
  // Deletes an abandoned/cancelled in-progress session. Simple delete, no
  // completion checks — unlike finalizeInProgressSession.
  // ---------------------------------------------------------------------------
  Future<void> deleteInProgressSession(
    String uid,
    String sessionRunId,
  ) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .doc(sessionRunId)
        .delete();
  }

  // ---------------------------------------------------------------------------
  // Returns the sessionRunId (doc id) of an existing in-progress session for
  // this exact planId+dayIndex combination, or null if none exists. A doc
  // only ever exists in this subcollection while genuinely unfinished —
  // finalizeInProgressSession() deletes it the moment it's finalized (see
  // that method) — so any doc found here is, by construction, still a
  // genuinely resumable/abandoned session. Used by the pre-Start discovery
  // step (see widgets/session_resume_prompt.dart) so Home/Plan Detail/Plan
  // Schedule can offer Resume vs. Start Over instead of silently creating a
  // new doc alongside an already-orphaned one. Two equality-only filters
  // (planId, dayIndex) — no composite index required, Firestore's automatic
  // single-field indexes already cover this. limit(1): at most one
  // in-progress session should ever exist per planId+dayIndex per user in
  // practice, and this discovery step is exactly what's meant to keep it
  // that way going forward. Fails soft (logs, returns null) on any error,
  // matching this file's existing convention.
  // ---------------------------------------------------------------------------
  Future<String?> findInProgressSessionRunId(
    String uid,
    String planId,
    int dayIndex,
  ) async {
    try {
      final snapshot = await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(_inProgressSessions)
          .where('planId', isEqualTo: planId)
          .where('dayIndex', isEqualTo: dayIndex)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      return snapshot.docs.first.id;
    } catch (e) {
      debugPrint('findInProgressSessionRunId error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Reads inProgressSessions/{sessionRunId} and returns whether every block
  // in blocks[] has done == true. Fails soft (logs, returns false) on any
  // read error or missing doc — matching updateInProgressSessionBlock's own
  // fail-soft convention. A caller routing on this (e.g. a cardio finish
  // handler deciding whether to show the mid-plan-cardio-complete screen or
  // finalize) is safe either way on a transient failure: false just routes
  // to "more blocks remain", nothing here writes, so no progress is lost
  // and the user can still finish normally once connectivity recovers.
  // ---------------------------------------------------------------------------
  Future<bool> isInProgressSessionFullyDone(
    String uid,
    String sessionRunId,
  ) async {
    try {
      final doc = await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(_inProgressSessions)
          .doc(sessionRunId)
          .get();
      if (!doc.exists) {
        debugPrint('isInProgressSessionFullyDone: no such session $sessionRunId');
        return false;
      }
      final rawBlocks = doc.data()?['blocks'];
      if (rawBlocks is! List) return false;
      return rawBlocks.every((b) => b is Map && b['done'] == true);
    } catch (e) {
      debugPrint('isInProgressSessionFullyDone error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Fetches approved and visible business partner profiles.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getBusinessPartners() async {
    final snap = await _db
        .collection(Collections.businessPartners)
        .where('isApproved', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .get();
    return snap.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Fetches a single businessPartners/{uid} doc regardless of isApproved/
  // isVisible — unlike getBusinessPartners() (which only returns
  // already-approved, publicly-visible profiles), this is used by the
  // coach-facing side to check the CALLER's own application status
  // (pending vs approved), so it must be able to read a not-yet-approved
  // doc. Returns null if no application exists for this uid.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getBusinessPartnerProfile(String uid) async {
    final doc =
        await _db.collection(Collections.businessPartners).doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  // ---------------------------------------------------------------------------
  // Registers the current user as a coach applicant — writes
  // businessPartners/{uid} with isApproved/isVisible both false (matching
  // getBusinessPartners()'s existing read filter exactly, so a separate
  // admin-approval dashboard built against this same collection can flip
  // both to true later without this needing to change) and sets
  // role: 'coach' on the user's own doc. Batched so both writes succeed
  // or fail together — a coach doc with no matching role, or vice versa,
  // would leave the app unable to consistently decide which UI to show.
  // ---------------------------------------------------------------------------
  Future<void> registerAsCoach({
    required String uid,
    required String name,
    required String type,
    required String bio,
    required String experience,
    String? email,
    // Firebase Storage download URLs for credential documents (see
    // storage_service.dart) — full-resolution, not base64, so admin
    // review can actually read fine print on a certificate. Optional:
    // an applicant can submit without one, though the UI encourages it.
    // The just-merged admin dashboard's adminListBusinessPartners
    // function spreads the whole businessPartners doc generically, so
    // this field reaches it with no Cloud Function changes needed — the
    // React UI itself doesn't render it yet (out of this app's scope,
    // that's admin UI).
    List<String>? credentialUrls,
  }) async {
    final batch = _db.batch();

    final partnerRef = _db.collection(Collections.businessPartners).doc(uid);
    batch.set(partnerRef, {
      'name': name,
      'type': type,
      'bio': bio,
      'experience': experience,
      if (email != null && email.isNotEmpty) 'email': email,
      if (credentialUrls != null && credentialUrls.isNotEmpty)
        'credentialUrls': credentialUrls,
      'isApproved': false,
      'isVisible': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final userRef = _db.collection(Collections.users).doc(uid);
    batch.set(userRef, {'role': 'coach'}, SetOptions(merge: true));

    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // "Request as my coach" from find_professional_screen.dart — writes
  // coachRequests/{autoId}, top-level (not a users/{uid} subcollection
  // like friendRequests/sentFriendRequests, per this collection's own
  // scoped shape). clientDisplayName is denormalized onto the request the
  // same way sendFriendRequest() denormalizes the sender's own name —
  // lets the coach dashboard's request list show who's asking without an
  // extra per-request profile read.
  // ---------------------------------------------------------------------------
  Future<void> sendCoachRequest({
    required String clientUid,
    required String clientDisplayName,
    required String coachUid,
  }) async {
    await _db.collection(Collections.coachRequests).add({
      'clientUid': clientUid,
      'clientDisplayName': clientDisplayName,
      'coachUid': coachUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Live stream of a coach's own PENDING incoming requests, for
  // coach_dashboard_screen.dart's request list. Sorted client-side
  // (newest first) rather than via an orderBy clause, so this stays a
  // plain two-equality-filter query — Firestore auto-indexes that
  // without needing a composite index, unlike adding orderBy on a third
  // field would.
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getCoachRequestsStream(String coachUid) {
    return _db
        .collection(Collections.coachRequests)
        .where('coachUid', isEqualTo: coachUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
      final requests =
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      requests.sort((a, b) {
        final aTs = a['createdAt'] as Timestamp?;
        final bTs = b['createdAt'] as Timestamp?;
        if (aTs == null || bTs == null) return 0;
        return bTs.compareTo(aTs);
      });
      return requests;
    });
  }

  // ---------------------------------------------------------------------------
  // A coach's current client list, for coach_dashboard_screen.dart.
  // coachClients/{coachUid}_{clientUid} is top-level with a composite doc
  // id (not a users/{uid} subcollection like friends/), so listing a
  // coach's clients queries the coachUid field rather than a
  // subcollection read.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCoachClients(String coachUid) async {
    final snap = await _db
        .collection(Collections.coachClients)
        .where('coachUid', isEqualTo: coachUid)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ---------------------------------------------------------------------------
  // Accepts a pending coach request — mirrors acceptFriendRequest()'s
  // shape: creates the mirrored relationship doc (coachClients here,
  // instead of a two-sided friends/ write, since this relationship is
  // asymmetric — only the coach side ever queries "my clients"), deletes
  // the resolved request, and notifies the client. clientDisplayName is
  // fetched fresh here (rather than trusting the possibly-stale one
  // already denormalized on the request doc) since this is the
  // authoritative write moment for the new coachClients doc — reads
  // publicProfiles/{clientUid}, NOT getUserProfile()/users/{clientUid}:
  // this runs on the COACH's session, and users/{uid} is locked to
  // owner-only reads, so a getUserProfile(clientUid) call here silently
  // PERMISSION_DENIED the whole batch every time (confirmed via
  // "Listen for Query(target=Query(users/{clientUid}...)) failed:
  // PERMISSION_DENIED" in the Firestore debug log) — the client's own
  // devices could accept fine in theory, but a coach accepting someone
  // else's request never could, which is exactly the "works for one
  // request, fails for another" symptom this traced back to.
  // ---------------------------------------------------------------------------
  Future<void> acceptCoachRequest({
    required String coachUid,
    required String coachDisplayName,
    required String clientUid,
    required String requestId,
  }) async {
    final clientProfile = await getPublicProfile(clientUid);
    final clientDisplayName =
        (clientProfile?['displayName'] as String?)?.trim();

    final batch = _db.batch();

    final clientRef =
        _db.collection(Collections.coachClients).doc('${coachUid}_$clientUid');
    batch.set(clientRef, {
      'coachUid': coachUid,
      'clientUid': clientUid,
      if (clientDisplayName != null && clientDisplayName.isNotEmpty)
        'clientDisplayName': clientDisplayName,
      // Denormalized here (not just clientDisplayName) so
      // getCoachPlansForClient() can label a coach's plans with their
      // name from this one doc, without a separate per-coach profile
      // read from the client's session.
      'coachDisplayName': coachDisplayName,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final requestRef = _db.collection(Collections.coachRequests).doc(requestId);
    batch.delete(requestRef);

    final notificationRef = _db
        .collection(Collections.users)
        .doc(clientUid)
        .collection(Collections.notifications)
        .doc();
    batch.set(notificationRef, {
      'type': 'coach_request_accepted',
      'fromUid': coachUid,
      'fromDisplayName': coachDisplayName,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } catch (e) {
      // Kept deliberately (not just for this investigation) — a
      // permission-denied here is otherwise easy to misdiagnose as a
      // coachRequests/coachClients rules bug rather than the actual
      // cross-user users/{uid} read it almost always turns out to be.
      debugPrint('[acceptCoachRequest] batch commit FAILED: coachUid=$coachUid '
          'clientUid=$clientUid requestId=$requestId error=$e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Declines a pending coach request — deletes it silently, matching
  // declineFriendRequest()'s own precedent (no notification, no other
  // side effect).
  // ---------------------------------------------------------------------------
  Future<void> declineCoachRequest(String requestId) async {
    await _db.collection(Collections.coachRequests).doc(requestId).delete();
  }

  // ---------------------------------------------------------------------------
  // Plans created by any coach this client has an ACCEPTED relationship
  // with (a coachClients doc exists for them), for explore_screen.dart's
  // "Coach [Name]'s Plans" section — separate from a coach's own
  // ordinary personal plans, which never carry isCoachPlan at all.
  //
  // Filters isCoachPlan==true plans down to this client's own coach(es)
  // CLIENT-SIDE rather than adding a second `where('createdBy', whereIn:
  // ...)` clause — combining whereIn with another equality filter would
  // need a composite index deployed alongside this change; the coach-
  // plan corpus is small enough (this is a small in-app coaching
  // feature, not a public marketplace) that fetching all of them and
  // filtering in Dart is simpler and avoids that extra deploy step.
  //
  // Each returned plan is denormalized with 'coachDisplayName' (sourced
  // from the matching coachClients doc, not a second profile read) so
  // the UI can group/label by coach without an extra round-trip.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCoachPlansForClient(
      String clientUid) async {
    final relationSnap = await _db
        .collection(Collections.coachClients)
        .where('clientUid', isEqualTo: clientUid)
        .get();
    if (relationSnap.docs.isEmpty) return [];

    final coachNamesByUid = <String, String>{};
    for (final doc in relationSnap.docs) {
      final data = doc.data();
      final coachUid = data['coachUid'] as String?;
      if (coachUid == null) continue;
      coachNamesByUid[coachUid] =
          (data['coachDisplayName'] as String?) ?? 'Your Coach';
    }
    if (coachNamesByUid.isEmpty) return [];

    final plansSnap = await _db
        .collection(Collections.plans)
        .where('isCoachPlan', isEqualTo: true)
        .get();

    return plansSnap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where((p) => coachNamesByUid.containsKey(p['createdBy']))
        .map((p) => {
              ...p,
              'coachDisplayName': coachNamesByUid[p['createdBy']],
            })
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Save a weight entry for today to users/{uid}/weightLogs/{date}.
  // Uses the date string as the doc id so one entry per day is enforced.
  // ---------------------------------------------------------------------------
  Future<void> saveWeightEntry(String uid, double weightKg) async {
    final date = DateTime.now()
        .toString()
        .substring(0, 10); // yyyy-MM-dd
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection('weightLogs')
        .doc(date)
        .set({
      'weightKg': weightKg,
      'date': date,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Get all weight log entries ordered by date ascending.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getWeightLogs(String uid) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection('weightLogs')
        .orderBy('date', descending: false)
        .get();
    return snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Stream of weight logs for live updates, ordered by date ascending.
  // Bounded to the most recent [limit] entries (previously fully
  // unbounded) — queries descending + limit so the cap always keeps the
  // NEWEST entries (never silently drops the true latest log, which
  // progress_screen.dart's summary row and log-weight prefill both rely
  // on), then reverses back to ascending so every existing caller's
  // "first = oldest, last = newest" assumption still holds. 400 comfortably
  // covers a full year of daily logging (the writer enforces at most one
  // entry per calendar day — see saveWeightEntry() above) plus headroom.
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getWeightLogsStream(
    String uid, {
    int limit = 400,
  }) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection('weightLogs')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList()
            .reversed
            .toList());
  }

  // ---------------------------------------------------------------------------
  // Saves a logged meal (from AI photo scan or manual text description) to
  // users/{uid}/nutritionLogs/{auto-id}. Uses add() so each call creates a
  // unique document, matching the pattern used by saveGymSession.
  // ---------------------------------------------------------------------------
  Future<void> saveNutritionLog(
    String uid, {
    required String foodName,
    required int calories,
    required String source, // 'scan' or 'manual'
    int? proteinG,
    int? carbsG,
    int? fatG,
    String? confidence, // 'high' | 'medium' | 'low'
    String? notes,
    // Only ever present for a photo-scanned meal (nutrition_scan_screen
    // .dart's _logMeal() only resolves one when _mode == _Mode.scan) —
    // text-described meals simply omit it, same optional-field pattern as
    // notes/confidence above.
    String? imageBase64,
  }) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.nutritionLogs)
        .add({
      'foodName': foodName,
      'calories': calories,
      'source': source,
      'proteinG': proteinG,
      'carbsG': carbsG,
      'fatG': fatG,
      'confidence': confidence,
      'notes': notes,
      if (imageBase64 != null && imageBase64.isNotEmpty)
        'imageBase64': imageBase64,
      'date': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Returns all meals logged today (since local midnight) for users/{uid},
  // newest first.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getTodaysNutritionLogs(String uid) async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.nutritionLogs)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(midnight))
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Sums calories across all meals logged today (since local midnight) for
  // users/{uid}. Returns 0 if no meals have been logged yet.
  // ---------------------------------------------------------------------------
  Future<int> getTodaysNutritionCalories(String uid) async {
    final logs = await getTodaysNutritionLogs(uid);
    int total = 0;
    for (final log in logs) {
      total += (log['calories'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // Sums protein/carbs/fat across all meals logged today (since local
  // midnight) for users/{uid} — same source data/pattern as
  // getTodaysNutritionCalories, just three fields instead of one.
  // Informational only (Home's macro display has no goal to compare
  // against), so this returns raw totals with no percentage/goal math.
  // ---------------------------------------------------------------------------
  Future<({int proteinG, int carbsG, int fatG})> getTodaysNutritionMacros(
      String uid) async {
    final logs = await getTodaysNutritionLogs(uid);
    int protein = 0;
    int carbs = 0;
    int fat = 0;
    for (final log in logs) {
      protein += (log['proteinG'] as num?)?.toInt() ?? 0;
      carbs += (log['carbsG'] as num?)?.toInt() ?? 0;
      fat += (log['fatG'] as num?)?.toInt() ?? 0;
    }
    return (proteinG: protein, carbsG: carbs, fatG: fat);
  }

  // ---------------------------------------------------------------------------
  // Returns a user's full logged-meal history for users/{uid} (no "since
  // midnight" filter, unlike getTodaysNutritionLogs), newest first — used
  // by the Progress screen's Nutrition tab.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getNutritionLogsHistory(
    String uid, {
    int limit = 100,
  }) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.nutritionLogs)
        .orderBy('date', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FEED / POSTS
  // A real, shared Firestore feed (top-level `posts` collection) so a
  // logged meal can be posted and seen by other users of the app — not a
  // mock. NOTE: this app does not yet have a real friend-relationship
  // system (Club's "Friends" tab is currently static mock data), so this
  // feed is app-wide for now, newest first. Once real friend
  // relationships exist, swap the query below for a `where('uid', whereIn:
  // friendUids)` filter to scope it to friends only.
  // ═══════════════════════════════════════════════════════════════════════

  // ---------------------------------------------------------------------------
  // Creates a feed post. Two shapes share this collection, picked by `type`:
  //   'meal'    (default) — foodName/calories/macros/imageBase64, posted
  //             from nutrition_scan_screen.dart.
  //   'workout' — sessionName/isCardio/cardioActivity/elapsedSeconds/
  //             totalSets/volume (calories = burned), posted from
  //             post_session_summary_screen.dart.
  // imageBase64 is optional (omit for text-described meals with no photo,
  // and always for workout posts). Denormalizes authorName/authorInitial
  // onto the post itself so the feed can render without an extra read per
  // post.
  // ---------------------------------------------------------------------------
  Future<void> createFeedPost({
    required String uid,
    required String authorName,
    required int calories,
    String type = 'meal',
    String? foodName,
    int? proteinG,
    int? carbsG,
    int? fatG,
    String? imageBase64,
    String? caption,
    String? sessionName,
    bool? isCardio,
    String? cardioActivity,
    int? elapsedSeconds,
    int? totalSets,
    double? volume,
    // Denormalized the same way authorName/authorInitial already are, so
    // FeedPostCard can render the poster's real photo without an extra
    // per-post profile read. Sourced from the poster's own users/{uid}
    // .photoBase64 at post-creation time by each call site — this method
    // itself doesn't look it up, matching how authorName is already
    // passed in rather than fetched here.
    String? authorPhotoBase64,
  }) async {
    final initial =
        authorName.trim().isNotEmpty ? authorName.trim()[0].toUpperCase() : '?';

    final postData = {
      'uid': uid,
      'authorName': authorName,
      'authorInitial': initial,
      if (authorPhotoBase64 != null && authorPhotoBase64.isNotEmpty)
        'authorPhotoBase64': authorPhotoBase64,
      'type': type,
      'foodName': foodName,
      'calories': calories,
      'proteinG': proteinG,
      'carbsG': carbsG,
      'fatG': fatG,
      'imageBase64': imageBase64,
      'caption': caption,
      'sessionName': sessionName,
      'isCardio': isCardio,
      'cardioActivity': cardioActivity,
      'elapsedSeconds': elapsedSeconds,
      'totalSets': totalSets,
      'volume': volume,
      'reactionCount': 0,
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    };
    // Diagnostic for the "Post to Feed failing" investigation — a single
    // consolidated line (uid/type/approx payload size) plus an explicit
    // try/catch around the write itself, so a permission-denied failure
    // (security rules) is unambiguously distinguishable in the logs from
    // a null-value/serialization error or a genuine network failure —
    // all three look identical from the caller's point of view otherwise.
    final approxPayloadBytes = postData.entries
        .fold<int>(0, (total, e) => total + '${e.value}'.length);
    debugPrint('[PostToFeed] createFeedPost: uid=$uid type=$type '
        'approxPayloadBytes=$approxPayloadBytes — writing to '
        '${Collections.posts} at ${DateTime.now()}');
    try {
      await _db.collection(Collections.posts).add(postData);
      debugPrint('[PostToFeed] createFeedPost: write succeeded at '
          '${DateTime.now()}');
    } on FirebaseException catch (e, stack) {
      debugPrint('[PostToFeed] createFeedPost: FirebaseException at '
          '${DateTime.now()} — code=${e.code} message=${e.message} '
          '${e.code == 'permission-denied' ? '(LIKELY A SECURITY RULES ISSUE)' : ''}');
      debugPrint('Stack: $stack');
      rethrow;
    } catch (e, stack) {
      debugPrint('[PostToFeed] createFeedPost: non-Firebase exception at '
          '${DateTime.now()}: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  bool _isVisibleFeedPost(Map<String, dynamic> data) {
    return data['isHidden'] != true;
  }

  // ---------------------------------------------------------------------------
  // Live stream of the most recent feed posts, newest first.
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getFeedPostsStream({int limit = 50}) {
    return _db
        .collection(Collections.posts)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .where(_isVisibleFeedPost)
            .toList());
  }

  // ---------------------------------------------------------------------------
  // Deletes a post document. Firestore does not cascade-delete
  // subcollections, so this leaves the post's `reactions`/`comments`
  // subcollections orphaned (unreachable once the parent doc is gone, but
  // not physically removed) — acceptable for FYP scope, but a real cleanup
  // would need a Cloud Function or batched subcollection delete.
  // ---------------------------------------------------------------------------
  Future<void> deletePost(String postId) async {
    await _db.collection(Collections.posts).doc(postId).delete();
  }

  // ---------------------------------------------------------------------------
  // Toggles a 🔥 reaction on a post for the given user (one reaction per
  // user per post — tapping again removes it). Keeps a denormalized
  // reactionCount on the post doc so the feed can show a count without an
  // extra read.
  // ---------------------------------------------------------------------------
  Future<void> toggleReaction(String postId, String uid) async {
    final postRef = _db.collection(Collections.posts).doc(postId);
    final reactionRef = postRef.collection('reactions').doc(uid);
    final existing = await reactionRef.get();

    if (existing.exists) {
      await reactionRef.delete();
      await postRef.update({'reactionCount': FieldValue.increment(-1)});
    } else {
      await reactionRef.set({
        'type': 'fire',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await postRef.update({'reactionCount': FieldValue.increment(1)});
    }
  }

  // ---------------------------------------------------------------------------
  // Whether the given user has already reacted to a post — used to show
  // the reaction button as filled/active.
  // ---------------------------------------------------------------------------
  Stream<bool> hasReactedStream(String postId, String uid) {
    return _db
        .collection(Collections.posts)
        .doc(postId)
        .collection('reactions')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  // ---------------------------------------------------------------------------
  // Adds a comment to a post and increments its denormalized commentCount.
  // authorPhotoBase64 is denormalized onto the comment doc the same way
  // authorPhotoBase64 already is on posts themselves (see createFeedPost) —
  // sourced from the commenter's own users/{uid}.photoBase64 by the caller
  // at comment-creation time, not looked up here.
  // ---------------------------------------------------------------------------
  Future<void> addComment(
    String postId, {
    required String uid,
    required String authorName,
    required String text,
    String? authorPhotoBase64,
  }) async {
    final postRef = _db.collection(Collections.posts).doc(postId);
    await postRef.collection('comments').add({
      'uid': uid,
      'authorName': authorName,
      'text': text,
      if (authorPhotoBase64 != null && authorPhotoBase64.isNotEmpty)
        'authorPhotoBase64': authorPhotoBase64,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await postRef.update({'commentCount': FieldValue.increment(1)});
  }

  // ---------------------------------------------------------------------------
  // Deletes a comment and decrements the post's denormalized commentCount —
  // mirrors addComment's increment.
  // ---------------------------------------------------------------------------
  Future<void> deleteComment(String postId, String commentId) async {
    final postRef = _db.collection(Collections.posts).doc(postId);
    await postRef.collection('comments').doc(commentId).delete();
    await postRef.update({'commentCount': FieldValue.increment(-1)});
  }

  // ---------------------------------------------------------------------------
  // Live stream of comments on a post, oldest first.
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getCommentsStream(String postId) {
    return _db
        .collection(Collections.posts)
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

// ---------------------------------------------------------------------------
  // Live stream of a single user's feed posts, newest first — used by
  // user_profile_screen.dart to show what a profile has posted.
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getUserPostsStream(String uid, {int limit = 50}) {
    return _db
        .collection(Collections.posts)
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .where(_isVisibleFeedPost)
            .toList());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FOLLOWS
  // Top-level `follows` collection, doc id `{followerUid}_{followingUid}` —
  // lets doc existence double as the "is following" check without a query.
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> followUser(String followerUid, String followingUid) async {
    await _db
        .collection(Collections.follows)
        .doc('${followerUid}_$followingUid')
        .set({
      'followerUid': followerUid,
      'followingUid': followingUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unfollowUser(String followerUid, String followingUid) async {
    await _db
        .collection(Collections.follows)
        .doc('${followerUid}_$followingUid')
        .delete();
  }

  Stream<bool> isFollowingStream(String followerUid, String followingUid) {
    return _db
        .collection(Collections.follows)
        .doc('${followerUid}_$followingUid')
        .snapshots()
        .map((doc) => doc.exists);
  }

  // ---------------------------------------------------------------------------
  // Number of users following `uid` — uses Firestore's aggregate count()
  // query (cloud_firestore ^5.4.4 here, well past the 4.9.0 minimum) so the
  // count is computed server-side instead of fetching every follow doc.
  // ---------------------------------------------------------------------------
  Future<int> getFollowerCount(String uid) async {
    final snapshot = await _db
        .collection(Collections.follows)
        .where('followingUid', isEqualTo: uid)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Number of users `uid` is following — same aggregate count() approach.
  // ---------------------------------------------------------------------------
  Future<int> getFollowingCount(String uid) async {
    final snapshot = await _db
        .collection(Collections.follows)
        .where('followerUid', isEqualTo: uid)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FRIENDS / FRIEND REQUESTS / NOTIFICATIONS
  // Mutual-acceptance friend system: a pending request lives at
  // users/{toUid}/friendRequests/{fromUid} until accepted or declined.
  // On accept, both users get a mirrored doc in their own friends
  // subcollection (users/{uid}/friends/{otherUid}).
  // ═══════════════════════════════════════════════════════════════════════

  /// Prefix-searches users by username. Returns uid, displayName,
  /// username for each match. Does not exclude the current user or
  /// existing friends — the UI layer filters those out.
  // Queries publicProfiles rather than users/{uid} — same reasoning as
  // isUsernameTaken() above: a cross-user query users/{uid}'s owner-only
  // rule can't satisfy. Upper bound includes the  suffix (the
  // highest valid Unicode code point) so this is a genuine prefix range
  // (matches "test" -> "testa", "testb", ...) rather than an exact-match-
  // only filter.
  Future<List<Map<String, dynamic>>> searchUsersByUsername(
    String query,
  ) async {
    final snapshot = await _db
        .collection(_publicProfiles)
        .where('username', isGreaterThanOrEqualTo: query)
        .where('username', isLessThanOrEqualTo: '$query')
        .limit(20)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'displayName': data['displayName'],
        'username': data['username'],
        'photoBase64': data['photoBase64'],
      };
    }).toList();
  }

  /// Batched lookup of publicProfiles/{uid}.photoBase64 for a list of uids —
  /// used to enrich rows whose own doc (friends/friendRequests
  /// subcollections) is denormalized once at request/accept time and never
  /// refreshed, so a photo uploaded after that point still shows up without
  /// needing to re-friend. Same 30-value whereIn chunking as
  /// getFriendsLeaderboardStream(). Returns only uids that have a photo set.
  Future<Map<String, String>> getPublicPhotosByUids(List<String> uids) async {
    if (uids.isEmpty) return {};
    final distinctUids = uids.toSet().toList();
    final chunks = <List<String>>[];
    for (var i = 0; i < distinctUids.length; i += 30) {
      final end =
          i + 30 > distinctUids.length ? distinctUids.length : i + 30;
      chunks.add(distinctUids.sublist(i, end));
    }
    final photos = <String, String>{};
    for (final chunk in chunks) {
      final snapshot = await _db
          .collection(_publicProfiles)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final photo = doc.data()['photoBase64'] as String?;
        if (photo != null && photo.isNotEmpty) photos[doc.id] = photo;
      }
    }
    return photos;
  }

  /// Sends a friend request from [fromUid] to [toUid]. Writes the
  /// pending request doc, a notification doc, AND a minimal marker on the
  /// sender's own side (users/{fromUid}/sentFriendRequests/{toUid}) — all
  /// in one batch, so they can never be observed out of sync. The marker
  /// is deliberately minimal ({sentAt}) since its only job is letting the
  /// sender check "did I already send this?" (see hasSentFriendRequest())
  /// without needing to read the recipient's private inbox.
  Future<void> sendFriendRequest(
    String fromUid,
    String fromDisplayName,
    String fromUsername,
    String toUid,
  ) async {
    final batch = _db.batch();

    final requestRef = _db
        .collection(Collections.users)
        .doc(toUid)
        .collection(Collections.friendRequests)
        .doc(fromUid);
    batch.set(requestRef, {
      'fromUid': fromUid,
      'fromDisplayName': fromDisplayName,
      'fromUsername': fromUsername,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final sentRef = _db
        .collection(Collections.users)
        .doc(fromUid)
        .collection(_sentFriendRequests)
        .doc(toUid);
    batch.set(sentRef, {
      'sentAt': FieldValue.serverTimestamp(),
    });

    final notificationRef = _db
        .collection(Collections.users)
        .doc(toUid)
        .collection(Collections.notifications)
        .doc();
    batch.set(notificationRef, {
      'type': 'friend_request',
      'fromUid': fromUid,
      'fromDisplayName': fromDisplayName,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Whether [fromUid] already has a pending friend request sent to
  /// [toUid]. Reads users/{fromUid}/sentFriendRequests/{toUid} — the
  /// sender's OWN marker doc, not the recipient's private friendRequests
  /// inbox (users/{toUid}/friendRequests/{fromUid}), which owner-only
  /// rules correctly deny reading unless the caller IS toUid. This is a
  /// self-scoped read (fromUid is always the caller here), so it's
  /// unconditionally allowed under those same rules.
  Future<bool> hasSentFriendRequest(String toUid, String fromUid) async {
    final doc = await _db
        .collection(Collections.users)
        .doc(fromUid)
        .collection(_sentFriendRequests)
        .doc(toUid)
        .get();
    return doc.exists;
  }

  /// Accepts a pending friend request: removes the request (both the
  /// recipient-side friendRequests doc and the requester's own
  /// sentFriendRequests marker — otherwise the marker would linger
  /// forever, making hasSentFriendRequest() keep reporting "already
  /// sent" for a request that's actually been resolved), writes a
  /// mirrored friends doc on both users, and notifies the requester.
  Future<void> acceptFriendRequest(
    String currentUid,
    String currentDisplayName,
    String currentUsername,
    String requesterUid,
    String requesterDisplayName,
    String requesterUsername,
  ) async {
    final batch = _db.batch();

    final requestRef = _db
        .collection(Collections.users)
        .doc(currentUid)
        .collection(Collections.friendRequests)
        .doc(requesterUid);
    batch.delete(requestRef);

    final sentRef = _db
        .collection(Collections.users)
        .doc(requesterUid)
        .collection(_sentFriendRequests)
        .doc(currentUid);
    batch.delete(sentRef);

    final myFriendRef = _db
        .collection(Collections.users)
        .doc(currentUid)
        .collection(Collections.friends)
        .doc(requesterUid);
    batch.set(myFriendRef, {
      'uid': requesterUid,
      'displayName': requesterDisplayName,
      'username': requesterUsername,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final theirFriendRef = _db
        .collection(Collections.users)
        .doc(requesterUid)
        .collection(Collections.friends)
        .doc(currentUid);
    batch.set(theirFriendRef, {
      'uid': currentUid,
      'displayName': currentDisplayName,
      'username': currentUsername,
      'addedAt': FieldValue.serverTimestamp(),
    });

    final notificationRef = _db
        .collection(Collections.users)
        .doc(requesterUid)
        .collection(Collections.notifications)
        .doc();
    batch.set(notificationRef, {
      'type': 'friend_accepted',
      'fromUid': currentUid,
      'fromDisplayName': currentDisplayName,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Declines a pending friend request — deletes it silently (both the
  /// recipient-side friendRequests doc and the requester's own
  /// sentFriendRequests marker, in one batch, same reasoning as
  /// acceptFriendRequest()'s cleanup above), no notification or other
  /// side effect.
  Future<void> declineFriendRequest(
    String currentUid,
    String requesterUid,
  ) async {
    final batch = _db.batch();

    final requestRef = _db
        .collection(Collections.users)
        .doc(currentUid)
        .collection(Collections.friendRequests)
        .doc(requesterUid);
    batch.delete(requestRef);

    final sentRef = _db
        .collection(Collections.users)
        .doc(requesterUid)
        .collection(_sentFriendRequests)
        .doc(currentUid);
    batch.delete(sentRef);

    await batch.commit();
  }

  /// Live stream of pending friend requests for [uid], newest first.
  Stream<List<Map<String, dynamic>>> getFriendRequestsStream(String uid) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.friendRequests)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'requesterUid': doc.id, ...doc.data()})
            .toList());
  }

  /// Live stream of accepted friends for [uid], alphabetical by name.
  Stream<List<Map<String, dynamic>>> getFriendsStream(String uid) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.friends)
        .orderBy('displayName', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  /// Live stream of the most recent notifications for [uid], newest first.
  Stream<List<Map<String, dynamic>>> getNotificationsStream(String uid) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.notifications)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'notificationId': doc.id, ...doc.data()})
            .toList());
  }

  /// Live, friends-scoped weekly leaderboard combining [uid] and
  /// [friendUids] (the caller already knows its friends list — e.g. from
  /// getFriendsStream — so this method takes it directly rather than
  /// re-fetching it internally, keeping the leaderboard reactive to
  /// friend-list changes if the caller re-invokes it with a new list).
  ///
  /// Firestore's whereIn operator caps at 30 values per query, so the
  /// combined uid list is chunked into groups of <=30 and every chunk's
  /// live .snapshots() stream is combined into one continuously-updating
  /// result. Neither `async` (StreamGroup) nor `rxdart` (combineLatest)
  /// is a declared pubspec.yaml dependency, so this is a small hand-rolled
  /// combine-latest: each chunk keeps its most recent snapshot in
  /// `latest`, and whenever any chunk emits, the merged/filtered/sorted
  /// list is recomputed and pushed out. In practice this will almost
  /// always be a single chunk/query under the hood, since most users
  /// will have far fewer than 30 friends — the chunking exists for
  /// correctness at scale, not because it's expected to trigger often.
  ///
  /// Users who have turned off leaderboardVisible are filtered out,
  /// except [uid]'s own row, which is always included.
  ///
  /// Reads publicProfiles/{uid} rather than users/{uid} — once real
  /// security rules lock users/{uid} to owner-only reads, this whereIn
  /// query (which by definition reads OTHER users' docs) would stop
  /// working entirely against the private collection. publicProfiles only
  /// ever carries the fields extracted below (see _publicProfileFields),
  /// kept in sync by every users/{uid} write site that touches them —
  /// same field names, so the extraction logic here is unchanged.
  Stream<List<Map<String, dynamic>>> getFriendsLeaderboardStream(
    String uid,
    List<String> friendUids,
  ) {
    final allUids = <String>{uid, ...friendUids}.toList();

    final chunks = <List<String>>[];
    for (var i = 0; i < allUids.length; i += 30) {
      final end = i + 30 > allUids.length ? allUids.length : i + 30;
      chunks.add(allUids.sublist(i, end));
    }

    final chunkStreams = chunks
        .map((chunk) => _db
            .collection(_publicProfiles)
            .where(FieldPath.documentId, whereIn: chunk)
            .snapshots())
        .toList();

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    final latest =
        List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.filled(
            chunkStreams.length, const []);
    final subs = <StreamSubscription>[];

    void emit() {
      if (controller.isClosed) return;
      final allDocs = latest.expand((docs) => docs).toList();
      final entries = allDocs.map((doc) {
        final data = doc.data();
        return <String, dynamic>{
          'uid': doc.id,
          'displayName': data['displayName'],
          'username': data['username'],
          'weeklyXp': (data['weeklyXp'] as num?)?.toInt() ?? 0,
          'level': data['level'],
          'leaderboardVisible': data['leaderboardVisible'] as bool? ?? true,
          'lastWeeklyXpUpdate': data['lastWeeklyXpUpdate'],
          'photoBase64': data['photoBase64'],
        };
      }).where((e) {
        final visible = e['leaderboardVisible'] as bool;
        return visible || e['uid'] == uid;
      }).toList();

      // Diagnostic for the "leaderboard still not showing photos"
      // investigation — logs exactly what each entry's publicProfiles doc
      // actually contained for photoBase64 at read time, per uid.
      for (final e in entries) {
        final photo = e['photoBase64'] as String?;
        final photoState = photo == null
            ? 'null (no photoBase64 field on publicProfiles doc)'
            : photo.isEmpty
                ? 'empty string'
                : '<present, ${photo.length} chars>';
        debugPrint('[LeaderboardPhoto] uid=${e['uid']} '
            'displayName=${e['displayName']} photoBase64=$photoState');
      }

      entries.sort((a, b) {
        final xpA = a['weeklyXp'] as int;
        final xpB = b['weeklyXp'] as int;
        if (xpA != xpB) return xpB.compareTo(xpA);
        final tsA = a['lastWeeklyXpUpdate'];
        final tsB = b['lastWeeklyXpUpdate'];
        final millisA = tsA is Timestamp ? tsA.millisecondsSinceEpoch : null;
        final millisB = tsB is Timestamp ? tsB.millisecondsSinceEpoch : null;
        // Missing lastWeeklyXpUpdate = lowest priority in the tiebreak
        // (sorts after any real timestamp) — earlier timestamp wins ties.
        if (millisA == null && millisB == null) return 0;
        if (millisA == null) return 1;
        if (millisB == null) return -1;
        return millisA.compareTo(millisB);
      });

      controller.add(entries);
    }

    for (var i = 0; i < chunkStreams.length; i++) {
      final index = i;
      subs.add(chunkStreams[index].listen((snap) {
        latest[index] = snap.docs;
        emit();
      }, onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
      }));
    }

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };

    return controller.stream;
  }

  /// Marks a single notification as read.
  Future<void> markNotificationRead(String uid, String notificationId) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.notifications)
        .doc(notificationId)
        .update({'read': true});
  }

  /// One-time unread notification count for a simple badge check. Swap
  /// for a stream (mapping snapshot.docs.length) if a live-updating
  /// badge is needed later.
  Future<int> getUnreadNotificationCount(String uid) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.notifications)
        .where('read', isEqualTo: false)
        .get();
    return snapshot.docs.length;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CHALLENGES
  // Individual-goal challenges (challenges/{challengeId}): each participant
  // tracks their OWN progress toward the same shared target — not a pooled
  // total. Admin-created challenges are isGlobal:true (discoverable by
  // anyone, joined directly, managed via Firebase Console the same way
  // Collections.exercises/injuryCategories are — no admin write path
  // exists in this app yet). User-created challenges are always
  // isGlobal:false and invite-only (see createChallenge()).
  //
  // challengeCategories/{categoryId} is read-only reference data from the
  // app's side (admin-managed via Firebase Console/future dashboard,
  // exactly like Collections.exercises/injuryCategories) — its collection
  // name isn't in Collections since that class is intentionally left
  // untouched here; it instead follows this file's own existing precedent
  // of a private collection-name const for things Collections doesn't
  // cover yet (see _planProgress/_inProgressSessions above).
  // ═══════════════════════════════════════════════════════════════════════

  static const _challengeCategories = 'challengeCategories';
  static const _challengeProgressCache = 'progressCache';
  static const _challengeProgressNotifications = 'progressNotifications';

  /// Fetches all challenge categories. Read-only from the app; admin adds/
  /// edits these directly in Firestore. Same fail-soft convention as
  /// getInjuryCategories() — a lookup failure here shouldn't crash
  /// whatever screen is trying to show category choices.
  Future<List<Map<String, dynamic>>> getChallengeCategories() async {
    try {
      final snapshot =
          await _db.collection(_challengeCategories).orderBy('name').get();
      return snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Reads a single challenge doc by id, or null if it doesn't exist.
  /// Same fail-soft convention as getPlan()/getSession() — used by
  /// challenge_detail_screen.dart/challenge_leaderboard_screen.dart, which
  /// only have a challengeId (from a card tap or a route's `extra`) and
  /// need the full doc to render.
  Future<Map<String, dynamic>?> getChallenge(String challengeId) async {
    try {
      final doc =
          await _db.collection(Collections.challenges).doc(challengeId).get();
      if (!doc.exists) return null;
      return {'id': doc.id, ...doc.data()!};
    } catch (_) {
      return null;
    }
  }

  /// Creates a user-made challenge (always private/invite-only — isGlobal
  /// is hardcoded false here; only an admin writing directly via Firebase
  /// Console can ever set isGlobal:true). The creator auto-joins
  /// participantUids; everyone else starts in invitedUids until they
  /// accept. One batch so the challenge doc and every invite notification
  /// succeed or fail together, matching sendFriendRequest()'s pattern.
  Future<String> createChallenge(
    String uid, {
    required String name,
    required String categoryId,
    required String metricType,
    required String unit,
    required double goalValue,
    required DateTime startDate,
    required DateTime endDate,
    List<String> invitedUids = const [],
  }) async {
    final batch = _db.batch();
    final challengeRef = _db.collection(Collections.challenges).doc();

    batch.set(challengeRef, {
      'name': name,
      'categoryId': categoryId,
      'metricType': metricType,
      'unit': unit,
      'goalValue': goalValue,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isGlobal': false,
      'createdBy': uid,
      'participantUids': [uid],
      'invitedUids': invitedUids,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (invitedUids.isNotEmpty) {
      final myProfile = await getUserProfile(uid);
      final myName = myProfile?['displayName'] as String? ?? 'Someone';
      _writeChallengeInviteNotifications(
        batch,
        challengeId: challengeRef.id,
        challengeName: name,
        fromUid: uid,
        fromDisplayName: myName,
        invitedUids: invitedUids,
      );
    }

    await batch.commit();
    return challengeRef.id;
  }

  /// Count of challenges [uid] has created (createdBy == uid). Used to gate
  /// new challenge creation on the free tier (see AppConstants
  /// .freeChallengeLimit).
  ///
  /// Deliberately queries participantUids arrayContains uid (same shape as
  /// getMyChallengesStream() above, filtering createdBy client-side)
  /// instead of where('createdBy', isEqualTo: uid) directly. The original
  /// createdBy-only query was rejected outright by firestore.rules'
  /// /challenges/{challengeId} read rule (`isGlobal==true || uid in
  /// participantUids || uid in invitedUids`) — Firestore denies an ENTIRE
  /// list query, not just individual result docs, whenever the rule can't
  /// be proven to hold for every possible matching document from the
  /// query's own where-clauses alone; createdBy==uid alone doesn't
  /// constrain participantUids/invitedUids/isGlobal at all, even though
  /// every real result would in fact satisfy the rule (the creator is
  /// always auto-added to participantUids at creation). That
  /// PERMISSION_DENIED was getting silently swallowed by
  /// create_challenge_screen.dart's generic `catch (_)`, surfacing only as
  /// "Something went wrong" for every non-premium user on their very
  /// first challenge (0 existing challenges, so this method's result was
  /// needed either way) — confirmed via this exact rule text and the
  /// query's where-clause shape, not by guessing. participantUids
  /// arrayContains uid IS provable against that rule's middle clause
  /// directly, so it isn't rejected; it also needs no new composite index
  /// (a single arrayContains filter with no orderBy uses Firestore's
  /// automatic single-field indexing) and is covered by the same index
  /// getMyChallengesStream() already relies on regardless.
  Future<int> getCreatedChallengeCount(String uid) async {
    final snapshot = await _db
        .collection(Collections.challenges)
        .where('participantUids', arrayContains: uid)
        .get();
    return snapshot.docs.where((d) => d.data()['createdBy'] == uid).length;
  }

  /// Shared notification-writing shape for a challenge_invite — one entry
  /// per invited uid, added to [batch] (not committed here). Used by both
  /// createChallenge() (invites sent at creation time) and
  /// inviteFriendsToChallenge() (invites sent later, from the challenge
  /// detail screen) so the two call sites can never drift into writing
  /// differently-shaped notification docs.
  void _writeChallengeInviteNotifications(
    WriteBatch batch, {
    required String challengeId,
    required String challengeName,
    required String fromUid,
    required String fromDisplayName,
    required List<String> invitedUids,
  }) {
    for (final invitedUid in invitedUids) {
      final notificationRef = _db
          .collection(Collections.users)
          .doc(invitedUid)
          .collection(Collections.notifications)
          .doc();
      batch.set(notificationRef, {
        'type': 'challenge_invite',
        'challengeId': challengeId,
        'challengeName': challengeName,
        'fromUid': fromUid,
        'fromDisplayName': fromDisplayName,
        'read': false,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Invites more friends to an already-existing challenge — adds them to
  /// invitedUids and sends each a challenge_invite notification, via the
  /// same _writeChallengeInviteNotifications() shape createChallenge()
  /// uses. One batch so the invitedUids update and every notification
  /// succeed or fail together. Callers are expected to have already
  /// filtered out uids that are already in participantUids/invitedUids
  /// (arrayUnion alone would just no-op a duplicate, but would still
  /// spam a fresh notification for someone already invited).
  Future<void> inviteFriendsToChallenge(
    String uid,
    String challengeId,
    String challengeName,
    List<String> invitedUids,
  ) async {
    if (invitedUids.isEmpty) return;
    final batch = _db.batch();
    final challengeRef = _db.collection(Collections.challenges).doc(challengeId);
    batch.update(challengeRef, {
      'invitedUids': FieldValue.arrayUnion(invitedUids),
    });

    final myProfile = await getUserProfile(uid);
    final myName = myProfile?['displayName'] as String? ?? 'Someone';
    _writeChallengeInviteNotifications(
      batch,
      challengeId: challengeId,
      challengeName: challengeName,
      fromUid: uid,
      fromDisplayName: myName,
      invitedUids: invitedUids,
    );

    await batch.commit();
  }

  /// Accepts a challenge invite: moves [uid] from invitedUids to
  /// participantUids. Both array ops happen in the same batched write, so
  /// they can never be observed half-applied.
  Future<void> acceptChallengeInvite(String uid, String challengeId) async {
    final batch = _db.batch();
    final ref = _db.collection(Collections.challenges).doc(challengeId);
    batch.update(ref, {
      'invitedUids': FieldValue.arrayRemove([uid]),
      'participantUids': FieldValue.arrayUnion([uid]),
    });
    await batch.commit();
  }

  /// Declines a challenge invite: removes [uid] from invitedUids only —
  /// never joins participantUids, no other side effect (mirrors
  /// declineFriendRequest()'s silent-decline precedent).
  Future<void> declineChallengeInvite(String uid, String challengeId) async {
    await _db.collection(Collections.challenges).doc(challengeId).update({
      'invitedUids': FieldValue.arrayRemove([uid]),
    });
  }

  /// Responds to a challenge_invite notification from the notifications
  /// sheet: updates the challenge doc (same invitedUids/participantUids
  /// array ops as acceptChallengeInvite()/declineChallengeInvite() above)
  /// AND writes 'accepted'/'declined' onto the notification doc itself,
  /// plus marks it read — all in ONE batch. Deliberately not composed from
  /// the two methods above (each commits its own separate batch) because
  /// the whole point is that the challenge-membership change and the
  /// notification's persisted status can never be observed out of sync —
  /// e.g. the challenge write landing while the status write fails, which
  /// would leave the row stuck re-showing Accept/Decline for an invite
  /// that's already been acted on.
  Future<void> respondToChallengeInvite(
    String uid,
    String challengeId,
    String notificationId, {
    required bool accept,
  }) async {
    final batch = _db.batch();

    final challengeRef = _db.collection(Collections.challenges).doc(challengeId);
    if (accept) {
      batch.update(challengeRef, {
        'invitedUids': FieldValue.arrayRemove([uid]),
        'participantUids': FieldValue.arrayUnion([uid]),
      });
    } else {
      batch.update(challengeRef, {
        'invitedUids': FieldValue.arrayRemove([uid]),
      });
    }

    final notificationRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.notifications)
        .doc(notificationId);
    batch.update(notificationRef, {
      'status': accept ? 'accepted' : 'declined',
      'read': true,
    });

    await batch.commit();
  }

  /// Joins a discoverable global challenge directly — no invite needed
  /// since isGlobal:true challenges are public.
  Future<void> joinChallenge(String uid, String challengeId) async {
    await _db.collection(Collections.challenges).doc(challengeId).update({
      'participantUids': FieldValue.arrayUnion([uid]),
    });
  }

  /// Permanently deletes a challenge — creator-only in practice (enforced
  /// by firestore.rules' `allow delete`, which requires resource.data
  /// .createdBy == request.auth.uid). No subcollection cleanup
  /// (progressCache/progressNotifications) — matches
  /// adminDeleteChallenge()'s own precedent in functions/index.js of not
  /// chasing orphaned subcollection docs; nothing ever reads them once
  /// this challengeId is gone (getChallengeLeaderboard() only reads
  /// progressCache for uids in a challenge's own still-current
  /// participantUids array).
  Future<void> deleteChallenge(String challengeId) async {
    await _db.collection(Collections.challenges).doc(challengeId).delete();
  }

  /// Removes [uid] from a challenge's participantUids — self-only in
  /// practice (enforced by firestore.rules' leave-a-private-challenge
  /// update branch, plus the pre-existing isGlobal branch that already
  /// covered public challenges). Mirrors declineChallengeInvite()'s shape:
  /// a single arrayRemove, no other side effect.
  Future<void> leaveChallenge(String challengeId, String uid) async {
    await _db.collection(Collections.challenges).doc(challengeId).update({
      'participantUids': FieldValue.arrayRemove([uid]),
    });
  }

  /// Live stream of challenges [uid] participates in (creator or accepted
  /// invite), soonest-ending first — matches the "what do I need to act on
  /// next" ordering a My Challenges list wants, same reasoning NRC/Strava
  /// use for their own active-challenge ordering.
  Stream<List<Map<String, dynamic>>> getMyChallengesStream(String uid) {
    return _db
        .collection(Collections.challenges)
        .where('participantUids', arrayContains: uid)
        .orderBy('endDate')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
  }

  /// Live stream of global (public) challenges [uid] hasn't already joined.
  /// Firestore has no "array does not contain" operator, so the
  /// already-joined filter happens client-side after the isGlobal query —
  /// fine at this app's scale (global challenge count is expected to stay
  /// small; admin-managed, not user-generated).
  Stream<List<Map<String, dynamic>>> getDiscoverableChallengesStream(
    String uid,
  ) {
    return _db
        .collection(Collections.challenges)
        .where('isGlobal', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) =>
                !((doc.data()['participantUids'] as List?) ?? [])
                    .contains(uid))
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  /// Computes [uid]'s own progress toward [challenge] (a map as returned
  /// by getMyChallengesStream/getDiscoverableChallengesStream — must
  /// include 'id', 'startDate', 'endDate', 'metricType', 'unit',
  /// 'participantUids', 'name'), reusing getSessionStats()'s exact
  /// date-range query shape on the same sessions subcollection.
  ///
  /// Manually-logged sessions are excluded entirely (isManuallyLogged ==
  /// true is skipped, not just deprioritized) — contributions must come
  /// from validated, anti-cheat-checked data only, same reasoning as this
  /// file's existing timing/bounds flags on gym sets.
  ///
  /// Metric extraction (see finalizeInProgressSession()'s own doc comment
  /// for why the shape differs by type):
  ///  - distance: 'cardio' promotes distanceMeters to the top level, read
  ///    directly; 'combined' preserves every cardio block in a
  ///    cardioBlocks[] array, summed; 'gym' (and manual, already excluded
  ///    above) never carries distance, contributes 0.
  ///  - calories: caloriesBurned summed across every qualifying type.
  ///  - duration: durationSeconds summed across every qualifying type.
  ///
  /// The raw sum is in the metric's natural stored unit (meters, calories,
  /// seconds) and is converted to the challenge's own `unit` before
  /// returning, so the caller can compare directly against goalValue.
  ///
  /// notifyFriends defaults to true: as a side effect, this also checks
  /// whether [uid]'s own progress increased since the last time this was
  /// computed for this challenge, and if so, opportunistically notifies
  /// [uid]'s friends among the other participants (see
  /// _maybeNotifyFriendsOfProgress()'s own doc comment for why this call
  /// site, not a Cloud Function, is the trigger).
  Future<double> computeChallengeProgress(
    String uid,
    Map<String, dynamic> challenge, {
    bool notifyFriends = true,
  }) async {
    final rawStart = challenge['startDate'];
    final rawEnd = challenge['endDate'];
    final startDate = rawStart is Timestamp ? rawStart.toDate() : DateTime(1970);
    final endDate = rawEnd is Timestamp ? rawEnd.toDate() : DateTime.now();
    final metricType = challenge['metricType'] as String? ?? 'distance';
    final unit = challenge['unit'] as String? ?? '';

    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate))
        .get();

    double total = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['isManuallyLogged'] == true) continue;
      final type = data['type'] as String? ?? '';

      switch (metricType) {
        case 'distance':
          if (type == 'cardio') {
            total += (data['distanceMeters'] as num?)?.toDouble() ?? 0;
          } else if (type == 'combined') {
            final blocks = data['cardioBlocks'];
            if (blocks is List) {
              for (final b in blocks) {
                if (b is Map) {
                  total += (b['distanceMeters'] as num?)?.toDouble() ?? 0;
                }
              }
            }
          }
          break;
        case 'calories':
          total += (data['caloriesBurned'] as num?)?.toDouble() ?? 0;
          break;
        case 'duration':
          total += (data['durationSeconds'] as num?)?.toDouble() ?? 0;
          break;
      }
    }

    double converted;
    switch (metricType) {
      case 'distance':
        // Raw total is always in meters (distanceMeters).
        converted = unit == 'km' ? total / 1000 : total;
        break;
      case 'duration':
        // Raw total is always in seconds (durationSeconds).
        if (unit == 'min') {
          converted = total / 60;
        } else if (unit == 'hr') {
          converted = total / 3600;
        } else {
          converted = total;
        }
        break;
      default:
        // calories: stored and displayed in the same unit, no conversion.
        converted = total;
    }

    final challengeId = challenge['id'] as String?;
    if (notifyFriends && challengeId != null) {
      try {
        await _maybeNotifyFriendsOfProgress(uid, challengeId, challenge, converted);
      } catch (_) {
        // Notification side effect must never block the progress number
        // the caller actually needs to render.
      }
    }

    return converted;
  }

  /// Trigger mechanism note: with no Cloud Functions in this project (see
  /// pubspec.yaml's unused cloud_functions dependency), there is no
  /// server-side hook that reacts to a new session write. So this runs
  /// client-side, embedded directly in computeChallengeProgress() itself
  /// — whichever screen calls that function (My Challenges list, a
  /// challenge detail view, pull-to-refresh, etc., in a later pass) gets
  /// this side effect for free, without needing its own separate wiring.
  /// It only ever compares/notifies for the CURRENT device's own uid, since
  /// a user's sessions subcollection can only be queried by that user's own
  /// device in the first place.
  ///
  /// "Did progress increase" is judged against
  /// challenges/{challengeId}/progressCache/{uid} (value, updatedAt),
  /// which this method refreshes to the latest computed value on every
  /// call regardless of outcome — so the next call always compares against
  /// today's true prior baseline, not a stale one.
  ///
  /// Once-per-day dedup: before writing a notification for a given
  /// (challenge, this uid as the friend who progressed, recipient) triple,
  /// checks for a marker doc at
  /// challenges/{challengeId}/progressNotifications/{recipientUid}_{uid}_{yyyy-mm-dd}.
  /// If it exists, that recipient has already been notified about this
  /// friend's progress on this challenge today — skipped. If not, the
  /// marker doc and the actual notification are written together in one
  /// batch, so a notification can never be sent without its dedup marker
  /// also landing (which would otherwise let it re-send on every later
  /// call this same day).
  Future<void> _maybeNotifyFriendsOfProgress(
    String uid,
    String challengeId,
    Map<String, dynamic> challenge,
    double newProgress,
  ) async {
    final cacheRef = _db
        .collection(Collections.challenges)
        .doc(challengeId)
        .collection(_challengeProgressCache)
        .doc(uid);
    final cacheDoc = await cacheRef.get();
    final previous = (cacheDoc.data()?['value'] as num?)?.toDouble() ?? 0;

    await cacheRef.set({
      'value': newProgress,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (newProgress <= previous) return;

    final participantUids =
        (challenge['participantUids'] as List?)?.cast<String>() ?? [];
    if (participantUids.length <= 1) return;

    final friendsSnapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.friends)
        .get();
    final friendUids = friendsSnapshot.docs.map((d) => d.id).toSet();

    final recipientUids = participantUids
        .where((p) => p != uid && friendUids.contains(p))
        .toList();
    if (recipientUids.isEmpty) return;

    final myProfile = await getUserProfile(uid);
    final myName = myProfile?['displayName'] as String? ?? 'A friend';
    final challengeName = challenge['name'] as String? ?? 'a challenge';

    final today = DateTime.now();
    final dateKey = '${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    for (final recipientUid in recipientUids) {
      final dedupRef = _db
          .collection(Collections.challenges)
          .doc(challengeId)
          .collection(_challengeProgressNotifications)
          .doc('${recipientUid}_${uid}_$dateKey');
      final dedupDoc = await dedupRef.get();
      if (dedupDoc.exists) continue;

      final batch = _db.batch();
      batch.set(dedupRef, {'sentAt': FieldValue.serverTimestamp()});
      final notificationRef = _db
          .collection(Collections.users)
          .doc(recipientUid)
          .collection(Collections.notifications)
          .doc();
      batch.set(notificationRef, {
        'type': 'challenge_friend_progress',
        'challengeId': challengeId,
        'challengeName': challengeName,
        'fromUid': uid,
        'fromDisplayName': myName,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    }
  }

  /// Fetches leaderboard rows for every uid in [participantUids] of
  /// [challengeId]: their cached progress value (challenges/{challengeId}/
  /// progressCache/{uid}) joined with their display name (publicProfiles/
  /// {uid}), sorted descending by progress. Reads progressCache rather
  /// than recomputing each participant's progress live from their own
  /// (private, owner-only-readable) sessions — matches the architecture
  /// decision already made for this leaderboard.
  ///
  /// Batch reads, not N sequential awaited gets: both progressCache and
  /// publicProfiles docs for one challenge's participants live in a
  /// single collection each, so a `whereIn` on FieldPath.documentId
  /// fetches an entire chunk of up to 30 uids in ONE round trip — the
  /// same chunking pattern getFriendsLeaderboardStream() already uses for
  /// Firestore's 30-value whereIn cap. In practice this is almost always
  /// exactly 2 queries total (one chunk each for progressCache and
  /// publicProfiles), regardless of how many participants there are, up
  /// to 30.
  ///
  /// A participant with no progressCache doc yet (hasn't triggered
  /// computeChallengeProgress()/the Cloud Function since joining) defaults
  /// to a progress value of 0 rather than being dropped from the list.
  Future<List<Map<String, dynamic>>> getChallengeLeaderboard(
    String challengeId,
    List<String> participantUids,
  ) async {
    if (participantUids.isEmpty) return [];

    final chunks = <List<String>>[];
    for (var i = 0; i < participantUids.length; i += 30) {
      final end =
          i + 30 > participantUids.length ? participantUids.length : i + 30;
      chunks.add(participantUids.sublist(i, end));
    }

    final progressByUid = <String, double>{};
    final profileByUid = <String, Map<String, dynamic>>{};

    for (final chunk in chunks) {
      final progressSnap = await _db
          .collection(Collections.challenges)
          .doc(challengeId)
          .collection(_challengeProgressCache)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in progressSnap.docs) {
        progressByUid[doc.id] = (doc.data()['value'] as num?)?.toDouble() ?? 0;
      }

      final profileSnap = await _db
          .collection(_publicProfiles)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in profileSnap.docs) {
        profileByUid[doc.id] = doc.data();
      }
    }

    final entries = participantUids.map((uid) {
      final profile = profileByUid[uid];
      return <String, dynamic>{
        'uid': uid,
        'displayName': profile?['displayName'] as String? ?? 'User',
        'value': progressByUid[uid] ?? 0.0,
      };
    }).toList();

    entries.sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
    return entries;
  }
}
