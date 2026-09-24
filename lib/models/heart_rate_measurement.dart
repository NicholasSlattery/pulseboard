import 'package:flutter/foundation.dart';

/// Skin-contact status reported in bits 1-2 of the Heart Rate Measurement
/// flags byte.
enum SensorContact {
  /// The strap does not report contact status.
  notSupported,

  /// The strap supports contact detection and reports NO skin contact.
  /// HR values in this state are not trustworthy.
  notDetected,

  /// The strap supports contact detection and reports good skin contact.
  detected,
}

/// A decoded Heart Rate Measurement (characteristic 0x2A37) packet.
@immutable
class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.bpm,
    required this.contact,
    required this.is16BitValue,
    this.energyExpendedKj,
    this.rrIntervals1024 = const [],
  });

  /// Heart rate in beats per minute. Some straps send 0 when they have no
  /// reading; see [hasValidHeartRate].
  final int bpm;

  final SensorContact contact;

  /// Whether the packet encoded HR as UINT16 (flags bit 0).
  final bool is16BitValue;

  /// Cumulative energy expended in kilojoules, if present (flags bit 3).
  final int? energyExpendedKj;

  /// RR intervals in the raw units defined by the spec: 1/1024 second.
  /// Kept raw so storage is lossless.
  final List<int> rrIntervals1024;

  /// RR intervals converted to milliseconds.
  List<double> get rrIntervalsMs => rrIntervals1024.map(rrToMilliseconds).toList(growable: false);

  /// True when the packet carries a usable HR value: non-zero and not
  /// explicitly flagged as "no skin contact".
  bool get hasValidHeartRate => bpm > 0 && contact != SensorContact.notDetected;

  static double rrToMilliseconds(int raw1024) => raw1024 * 1000.0 / 1024.0;

  @override
  bool operator ==(Object other) =>
      other is HeartRateMeasurement &&
      other.bpm == bpm &&
      other.contact == contact &&
      other.is16BitValue == is16BitValue &&
      other.energyExpendedKj == energyExpendedKj &&
      listEquals(other.rrIntervals1024, rrIntervals1024);

  @override
  int get hashCode =>
      Object.hash(bpm, contact, is16BitValue, energyExpendedKj, Object.hashAll(rrIntervals1024));

  @override
  String toString() =>
      'HeartRateMeasurement(bpm: $bpm, contact: ${contact.name}, '
      '16bit: $is16BitValue, energy: $energyExpendedKj, rr: $rrIntervals1024)';
}
