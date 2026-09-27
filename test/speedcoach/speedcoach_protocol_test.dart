import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/speedcoach/speedcoach_protocol.dart';

List<int> hex(String s) =>
    s.split(' ').where((p) => p.isNotEmpty).map((p) => int.parse(p, radix: 16)).toList();

String mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

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

  // Real packets captured by PulseBoard from a SpeedCoach GPS Pro (fw 2.25),
  // with the values the SpeedCoach itself displayed at the time (from video).
  group('SpeedCoachStrokePacket - verified against the SpeedCoach display', () {
    const verified = <String, (double rate, String split, int count)>{
      '33 ff 6a 00 00 00 f2 00 00 00 82 00 00 00 0e 00 00 00 00 00': (25.5, '7:51', 14),
      '1a ff 67 00 00 00 d3 01 00 00 7a 00 00 00 0f 00 00 00 00 00': (13, '8:05', 15),
      '3d ff 5d 00 00 00 a4 00 00 00 76 00 00 00 10 00 00 00 00 00': (30.5, '8:57', 16),
      '62 ff 4a 00 00 00 4e 00 00 00 73 00 00 00 11 00 00 00 00 00': (49, '11:15', 17),
      '5e ff 3c 00 00 00 46 00 00 00 71 00 00 00 12 00 00 00 00 00': (47, '13:53', 18),
      '29 ff 26 00 00 00 40 00 00 00 65 00 00 00 13 00 00 00 00 00': (20.5, '21:55', 19),
      '2e ff 18 00 00 00 46 00 00 00 5e 00 00 00 14 00 00 00 00 00': (23, '34:43', 20),
      '47 ff 1a 00 00 00 2b 00 00 00 5c 00 00 00 15 00 00 00 00 00': (35.5, '32:03', 21),
      '39 ff 1a 00 00 00 38 00 00 00 56 00 00 00 16 00 00 00 00 00': (28.5, '32:03', 22),
    };

    verified.forEach((packet, expected) {
      final (rate, split, count) = expected;
      test('stroke $count: rate $rate, split $split', () {
        final p = SpeedCoachStrokePacket.parse(hex(packet))!;
        expect(p.strokeRate, rate);
        expect(mmss(p.split!), split);
        expect(p.strokeCount, count);
        expect(p.pieceRunning, isTrue);
        expect(p.isIdle, isFalse);
      });
    });

    test('distance per stroke and average split', () {
      final p = SpeedCoachStrokePacket.parse(
        hex('33 ff 6a 00 00 00 f2 00 00 00 82 00 00 00 0e 00 00 00 00 00'),
      )!;
      expect(p.distancePerStrokeCm, 242);
      expect(p.averageSpeedCmPerSecond, 130);
      expect(mmss(p.averageSplit!), '6:24'); // 50000 / 130 = 384.6 s
    });

    test('no speed (FF FF) means idle, no split', () {
      final p = SpeedCoachStrokePacket.parse(
        hex('00 ff ff ff 00 00 ff ff 00 00 00 00 00 00 5d 00 00 00 00 00'),
      )!;
      expect(p.isIdle, isTrue);
      expect(p.split, isNull);
      expect(p.strokeCount, 93);
    });

    test('bytes 4-5 FF FF: no piece running', () {
      final p = SpeedCoachStrokePacket.parse(
        hex('d4 ff 79 00 ff ff 42 00 00 00 00 00 00 00 00 00 00 00 00 00'),
      )!;
      expect(p.pieceRunning, isFalse);
      expect(p.strokeRate, 106);
    });

    test('rejects wrong lengths', () {
      expect(SpeedCoachStrokePacket.parse(hex('01 02 03')), isNull);
    });
  });

  group('SpeedCoachStatusPacket', () {
    test('distance (cm) and elapsed time (ms)', () {
      // 16:11:40.94: display showed 0:19.x
      final p = SpeedCoachStatusPacket.parse(
        hex('b0 8a e8 17 95 a2 68 cb 76 09 00 00 00 00 00 00 20 4a 00 00'),
      )!;
      expect(p.elapsed, const Duration(milliseconds: 18976));
      expect(p.distanceMeters, closeTo(24.22, 0.001));
      expect(p.latitude, isNotNull);
      expect(p.longitude, isNotNull);
      expect(p.longitude!, lessThan(0)); // signed int32
      expect(p.isReset, isFalse);
    });

    test('all-zero distance and time is a reset', () {
      final p = SpeedCoachStatusPacket.parse(
        hex('f9 94 e8 17 9b a2 68 cb 00 00 00 00 00 00 00 00 00 00 00 00'),
      )!;
      expect(p.isReset, isTrue);
      expect(p.distanceMeters, 0);
    });

    test('elapsed time crosses a byte boundary correctly', () {
      final p = SpeedCoachStatusPacket.parse(
        hex('ee aa f5 17 bb da 1d cb 00 00 00 00 00 00 00 00 a6 00 02 00'),
      )!;
      expect(p.elapsed, const Duration(milliseconds: 131238));
    });

    test('rejects wrong lengths', () {
      expect(SpeedCoachStatusPacket.parse([]), isNull);
    });
  });

  group('SpeedCoachPieceStart', () {
    test('decodes the SpeedCoach local start time', () {
      final p = SpeedCoachPieceStart.parse(
        hex('16 0b 0b 1a 09 ea 07 00 00 00 03 00 00 00 00 00 00 00 00 00'),
      )!;
      expect(p.startedAt, DateTime(2026, 9, 26, 11, 11, 22));
    });

    test('rejects nonsense dates', () {
      expect(SpeedCoachPieceStart.parse(hex('ff ff ff ff ff ff ff')), isNull);
      expect(SpeedCoachPieceStart.parse(hex('01 02')), isNull);
    });
  });
}
