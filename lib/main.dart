// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'core/router.dart';
import 'core/app_theme.dart';
import 'core/tap_lock_overlay.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService().init();
  runApp(const ProviderScope(child: WiseWorkoutApp()));
}

class WiseWorkoutApp extends ConsumerWidget {
  const WiseWorkoutApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'WiseWorkout',
      theme: WW.theme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Global double-tap/duplicate-navigation guard — see
      // tap_lock_overlay.dart's own doc comment for the crash this fixes
      // and why it's applied here rather than per-screen.
      builder: (context, child) =>
          TapLockOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}
