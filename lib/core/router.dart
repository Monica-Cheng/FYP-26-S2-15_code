// lib/core/router.dart
// All navigation routes defined in one place
// NEVER use Navigator.push anywhere — always use context.go() or context.push()

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Screen imports — add as you build each screen
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/onboarding/onboarding_step1_screen.dart';
import '../screens/onboarding/onboarding_step2_screen.dart';
import '../screens/onboarding/onboarding_step3_screen.dart';
import '../screens/plans/gym_session_screen.dart';
import '../screens/onboarding/onboarding_walkthrough_screen.dart';
import '../screens/plans/post_session_summary_screen.dart';
import '../screens/home/manual_activity_log_screen.dart';
import '../screens/home/missed_checkin_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/user_profile_screen.dart';
import '../screens/settings/health_profile_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/club/friends_screen.dart';
import '../screens/coach/find_professional_screen.dart';
import '../screens/plans/exercise_detail_screen.dart';
import '../screens/plans/plan_detail_screen.dart';
import '../screens/plans/plan_match_screen.dart';
import '../screens/plans/build_routine_screen.dart';
import '../screens/plans/explore_screen.dart';
import '../screens/plans/plan_schedule_screen.dart';
import '../screens/plans/mid_plan_cardio_complete_screen.dart';
import '../screens/progress/activity_detail_screen.dart';
import '../screens/cardio/cardio_setup_screen.dart';
import '../screens/cardio/cardio_session_screen.dart';
import '../screens/cardio/outdoor_cardio_screen.dart';
import '../screens/nutrition/nutrition_scan_screen.dart';
import '../screens/splash_screen.dart';

// Route path constants — use these instead of hardcoding strings
class Routes {
  Routes._();
  static const String splash = '/splash';
  static const String walkthrough = '/walkthrough';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String register = '/register';
  static const String onboarding = '/onboarding';
  static const String onboardingStep1 = '/onboarding-step1';
  static const String onboardingStep2 = '/onboarding-step2';
  static const String onboardingStep3 = '/onboarding-step3';
  static const String home = '/home';
  static const String plans = '/plans';
  static const String coach = '/coach';
  static const String club = '/club';
  static const String friends = '/friends';
  static const String progress = '/progress';
  static const String gymSession = '/gym-session';
  static const String postSessionSummary = '/post-session-summary';
  static const String profile = '/profile';
  static const String userProfile = '/user-profile';
  static const String settings = '/settings';
  static const String healthProfile = '/health-profile';
  static const String editProfile = '/edit-profile';
  static const String manualActivityLog = '/manual-activity-log';
  static const String missedCheckin = '/missed-checkin';
  static const String planDetail = '/plan-detail';
  static const String exerciseDetail = '/exercise-detail';
  static const String activityDetail = '/activity-detail';
  static const String findProfessional = '/find-professional';
  static const String planMatch = '/plan-match';
  static const String planSchedule = '/plan-schedule';
  static const String explore = '/explore';
  static const String buildRoutine = '/build-routine';
  static const String editRoutine = '/edit-routine';
  static const String cardioSetup = '/cardio-setup';
  static const String cardioSession = '/cardio-session';
  // Temporary/scaffolding route for testing the map-renders-and-permission
  // flow in isolation. Not linked from anywhere in the app yet — a later
  // task wires proper navigation from cardio setup's Outdoor mode and this
  // constant/route can be removed then.
  static const String outdoorCardioTest = '/outdoor-cardio-test';
  static const String nutritionScan = '/nutrition-scan';
  static const String midPlanCardioComplete = '/mid-plan-cardio-complete';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.splash,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final location = state.matchedLocation;

      // Public routes — always allow.
      final isPublicRoute = location == Routes.splash ||
          location == Routes.walkthrough ||
          location == Routes.login ||
          location == Routes.register ||
          location == Routes.forgotPassword;
      if (isPublicRoute) return null;

