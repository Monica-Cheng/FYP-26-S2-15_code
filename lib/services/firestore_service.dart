// lib/services/firestore_service.dart
// Handles ALL Firestore reads and writes for WiseWorkout.
// NEVER import cloud_firestore directly in a screen or widget — always go through this service.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _planProgress = 'planProgress';
  static const _inProgressSessions = 'inProgressSessions';

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
  // ---------------------------------------------------------------------------
  Future<void> updateUserProfile(
    String uid,
    Map<String, dynamic> data,
  ) async {
    await _db.collection(Collections.users).doc(uid).update(data);
  }

  // ---------------------------------------------------------------------------
  // Reads users/{uid} and returns the data map, or null if the document
  // does not exist. Use for one-off profile reads (not reactive — for
  // reactive updates use a StreamProvider in lib/providers/).
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc =
        await _db.collection(Collections.users).doc(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  // ---------------------------------------------------------------------------
  // Checks whether a username is already taken by another user document.
  // ---------------------------------------------------------------------------
  Future<bool> isUsernameTaken(String username) async {
    final snapshot = await _db
        .collection(Collections.users)
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Persists onboarding step 1 — body profile fields — into users/{uid}.
  // Expected keys in bodyProfile:
  //   displayName, dob, biologicalSex, heightCm, weightKg,
  //   preferredUnits, healthConnected, wearableConnected
  // ---------------------------------------------------------------------------
  Future<void> saveOnboardingStep1(
    String uid,
    Map<String, dynamic> bodyProfile,
  ) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .set(bodyProfile, SetOptions(merge: true));
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
  // Persists onboarding step 3 — device permission preferences — into users/{uid}.
  // Expected keys in permissions:
  //   notificationsEnabled, locationEnabled, motionEnabled
  // ---------------------------------------------------------------------------
  Future<void> saveOnboardingStep3(
    String uid,
    Map<String, dynamic> permissions,
  ) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .set(permissions, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Marks onboarding as complete for users/{uid}.
  // Call after saveOnboardingStep3 succeeds. The router guards check this
  // flag to decide whether to show onboarding or the main app shell.
  // ---------------------------------------------------------------------------
  Future<void> markOnboardingComplete(String uid) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .update({'onboardingComplete': true});
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
    final rawExercises = sessionData['exercises'];
    int totalSets = 0;
    double totalVolume = 0.0;

    // Build a cleaned exercises list: only completed sets, numeric kg/reps.
    final List<Map<String, dynamic>> cleanedExercises = [];

    if (rawExercises is List) {
      for (final e in rawExercises) {
        if (e is! Map) continue;
        final sets = e['sets'];
        if (sets is! List) continue;

        final List<Map<String, dynamic>> doneSets = [];
        for (final s in sets) {
          if (s is! Map || s['done'] != true) continue;
          final kg = double.tryParse(s['kg']?.toString() ?? '');
          final reps = int.tryParse(s['reps']?.toString() ?? '');
          totalSets++;
          totalVolume += (kg ?? 0) * (reps ?? 0);
          doneSets.add({'kg': kg, 'reps': reps, 'done': true});
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
        double.tryParse(profile?['weight']?.toString() ?? '70') ?? 70.0;
    final durationHours = (sessionData['elapsedSeconds'] as int) / 3600;
    int caloriesBurned = (5.0 * weightKg * durationHours).round();
    caloriesBurned = caloriesBurned.clamp(50, 2000);

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
      print('Writing to Firestore...');
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
        'caloriesBurned': caloriesBurned,
        'xpEarned': totalSets * 15,
        'isManuallyLogged': false,
        'planIsCustom': planIsCustom,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (photoBase64 != null && photoBase64.isNotEmpty)
          'photoBase64': photoBase64,
      });
      print('Firestore write successful!');
      return ref.id;
    } catch (e) {
      print('Firestore write error: $e');
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
  // Returns the [limit] most recent sessions for users/{uid}, newest first.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getRecentSessions(
    String uid, {
    int limit = 10,
  }) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .orderBy('date', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Live stream of the [limit] most recent sessions for users/{uid}, newest
  // first — same query as getRecentSessions() (kept as-is; other callers may
  // still use the one-shot version) but reactive, so a screen listening to
  // this updates automatically when a new session is saved elsewhere,
  // without requiring a manual refetch/app restart.
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getRecentSessionsStream(
    String uid, {
    int limit = 20,
  }) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  // ---------------------------------------------------------------------------
  // Returns lifetime totals across all sessions for users/{uid}: session
  // count and summed gym volume (kg). Used by the Profile stats row.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getLifetimeStats(String uid) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .get();

    int sessionCount = snapshot.docs.length;
    double totalVolume = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final vol = data['totalVolume'];
      if (vol is num) {
        totalVolume += vol.toDouble();
      }
    }

    return {
      'sessionCount': sessionCount,
      'totalVolume': totalVolume,
    };
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

  /// Saves the user's current injuries and filtering
  /// preference to their user document.
  Future<void> saveUserInjuries(
    String uid, {
    required List<Map<String, dynamic>> injuries,
    required bool filteringEnabled,
  }) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .update({
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
      final doc = await _db
          .collection(Collections.users)
          .doc(uid)
          .get();
      final data = doc.data();
      return {
        'injuries': data?['injuries'] ?? [],
        'injuryFilteringEnabled':
            data?['injuryFilteringEnabled'] ?? false,
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
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        [];
    if (injuryRisk.isEmpty) return null;
    for (final injury in userInjuries) {
      final bodyPart =
          (injury['bodyPart'] as String? ?? '')
              .toLowerCase();
      if (injuryRisk.contains(bodyPart)) {
        return injury['name'] as String?;
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
  // Returns the calorie goal settings from users/{uid}:
  //   'calorieGoalActive': bool  (default false)
  //   'dailyCalorieGoal':  int   (default 500)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getUserCalorieGoal(String uid) async {
    final doc = await _db.collection(Collections.users).doc(uid).get();
    final data = doc.data();
    return {
      'calorieGoalActive': data?['calorieGoalActive'] as bool? ?? false,
      'dailyCalorieGoal':
          (data?['dailyCalorieGoal'] as num?)?.toInt() ?? 500,
    };
  }

  // ---------------------------------------------------------------------------
  // Adds xpEarned to the user's totalXp and weeklyXp, then recalculates and
  // updates their level. Uses merge:true so unrelated fields are untouched.
  // ---------------------------------------------------------------------------
  Future<void> addXpToUser(String uid, int xpEarned) async {
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

    await _db.collection(Collections.users).doc(uid).set({
      'totalXp': newTotal,
      'weeklyXp': newWeekly,
      'weekStartDate': Timestamp.fromDate(currentWeekStart),
      'lastWeeklyXpUpdate': FieldValue.serverTimestamp(),
      'level': _calculateLevel(newTotal),
    }, SetOptions(merge: true));
  }

  // Most recent Monday at local midnight (device-local time).
  static DateTime _currentWeekStart() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static int _calculateLevel(int totalXp) {
    const thresholds = [0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000];
    int level = 1;
    for (int i = 0; i < thresholds.length; i++) {
      if (totalXp >= thresholds[i]) level = i + 1;
    }
    return level;
  }

  // ---------------------------------------------------------------------------
  // Calculates the current workout streak for users/{uid}.
  // Counts consecutive days (going back from today) with at least one session.
  // If today has no session, yesterday is checked first — streak still counts.
  // ---------------------------------------------------------------------------
  Future<int> calculateStreak(String uid) async {
    final snapshot = await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(Collections.sessions)
        .orderBy('date', descending: true)
        .get();

    if (snapshot.docs.isEmpty) return 0;

    String _key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final sessionDates = <String>{};
    for (final doc in snapshot.docs) {
      final ts = doc.data()['date'];
      if (ts is Timestamp) {
        sessionDates.add(_key(ts.toDate().toLocal()));
      }
    }

    final now = DateTime.now();
    // If today has no session, start counting from yesterday.
    DateTime check =
        sessionDates.contains(_key(now)) ? now : now.subtract(const Duration(days: 1));

    if (!sessionDates.contains(_key(check))) return 0;

    int streak = 0;
    while (sessionDates.contains(_key(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
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
  // ---------------------------------------------------------------------------
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
    int totalCalories = 0;
    double totalVolume = 0;
    int totalSessions = 0;
    int gymSessions = 0;
    int cardioSessions = 0;

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
        bucketIndex =
            (date.month - startDate.month).clamp(0, bucketCount - 1);
      }

      caloriesByBucket[bucketIndex] += cals;
      if (type == 'gym') volumeByBucket[bucketIndex] += vol;
      totalCalories += cals.round();
      totalVolume += vol;
      totalSessions++;
      if (type == 'gym') gymSessions++;
      if (type == 'cardio') cardioSessions++;
    }

    return {
      'caloriesByDay': caloriesByBucket,
      'volumeByDay': volumeByBucket,
      'totalCalories': totalCalories,
      'totalVolume': totalVolume.round(),
      'totalSessions': totalSessions,
      'gymSessions': gymSessions,
      'cardioSessions': cardioSessions,
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
  // planProgress subcollection helpers — per-plan progress isolation.
  // ---------------------------------------------------------------------------

  Future<void> initPlanProgress(String uid, String planId) async {
    await _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_planProgress)
        .doc(planId)
        .set({
      'planId': planId,
      'currentDayIndex': 1,
      'lastCompletedDate': '',
      'lastCompletedDayIndex': 0,
      'compressedDays': [],
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
      'compressedDays': [],
      'breakModeActive': false,
      'trackingStartDate': null,
    };
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

  // ---------------------------------------------------------------------------
  // Sets the user's tracked plan. Progress is stored per-plan in the
  // planProgress subcollection; only trackedPlanId/Name live on the user doc.
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
  // happens on the next app open via checkAndAdvanceDay.
  // ---------------------------------------------------------------------------
  Future<void> markSessionComplete(String uid, String planId) async {
    final progress = await getPlanProgress(uid, planId);
    final currentDayIndex =
        (progress?['currentDayIndex'] as num?)?.toInt() ?? 1;
    final today = DateTime.now().toString().substring(0, 10);
    await updatePlanProgress(uid, planId, {
      'lastCompletedDate': today,
      'lastCompletedDayIndex': currentDayIndex,
    });
  }

  // ---------------------------------------------------------------------------
  // Advances currentDayIndex if the last completed session was on a previous
  // calendar day and the index has not been advanced yet.
  // Returns the effective currentDayIndex (new value or unchanged).
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
      await updatePlanProgress(uid, planId, {'currentDayIndex': newIndex});
      return newIndex;
    }
    return currentDayIndex;
  }

  // ---------------------------------------------------------------------------
  // Saves a custom user-built routine to:
  //   1. users/{uid}/customRoutines/{auto-id}  — private copy
  //   2. plans/{auto-id}                       — discoverable plan entry
  // ---------------------------------------------------------------------------
  Future<void> saveCustomRoutine({
    required String uid,
    required String routineName,
    required List<Map<String, dynamic>> sessions,
    required int daysPerWeek,
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
    });

    await _db.collection(Collections.plans).add({
      'name': routineName,
      'level': 'Custom',
      'type': 'Gym',
      'daysPerWeek': daysPerWeek,
      'description': 'Custom routine created by user',
      'isCustom': true,
      'createdBy': uid,
      'sessions': sessions,
      'createdAt': FieldValue.serverTimestamp(),
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
  // ---------------------------------------------------------------------------
  Future<void> deleteCustomPlan(
      String uid, String planId, String planName) async {
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
  // Saves a completed cardio session to users/{uid}/sessions/{auto-id}.
  // XP is awarded at 0.5× calories, clamped to 20–500.
  // ---------------------------------------------------------------------------
  Future<String> saveCardioSession({
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
    final xpEarned = (caloriesBurned * 0.5).round().clamp(20, 500);
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
    return ref.id;
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
        print('getSession: no such session $sessionId');
        return null;
      }
      return {'id': doc.id, ...doc.data()!};
    } catch (e) {
      print('getSession error: $e');
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
  // Creates a new in-progress session at
  // users/{uid}/inProgressSessions/{auto-id}. `blocks` is the day's raw
  // exercises array (as already stored in customRoutines/plans); each entry
  // is written with `done: false` seeded on regardless of block type — for
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
    final seededBlocks =
        blocks.map((b) => {...b, 'done': false}).toList();
    // TEMPORARY DEBUG — remove once the second-cardio-block bug is
    // confirmed fixed.
    print('DEBUG_BLOCKINDEX: createInProgressSession planId=$planId '
        'dayIndex=$dayIndex blocks.length=${seededBlocks.length}');
    for (var i = 0; i < seededBlocks.length; i++) {
      final b = seededBlocks[i];
      print('DEBUG_BLOCKINDEX:   [$i] name=${b['name']} '
          'isCardio=${b['isCardio']}');
    }
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
    // TEMPORARY DEBUG — remove once the post-always-fresh-key regression is
    // confirmed fixed.
    print('DEBUG_REGRESSION: createInProgressSession created '
        'sessionRunId=${ref.id} planId=$planId dayIndex=$dayIndex');
    return ref.id;
  }

  // ---------------------------------------------------------------------------
  // Marks a single block within an in-progress session done or not-done.
  // Firestore has no in-place array-element update, so the whole `blocks`
  // array is read, blocks[blockIndex] is replaced with blockData, and the
  // full array is written back. Fails soft (logs, doesn't throw) if the doc
  // is missing or blockIndex is out of range — a stray/late update after
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
    int blockIndex,
    Map<String, dynamic> blockData,
  ) async {
    final docRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .doc(sessionRunId);
    // TEMPORARY DEBUG — remove once the second-cardio-block bug is
    // confirmed fixed.
    print('DEBUG_BLOCKINDEX: updateInProgressSessionBlock called '
        'sessionRunId=$sessionRunId blockIndex=$blockIndex');
    try {
      final doc = await docRef.get();
      if (!doc.exists) {
        print('updateInProgressSessionBlock: no such session $sessionRunId');
        return;
      }
      final rawBlocks = doc.data()?['blocks'];
      if (rawBlocks is! List ||
          blockIndex < 0 ||
          blockIndex >= rawBlocks.length) {
        print('updateInProgressSessionBlock: blockIndex $blockIndex out of '
            'range for session $sessionRunId');
        return;
      }
      final blocks = rawBlocks
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      final rawSets = blockData['sets'];
      final done = rawSets is List
          ? rawSets.every((s) => s is Map && s['done'] == true)
          : true;
      blocks[blockIndex] = {...blockData, 'done': done};
      // TEMPORARY DEBUG — remove once the second-cardio-block bug is
      // confirmed fixed.
      print('DEBUG_BLOCKINDEX: updateInProgressSessionBlock about to write '
          'sessionRunId=$sessionRunId blocks.length=${blocks.length}');
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        print('DEBUG_BLOCKINDEX:   [$i] name=${b['name']} '
            'isCardio=${b['isCardio']} done=${b['done']}');
      }
      await docRef.update({'blocks': blocks});
    } catch (e) {
      print('updateInProgressSessionBlock error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Appends a brand-new block to an in-progress session's blocks[] array and
  // returns its new index (the array's new length - 1) — for a block added
  // mid-session (gym_session_screen.dart's "+ Add" sheets) that never had a
  // slot from createInProgressSession()'s original seeding at all, unlike
  // updateInProgressSessionBlock(), which only ever replaces an EXISTING
  // slot and fails soft on an out-of-range index rather than growing the
  // array. done:false is always seeded on, same as createInProgressSession()
  // does for every block it originally seeds. Fails soft (logs, returns
  // null) on a missing doc or any error — an add should never be able to
  // block the user from continuing their workout; the caller falls back to
  // originalIndex: -1 (no sync) exactly as it already does today when this
  // returns null.
  // ---------------------------------------------------------------------------
  Future<int?> appendInProgressSessionBlock(
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
        print('appendInProgressSessionBlock: no such session $sessionRunId');
        return null;
      }
      final rawBlocks = doc.data()?['blocks'];
      final blocks = rawBlocks is List
          ? rawBlocks.map((b) => Map<String, dynamic>.from(b as Map)).toList()
          : <Map<String, dynamic>>[];
      blocks.add({...blockData, 'done': false});
      final newIndex = blocks.length - 1;
      await docRef.update({'blocks': blocks});
      return newIndex;
    } catch (e) {
      print('appendInProgressSessionBlock error: $e');
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
  // removedOriginalIndices are each block's stable originalIndex (not a
  // transient in-memory _exercises array position — see
  // gym_session_screen.dart's _ExerciseData.originalIndex), removed
  // highest-index-first so removing one never shifts the position of
  // another index still queued for removal in the same pass. Fails soft
  // (logs, doesn't throw) matching updateInProgressSessionBlock()'s own
  // convention — a stray/late call after the session was already
  // finalized/abandoned shouldn't crash the caller.
  // ---------------------------------------------------------------------------
  Future<void> dismissInjuryReview(
    String uid,
    String sessionRunId,
    List<int> removedOriginalIndices,
  ) async {
    final docRef = _db
        .collection(Collections.users)
        .doc(uid)
        .collection(_inProgressSessions)
        .doc(sessionRunId);
    try {
      final doc = await docRef.get();
      if (!doc.exists) {
        print('dismissInjuryReview: no such session $sessionRunId');
        return;
      }
      final rawBlocks = doc.data()?['blocks'];
      final blocks = rawBlocks is List
          ? rawBlocks.map((b) => Map<String, dynamic>.from(b as Map)).toList()
          : <Map<String, dynamic>>[];
      final sortedIndices = [...removedOriginalIndices]
        ..sort((a, b) => b.compareTo(a));
      for (final index in sortedIndices) {
        if (index >= 0 && index < blocks.length) {
          blocks.removeAt(index);
        }
      }
      await docRef.update({
        'blocks': blocks,
        'injuryReviewDismissed': true,
      });
    } catch (e) {
      print('dismissInjuryReview error: $e');
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
        print('getInProgressSession: no such session $sessionRunId');
        return null;
      }
      return doc.data();
    } catch (e) {
      print('getInProgressSession error: $e');
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
  Future<String> finalizeInProgressSession(
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
    final data = doc.data() ?? {};
    final rawBlocks = data['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.map((b) => Map<String, dynamic>.from(b as Map)).toList()
        : <Map<String, dynamic>>[];

    // TEMPORARY DEBUG — remove once the post-always-fresh-key regression is
    // confirmed fixed. Same name/isCardio/done format as the earlier
    // DEBUG_BLOCKINDEX logs. Logs every block (done or not) — see
    // doneBlocks below for what's actually finalized.
    print('DEBUG_REGRESSION: finalizeInProgressSession sessionRunId='
        '$sessionRunId blocks.length=${blocks.length}');
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      print('DEBUG_REGRESSION:   [$i] name=${b['name']} '
          'isCardio=${b['isCardio']} done=${b['done']}');
    }

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
    for (final e in gymBlocks) {
      final sets = e['sets'];
      if (sets is! List) continue;
      final List<Map<String, dynamic>> doneSets = [];
      for (final s in sets) {
        if (s is! Map || s['done'] != true) continue;
        final kg = double.tryParse(s['kg']?.toString() ?? '');
        final reps = int.tryParse(s['reps']?.toString() ?? '');
        totalSets++;
        totalVolume += (kg ?? 0) * (reps ?? 0);
        doneSets.add({'kg': kg, 'reps': reps, 'done': true});
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
    int caloriesBurned = 0;
    for (final b in [...gymBlocks, ...cardioBlocks]) {
      durationSeconds += (b['durationSeconds'] as num?)?.toInt() ?? 0;
      caloriesBurned += (b['caloriesBurned'] as num?)?.toInt() ?? 0;
    }
    final xpEarned = totalSets * 15 +
        cardioBlocks.fold<int>(0, (acc, b) {
          final cals = (b['caloriesBurned'] as num?)?.toInt() ?? 0;
          return acc + (cals * 0.5).round().clamp(20, 500);
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
    return ref.id;
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
        print('isInProgressSessionFullyDone: no such session $sessionRunId');
        return false;
      }
      final rawBlocks = doc.data()?['blocks'];
      if (rawBlocks is! List) return false;
      return rawBlocks.every((b) => b is Map && b['done'] == true);
    } catch (e) {
      print('isInProgressSessionFullyDone error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Fetches approved and visible business partner profiles.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getBusinessPartners() async {
    final snap = await _db
        .collection('businessPartners')
        .where('isApproved', isEqualTo: true)
        .where('isVisible', isEqualTo: true)
        .get();
    return snap.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
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
  // ---------------------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> getWeightLogsStream(String uid) {
    return _db
        .collection(Collections.users)
        .doc(uid)
        .collection('weightLogs')
        .orderBy('date', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
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
  }) async {
    final initial =
        authorName.trim().isNotEmpty ? authorName.trim()[0].toUpperCase() : '?';

    await _db.collection(Collections.posts).add({
      'uid': uid,
      'authorName': authorName,
      'authorInitial': initial,
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
    });
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
        .map((snapshot) =>
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
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
  // ---------------------------------------------------------------------------
  Future<void> addComment(
    String postId, {
    required String uid,
    required String authorName,
    required String text,
  }) async {
    final postRef = _db.collection(Collections.posts).doc(postId);
    await postRef.collection('comments').add({
      'uid': uid,
      'authorName': authorName,
      'text': text,
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
        .map((snapshot) =>
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList());
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
  Future<List<Map<String, dynamic>>> searchUsersByUsername(
    String query,
  ) async {
    final snapshot = await _db
        .collection(Collections.users)
        .where('username', isGreaterThanOrEqualTo: query)
        .where('username', isLessThanOrEqualTo: '$query')
        .limit(20)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'uid': doc.id,
        'displayName': data['displayName'],
        'username': data['username'],
      };
    }).toList();
  }

  /// Sends a friend request from [fromUid] to [toUid]. Writes the
  /// pending request doc and a notification doc in a single batch —
  /// the first WriteBatch in this file — so they always succeed or
  /// fail together.
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
  /// [toUid] (i.e. users/{toUid}/friendRequests/{fromUid} exists).
  Future<bool> hasSentFriendRequest(String toUid, String fromUid) async {
    final doc = await _db
        .collection(Collections.users)
        .doc(toUid)
        .collection(Collections.friendRequests)
        .doc(fromUid)
        .get();
    return doc.exists;
  }

  /// Accepts a pending friend request: removes the request, writes a
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

  /// Declines a pending friend request — deletes it silently, no
  /// notification or other side effect.
  Future<void> declineFriendRequest(
    String currentUid,
    String requesterUid,
  ) async {
    await _db
        .collection(Collections.users)
        .doc(currentUid)
        .collection(Collections.friendRequests)
        .doc(requesterUid)
        .delete();
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
            .collection(Collections.users)
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
        };
      }).where((e) {
        final visible = e['leaderboardVisible'] as bool;
        return visible || e['uid'] == uid;
      }).toList();

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
}