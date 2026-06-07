// lib/screens/onboarding/onboarding_step3_screen.dart
// Onboarding Step 3 — Permission Priming.
// Three full-screen cards (notifications, location, motion) shown one at a time.
// Enable taps: saves permission flag via FirestoreService.saveOnboardingStep3(),
//              turns button green, advances after 600 ms.
// Skip taps:   advances without saving.
// After card 3: calls markOnboardingComplete() then navigates to Routes.home.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Card data model ────────────────────────────────────────────────────────────

class _CardData {
  final String id;
  final Color accentColor;
  final Color iconBg;
  final IconData iconData;
  final bool hasBadge;
  final String headline;
  final String body;
  final List<String> benefits;
  final String ctaLabel;
  final String note;

  const _CardData({
    required this.id,
    required this.accentColor,
    required this.iconBg,
    required this.iconData,
    this.hasBadge = false,
    required this.headline,
    required this.body,
    required this.benefits,
    required this.ctaLabel,
    required this.note,
  });
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class OnboardingStep3Screen extends StatefulWidget {
  const OnboardingStep3Screen({super.key});

  @override
  State<OnboardingStep3Screen> createState() => _OnboardingStep3ScreenState();
}

class _OnboardingStep3ScreenState extends State<OnboardingStep3Screen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  int _cardIndex = 0;
  bool _tapped = false;
  Map<String, bool> _permissions = {
    'notifications': false,
    'location': false,
    'motion': false,
  };
  bool _isLoading = false;

  static const List<_CardData> _cards = [
    _CardData(
      id: 'notifications',
      accentColor: WW.primary,
      iconBg: WW.chipBg,
      iconData: Icons.notifications_rounded,
      hasBadge: true,
      headline: 'Never miss a workout',
      body:
          "Get timely reminders for your scheduled sessions, celebrate milestones, and receive nudges when you're about to break your streak.",
      benefits: ['Session reminders', 'Milestone alerts', 'Streak protection'],
      ctaLabel: 'Enable Notifications',
      note: 'You can change this any time in Settings.',
    ),
    _CardData(
      id: 'location',
      accentColor: WW.teal,
      iconBg: WW.tealBg,
      iconData: Icons.location_on_rounded,
      headline: 'Track your routes',
      body:
          'GPS tracking maps your outdoor runs, cycling rides, and walks in real time — showing pace, elevation and route replay in your summary.',
      benefits: ['Live GPS mapping', 'Pace & elevation', 'Route history'],
      ctaLabel: 'Enable Location',
      note: 'Used only during active outdoor sessions.',
    ),
    _CardData(
      id: 'motion',
      accentColor: WW.lavender,
      iconBg: WW.lavenderBg,
      iconData: Icons.phone_android_rounded,
      headline: 'Auto-track your activity',
      body:
          "Let WiseWorkout count your daily steps and estimate calories automatically using your phone's built-in motion sensors.",
      benefits: ['Step counting', 'Calorie estimation', 'Activity detection'],
      ctaLabel: 'Enable Motion & Fitness',
      note: 'Never affects battery beyond normal usage.',
    ),
  ];