      // Onboarding routes — allow only while logged in.
      // (Splash already sent unauthenticated users to login.)
      if (user == null) return Routes.login;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.walkthrough,
        builder: (context, state) => const OnboardingWalkthroughScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.onboardingStep1,
        builder: (context, state) => const OnboardingStep1Screen(),
      ),
      GoRoute(
        path: Routes.onboardingStep2,
        builder: (context, state) => const OnboardingStep2Screen(),
      ),
      GoRoute(
        path: Routes.onboardingStep3,
        builder: (context, state) => const OnboardingStep3Screen(),
      ),
      GoRoute(
        path: Routes.gymSession,
        // A plain builder: here lets GoRouter fall back to its default
        // pageKey, which is derived only from the matched path string
        // (confirmed against the installed go_router 14.8.1 source —
        // match.dart's ValueKey<String>(newMatchedPath)) — the same key
        // for every navigation to this route regardless of `extra`, which
        // lets Flutter's Page reconciliation reuse whatever GymSessionScreen
        // instance is already buried in the Navigator's route list instead
        // of creating a fresh one — so initState()/_loadPlanSession() never
        // re-runs and the screen keeps showing stale state.
        //
        // An earlier fix generated a unique key only when extra carried a
        // sessionRunId (the resume/mid-plan-cardio-return case), keeping a
        // single static key for every "fresh start" push (no sessionRunId)
        // on the theory that a first-time plan start needed to match
        // exactly one prior stable-key behavior. That was scoped too
        // narrowly: FOUR different entry points all push this route with no
        // sessionRunId — home_screen.dart's Start Workout,
        // plan_schedule_screen.dart's Start Session, plan_detail_screen.dart's
        // Preview (_onStartDay), and plans_screen.dart's tracked-plan-card
        // tap — so all four shared that one static key. Visiting more than
        // one of them in the same app session (without the earlier instance
        // ever being popped) reused the buried instance across genuinely
        // different plans/days, silently carrying over stale
        // planId/dayIndex/_sessionRunId state from whichever entry point
        // was visited first.
        //
        // Fix: always generate a unique key, for every navigation to this
        // route, with no static fallback — "always fresh, never reused" is
        // now the single invariant for this route, replacing the previous
        // sessionRunId-conditional logic entirely rather than patching
        // around it. The timestamp suffix guarantees uniqueness even for
        // two pushes carrying the identical sessionRunId/planId (e.g. a
        // third cardio block's resume, or the same plan started twice).
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final readOnly = extra?['readOnly'] as bool? ?? false;
          final sessionRunId = extra?['sessionRunId'] as String?;
          final planId = extra?['planId'] as String?;
          final key = ValueKey(
              'gym-session-${sessionRunId ?? planId ?? 'none'}-${DateTime.now().microsecondsSinceEpoch}');
          return MaterialPage(
            key: key,
            child: GymSessionScreen(readOnly: readOnly),
          );
        },
      ),
      GoRoute(
        path: Routes.postSessionSummary,
        builder: (context, state) => const PostSessionSummaryScreen(),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.userProfile,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return UserProfileScreen(
            uid: extra?['uid'] as String? ?? '',
            initialName: extra?['authorName'] as String?,
          );
        },
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.healthProfile,
        builder: (context, state) => const HealthProfileScreen(),
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: Routes.manualActivityLog,
        builder: (context, state) => const ManualActivityLogScreen(),
      ),
      GoRoute(
        path: Routes.missedCheckin,
        builder: (context, state) => const MissedCheckinScreen(),
      ),
      GoRoute(
        path: Routes.planDetail,
        builder: (context, state) => const PlanDetailScreen(),
      ),
      GoRoute(
        path: Routes.exerciseDetail,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final name = extra?['name'] as String? ?? '';
          final muscle = extra?['muscle'] as String? ?? '';
          return ExerciseDetailScreen(
            exerciseName: name,
            muscle: muscle,
          );
        },
      ),
      GoRoute(
        path: Routes.activityDetail,
        builder: (context, state) => const ActivityDetailScreen(),
      ),
      GoRoute(
        path: Routes.findProfessional,
        builder: (context, state) => const FindProfessionalScreen(),
      ),
      GoRoute(
        path: Routes.planMatch,
        builder: (context, state) => const PlanMatchScreen(),
      ),
      GoRoute(
        path: Routes.planSchedule,
        builder: (context, state) => const PlanScheduleScreen(),
      ),
      GoRoute(
        path: Routes.explore,
        builder: (context, state) => const ExploreScreen(),
      ),
      GoRoute(
        path: Routes.buildRoutine,
        builder: (context, state) => const BuildRoutineScreen(),
      ),
      GoRoute(
        path: Routes.editRoutine,
        builder: (context, state) => const BuildRoutineScreen(),
      ),
      GoRoute(
        path: Routes.cardioSetup,
        builder: (context, state) => const CardioSetupScreen(),
      ),
      GoRoute(
        path: Routes.cardioSession,
        builder: (context, state) => const CardioSessionScreen(),
      ),
      GoRoute(
        path: Routes.nutritionScan,
        builder: (context, state) => NutritionScanScreen(
          startInDescribeMode: state.extra == 'describe',
        ),
      ),
      // Temporary/scaffolding — see the Routes.outdoorCardioTest comment.
      GoRoute(
        path: Routes.outdoorCardioTest,
        builder: (context, state) => const OutdoorCardioScreen(),
      ),
      GoRoute(
        path: Routes.midPlanCardioComplete,
        builder: (context, state) => const MidPlanCardioCompleteScreen(),
      ),
      GoRoute(
        path: Routes.friends,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final expandRequests = extra?['expandRequests'] as bool? ?? false;
          return FriendsScreen(initialRequestsExpanded: expandRequests);
        },
      ),
      // Add more routes here as you build each screen
    ],
  );
});
