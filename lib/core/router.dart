// lib/core/router.dart
// All navigation routes defined in one place
// NEVER use Navigator.push anywhere — always use context.go() or context.push()

import 'package:firebase_auth/firebase_auth.dart';
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
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/settings/health_profile_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/coach/find_professional_screen.dart';
import '../screens/plans/plan_detail_screen.dart';
import '../screens/progress/activity_detail_screen.dart';
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
  static const String progress = '/progress';
  static const String gymSession = '/gym-session';
  static const String postSessionSummary = '/post-session-summary';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String healthProfile = '/health-profile';
  static const String editProfile = '/edit-profile';
  static const String manualActivityLog = '/manual-activity-log';
  static const String planDetail = '/plan-detail';
  static const String activityDetail = '/activity-detail';
  static const String findProfessional = '/find-professional';
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
        builder: (context, state) => const GymSessionScreen(),
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
        path: Routes.planDetail,
        builder: (context, state) => const PlanDetailScreen(),
      ),
      GoRoute(
        path: Routes.activityDetail,
        builder: (context, state) => const ActivityDetailScreen(),
      ),
      GoRoute(
        path: Routes.findProfessional,
        builder: (context, state) => const FindProfessionalScreen(),
      ),
      // Add more routes here as you build each screen
    ],
  );
});
