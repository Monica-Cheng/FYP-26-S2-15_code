// lib/screens/splash_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import '../core/router.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _spinCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  Timer? _timer;

  final _auth = AuthService();
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _timer = Timer(const Duration(seconds: 2), _checkAndNavigate);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _spinCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndNavigate() async {
    if (!mounted) return;

    final user = _auth.getCurrentUser();

    if (user == null) {
      context.go(Routes.walkthrough);
      return;
    }

    try {
      final profile = await _firestore.getUserProfile(user.uid);
      if (!mounted) return;
      final onboardingComplete = profile?['onboardingComplete'] == true;
      context.go(
        onboardingComplete ? Routes.home : Routes.onboardingStep1,
      );
    } catch (_) {
      if (mounted) context.go(Routes.walkthrough);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient background
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1E1A3A),
                  Color(0xFF24245A),
                  Color(0xFF2E3D8F),
                  Color(0xFF6F82EE),
                ],
              ),
            ),
          ),

          // Radial glow overlay
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.12),
                radius: 0.8,
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.04),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.18, 0.40],
              ),
            ),
          ),

          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo block — fades in
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(_fadeAnim),
                    child: Column(
                      children: [
                        // Logo mark
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: WW.primaryDark,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x382D3A8C),
                                blurRadius: 24,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: CustomPaint(
                            painter: _LogoPainter(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Wordmark
                        const Text(
                          'WiseWorkout',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Tagline
                        Text(
                          'Train smarter. Not harder.',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: WW.textSec,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 56),

                // Spinner
                _ArcSpinner(controller: _spinCtrl),
                const SizedBox(height: 14),
                const Text(
                  'Loading your profile...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Version tag
          const Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Text(
              'v1.0 · FYP-26-S2-15',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white54,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Arc spinner ───────────────────────────────────────────────────────────────

class _ArcSpinner extends StatelessWidget {
  final AnimationController controller;

  const _ArcSpinner({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(32, 32),
          painter: _ArcSpinnerPainter(turn: controller.value),
        );
      },
    );
  }
}

class _ArcSpinnerPainter extends CustomPainter {
  final double turn;
  const _ArcSpinnerPainter({required this.turn});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width - 3) / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Track
    final trackPaint = Paint()
      ..color = WW.elevated
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), radius, trackPaint);

    // Arc
    final arcPaint = Paint()
      ..color = WW.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      turn * 2 * math.pi - math.pi / 2,
      math.pi * 0.75,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcSpinnerPainter old) => old.turn != turn;
}

// ── Logo painter ──────────────────────────────────────────────────────────────

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Scale from 40×40 viewBox to actual size
    final sx = size.width / 40;
    final sy = size.height / 40;

    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5 * sx
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // M8 14h3l4 10 4-10h2l4 10 4-10h3
    final path = Path()
      ..moveTo(8 * sx, 14 * sy)
      ..lineTo(11 * sx, 14 * sy)
      ..lineTo(15 * sx, 24 * sy)
      ..lineTo(19 * sx, 14 * sy)
      ..lineTo(21 * sx, 14 * sy)
      ..lineTo(25 * sx, 24 * sy)
      ..lineTo(29 * sx, 14 * sy)
      ..lineTo(32 * sx, 14 * sy);

    canvas.drawPath(path, linePaint);

    // Circle at cx=20 cy=28 r=2.5
    final dotPaint = Paint()
      ..color = WW.lavender
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(20 * sx, 28 * sy), 2.5 * sx, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
