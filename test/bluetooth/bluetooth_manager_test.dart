import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/bluetooth/ble_adapter.dart';
import 'package:pulseboard/bluetooth/bluetooth_manager.dart';
import 'package:pulseboard/bluetooth/reconnect_policy.dart';
import 'package:pulseboard/models/heart_rate_reading.dart';
import 'package:pulseboard/models/sensor_state.dart';

import '../support/fake_ble_adapter.dart';

void main() {
  late FakeBleAdapter adapter;
  late BluetoothManager manager;

  BluetoothManager build() =>
      BluetoothManager(adapter: adapter, policy: ReconnectPolicy(jitterFraction: 0));

  setUp(() {
    adapter = FakeBleAdapter();
  });

  test('keeps many sensors connected independently', () {
    fakeAsync((async) {
      manager = build();
      final readings = <HeartRateReading>[];
      manager.readings.listen(readings.add);
      unawaited(manager.initialize());
      async.flushMicrotasks();

      manager.syncAssignedSensors({'A': 'Strap A', 'B': 'Strap B', 'C': 'Strap C'});
      async.flushMicrotasks();
      for (final id in ['A', 'B', 'C']) {
        adapter.pushHr(id, 100 + id.codeUnitAt(0));
      }
      async.elapse(const Duration(milliseconds: 200));

      expect(manager.sensors.length, 3);
      for (final s in manager.sensors.values) {
        expect(s.connection, SensorConnectionState.receiving);
      }
      expect(readings.map((r) => r.sensorId).toSet(), {'A', 'B', 'C'});

      // B drops; A and C are unaffected.
      adapter.linkDown('B');
      adapter.pushHr('A', 170);
      adapter.pushHr('C', 171);
      async.elapse(const Duration(milliseconds: 200));
      expect(manager.sensors['B']!.connection, SensorConnectionState.reconnecting);
      expect(manager.sensors['B']!.displayBpm, isNull);
      expect(manager.sensors['A']!.displayBpm, 170);
      expect(manager.sensors['C']!.displayBpm, 171);
      expect(adapter.disconnectCalls, isNot(contains('A')));
      expect(adapter.disconnectCalls, isNot(contains('C')));

      // B comes back on its own.
      async.elapse(const Duration(seconds: 1));
      adapter.pushHr('B', 140);
      async.elapse(const Duration(milliseconds: 200));
      expect(manager.sensors['B']!.displayBpm, 140);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('supports 20 simultaneous sensors', () {
    fakeAsync((async) {
      manager = build();
      unawaited(manager.initialize());
      async.flushMicrotasks();
      final ids = List.generate(20, (i) => 'S$i');
      manager.syncAssignedSensors({for (final id in ids) id: null});
      async.flushMicrotasks();
      for (var t = 0; t < 10; t++) {
        for (final id in ids) {
          adapter.pushHr(id, 120 + t);
        }
        async.elapse(const Duration(seconds: 1));
      }
      expect(manager.sensors.length, 20);
      expect(manager.sensors.values.every((s) => s.displayBpm == 129), isTrue);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('coalesces state emissions', () {
    fakeAsync((async) {
      manager = build();
      var emissions = 0;
      manager.sensorsStream.listen((_) => emissions++);
      unawaited(manager.initialize());
      async.flushMicrotasks();
      manager.syncAssignedSensors({'A': null, 'B': null});
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 150));
      emissions = 0;

      // 50 packets within one emit window -> one emission.
      for (var i = 0; i < 25; i++) {
        adapter.pushHr('A', 100 + i);
        adapter.pushHr('B', 100 + i);
      }
      async.elapse(const Duration(milliseconds: 150));
      expect(emissions, 1);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('scan lists heart-rate devices, ignores others and auto-stops', () {
    fakeAsync((async) {
      manager = build();
      unawaited(manager.initialize());
      async.flushMicrotasks();
      unawaited(manager.startScan());
      async.flushMicrotasks();
      expect(adapter.scanning, isTrue);
      expect(adapter.lastScanHeartRateOnly, isTrue);
      expect(manager.status.isScanning, isTrue);

      adapter.advertise('HR1', name: 'Polar H10 1234');
      adapter.advertise('HR1', name: 'Polar H10 1234', rssi: -50); // duplicate
      adapter.advertise('SPEAKER', name: 'Speaker', hr: false);
      async.elapse(const Duration(milliseconds: 200));

      expect(manager.sensors.keys, ['HR1']);
      expect(manager.sensors['HR1']!.rssi, -50);
      expect(manager.sensors['HR1']!.connection, SensorConnectionState.discovered);

      async.elapse(const Duration(seconds: 30));
      expect(adapter.scanning, isFalse);
      expect(manager.status.isScanning, isFalse);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('scan includes devices already connected to the phone by another app', () {
    fakeAsync((async) {
      adapter.systemDevices = [
        BleAdvertisement(
          deviceId: 'SYS',
          timestamp: DateTime(2026),
          name: 'Garmin HRM',
          isSystemConnected: true,
        ),
      ];
      manager = build();
      unawaited(manager.initialize());
      async.flushMicrotasks();
      unawaited(manager.startScan());
      async.elapse(const Duration(milliseconds: 200));
      expect(manager.sensors['SYS']!.isSystemConnected, isTrue);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('user-disconnected sensors are not auto-connected by sync', () {
    fakeAsync((async) {
      manager = build();
      unawaited(manager.initialize());
      async.flushMicrotasks();
      manager.syncAssignedSensors({'A': null});
      async.flushMicrotasks();
      unawaited(manager.disconnect('A'));
      async.flushMicrotasks();
      manager.syncAssignedSensors({'A': null});
      async.elapse(const Duration(minutes: 1));
      expect(manager.sensors['A']!.connection, SensorConnectionState.disconnected);
      expect(adapter.connectCalls.length, 1);

      manager.connect('A');
      async.flushMicrotasks();
      expect(adapter.connectCalls.length, 2);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('Bluetooth turning off and on propagates to every sensor', () {
    fakeAsync((async) {
      manager = build();
      unawaited(manager.initialize());
      async.flushMicrotasks();
      manager.syncAssignedSensors({'A': null, 'B': null});
      async.flushMicrotasks();

      adapter.availability.add(BleAvailability.poweredOff);
      adapter.linkDown('A');
      adapter.linkDown('B');
      async.elapse(const Duration(seconds: 30));
      expect(manager.status.availability, BleAvailability.poweredOff);
      expect(adapter.connectCalls.length, 2);

      adapter.availability.add(BleAvailability.poweredOn);
      async.elapse(const Duration(milliseconds: 200));
      expect(adapter.connectCalls.length, 4);
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('forget disconnects and removes a sensor', () {
    fakeAsync((async) {
      manager = build();
      unawaited(manager.initialize());
      async.flushMicrotasks();
      manager.syncAssignedSensors({'A': null});
      async.flushMicrotasks();
      unawaited(manager.forget('A'));
      async.elapse(const Duration(milliseconds: 200));
      expect(manager.sensors, isEmpty);
      expect(adapter.disconnectCalls, contains('A'));
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
