// lib/core/constants.dart
// All Firestore collection names and app-wide constants
// NEVER hardcode these strings anywhere else in the app

class Collections {
  Collections._();
  static const String users = 'users';
  static const String plans = 'plans';
  static const String exercises = 'exercises';
  static const String injuryCategories = 'injuryCategories';
  static const String sessions = 'sessions';
  static const String xpEvents = 'xpEvents';
  static const String challenges = 'challenges';
  static const String nutritionLogs = 'nutritionLogs';
  static const String posts = 'posts';
  static const String follows = 'follows';
  static const String friendRequests = 'friendRequests';
  static const String friends = 'friends';
  static const String notifications = 'notifications';
  static const String businessPartners = 'businessPartners';
  static const String coachRequests = 'coachRequests';
  static const String coachClients = 'coachClients';
  static const String wiseCoachMessages = 'wiseCoachMessages';
}

class AppConstants {
  AppConstants._();
  static const String appName = 'WiseWorkout';
  // Single source of truth for the WiseCoach free-tier chat message limit
  // — functions/index.js's FREE_MESSAGE_LIMIT mirrors this value by hand
  // (the Cloud Function runs in a separate JS runtime and can't import
  // this file directly); keep both in sync if this ever changes.
  static const int freeMessageLimit = 25;
  static const int freeRoutineLimit = 3;
  // Free-tier cap on challenges a user has CREATED (createdBy == uid) —
  // distinct from challenges they've joined/were invited to, which don't
  // count against this. Enforced in create_challenge_screen.dart's
  // _submit(), via FirestoreService.getCreatedChallengeCount().
  static const int freeChallengeLimit = 3;
}