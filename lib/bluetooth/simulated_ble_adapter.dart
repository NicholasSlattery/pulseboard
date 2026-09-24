import 'dart:async';
import 'dart:math';

import 'ble_adapter.dart';
import 'ble_uuids.dart';

/// Fake heart-rate straps for developing the UI without hardware (e.g. on
/// Windows). Only used when the app is built with
/// `--dart-define=PULSEBOARD_SIMULATOR=true`; the dashboard shows a clear
/// "SIMULATED DATA" banner whenever it is active.
///
/// Behaviour: [deviceCount] straps advertise the Heart Rate Service and
/// battery service. Strap #3 periodically "rows out of range" for 12 s every
/// 2 minutes so reconnect/stale handling can be seen in action.
class SimulatedBleAdapter implements BleAdapter {
  SimulatedBleAdapter({this.deviceCount = 8, int seed = 42}) : _random = Random(seed) {
    for (var i = 0; i < deviceCount; i++) {
      final id = 'SIM-${(i + 1).toString().padLeft(4, '0')}';
      _devices[id] = _SimDevice(
        id: id,
        name: 'SIM HR ${(i + 1).toString().padLeft(2, '0')}',
        restingHr: 55 + _random.nextInt(15),
        peakHr: 175 + _random.nextInt(20),
        phase: _random.nextDouble() * 2 * pi,
        battery: 40 + _random.nextInt(60),
        dropsOut: i == 2,
      );
    }
  }

  final int deviceCount;
  final Random _random;
  final Map<String, _SimDevice> _devices = {};
  final _availability = StreamController<BleAvailability>.broadcast();
  final _ads = StreamController<BleAdvertisement>.broadcast();
  final _links = StreamController<({String id, bool up})>.broadcast();
  final _values = StreamController<({String id, List<int> value})>.broadcast();
  final DateTime _start = DateTime.now();
  Timer? _scanTimer;

  @override
  Stream<BleAvailability> get availabilityChanges => _availability.stream;

  @override
  Future<BleAvailability> getAvailability() async => BleAvailability.poweredOn;

  @override
  Future<void> requestPermission() async {}

  @override
  Stream<BleAdvertisement> get advertisements => _ads.stream;

  @override
  Future<void> startScan({required bool heartRateOnly}) async {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      for (final d in _devices.values) {
        if (d.connected || _outOfRange(d)) continue;
        _ads.add(
          BleAdvertisement(
            deviceId: d.id,
            timestamp: DateTime.now(),
            name: d.name,
            rssi: -50 - _random.nextInt(35),
            serviceUuids: [BleUuids.heartRateService],
          ),
        );
      }
    });
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  Future<List<BleAdvertisement>> getSystemConnectedHeartRateDevices() async => const [];

  @override
  Stream<bool> connectionChanges(String deviceId) =>
      _links.stream.where((e) => e.id == deviceId).map((e) => e.up);

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    final d = _devices[deviceId];
    if (d == null) {
      throw const BleException(BleErrorKind.deviceNotFound, 'unknown simulated device');
    }
    await Future<void>.delayed(Duration(milliseconds: 300 + _random.nextInt(700)));
    if (_outOfRange(d)) {
      // Behave like CoreBluetooth: wait, then time out.
      await Future<void>.delayed(timeout);
      throw const BleException(BleErrorKind.timeout, 'simulated strap out of range');
    }
    d.connected = true;
    _links.add((id: deviceId, up: true));
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final d = _devices[deviceId];
    if (d == null) return;
    d.notifyTimer?.cancel();
    d.notifyTimer = null;
    if (d.connected) {
      d.connected = false;
      _links.add((id: deviceId, up: false));
    }
  }

  @override
  Future<GattProfile> discoverServices(String deviceId, {required Duration timeout}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return GattProfile({
      BleUuids.heartRateService: {
        BleUuids.heartRateMeasurement: {GattProperty.notify},
      },
      BleUuids.batteryService: {
        BleUuids.batteryLevel: {GattProperty.read},
      },
    });
  }

  @override
  Stream<List<int>> characteristicValues(String deviceId, String characteristicUuid) => _values
      .stream
      .where(
        (e) =>
            e.id == deviceId && BleUuids.equal(characteristicUuid, BleUuids.heartRateMeasurement),
      )
      .map((e) => e.value);

  @override
  Future<void> subscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  }) async {
    final d = _devices[deviceId];
    if (d == null || !d.connected) {
      throw const BleException(BleErrorKind.connectionFailed, 'not connected');
    }
    d.notifyTimer?.cancel();
    d.notifyTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick(d));
  }

  @override
  Future<List<int>> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  }) async {
    final d = _devices[deviceId];
    if (d == null) throw const BleException(BleErrorKind.deviceNotFound, 'unknown');
    return [d.battery];
  }

  @override
  Future<int?> readRssi(String deviceId) async => -55 - _random.nextInt(25);

  void _tick(_SimDevice d) {
    if (_outOfRange(d)) {
      // Signal lost mid-workout.
      d.notifyTimer?.cancel();
      d.notifyTimer = null;
      d.connected = false;
      _links.add((id: d.id, up: false));
      return;
    }
    final t = DateTime.now().difference(_start).inMilliseconds / 1000.0;
    // Interval-style effort: ~4 min cycles plus noise.
    final effort = (sin(t / 38 + d.phase) + 1) / 2;
    final bpm =
        (d.restingHr + (d.peakHr - d.restingHr) * (0.35 + 0.65 * effort) + _random.nextInt(5) - 2)
            .round()
            .clamp(40, 220);
    final rr = (60000 / bpm * 1024 / 1000).round();
    // flags: UINT8 HR, contact supported+detected, RR present.
    _values.add((id: d.id, value: [0x16, bpm, rr & 0xFF, rr >> 8]));
  }

  bool _outOfRange(_SimDevice d) {
    if (!d.dropsOut) return false;
    final s = DateTime.now().difference(_start).inSeconds % 120;
    return s >= 90 && s < 102;
  }
}

class _SimDevice {
  _SimDevice({
    required this.id,
    required this.name,
    required this.restingHr,
    required this.peakHr,
    required this.phase,
    required this.battery,
    required this.dropsOut,
  });

  final String id;
  final String name;
  final int restingHr;
  final int peakHr;
  final double phase;
  final int battery;
  final bool dropsOut;
  bool connected = false;
  Timer? notifyTimer;
}
