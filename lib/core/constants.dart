// lib/core/constants.dart
// All Firestore collection names and app-wide constants
// NEVER hardcode these strings anywhere else in the app

class Collections {
  Collections._();
  static const String users = 'users';
  static const String plans = 'plans';
  static const String exercises = 'exercises';
  static const String sessions = 'sessions';
  static const String xpEvents = 'xpEvents';
  static const String challenges = 'challenges';
}

class AppConstants {
  AppConstants._();
  static const String appName = 'WiseWorkout';
  static const int freeMessageLimit = 10;
  static const int freeRoutineLimit = 3;
  static const int freeChallengeLimit = 1;
}
