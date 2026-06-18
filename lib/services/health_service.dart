import 'dart:io';
import 'package:health/health.dart';

class HealthService {
  static final HealthService _instance = HealthService._internal();
  factory HealthService() => _instance;
  HealthService._internal();

  final Health _health = Health();

  static const List<HealthDataType> _readTypes = [
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  /// Request HealthKit permissions. Returns true if granted, false otherwise.
  /// Always returns false on Android or simulator.
  Future<bool> requestPermissions() async {
    if (!Platform.isIOS) return false;
    try {
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
