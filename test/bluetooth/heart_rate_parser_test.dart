import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/bluetooth/heart_rate_parser.dart';
import 'package:pulseboard/models/heart_rate_measurement.dart';

void main() {
  group('HeartRateParser - heart rate value format', () {
    test('parses UINT8 heart rate', () {
      final m = HeartRateParser.parse([0x00, 72]);
      expect(m.bpm, 72);
      expect(m.is16BitValue, isFalse);
      expect(m.contact, SensorContact.notSupported);
      expect(m.energyExpendedKj, isNull);
      expect(m.rrIntervals1024, isEmpty);
    });

    test('parses max UINT8 value 255', () {
      expect(HeartRateParser.parse([0x00, 0xFF]).bpm, 255);
    });

    test('parses UINT16 heart rate little-endian', () {
      // 0x012C = 300 (would be impossible as UINT8)
      final m = HeartRateParser.parse([0x01, 0x2C, 0x01]);
      expect(m.bpm, 300);
      expect(m.is16BitValue, isTrue);
    });

    test('parses UINT16 heart rate with small value', () {
      final m = HeartRateParser.parse([0x01, 150, 0x00]);
      expect(m.bpm, 150);
      expect(m.is16BitValue, isTrue);
    });

    test('ignores trailing bytes when no optional flags are set', () {
      expect(HeartRateParser.parse([0x00, 80, 0x99, 0x98]).bpm, 80);
    });

    test('ignores reserved flag bits 5-7', () {
      final m = HeartRateParser.parse([0xE0, 90]);
      expect(m.bpm, 90);
      expect(m.contact, SensorContact.notSupported);
    });
  });

  group('HeartRateParser - sensor contact', () {
    test('bits 0b00 -> not supported', () {
      expect(HeartRateParser.parse([0x00, 60]).contact, SensorContact.notSupported);
    });

    test('bits 0b01 (detected without supported) -> not supported', () {
      expect(HeartRateParser.parse([0x02, 60]).contact, SensorContact.notSupported);
    });

    test('bits 0b10 -> supported, not detected', () {
      final m = HeartRateParser.parse([0x04, 60]);
      expect(m.contact, SensorContact.notDetected);
      expect(m.hasValidHeartRate, isFalse);
    });

    test('bits 0b11 -> supported and detected', () {
      final m = HeartRateParser.parse([0x06, 60]);
      expect(m.contact, SensorContact.detected);
      expect(m.hasValidHeartRate, isTrue);
    });

    test('zero bpm is never a valid reading', () {
      expect(HeartRateParser.parse([0x06, 0]).hasValidHeartRate, isFalse);
      expect(HeartRateParser.parse([0x00, 0]).hasValidHeartRate, isFalse);
    });
  });

  group('HeartRateParser - energy expended', () {
    test('parses energy after UINT8 HR', () {
      // flags: energy present (0x08); HR 100; energy 0x0203 = 515 kJ
      final m = HeartRateParser.parse([0x08, 100, 0x03, 0x02]);
      expect(m.bpm, 100);
      expect(m.energyExpendedKj, 515);
    });

    test('parses energy after UINT16 HR', () {
      final m = HeartRateParser.parse([0x09, 0x64, 0x00, 0xFF, 0xFF]);
      expect(m.bpm, 100);
      expect(m.energyExpendedKj, 65535);
    });

    test('throws when energy flag set but field is truncated', () {
      expect(
        () => HeartRateParser.parse([0x08, 100, 0x03]),
        throwsA(isA<HeartRateParseException>()),
      );
    });
  });

  group('HeartRateParser - RR intervals', () {
    test('parses a single RR interval', () {
      // 0x0334 = 820 -> 820/1024 s = 800.78 ms
      final m = HeartRateParser.parse([0x10, 75, 0x34, 0x03]);
      expect(m.rrIntervals1024, [820]);
      expect(m.rrIntervalsMs.single, closeTo(800.78, 0.01));
    });

    test('parses multiple RR intervals', () {
      final m = HeartRateParser.parse([0x10, 75, 0x00, 0x04, 0x00, 0x02]);
      expect(m.rrIntervals1024, [1024, 512]);
      expect(m.rrIntervalsMs, [1000.0, 500.0]);
    });

    test('parses RR intervals after energy and UINT16 HR', () {
      final m = HeartRateParser.parse([
        0x1F, // 16-bit HR, contact detected+supported, energy, RR
        0xB4, 0x00, // HR 180
        0x10, 0x00, // energy 16
        0x55, 0x01, // RR 341
      ]);
      expect(m.bpm, 180);
      expect(m.contact, SensorContact.detected);
      expect(m.energyExpendedKj, 16);
      expect(m.rrIntervals1024, [341]);
    });

    test('RR flag with no RR bytes yields empty list', () {
      expect(HeartRateParser.parse([0x10, 75]).rrIntervals1024, isEmpty);
    });

    test('dangling odd byte after RR intervals is ignored', () {
      final m = HeartRateParser.parse([0x10, 75, 0x00, 0x04, 0x07]);
      expect(m.bpm, 75);
      expect(m.rrIntervals1024, [1024]);
    });

    test('RR bytes are ignored when RR flag is not set', () {
      expect(HeartRateParser.parse([0x00, 75, 0x00, 0x04]).rrIntervals1024, isEmpty);
    });
  });

  group('HeartRateParser - malformed packets', () {
    test('empty packet throws', () {
      expect(() => HeartRateParser.parse([]), throwsA(isA<HeartRateParseException>()));
    });

    test('flags only (missing UINT8 HR) throws', () {
      expect(() => HeartRateParser.parse([0x00]), throwsA(isA<HeartRateParseException>()));
    });

    test('UINT16 flag with only one HR byte throws', () {
      expect(() => HeartRateParser.parse([0x01, 0x50]), throwsA(isA<HeartRateParseException>()));
    });

    test('out-of-range byte values throw', () {
      expect(() => HeartRateParser.parse([0x00, 300]), throwsA(isA<HeartRateParseException>()));
      expect(() => HeartRateParser.parse([-1, 60]), throwsA(isA<HeartRateParseException>()));
    });

    test('tryParse returns null instead of throwing', () {
      expect(HeartRateParser.tryParse([]), isNull);
      expect(HeartRateParser.tryParse([0x01, 0x50]), isNull);
      expect(HeartRateParser.tryParse([0x00, 61])?.bpm, 61);
    });
  });

  group('parseBatteryLevel', () {
    test('valid percentages', () {
      expect(parseBatteryLevel([0]), 0);
      expect(parseBatteryLevel([87]), 87);
      expect(parseBatteryLevel([100]), 100);
    });

    test('invalid input returns null', () {
      expect(parseBatteryLevel([]), isNull);
      expect(parseBatteryLevel([101]), isNull);
      expect(parseBatteryLevel([255]), isNull);
    });
  });
}
