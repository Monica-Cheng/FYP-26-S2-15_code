// lib/core/router.dart
// All navigation routes defined in one place
// NEVER use Navigator.push anywhere — always use context.go() or context.push()

import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Screen imports — add as you build each screen
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/home/home_screen.dart';

// Route path constants — use these instead of hardcoding strings
class Routes {
  Routes._();
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String register = '/register';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String plans = '/plans';
  static const String coach = '/coach';
  static const String club = '/club';
  static const String progress = '/progress';
  static const String gymSession = '/gym-session';
  static const String profile = '/profile';
  static const String settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.login,
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
      // Add more routes here as you build each screen
    ],
  );
});
