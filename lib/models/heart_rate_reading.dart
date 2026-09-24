import 'package:flutter/foundation.dart';

import 'heart_rate_measurement.dart';

/// A timestamped, decoded HR notification from a specific sensor.
@immutable
class HeartRateReading {
  const HeartRateReading({
    required this.sensorId,
    required this.timestamp,
    required this.measurement,
  });

  final String sensorId;

  /// Time the notification arrived on this device.
  final DateTime timestamp;
  final HeartRateMeasurement measurement;

  int get bpm => measurement.bpm;
  bool get isValid => measurement.hasValidHeartRate;
}
