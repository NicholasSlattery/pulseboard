import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/bluetooth/ble_adapter.dart';
import 'package:pulseboard/bluetooth/heart_rate_sensor_connection.dart';
import 'package:pulseboard/bluetooth/reconnect_policy.dart';
import 'package:pulseboard/models/connection_event.dart';
import 'package:pulseboard/models/heart_rate_reading.dart';
import 'package:pulseboard/models/sensor_state.dart';

import '../support/fake_ble_adapter.dart';

/// Test harness around one connection.
class _Harness {
  _Harness(this.adapter, {String id = 'A', SensorConnectionConfig? config}) {
    connection = HeartRateSensorConnection(
      sensorId: id,
      adapter: adapter,
      policy: ReconnectPolicy(jitterFraction: 0),
      config: config ?? const SensorConnectionConfig(),
      onStateChanged: (c) => states.add(c.state.connection),
      onReading: readings.add,
      onEvent: events.add,
    );
  }

  final FakeBleAdapter adapter;
  late final HeartRateSensorConnection connection;
  final List<SensorConnectionState> states = [];
  final List<HeartRateReading> readings = [];
  final List<ConnectionEvent> events = [];

  SensorLiveState get state => connection.state;
  List<ConnectionEventType> get eventTypes => events.map((e) => e.type).toList();
}

