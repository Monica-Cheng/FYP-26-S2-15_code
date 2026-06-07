// lib/core/router.dart
// All navigation routes defined in one place
// NEVER use Navigator.push anywhere — always use context.go() or context.push()

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'constants.dart';

// Screen imports — add as you build each screen
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/onboarding/onboarding_step1_screen.dart';
import '../screens/onboarding/onboarding_step2_screen.dart';
import '../screens/onboarding/onboarding_step3_screen.dart';
import '../screens/plans/gym_session_screen.dart';
import '../screens/plans/post_session_summary_screen.dart';

// Route path constants — use these instead of hardcoding strings
class Routes {
  Routes._();
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
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.login,
    redirect: (context, state) async {
      final user = FirebaseAuth.instance.currentUser;
      final location = state.matchedLocation;

      // Not logged in — allow auth screens, redirect everything else to login.
      if (user == null) {
        final isAuthRoute = location == Routes.login ||
            location == Routes.register ||
            location == Routes.forgotPassword;
        return isAuthRoute ? null : Routes.login;
      }

      // Logged in — check whether the user has completed onboarding.
      final doc = await FirebaseFirestore.instance
          .collection(Collections.users)
          .doc(user.uid)
          .get();
      final onboardingComplete = doc.data()?['onboardingComplete'] == true;

      final isAuthRoute = location == Routes.login ||
          location == Routes.register ||
          location == Routes.forgotPassword;

      if (onboardingComplete) {
        // Fully onboarded — bounce auth and onboarding screens to home.
        if (isAuthRoute || location.startsWith('/onboarding')) {
          return Routes.home;
        }
        return null;
      } else {
        // Onboarding incomplete — bounce auth screens and home to step 1.
        if (isAuthRoute || location == Routes.home) {
          return Routes.onboardingStep1;
        }
        return null;
      }
    },
    routes: [
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
      // Add more routes here as you build each screen
    ],
  );
});
