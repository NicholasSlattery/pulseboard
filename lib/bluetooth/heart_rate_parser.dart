import '../models/heart_rate_measurement.dart';

/// Thrown when a Heart Rate Measurement packet cannot be decoded.
class HeartRateParseException implements Exception {
  const HeartRateParseException(this.message, this.bytes);

  final String message;
  final List<int> bytes;

  @override
  String toString() => 'HeartRateParseException: $message (${bytes.length} bytes)';
}

/// Decoder for the Bluetooth SIG Heart Rate Measurement characteristic
/// (0x2A37), per the Heart Rate Service specification.
///
/// Packet layout (little-endian):
///
/// | Field             | Size        | Present when         |
/// |-------------------|-------------|----------------------|
/// | Flags             | 1 byte      | always               |
/// | Heart rate        | 1 or 2 bytes| always (bit 0 = size)|
/// | Energy expended   | 2 bytes     | flags bit 3          |
/// | RR intervals      | 2 bytes each| flags bit 4          |
///
/// Flags:
/// * bit 0   - 0: HR is UINT8, 1: HR is UINT16
/// * bit 1-2 - sensor contact: 0b00/0b01 not supported, 0b10 supported but
///             not detected, 0b11 supported and detected
/// * bit 3   - energy expended (UINT16, kJ) present
/// * bit 4   - one or more RR intervals (UINT16, 1/1024 s) present
/// * bit 5-7 - reserved for future use (ignored)
abstract final class HeartRateParser {
  static const int _flagHr16Bit = 0x01;
  static const int _flagContactDetected = 0x02;
  static const int _flagContactSupported = 0x04;
  static const int _flagEnergyExpended = 0x08;
  static const int _flagRrIntervals = 0x10;

  /// Decodes [bytes]. Throws [HeartRateParseException] on malformed input.
  ///
  /// Strict on the mandatory HR field and the energy field; lenient on a
  /// dangling odd byte after the RR intervals (seen on some cheap straps),
  /// which is ignored rather than discarding an otherwise valid HR value.
  static HeartRateMeasurement parse(List<int> bytes) {
    if (bytes.isEmpty) {
      throw HeartRateParseException('empty packet', bytes);
    }
    for (final b in bytes) {
      if (b < 0 || b > 0xFF) {
        throw HeartRateParseException('byte out of range: $b', bytes);
      }
    }

    final flags = bytes[0];
    final is16Bit = (flags & _flagHr16Bit) != 0;
    var offset = 1;

    final int bpm;
    if (is16Bit) {
      if (bytes.length < offset + 2) {
        throw HeartRateParseException('truncated UINT16 heart rate', bytes);
      }
      bpm = _uint16(bytes, offset);
      offset += 2;
    } else {
      if (bytes.length < offset + 1) {
        throw HeartRateParseException('truncated UINT8 heart rate', bytes);
      }
      bpm = bytes[offset];
      offset += 1;
    }

    final contact = _decodeContact(flags);

    int? energy;
    if ((flags & _flagEnergyExpended) != 0) {
      if (bytes.length < offset + 2) {
        throw HeartRateParseException('truncated energy expended field', bytes);
      }
      energy = _uint16(bytes, offset);
      offset += 2;
    }

    final rr = <int>[];
    if ((flags & _flagRrIntervals) != 0) {
      while (offset + 1 < bytes.length) {
        rr.add(_uint16(bytes, offset));
        offset += 2;
      }
    }

    return HeartRateMeasurement(
      bpm: bpm,
      contact: contact,
      is16BitValue: is16Bit,
      energyExpendedKj: energy,
      rrIntervals1024: List.unmodifiable(rr),
    );
  }

  /// Like [parse] but returns null instead of throwing.
  static HeartRateMeasurement? tryParse(List<int> bytes) {
    try {
      return parse(bytes);
    } on HeartRateParseException {
      return null;
    }
  }

  static SensorContact _decodeContact(int flags) {
    if ((flags & _flagContactSupported) == 0) return SensorContact.notSupported;
    return (flags & _flagContactDetected) != 0 ? SensorContact.detected : SensorContact.notDetected;
  }

  static int _uint16(List<int> bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8);
}

/// Decodes the Battery Level characteristic (0x2A19): a single UINT8 in the
/// range 0-100. Returns null for anything else.
int? parseBatteryLevel(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final value = bytes[0];
  if (value < 0 || value > 100) return null;
  return value;
}
