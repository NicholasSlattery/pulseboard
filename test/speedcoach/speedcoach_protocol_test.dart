import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/speedcoach/speedcoach_protocol.dart';

List<int> hex(String s) =>
    s.split(' ').where((p) => p.isNotEmpty).map((p) => int.parse(p, radix: 16)).toList();

void main() {
  group('SpeedCoachUuids', () {
    test('18 characteristics in NK order', () {
      expect(SpeedCoachUuids.suffixes.length, 18);
      expect(SpeedCoachUuids.char('0103'), '3291ddee-0889-409c-b993-24ec01039970');
    });

    test('suffixOf recognises only NK characteristics', () {
      expect(SpeedCoachUuids.suffixOf('3291DDEE-0889-409C-B993-24EC02039970'), '0203');
      expect(SpeedCoachUuids.suffixOf('00002a37-0000-1000-8000-00805f9b34fb'), isNull);
      expect(SpeedCoachUuids.suffixOf(SpeedCoachUuids.service), '0000');
    });
  });

  // Packets below are real captures from a SpeedCoach GPS Pro (fw 2.25).
  group('SpeedCoachStatusPacket', () {
    test('elapsed time while paused at 1:15.05', () {
      final p = SpeedCoachStatusPacket.parse(
        hex('ee aa f5 17 bb da 1d cb 00 00 00 00 00 00 00 00 2e 25 01 00'),
      )!;
      expect(p.elapsed, const Duration(milliseconds: 75054));
    });

    test('elapsed time crosses a byte boundary correctly', () {
      final p = SpeedCoachStatusPacket.parse(
        hex('ee aa f5 17 bb da 1d cb 00 00 00 00 00 00 00 00 a6 00 02 00'),
      )!;
      expect(p.elapsed, const Duration(milliseconds: 131238));
    });

    test('rejects wrong lengths', () {
      expect(SpeedCoachStatusPacket.parse(hex('01 02 03')), isNull);
      expect(SpeedCoachStatusPacket.parse([]), isNull);
    });
  });

  group('SpeedCoachStrokePacket', () {
    test('stroke count', () {
      final p = SpeedCoachStrokePacket.parse(
        hex('1e ff 00 00 00 00 00 00 00 00 00 00 00 00 26 00 00 00 00 00'),
      )!;
      expect(p.strokeCount, 38);
      expect(p.isIdle, isFalse);
    });

    test('idle marker', () {
      final p = SpeedCoachStrokePacket.parse(
        hex('00 ff ff ff 00 00 ff ff 00 00 00 00 00 00 5d 00 00 00 00 00'),
      )!;
      expect(p.isIdle, isTrue);
      expect(p.strokeCount, 93);
    });
  });

  group('StrokeRateEstimator', () {
    final t0 = DateTime(2026, 9, 25, 6);

    test('steady 2 s strokes -> 30 spm', () {
      final e = StrokeRateEstimator();
      for (var i = 0; i < 6; i++) {
        e.addStroke(10 + i, t0.add(Duration(seconds: 2 * i)));
      }
      expect(e.rate, closeTo(30, 0.01));
    });

    test('median ignores one late packet', () {
      final e = StrokeRateEstimator();
      final times = [0, 2000, 4000, 6600, 8000, 10000];
      for (var i = 0; i < times.length; i++) {
        e.addStroke(i, t0.add(Duration(milliseconds: times[i])));
      }
      expect(e.rate, closeTo(30, 0.01));
    });

    test('long pause or skipped count resets', () {
      final e = StrokeRateEstimator();
      e.addStroke(1, t0);
      e.addStroke(2, t0.add(const Duration(seconds: 2)));
      expect(e.rate, closeTo(30, 0.01));
      e.addStroke(3, t0.add(const Duration(seconds: 30)));
      expect(e.rate, isNull);
      e.addStroke(5, t0.add(const Duration(seconds: 32)));
      expect(e.rate, isNull);
    });

    test('counter wrap 255 -> 0 counts as one stroke', () {
      final e = StrokeRateEstimator();
      e.addStroke(255, t0);
      e.addStroke(0, t0.add(const Duration(milliseconds: 1500)));
      expect(e.rate, closeTo(40, 0.01));
    });
  });
}
