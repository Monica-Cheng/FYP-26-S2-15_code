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
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Creeps toward 88% over an unknown-duration window (real loading time
  // varies with network conditions) instead of a bar hardcoded to fill in a
  // fixed span; _checkAndNavigate animates the remaining stretch to 100%
  // right when navigation actually fires, whether that's fast or slow.
  late AnimationController _progressCtrl;

  Timer? _timer;

  final _auth = AuthService();
  final _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..animateTo(0.88, curve: Curves.easeOutCubic);

    _timer = Timer(const Duration(seconds: 2), _checkAndNavigate);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndNavigate() async {
    if (!mounted) return;

    final user = _auth.getCurrentUser();

    if (user == null) {
      _progressCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      context.go(Routes.walkthrough);
      return;
    }

    try {
      final profile = await _firestore.getUserProfile(user.uid);
      if (!mounted) return;
      final onboardingComplete = profile?['onboardingComplete'] == true;
      _progressCtrl.animateTo(
        1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      context.go(
        onboardingComplete ? Routes.home : Routes.onboardingStep1,
      );
    } catch (_) {
      if (mounted) {
        _progressCtrl.animateTo(
          1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
        context.go(Routes.walkthrough);
      }
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

          // Soft wave/glow graphic decorating the bottom of the screen
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 200,
            child: IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: _BottomWavePainter(),
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
                        // Logo mark, ringed by 6 static feature badges
                        _IconRing(
                          child: Container(
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

                const Text(
                  'Loading your profile...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                _ProgressBar(animation: _progressCtrl),
                const SizedBox(height: 10),
                Text(
                  "This won't take long",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Icon ring ────────────────────────────────────────────────────────────────
// Static (non-animated, per time-constraint decision) ring of 6 feature
// badges around the central logo, connected by a faint circular guide line
// with a few decorative dots — purely decorative, no interaction/state.

class _IconRing extends StatelessWidget {
  final Widget child;

  const _IconRing({required this.child});

  static const List<IconData> _icons = [
    Icons.fitness_center_rounded,
    Icons.monitor_heart_rounded,
    Icons.directions_run_rounded,
    Icons.chat_bubble_rounded,
    Icons.trending_up_rounded,
    Icons.local_fire_department_rounded,
  ];

  static const double _size = 240;
  static const double _ringRadius = 96;
  static const double _badgeSize = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const CustomPaint(
            size: Size(_size, _size),
            painter: _RingGuidePainter(),
          ),
          for (var i = 0; i < _icons.length; i++) _badge(i),
          child,
        ],
      ),
    );
  }

  Widget _badge(int index) {
    final angle = (2 * math.pi / _icons.length) * index - math.pi / 2;
    final offset = Offset(
      _ringRadius * math.cos(angle),
      _ringRadius * math.sin(angle),
    );
    return Transform.translate(
      offset: offset,
      child: Container(
        width: _badgeSize,
        height: _badgeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: WW.lavender.withOpacity(0.22),
          border: Border.all(color: Colors.white.withOpacity(0.20)),
        ),
        child: Icon(
          _icons[index],
          color: Colors.white.withOpacity(0.9),
          size: 18,
        ),
      ),
    );
  }
}

class _RingGuidePainter extends CustomPainter {
  const _RingGuidePainter();

  static const List<double> _dotAnglesDeg = [20, 95, 160, 230, 300];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, _IconRing._ringRadius, linePaint);

    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.28)
      ..style = PaintingStyle.fill;
    for (final deg in _dotAnglesDeg) {
      final rad = deg * math.pi / 180;
      final p = center +
          Offset(
            _IconRing._ringRadius * math.cos(rad),
            _IconRing._ringRadius * math.sin(rad),
          );
      canvas.drawCircle(p, 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Progress bar ─────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final Animation<double> animation;

  const _ProgressBar({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Container(
          width: 180,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: animation.value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: WW.lavender,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Bottom wave/glow ─────────────────────────────────────────────────────────

class _BottomWavePainter extends CustomPainter {
  const _BottomWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    _layer(canvas, size,
        amplitude: 20,
        phase: 0,
        yFraction: 0.55,
        color: WW.primaryDark.withOpacity(0.35));
    _layer(canvas, size,
        amplitude: 14,
        phase: math.pi / 2.5,
        yFraction: 0.72,
        color: WW.lavender.withOpacity(0.22));
  }

  void _layer(
    Canvas canvas,
    Size size, {
    required double amplitude,
    required double phase,
    required double yFraction,
    required Color color,
  }) {
    final baseY = size.height * yFraction;
    final path = Path()..moveTo(0, baseY);
    for (double x = 0; x <= size.width; x += 8) {
      final y = baseY +
          amplitude * math.sin((x / size.width * 2 * math.pi) + phase);
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
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
