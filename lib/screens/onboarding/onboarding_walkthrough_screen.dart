// lib/screens/onboarding/onboarding_walkthrough_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';

// ── Card data ──────────────────────────────────────────────────────────────────

class _CardData {
  final String title;
  final String body;
  final Color illustrationBg;
  final Widget illustration;

  const _CardData({
    required this.title,
    required this.body,
    required this.illustrationBg,
    required this.illustration,
  });
}

final List<_CardData> _kCards = [
  _CardData(
    title: 'Your AI fitness coach',
    body:
        'WiseCoach learns your training and tells you exactly what to do next.',
    illustrationBg: WW.lavenderBg,
    illustration: const _CoachIllustration(),
  ),
  _CardData(
    title: 'Plans that adapt to real life',
    body:
        'Gym and running plans that automatically adjust when life gets in the way.',
    illustrationBg: WW.tealBg,
    illustration: const _CalendarIllustration(),
  ),
  _CardData(
    title: 'Train with your squad',
    body:
        'Leaderboards, challenges and social accountability to keep you going.',
    illustrationBg: WW.elevated,
    illustration: const _PodiumIllustration(),
  ),
];

// ── Screen ─────────────────────────────────────────────────────────────────────

class OnboardingWalkthroughScreen extends StatefulWidget {
  const OnboardingWalkthroughScreen({super.key});

  @override
  State<OnboardingWalkthroughScreen> createState() =>
      _OnboardingWalkthroughScreenState();
}

class _OnboardingWalkthroughScreenState
    extends State<OnboardingWalkthroughScreen> {
  int _currentIndex = 0;

  void _goTo(int index) {
    final clamped = index.clamp(0, _kCards.length - 1);
    if (clamped == _currentIndex) return;
    setState(() => _currentIndex = clamped);
  }

  void _next() => _goTo(_currentIndex + 1);
  void _skip() => _goTo(_kCards.length - 1);

  bool get _isLast => _currentIndex == _kCards.length - 1;

  @override
  Widget build(BuildContext context) {
    final card = _kCards[_currentIndex];

    return Scaffold(
      backgroundColor: WW.bg,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -200) _next();
          if (v > 200) _goTo(_currentIndex - 1);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Illustration area ──────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, anim) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(parent: anim, curve: Curves.easeOut),
                      );
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: _IllustrationPane(
                      key: ValueKey(_currentIndex),
                      bg: card.illustrationBg,
                      illustration: card.illustration,
                    ),
                  ),
                  // Skip button
                  if (!_isLast)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      right: 20,
                      child: GestureDetector(
                        onTap: _skip,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: WW.textSec,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Text + dots + CTA ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title + body
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, anim) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(parent: anim, curve: Curves.easeOut),
                      );
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: _TextBlock(
                      key: ValueKey('text_$_currentIndex'),
                      title: card.title,
                      body: card.body,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_kCards.length, (i) {
                      final active = i == _currentIndex;
                      return GestureDetector(
                        onTap: () => _goTo(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          width: active ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: active ? WW.primary : WW.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 22),

                  // CTA buttons
                  if (_isLast) ...[
                    _PrimaryButton(
                      label: 'Create Account',
                      onTap: () => context.go(Routes.register),
                    ),
                    const SizedBox(height: 12),
                    _OutlineButton(
                      label: 'Log In',
                      onTap: () => context.go(Routes.login),
                    ),
                  ] else
                    _PrimaryButton(
                      label: 'Next',
                      onTap: _next,
                    ),

                  SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 44),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Illustration pane ─────────────────────────────────────────────────────────

class _IllustrationPane extends StatelessWidget {
  final Color bg;
  final Widget illustration;

  const _IllustrationPane({
    super.key,
    required this.bg,
    required this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Center(child: illustration),
    );
  }
}

// ── Text block ────────────────────────────────────────────────────────────────

class _TextBlock extends StatelessWidget {
  final String title;
  final String body;

  const _TextBlock({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: WW.primaryDark,
            letterSpacing: -0.6,
            height: 1.18,
          ),
        ),
        const SizedBox(height: 11),
        Text(
          body,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: WW.textSec,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

// ── Buttons ───────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: WW.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: WW.primary.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WW.primary, width: 1.5),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: WW.primary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Illustrations ─────────────────────────────────────────────────────────────

class _CoachIllustration extends StatelessWidget {
  const _CoachIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 220,
      child: CustomPaint(painter: _CoachPainter()),
    );
  }
}

class _CalendarIllustration extends StatelessWidget {
  const _CalendarIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 220,
      child: CustomPaint(painter: _CalendarPainter()),
    );
  }
}

