import 'dart:async';

import 'package:pulseboard/bluetooth/ble_adapter.dart';
import 'package:pulseboard/bluetooth/ble_uuids.dart';

/// Scriptable in-memory [BleAdapter] for tests. Every sensor is keyed by id;
/// tests drive link events, packets and failures explicitly.
class FakeBleAdapter implements BleAdapter {
  final availability = StreamController<BleAvailability>.broadcast();
  final ads = StreamController<BleAdvertisement>.broadcast();
  final _links = StreamController<({String id, bool up})>.broadcast();
  final _values = StreamController<({String id, String char, List<int> value})>.broadcast();

  BleAvailability currentAvailability = BleAvailability.poweredOn;

  /// Override to script connect behaviour. Default: link comes up at once.
  Future<void> Function(String id, Duration timeout)? onConnect;

  /// Profile returned by discoverServices (per device override possible).
  GattProfile defaultProfile = GattProfile({
    BleUuids.heartRateService: {
      BleUuids.heartRateMeasurement: {GattProperty.notify},
    },
    BleUuids.batteryService: {
      BleUuids.batteryLevel: {GattProperty.read},
    },
  });
  final Map<String, GattProfile> profiles = {};
  Object? subscribeError;
  int batteryLevel = 77;
  List<BleAdvertisement> systemDevices = [];

  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];
  final List<String> subscribeCalls = [];
  final Set<String> linked = {};
  bool scanning = false;
  bool? lastScanHeartRateOnly;

  // --- helpers for tests ---

  void linkDown(String id) {
    linked.remove(id);
    _links.add((id: id, up: false));
  }

  void linkUp(String id) {
    linked.add(id);
    _links.add((id: id, up: true));
  }

  void pushPacket(String id, List<int> bytes) =>
      _values.add((id: id, char: BleUuids.heartRateMeasurement, value: bytes));

  void pushHr(String id, int bpm) => pushPacket(id, [0x00, bpm]);

  void advertise(String id, {String? name, int rssi = -60, bool hr = true}) => ads.add(
    BleAdvertisement(
      deviceId: id,
      timestamp: DateTime.now(),
      name: name,
      rssi: rssi,
      serviceUuids: hr ? [BleUuids.heartRateService] : const [],
    ),
  );

  // --- BleAdapter ---

  @override
  Stream<BleAvailability> get availabilityChanges => availability.stream;

  @override
  Future<BleAvailability> getAvailability() async => currentAvailability;

  @override
  Future<void> requestPermission() async {}

  @override
  Stream<BleAdvertisement> get advertisements => ads.stream;

  @override
  Future<void> startScan({required bool heartRateOnly}) async {
    scanning = true;
    lastScanHeartRateOnly = heartRateOnly;
  }

  @override
  Future<void> stopScan() async => scanning = false;

  @override
  Future<List<BleAdvertisement>> getSystemConnectedHeartRateDevices() async => systemDevices;

  @override
  Stream<bool> connectionChanges(String deviceId) =>
      _links.stream.where((e) => e.id == deviceId).map((e) => e.up);

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    connectCalls.add(deviceId);
    final handler = onConnect;
    if (handler != null) {
      await handler(deviceId, timeout);
      return;
    }
    linkUp(deviceId);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCalls.add(deviceId);
    if (linked.contains(deviceId)) linkDown(deviceId);
  }

  @override
  Future<GattProfile> discoverServices(String deviceId, {required Duration timeout}) async =>
      profiles[deviceId] ?? defaultProfile;

  @override
  Stream<List<int>> characteristicValues(String deviceId, String characteristicUuid) => _values
      .stream
      .where((e) => e.id == deviceId && e.char == BleUuids.normalize(characteristicUuid))
      .map((e) => e.value);

  @override
  Future<void> subscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  }) async {
    subscribeCalls.add(deviceId);
    final error = subscribeError;
    if (error != null) throw error;
  }

  @override
  Future<List<int>> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  }) async => [batteryLevel];

  @override
  Future<int?> readRssi(String deviceId) async => -58;
}
