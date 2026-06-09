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
        'caloriesBurned': totalSets * 8,
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