class _PodiumIllustration extends StatelessWidget {
  const _PodiumIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 220,
      child: CustomPaint(painter: _PodiumPainter()),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

class _CoachPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFFE8EAF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final lavBg = Paint()..color = WW.lavenderBg..style = PaintingStyle.fill;
    final lav = Paint()..color = WW.lavender..style = PaintingStyle.fill;
    final primary = Paint()..color = WW.primary..style = PaintingStyle.fill;
    final textDark = Paint()
      ..color = const Color(0xFFD8CCEE)
      ..style = PaintingStyle.fill;
    final textLight = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    final textLighter = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    // Phone shell
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(80, 16, 100, 176), const Radius.circular(18)),
        white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(80, 16, 100, 176), const Radius.circular(18)),
        border);
    // Notch bar
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(107, 22, 46, 10), const Radius.circular(5)),
        Paint()..color = const Color(0xFFE8EAF8));

    // Coach bubble 1
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(90, 46, 72, 42), const Radius.circular(12)),
        lavBg);
    canvas.drawCircle(const Offset(100, 67), 10, lav);
    // Check mark
    final checkPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final checkPath = Path()
      ..moveTo(97, 67)
      ..lineTo(99.5, 69.5)
      ..lineTo(104, 64.5);
    canvas.drawPath(checkPath, checkPaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(114, 56, 40, 7), const Radius.circular(3.5)),
        textDark);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(114, 67, 28, 7), const Radius.circular(3.5)),
        textDark);

    // User bubble
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(98, 100, 64, 30), const Radius.circular(12)),
        primary);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(104, 108, 42, 6), const Radius.circular(3)),
        textLight);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(104, 118, 28, 6), const Radius.circular(3)),
        textLighter);

    // Coach bubble 2
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(90, 142, 72, 38), const Radius.circular(12)),
        lavBg);
    canvas.drawCircle(const Offset(100, 161), 10, lav);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(114, 151, 40, 7), const Radius.circular(3.5)),
        textDark);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(114, 161, 32, 7), const Radius.circular(3.5)),
        textDark);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(114, 171, 22, 7), const Radius.circular(3.5)),
        textDark);

    // Sparkles
    _drawStar(canvas, const Offset(196, 47.5), 5,
        WW.lavender.withOpacity(0.55));
    _drawStar(
        canvas, const Offset(46, 94.8), 3, WW.primary.withOpacity(0.4));
    canvas.drawCircle(const Offset(220, 160), 5,
        Paint()..color = WW.lavender.withOpacity(0.25));
    canvas.drawCircle(const Offset(40, 50), 4,
        Paint()..color = WW.primary.withOpacity(0.2));
  }

  void _drawStar(Canvas canvas, Offset center, double r, Color color) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = i * 3.14159265 / 4;
      final radius = i.isEven ? r : r * 0.45;
      final x = center.dx + radius * _cos(angle);
      final y = center.dy - radius * _sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  double _cos(double a) => _sin(a + 1.5707963);
  double _sin(double a) {
    double x = a % 6.2831853;
    if (x > 3.1415926) x -= 6.2831853;
    if (x < -3.1415926) x += 6.2831853;
    final x3 = x * x * x;
    final x5 = x3 * x * x;
    final x7 = x5 * x * x;
    return x - x3 / 6 + x5 / 120 - x7 / 5040;
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CalendarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = WW.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final teal = Paint()..color = WW.teal..style = PaintingStyle.fill;
    final primary = Paint()..color = WW.primary..style = PaintingStyle.fill;
    final lightGrey = Paint()
      ..color = WW.elevated
      ..style = PaintingStyle.fill;
    final chipBg = Paint()..color = WW.chipBg..style = PaintingStyle.fill;

    // Calendar base
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(50, 36, 160, 148), const Radius.circular(18)),
        white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(50, 36, 160, 148), const Radius.circular(18)),
        borderPaint);

    // Header
    final headerPath = Path()
      ..addRRect(RRect.fromRectAndCorners(
        const Rect.fromLTWH(50, 36, 160, 44),
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
      ));
    canvas.drawPath(headerPath, teal);
    // Header text
    final tp = TextPainter(
      text: const TextSpan(
        text: 'May 2025',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(130 - tp.width / 2, 52));

    // Day labels
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    for (int i = 0; i < 7; i++) {
      final lp = TextPainter(
        text: TextSpan(
          text: dayLabels[i],
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: WW.textSec,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lp.paint(canvas, Offset(70 + i * 22 - lp.width / 2, 88));
    }

    // Week rows
    const rows = [
      [0, 0, 0, 1, 2, 3, 4],
      [5, 6, 7, 8, 9, 10, 11],
      [12, 13, 14, 15, 16, 17, 18],
    ];
    final filledCells = {
      '0,5', '1,2', '1,4', '2,0', '2,3'
    };
    final weekendCells = {'0,6', '1,6', '2,6'};

    for (int ri = 0; ri < rows.length; ri++) {
      for (int ci = 0; ci < 7; ci++) {
        final d = rows[ri][ci];
        if (d == 0) continue;
        final cx = 70.0 + ci * 22;
        final cy = 116.0 + ri * 26;
        final key = '$ri,$ci';

        if (filledCells.contains(key)) {
          canvas.drawCircle(Offset(cx, cy), 11, primary);
        } else if (weekendCells.contains(key)) {
          canvas.drawCircle(Offset(cx, cy), 11, lightGrey);
        }

        final color = filledCells.contains(key) ? Colors.white : WW.text;
        final np = TextPainter(
          text: TextSpan(
            text: '$d',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        np.paint(canvas, Offset(cx - np.width / 2, cy - np.height / 2 + 1));
      }
    }

    // "Adjusted ✓" chip
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(158, 172, 52, 28), const Radius.circular(10)),
        chipBg);
    final cp = TextPainter(
      text: const TextSpan(
        text: 'Adjusted ✓',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: WW.primary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    cp.paint(canvas, Offset(184 - cp.width / 2, 183));

    // Sparkles
    _drawStar(canvas, const Offset(220, 57.5), 4,
        WW.teal.withOpacity(0.5));
    canvas.drawCircle(const Offset(38, 100), 5,
        Paint()..color = WW.primary.withOpacity(0.2));
  }

  void _drawStar(Canvas canvas, Offset center, double r, Color color) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = i * 3.14159265 / 4;
      final radius = i.isEven ? r : r * 0.45;
      final x = center.dx + radius * _cos(angle);
      final y = center.dy - radius * _sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  double _cos(double a) => _sin(a + 1.5707963);
  double _sin(double a) {
    double x = a % 6.2831853;
    if (x > 3.1415926) x -= 6.2831853;
    if (x < -3.1415926) x += 6.2831853;
    final x3 = x * x * x;
    final x5 = x3 * x * x;
    final x7 = x5 * x * x;
    return x - x3 / 6 + x5 / 120 - x7 / 5040;
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PodiumPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final silver = Paint()
      ..color = const Color(0xFFD9DFF8)
      ..style = PaintingStyle.fill;
    final primary = Paint()..color = WW.primary..style = PaintingStyle.fill;
    final lavender = Paint()..color = WW.lavender..style = PaintingStyle.fill;
    final grey = Paint()
      ..color = const Color(0xFFC8C8D8)
      ..style = PaintingStyle.fill;
    final chipBg = Paint()..color = WW.chipBg..style = PaintingStyle.fill;
    final tealBg = Paint()..color = WW.tealBg..style = PaintingStyle.fill;
    final gold = Paint()
      ..color = WW.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Podium blocks
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(74, 124, 40, 66), const Radius.circular(8)),
        silver);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(110, 104, 40, 86), const Radius.circular(8)),
        primary);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(146, 136, 40, 54), const Radius.circular(8)),
        silver);

    // Rank numbers
    void drawRank(String n, Offset pos, Color color) {
      final tp = TextPainter(
        text: TextSpan(
          text: n,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    drawRank('2', const Offset(94, 160), WW.textSec);
    drawRank('1', const Offset(130, 138), Colors.white);
    drawRank('3', const Offset(166, 172), WW.textSec);

    // Avatars
    canvas.drawCircle(const Offset(94, 106), 16, grey);
    canvas.drawCircle(const Offset(130, 84), 18, primary);
    canvas.drawCircle(const Offset(166, 118), 16, lavender);

    // Crown above center avatar
    final crownPath = Path()
      ..moveTo(120, 80)
      ..lineTo(123.5, 74)
      ..lineTo(130, 77.5)
      ..lineTo(136.5, 74)
      ..lineTo(140, 80);
    canvas.drawPath(crownPath, gold);

    // XP chip
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(60, 36, 60, 22), const Radius.circular(11)),
        chipBg);
    final xpTp = TextPainter(
      text: const TextSpan(
        text: '+250 XP',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: WW.primary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    xpTp.paint(canvas, Offset(90 - xpTp.width / 2, 44));

    // Streak chip
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(140, 36, 60, 22), const Radius.circular(11)),
        tealBg);
    final stTp = TextPainter(
      text: const TextSpan(
        text: 'Streak 🔥',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: WW.teal),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stTp.paint(canvas, Offset(170 - stTp.width / 2, 44));

    // Star
    _drawStar(canvas, const Offset(218, 86), 6, WW.gold.withOpacity(0.75));
  }

  void _drawStar(Canvas canvas, Offset center, double r, Color color) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = i * 3.14159265 / 5 - 3.14159265 / 2;
      final radius = i.isEven ? r : r * 0.4;
      final x = center.dx + radius * _cos(angle);
      final y = center.dy + radius * _sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  double _cos(double a) => _sin(a + 1.5707963);
  double _sin(double a) {
    double x = a % 6.2831853;
    if (x > 3.1415926) x -= 6.2831853;
    if (x < -3.1415926) x += 6.2831853;
    final x3 = x * x * x;
    final x5 = x3 * x * x;
    final x7 = x5 * x * x;
    return x - x3 / 6 + x5 / 120 - x7 / 5040;
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