void main() {
  const staleAfter = Duration(seconds: 5);
  const lostAfter = Duration(seconds: 15);

  test('connects, subscribes and starts receiving', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();

      expect(h.state.connection, SensorConnectionState.subscribing);
      expect(adapter.subscribeCalls, ['A']);
      expect(
        h.states,
        containsAllInOrder([
          SensorConnectionState.connecting,
          SensorConnectionState.connected,
          SensorConnectionState.subscribing,
        ]),
      );

      adapter.pushHr('A', 142);
      async.flushMicrotasks();
      expect(h.state.connection, SensorConnectionState.receiving);
      expect(h.state.displayBpm, 142);
      expect(h.state.batteryPercent, 77);
      expect(h.readings.single.bpm, 142);
      expect(h.eventTypes, [ConnectionEventType.connected, ConnectionEventType.receiving]);
    });
  });

  test('unexpected link loss shows disconnected immediately and reconnects with backoff', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();
      adapter.pushHr('A', 150);
      async.flushMicrotasks();

      adapter.linkDown('A');
      async.flushMicrotasks();
      expect(h.state.connection, SensorConnectionState.reconnecting);
      expect(h.state.displayBpm, isNull, reason: 'never show an old BPM as current');
      expect(h.eventTypes, contains(ConnectionEventType.lost));
      expect(adapter.connectCalls.length, 1);

      // First retry after ~1 s (jitter disabled).
      async.elapse(const Duration(milliseconds: 999));
      expect(adapter.connectCalls.length, 1);
      async.elapse(const Duration(milliseconds: 2));
      expect(adapter.connectCalls.length, 2);
      expect(h.state.connection, SensorConnectionState.subscribing);

      adapter.pushHr('A', 151);
      async.flushMicrotasks();
      expect(h.state.displayBpm, 151);
    });
  });

  test('failed attempts back off exponentially and cancel the pending request', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter()
        ..onConnect = (id, timeout) async {
          await Future<void>.delayed(timeout);
          throw const BleException(BleErrorKind.timeout, 'timeout');
        };
      final h = _Harness(
        adapter,
        config: const SensorConnectionConfig(connectTimeout: Duration(seconds: 20)),
      );
      h.connection.connect();

      async.elapse(const Duration(seconds: 20));
      expect(adapter.connectCalls.length, 1);
      expect(adapter.disconnectCalls, ['A'], reason: 'pending CoreBluetooth request cancelled');
      expect(h.state.connection, SensorConnectionState.reconnecting);
      expect(h.state.reconnectAttempt, 1);

      // retry 1 after 1 s, fails after 20 s; retry 2 after 2 s...
      async.elapse(const Duration(seconds: 1));
      expect(adapter.connectCalls.length, 2);
      async.elapse(const Duration(seconds: 20));
      async.elapse(const Duration(milliseconds: 1999));
      expect(adapter.connectCalls.length, 2);
      async.elapse(const Duration(milliseconds: 2));
      expect(adapter.connectCalls.length, 3);
      expect(h.eventTypes.where((e) => e == ConnectionEventType.attemptFailed).length, 2);
    });
  });

  test('device without Heart Rate Service fails without retrying', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter()..profiles['A'] = const GattProfile({});
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();

      expect(h.state.connection, SensorConnectionState.failed);
      expect(h.state.error, contains('Heart Rate Service'));
      expect(h.connection.wanted, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(adapter.connectCalls.length, 1);
    });
  });

  test('readings go stale and then lost; stale BPM is never current after lost', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();
      adapter.pushHr('A', 120);
      async.flushMicrotasks();

      bool refresh() => h.connection.refreshFreshness(clock.now(), staleAfter, lostAfter);

      async.elapse(const Duration(seconds: 5));
      refresh();
      expect(h.state.freshness, SignalFreshness.fresh);

      async.elapse(const Duration(seconds: 1));
      refresh();
      expect(h.state.freshness, SignalFreshness.stale);
      expect(h.state.isStale, isTrue);
      expect(h.state.displayBpm, 120);

      async.elapse(const Duration(seconds: 10));
      refresh();
      expect(h.state.freshness, SignalFreshness.lost);
      expect(h.state.displayBpm, isNull);

      adapter.pushHr('A', 125);
      async.flushMicrotasks();
      expect(h.state.freshness, SignalFreshness.fresh);
      expect(h.state.displayBpm, 125);
    });
  });

  test('user disconnect stops reconnection', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();
      adapter.pushHr('A', 100);
      async.flushMicrotasks();

      unawaited(h.connection.disconnect());
      async.flushMicrotasks();
      expect(h.state.connection, SensorConnectionState.disconnected);
      expect(h.eventTypes.last, ConnectionEventType.userDisconnected);
      async.elapse(const Duration(minutes: 2));
      expect(adapter.connectCalls.length, 1);
    });
  });

  test('with auto-reconnect disabled a lost sensor stays disconnected', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter, config: const SensorConnectionConfig(autoReconnect: false));
      h.connection.connect();
      async.flushMicrotasks();
      adapter.pushHr('A', 100);
      async.flushMicrotasks();

      adapter.linkDown('A');
      async.elapse(const Duration(minutes: 1));
      expect(h.state.connection, SensorConnectionState.disconnected);
      expect(adapter.connectCalls.length, 1);

      // Re-enabling resumes.
      h.connection.updateConfig(const SensorConnectionConfig(autoReconnect: true));
      async.flushMicrotasks();
      expect(adapter.connectCalls.length, 2);
    });
  });

  test('watchdog recycles a link that stops delivering data', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();
      adapter.pushHr('A', 100);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 36));
      expect(h.eventTypes, contains(ConnectionEventType.dataTimeout));
      expect(adapter.disconnectCalls, contains('A'));
      expect(adapter.connectCalls.length, greaterThanOrEqualTo(2));
    });
  });

  test('Bluetooth off pauses attempts; turning it on reconnects', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();
      adapter.pushHr('A', 100);
      async.flushMicrotasks();

      h.connection.onBluetoothAvailability(false);
      adapter.linkDown('A');
      async.elapse(const Duration(minutes: 1));
      expect(h.state.connection, SensorConnectionState.reconnecting);
      expect(h.state.error, 'Waiting for Bluetooth');
      expect(adapter.connectCalls.length, 1);

      h.connection.onBluetoothAvailability(true);
      async.flushMicrotasks();
      expect(adapter.connectCalls.length, 2);
      expect(h.state.connection, SensorConnectionState.subscribing);
    });
  });

  test('advertisement during backoff triggers an immediate retry', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();
      adapter.pushHr('A', 100);
      async.flushMicrotasks();

      // Drive backoff up by failing a few attempts.
      adapter.onConnect = (id, t) async =>
          throw const BleException(BleErrorKind.connectionFailed, 'nope');
      adapter.linkDown('A');
      async.elapse(const Duration(seconds: 1)); // attempt 1 fails
      async.elapse(const Duration(seconds: 2)); // attempt 2 fails
      final callsBefore = adapter.connectCalls.length;
      expect(h.state.nextReconnectAt, isNotNull);

      adapter.onConnect = null;
      h.connection.onAdvertisement(
        BleAdvertisement(deviceId: 'A', timestamp: DateTime.now(), rssi: -70),
      );
      async.flushMicrotasks();
      expect(adapter.connectCalls.length, callsBefore + 1);
      expect(h.state.connection, SensorConnectionState.subscribing);
    });
  });

  test('malformed and no-contact packets never produce readings', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();

      adapter.pushPacket('A', []);
      adapter.pushPacket('A', [0x01, 0x50]);
      async.flushMicrotasks();
      expect(h.readings, isEmpty);
      expect(h.state.connection, SensorConnectionState.subscribing);

      adapter.pushPacket('A', [0x04, 90]); // contact supported, not detected
      async.flushMicrotasks();
      expect(h.readings, isEmpty);
      expect(h.state.noSkinContact, isTrue);
      expect(h.state.displayBpm, isNull);

      adapter.pushPacket('A', [0x06, 91]); // contact detected
      async.flushMicrotasks();
      expect(h.readings.single.bpm, 91);
      expect(h.state.displayBpm, 91);
    });
  });

  test('subscribe failure tears down and retries', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter()
        ..subscribeError = const BleException(BleErrorKind.operationFailed, 'boom');
      final h = _Harness(adapter);
      h.connection.connect();
      async.flushMicrotasks();
      expect(h.state.connection, SensorConnectionState.reconnecting);
      expect(adapter.disconnectCalls, ['A']);

      adapter.subscribeError = null;
      async.elapse(const Duration(seconds: 1));
      expect(h.state.connection, SensorConnectionState.subscribing);
    });
  });

  test('a stray link-up while not wanted is disconnected', () {
    fakeAsync((async) {
      final adapter = FakeBleAdapter();
      _Harness(adapter);
      adapter.linkUp('A');
      async.flushMicrotasks();
      expect(adapter.disconnectCalls, ['A']);
    });
  });
}
