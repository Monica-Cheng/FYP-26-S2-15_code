// lib/services/firestore_service.dart
// Handles ALL Firestore reads and writes for WiseWorkout.
// NEVER import cloud_firestore directly in a screen or widget — always go through this service.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
  Future<void> saveGymSession(
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

    try {
      print('Writing to Firestore...');
      await _db
          .collection(Collections.users)
          .doc(uid)
          .collection(Collections.sessions)
          .add({
        'type': 'gym',
        'sessionName': sessionData['sessionName'],
        'date': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'durationSeconds': sessionData['elapsedSeconds'],
        'exercises': cleanedExercises,
        'totalSets': totalSets,
        'totalVolume': totalVolume,
        'caloriesBurned': caloriesBurned,
        'xpEarned': totalSets * 15,
        'isManuallyLogged': false,
      });
      print('Firestore write successful!');
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
    final newWeekly = ((data['weeklyXp'] as num?)?.toInt() ?? 0) + xpEarned;
    await _db.collection(Collections.users).doc(uid).set({
      'totalXp': newTotal,
      'weeklyXp': newWeekly,
      'level': _calculateLevel(newTotal),
    }, SetOptions(merge: true));
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
    });
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
}
