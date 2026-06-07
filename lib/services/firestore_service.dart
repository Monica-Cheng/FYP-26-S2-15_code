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
}
