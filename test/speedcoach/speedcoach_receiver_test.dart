import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/speedcoach/speedcoach_protocol.dart';
import 'package:pulseboard/speedcoach/speedcoach_receiver.dart';

import '../support/fake_peripheral.dart';

List<int> hex(String s) =>
    s.split(' ').where((p) => p.isNotEmpty).map((p) => int.parse(p, radix: 16)).toList();

List<int> statusPacket(int ms, {int cm = 0}) => [
  ...hex('ee aa f5 17 bb da 1d cb'),
  cm & 0xFF, (cm >> 8) & 0xFF, (cm >> 16) & 0xFF, (cm >> 24) & 0xFF, 0, 0, 0, 0, //
  ms & 0xFF, (ms >> 8) & 0xFF, (ms >> 16) & 0xFF, (ms >> 24) & 0xFF,
];

List<int> strokePacket(int count, {int rateTimesTwo = 60, int speed = 250}) => [
  rateTimesTwo,
  0xFF,
  speed & 0xFF,
  speed >> 8,
  0,
  0,
  120,
  0,
  0,
  0,
  200,
  0,
  0,
  0,
  count,
  0,
  0,
  0,
  0,
  0, //
];

void main() {
  test('publishes NK service with all 18 characteristics and advertises the pairing name', () {
    fakeAsync((async) {
      final p = FakePeripheral();
      final r = SpeedCoachReceiver(adapter: p);
      unawaited(r.start(advertisedName: SpeedCoachNames.pairing, boatName: 'Varsity 4+'));
      async.flushMicrotasks();

      expect(p.addedServices, [SpeedCoachUuids.service]);
      expect(p.addedCharacteristics.length, 18);
      expect(p.advertisedName, 'NK LiNKp');
      expect(r.state.status, SpeedCoachReceiverStatus.waiting);
      unawaited(r.stop());
      async.flushMicrotasks();
      unawaited(r.dispose());
    });
  });

  test('answers the SpeedCoach reads like NK LiNK', () {
    fakeAsync((async) {
      final p = FakePeripheral();
      final r = SpeedCoachReceiver(adapter: p);
      unawaited(r.start(advertisedName: SpeedCoachNames.pairing, boatName: 'Varsity 4+'));
      async.flushMicrotasks();

      expect(String.fromCharCodes(p.read('0005')), 'Varsity 4+');
      final control = p.read('2005');
      expect(control.length, 20);
      expect(control.first, 1);
      expect(control.skip(1).every((b) => b == 0), isTrue);
      expect(p.read('0104'), isEmpty);
      unawaited(r.dispose());
    });
  });

  test('decodes serial, elapsed time, distance, strokes, rate and split', () {
    fakeAsync((async) {
      final p = FakePeripheral();
      final r = SpeedCoachReceiver(adapter: p);
      final serials = <String>[];
      r.serialReported.listen(serials.add);
      unawaited(r.start(advertisedName: SpeedCoachNames.pairing, boatName: 'B'));
      async.flushMicrotasks();

      p.write('1005', '2226780'.codeUnits);
      async.flushMicrotasks();
      expect(r.state.serial, '2226780');
      expect(serials, ['2226780']);
      expect(r.state.status, SpeedCoachReceiverStatus.streaming);

      p.write('0103', statusPacket(75054, cm: 12345));
      expect(r.state.elapsed, const Duration(milliseconds: 75054));
      expect(r.state.distanceMeters, 123.45);

      for (var i = 0; i < 5; i++) {
        p.write('0203', strokePacket(40 + i));
        p.write('0103', statusPacket(80000 + i * 2000));
        async.elapse(const Duration(seconds: 2));
      }
      expect(r.state.strokeCount, 44);
      expect(r.state.strokeRate, 30);
      expect(r.state.split, const Duration(seconds: 200)); // 50000 / 250
      expect(r.state.averageSplit, const Duration(seconds: 250));
      expect(r.state.distancePerStrokeMeters, 1.2);
      expect(r.packetLog.length, 12);
      expect(r.packetLogCsv().split('\r\n').first, 'time_utc,characteristic,hex');
      unawaited(r.dispose());
    });
  });

  test('idle packet clears the split; silence drops back to waiting', () {
    fakeAsync((async) {
      final p = FakePeripheral();
      final r = SpeedCoachReceiver(adapter: p);
      unawaited(r.start(advertisedName: SpeedCoachNames.pairing, boatName: 'B'));
      async.flushMicrotasks();
      p.write('0203', strokePacket(1));
      async.elapse(const Duration(seconds: 2));
      p.write('0203', strokePacket(2));
      expect(r.state.strokeRate, isNotNull);

      p.write('0203', hex('00 ff ff ff 00 00 ff ff 00 00 00 00 00 00 02 00 00 00 00 00'));
      expect(r.state.split, isNull);
      expect(r.state.strokeRate, isNull);

      async.elapse(const Duration(seconds: 6));
      expect(r.state.status, SpeedCoachReceiverStatus.waiting);
      unawaited(r.dispose());
    });
  });

  test('reports unsupported where the advertised name cannot be set', () {
    fakeAsync((async) {
      final p = FakePeripheral(supportsLocalName: false);
      final r = SpeedCoachReceiver(adapter: p);
      unawaited(r.start(advertisedName: SpeedCoachNames.pairing, boatName: 'B'));
      async.flushMicrotasks();
      expect(r.state.status, SpeedCoachReceiverStatus.unsupported);
      expect(p.addedServices, isEmpty);
      unawaited(r.dispose());
    });
  });

  test('Bluetooth off gives a clear error', () {
    fakeAsync((async) {
      final p = FakePeripheral()..ready = false;
      final r = SpeedCoachReceiver(adapter: p);
      unawaited(r.start(advertisedName: SpeedCoachNames.pairing, boatName: 'B'));
      async.flushMicrotasks();
      expect(r.state.status, SpeedCoachReceiverStatus.error);
      expect(r.state.error, contains('Bluetooth'));
      unawaited(r.dispose());
    });
  });

  test('ignores writes to unrelated characteristics', () {
    fakeAsync((async) {
      final p = FakePeripheral();
      final r = SpeedCoachReceiver(adapter: p);
      unawaited(r.start(advertisedName: SpeedCoachNames.pairing, boatName: 'B'));
      async.flushMicrotasks();
      p.onWrite!('X', '00002a37-0000-1000-8000-00805f9b34fb', Uint8List.fromList([1, 2]));
      expect(r.state.packetsReceived, 0);
      unawaited(r.dispose());
    });
  });
}