  // ---------------------------------------------------------------------------
  // Enable button handler — saves permission, animates, then advances.
  // ---------------------------------------------------------------------------
  Future<void> _handleEnable() async {
    if (_tapped) return;

    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    final card = _cards[_cardIndex];
    setState(() {
      _tapped = true;
      _permissions[card.id] = true;
    });

    // Fire-and-forget save so the 600 ms animation is not blocked.
    _firestoreService
        .saveOnboardingStep3(uid, {'${card.id}Enabled': true})
        .catchError((_) {});

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) _advance();
  }

  // ---------------------------------------------------------------------------
  // Skip — advances without saving the permission.
  // ---------------------------------------------------------------------------
  void _handleSkip() => _advance();

  // ---------------------------------------------------------------------------
  // Moves to the next card or finishes onboarding after the last card.
  // ---------------------------------------------------------------------------
  void _advance() {
    if (_cardIndex < _cards.length - 1) {
      setState(() {
        _cardIndex++;
        _tapped = false;
      });
    } else {
      _finishOnboarding();
    }
  }

  // ---------------------------------------------------------------------------
  // Marks onboarding complete in Firestore then navigates home.
  // ---------------------------------------------------------------------------
  Future<void> _finishOnboarding() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      await _firestoreService.markOnboardingComplete(uid);
      if (mounted) context.go(Routes.home);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: WW.bg,
        body: Center(child: CircularProgressIndicator(color: WW.primary)),
      );
    }

    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildStepHeader(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_cardIndex),
                  child: _buildCard(_cards[_cardIndex]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step header ──────────────────────────────────────────────────────────

  Widget _buildStepHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step 3 of 3 · ${_cardIndex + 1}/3',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WW.textSec,
                  letterSpacing: 0.3,
                ),
              ),
              // Animated progress dots — filled up to current, current elongated
              Row(
                children: List.generate(3, (i) {
                  final active = i <= _cardIndex;
                  final current = i == _cardIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                    width: current ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active ? WW.primary : WW.elevated,
                      borderRadius: BorderRadius.circular(3.5),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Step 3 is the final step — progress bar is always full.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: const LinearProgressIndicator(
              value: 1.0,
              backgroundColor: WW.elevated,
              color: WW.primary,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Card content ─────────────────────────────────────────────────────────

  Widget _buildCard(_CardData card) {
    final isLast = _cardIndex == _cards.length - 1;
    final rippleColor = card.accentColor.withOpacity(0.15);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),

          // ── Icon with ripple rings ──────────────────────────────────────
          _PulsingRipple(
            rippleColor: rippleColor,
            iconBg: card.iconBg,
            accentColor: card.accentColor,
            iconWidget: _buildIconWidget(card),
          ),
          const SizedBox(height: 32),

          // ── Headline ───────────────────────────────────────────────────
          Text(
            card.headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),

          // ── Body ───────────────────────────────────────────────────────
          Text(
            card.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: WW.textSec,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 28),

          // ── Benefit pills ──────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: card.benefits.map((b) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: card.iconBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: card.accentColor.withOpacity(0.2),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  b,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: card.accentColor,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 36),

          // ── Enable CTA button ──────────────────────────────────────────
          GestureDetector(
            onTap: _tapped ? null : _handleEnable,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                color: _tapped ? const Color(0xFF10B981) : card.accentColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: (_tapped
                            ? const Color(0xFF10B981)
                            : card.accentColor)
                        .withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _tapped
                      ? Row(
                          key: const ValueKey('done'),
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Done',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          key: const ValueKey('cta'),
                          card.ctaLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Skip link ──────────────────────────────────────────────────
          GestureDetector(
            onTap: _handleSkip,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                isLast ? 'Skip and go to Home' : 'Skip for now',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WW.textSec,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Footer note ────────────────────────────────────────────────
          Text(
            card.note,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: WW.textSec,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Builds the icon widget for a card, adding a red badge dot for notifications.
  Widget _buildIconWidget(_CardData card) {
    if (!card.hasBadge) {
      return Icon(card.iconData, color: card.accentColor, size: 44);
    }
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(card.iconData, color: card.accentColor, size: 44),
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
              border: Border.all(color: card.iconBg, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pulsing ripple icon container ──────────────────────────────────────────────
// Renders two concentric ripple rings that expand and fade, with the icon
// sitting in a rounded-square container on top.

class _PulsingRipple extends StatefulWidget {
  final Color rippleColor;
  final Color iconBg;
  final Color accentColor;
  final Widget iconWidget;

  const _PulsingRipple({
    required this.rippleColor,
    required this.iconBg,
    required this.accentColor,
    required this.iconWidget,
  });

  @override
  State<_PulsingRipple> createState() => _PulsingRippleState();
}

class _PulsingRippleState extends State<_PulsingRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Builds one ripple ring at the given phase offset (0.0–1.0).
  Widget _ring(double phase) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = (_controller.value + phase) % 1.0;
        return Opacity(
          opacity: (1.0 - t) * 0.6,
          child: Transform.scale(
            scale: 0.8 + t, // expands from 0.8× to 1.8× of the 120px base
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.rippleColor,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(0.0),
          _ring(0.35), // second ring offset by 35% so they stagger
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: widget.iconBg,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: widget.accentColor.withOpacity(0.13),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.rippleColor,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(child: widget.iconWidget),
          ),
        ],
      ),
    );
  }
}
