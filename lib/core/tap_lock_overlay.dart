// lib/core/tap_lock_overlay.dart
//
// Global guard against rapid double-taps triggering duplicate navigation.
// Wraps the WHOLE app once (see main.dart's MaterialApp.router `builder`) —
// not any individual screen. A real crash (GlobalKey collision at the root
// Navigator/HeroControllerScope level) was traced to a user tapping twice
// in quick succession, likely during a slow/laggy frame, before the first
// tap's context.push()/go() had been reconciled into the tree — two
// near-simultaneous navigations to the same route can produce colliding
// page keys. Per-route fixes already exist for the two routes that
// actually crashed this way (router.dart's _lastGymSessionIdentity/
// _lastCardioSetupIdentity), but this closes the same failure class for
// EVERY route, without touching any of the ~35 files/114 call sites that
// call context.go()/context.push().
//
// Mechanism: after any pointer-down lands anywhere in the app, a
// full-screen invisible AbsorbPointer appears for _lockDuration and
// swallows every subsequent pointer-down until it expires — so a rapid
// second tap never reaches its button's onTap at all, and never gets the
// chance to fire a second, colliding navigation. The triggering tap itself
// is never touched — the overlay only appears AFTER it's already been
// dispatched to its target via the normal hit-test pass — so a normal
// single tap has zero added delay.
import 'dart:async';

import 'package:flutter/material.dart';

class TapLockOverlay extends StatefulWidget {
  final Widget child;
  const TapLockOverlay({super.key, required this.child});

  @override
  State<TapLockOverlay> createState() => _TapLockOverlayState();
}

class _TapLockOverlayState extends State<TapLockOverlay> {
  static const _lockDuration = Duration(milliseconds: 350);
  Timer? _timer;
  bool _locked = false;

  void _armLock() {
    _timer?.cancel();
    if (!_locked) setState(() => _locked = true);
    _timer = Timer(_lockDuration, () {
      if (mounted) setState(() => _locked = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _armLock(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_locked)
            const AbsorbPointer(
              absorbing: true,
              child: SizedBox.expand(),
            ),
        ],
      ),
    );
  }
}
