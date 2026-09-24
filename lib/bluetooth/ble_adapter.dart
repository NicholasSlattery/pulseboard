import 'package:flutter/foundation.dart';

import 'ble_uuids.dart';

/// Host Bluetooth adapter state.
enum BleAvailability {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn;

  bool get isReady => this == poweredOn;
}

/// One advertisement (scan result) from a nearby device.
@immutable
class BleAdvertisement {
  const BleAdvertisement({
    required this.deviceId,
    required this.timestamp,
    this.name,
    this.rssi,
    this.serviceUuids = const [],
    this.isSystemConnected = false,
  });

  final String deviceId;
  final DateTime timestamp;

  /// Advertised local name. May be null: some straps only reveal a useful
  /// name after connecting.
  final String? name;
  final int? rssi;

  /// Advertised service UUIDs, normalised to lower-case 128-bit strings.
  final List<String> serviceUuids;

  /// Already connected to this phone at the OS level (e.g. by another app).
  final bool isSystemConnected;

  bool get advertisesHeartRate => serviceUuids.contains(BleUuids.heartRateService);
}

enum GattProperty { read, write, writeWithoutResponse, notify, indicate }

/// Result of GATT service discovery: service UUID -> characteristic UUID ->
/// properties. All UUIDs normalised.
@immutable
class GattProfile {
  const GattProfile(this.services);

  final Map<String, Map<String, Set<GattProperty>>> services;

  bool hasService(String service) => services.containsKey(BleUuids.normalize(service));

  bool hasCharacteristic(String service, String characteristic) =>
      services[BleUuids.normalize(service)]?.containsKey(BleUuids.normalize(characteristic)) ??
      false;

  Set<GattProperty> propertiesOf(String service, String characteristic) =>
      services[BleUuids.normalize(service)]?[BleUuids.normalize(characteristic)] ?? const {};
}

enum BleErrorKind {
  bluetoothUnavailable,
  unauthorized,
  timeout,
  deviceNotFound,
  connectionFailed,
  serviceNotFound,
  characteristicNotFound,
  operationFailed,
}

/// Normalised error type so the rest of the app never depends on a specific
/// plugin's exception classes.
class BleException implements Exception {
  const BleException(this.kind, this.message);

  final BleErrorKind kind;
  final String message;

  /// Short, coach-friendly explanation for the UI.
  String get userMessage => switch (kind) {
    BleErrorKind.bluetoothUnavailable => 'Bluetooth is off or unavailable.',
    BleErrorKind.unauthorized => 'Bluetooth permission was denied.',
    BleErrorKind.timeout => 'Sensor did not respond in time. Is it worn and nearby?',
    BleErrorKind.deviceNotFound => 'Sensor not found. Wake it by wearing the strap.',
    BleErrorKind.connectionFailed =>
      'Could not connect. The strap may be connected to another device.',
    BleErrorKind.serviceNotFound => 'This device does not provide the Heart Rate Service.',
    BleErrorKind.characteristicNotFound =>
      'Heart Rate Measurement characteristic missing on this device.',
    BleErrorKind.operationFailed => 'Bluetooth operation failed.',
  };

  @override
  String toString() => 'BleException(${kind.name}): $message';
}

/// The only BLE surface the app uses. Implemented by [UniversalBleAdapter]
/// for real hardware and by fakes/simulators for tests and UI development.
///
/// Every method is keyed by device id: there is deliberately no notion of a
/// single "current device".
abstract interface class BleAdapter {
  Stream<BleAvailability> get availabilityChanges;
  Future<BleAvailability> getAvailability();

  /// On iOS this triggers the system permission prompt the first time.
  Future<void> requestPermission();

  /// Broadcast stream of advertisements while scanning.
  Stream<BleAdvertisement> get advertisements;
  Future<void> startScan({required bool heartRateOnly});
  Future<void> stopScan();

  /// Heart-rate devices already connected to this phone at the OS level.
  /// Such devices don't advertise, so a scan alone would never find them.
  Future<List<BleAdvertisement>> getSystemConnectedHeartRateDevices();

  /// Link up (true) / down (false) events for one device.
  Stream<bool> connectionChanges(String deviceId);

  /// Completes when the link is up. Throws [BleException] on failure or
  /// timeout.
  Future<void> connect(String deviceId, {required Duration timeout});

  /// Tears down the link or cancels a pending connection. Never throws.
  Future<void> disconnect(String deviceId);

  Future<GattProfile> discoverServices(String deviceId, {required Duration timeout});

  /// Values notified/read for a characteristic. Listen BEFORE calling
  /// [subscribe] so the first packet is not missed.
  Stream<List<int>> characteristicValues(String deviceId, String characteristicUuid);

  Future<void> subscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  });

  Future<List<int>> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  });

  /// RSSI of a connected device, or null if unsupported on this platform.
  Future<int?> readRssi(String deviceId);
}
