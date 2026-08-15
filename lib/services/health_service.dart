// lib/services/health_service.dart
// Reads heart-rate data from the device's native health store (Apple
// HealthKit / Android Health Connect) via the `health` package, for use
// during cardio sessions.

import 'dart:io';
import 'package:health/health.dart';

class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final Health _health = Health();
  bool _configured = false;

  // Heart Rate is the only type any call site in the app actually reads —
  // getTodaySteps()/getTodayCalories() below are unreachable dead code (no
  // callers anywhere in the repo, confirmed by grep), so STEPS/
  // ACTIVE_ENERGY_BURNED were dropped here to keep the OS permission
  // dialog limited to what's actually used.
  static const List<HealthDataType> _readTypes = [
    HealthDataType.HEART_RATE,
  ];

  /// health: ^12.0.0's `Health` class docs say `configure()` must be called
  /// before any other method — cheap, only needs to run once per app launch.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Request HealthKit (iOS) or Health Connect (Android) permissions for
  /// _readTypes. Returns true only if the grant actually succeeded — on iOS
  /// that means the permission dialog was shown without error (HealthKit
  /// never discloses real READ grant state); on Android it reflects the
  /// real Health Connect grant, since Health Connect's permission API can
  /// disclose it. `requestAuthorization` throws on Android if the Health
  /// Connect app isn't installed on the device — caught below, same as any
  /// other failure.
  Future<bool> requestPermissions() async {
    if (!Platform.isIOS && !Platform.isAndroid) return false;
    try {
      await _ensureConfigured();
      final requested = await _health.requestAuthorization(_readTypes);
      return requested;
    } catch (_) {
      return false;
    }
  }

  /// Returns the most recent heart rate in bpm, or null if unavailable.
  Future<double?> getLatestHeartRate() async {
    if (!Platform.isIOS) return null;
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 1));
      final points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: [HealthDataType.HEART_RATE],
      );
      if (points.isEmpty) return null;
      points.sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
      final val = points.first.value;
      if (val is NumericHealthValue) return val.numericValue.toDouble();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns today's total step count, or null if unavailable.
  Future<int?> getTodaySteps() async {
    if (!Platform.isIOS) return null;
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final steps = await _health.getTotalStepsInInterval(midnight, now);
      return steps;
    } catch (_) {
      return null;
    }
  }

  /// Returns today's active calories burned, or null if unavailable.
  Future<double?> getTodayCalories() async {
    if (!Platform.isIOS) return null;
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final points = await _health.getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
      );
      if (points.isEmpty) return null;
      double total = 0;
      for (final p in points) {
        if (p.value is NumericHealthValue) {
          total += (p.value as NumericHealthValue).numericValue.toDouble();
        }
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  /// Returns heart rate readings over a time range as a list of (time, bpm) pairs.
  /// Used to compute avg and max after a session.
  Future<List<({DateTime time, double bpm})>> getHeartRateInRange(
      DateTime start, DateTime end) async {
    if (!Platform.isIOS) return [];
    try {
      final points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: [HealthDataType.HEART_RATE],
      );
      final result = <({DateTime time, double bpm})>[];
      for (final p in points) {
        if (p.value is NumericHealthValue) {
          result.add((
            time: p.dateFrom,
            bpm: (p.value as NumericHealthValue).numericValue.toDouble(),
          ));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }
}
