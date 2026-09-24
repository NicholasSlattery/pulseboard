import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_adapter.dart';
import 'ble_uuids.dart';

final _log = Logger('BLE.Adapter');

/// [BleAdapter] backed by the `universal_ble` plugin (CoreBluetooth on iOS,
/// WinRT on Windows).
///
/// Notes on the plugin's behaviour, verified against its source (v2.3):
/// * iOS `connect` resolves unknown ids via `retrievePeripherals(withIdentifiers:)`,
///   so remembered sensors can be reconnected after an app restart without
///   scanning first.
/// * CoreBluetooth connection requests never time out natively. The plugin's
///   timeout is Dart-side only, so after a timeout we explicitly `disconnect`
///   to cancel the pending request (done by the sensor connection).
/// * The default command queue is global; one slow device would delay GATT
///   operations for every other strap. We switch to per-device queues.
class UniversalBleAdapter implements BleAdapter {
  UniversalBleAdapter() {
    UniversalBle.queueType = QueueType.perDevice;
    UniversalBle.timeout = const Duration(seconds: 15);
  }

  @override
  Stream<BleAvailability> get availabilityChanges =>
      UniversalBle.availabilityStream.map(_mapAvailability);

  @override
  Future<BleAvailability> getAvailability() async {
    try {
      return _mapAvailability(await UniversalBle.getBluetoothAvailabilityState());
    } catch (e) {
      _log.warning('getAvailability failed: $e');
      return BleAvailability.unknown;
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await UniversalBle.requestPermissions();
    } catch (e) {
      // Denial is reflected in the availability state (unauthorized); the UI
      // explains how to fix it.
      _log.warning('Permission request failed: $e');
    }
  }

  @override
  Stream<BleAdvertisement> get advertisements => UniversalBle.scanStream.map(_mapDevice);

  @override
  Future<void> startScan({required bool heartRateOnly}) async {
    try {
      await UniversalBle.startScan(
        scanFilter: heartRateOnly ? ScanFilter(withServices: [BleUuids.heartRateService]) : null,
      );
    } catch (e) {
      throw _wrap(e, 'startScan');
    }
  }

  @override
  Future<void> stopScan() async {
    try {
      await UniversalBle.stopScan();
    } catch (e) {
      _log.fine('stopScan failed: $e');
    }
  }

  @override
  Future<List<BleAdvertisement>> getSystemConnectedHeartRateDevices() async {
    // On Apple this is a cheap CoreBluetooth query. On Windows/Android the
    // plugin would connect to every paired device to discover its services,
    // which is far too heavy to do on every scan.
    if (!_isApple) return const [];
    try {
      final devices = await UniversalBle.getSystemDevices(
        withServices: [BleUuids.heartRateService],
        timeout: const Duration(seconds: 5),
      );
      return devices.map((d) => _mapDevice(d, systemConnected: true)).toList(growable: false);
    } catch (e) {
      _log.fine('getSystemDevices failed: $e');
      return const [];
    }
  }

  @override
  Stream<bool> connectionChanges(String deviceId) => UniversalBle.connectionStream(deviceId);

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    try {
      await UniversalBle.connect(deviceId, timeout: timeout);
    } on TimeoutException {
      throw const BleException(BleErrorKind.timeout, 'connect timed out');
    } catch (e) {
      throw _wrap(e, 'connect');
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    try {
      await UniversalBle.disconnect(deviceId, timeout: const Duration(seconds: 5));
    } catch (e) {
      _log.fine('disconnect($deviceId) failed: $e');
    }
  }

  @override
  Future<GattProfile> discoverServices(String deviceId, {required Duration timeout}) async {
    try {
      final services = await UniversalBle.discoverServices(deviceId, timeout: timeout);
      return GattProfile({
        for (final s in services)
          BleUuids.normalize(s.uuid): {
            for (final c in s.characteristics)
              BleUuids.normalize(c.uuid): c.properties.map(_mapProperty).nonNulls.toSet(),
          },
      });
    } on TimeoutException {
      throw const BleException(BleErrorKind.timeout, 'service discovery timed out');
    } catch (e) {
      throw _wrap(e, 'discoverServices');
    }
  }

  @override
  Stream<List<int>> characteristicValues(String deviceId, String characteristicUuid) =>
      UniversalBle.characteristicValueStream(deviceId, characteristicUuid);

  @override
  Future<void> subscribe(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  }) async {
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        serviceUuid,
        characteristicUuid,
        timeout: timeout,
      );
    } on TimeoutException {
      throw const BleException(BleErrorKind.timeout, 'subscribe timed out');
    } catch (e) {
      throw _wrap(e, 'subscribe');
    }
  }

  @override
  Future<List<int>> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid, {
    required Duration timeout,
  }) async {
    try {
      return await UniversalBle.read(deviceId, serviceUuid, characteristicUuid, timeout: timeout);
    } on TimeoutException {
      throw const BleException(BleErrorKind.timeout, 'read timed out');
    } catch (e) {
      throw _wrap(e, 'read');
    }
  }

  @override
  Future<int?> readRssi(String deviceId) async {
    // RSSI of connected devices is only available on Apple/Android.
    final supported = _isApple || (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (!supported) return null;
    try {
      return await UniversalBle.readRssi(deviceId, timeout: const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static BleAdvertisement _mapDevice(BleDevice d, {bool systemConnected = false}) {
    final name = d.name?.trim();
    return BleAdvertisement(
      deviceId: d.deviceId,
      timestamp: d.timestampDateTime ?? DateTime.now(),
      name: (name == null || name.isEmpty) ? null : name,
      rssi: d.rssi,
      serviceUuids: d.services.map(BleUuids.normalize).toList(growable: false),
      isSystemConnected: systemConnected || (d.isSystemDevice ?? false),
    );
  }

  static BleAvailability _mapAvailability(AvailabilityState s) => switch (s) {
    AvailabilityState.unknown => BleAvailability.unknown,
    AvailabilityState.resetting => BleAvailability.resetting,
    AvailabilityState.unsupported => BleAvailability.unsupported,
    AvailabilityState.unauthorized => BleAvailability.unauthorized,
    AvailabilityState.poweredOff => BleAvailability.poweredOff,
    AvailabilityState.poweredOn => BleAvailability.poweredOn,
  };

  static GattProperty? _mapProperty(CharacteristicProperty p) => switch (p) {
    CharacteristicProperty.read => GattProperty.read,
    CharacteristicProperty.write => GattProperty.write,
    CharacteristicProperty.writeWithoutResponse => GattProperty.writeWithoutResponse,
    CharacteristicProperty.notify => GattProperty.notify,
    CharacteristicProperty.indicate => GattProperty.indicate,
    _ => null,
  };

  static BleException _wrap(Object error, String operation) {
    if (error is BleException) return error;
    var kind = BleErrorKind.operationFailed;
    if (error is UniversalBleException) {
      kind = switch (error.code) {
        UniversalBleErrorCode.bluetoothNotAvailable ||
        UniversalBleErrorCode.bluetoothNotEnabled => BleErrorKind.bluetoothUnavailable,
        UniversalBleErrorCode.bluetoothNotAllowed ||
        UniversalBleErrorCode.bluetoothUnauthorized => BleErrorKind.unauthorized,
        UniversalBleErrorCode.connectionTimeout ||
        UniversalBleErrorCode.operationTimeout => BleErrorKind.timeout,
        UniversalBleErrorCode.deviceNotFound => BleErrorKind.deviceNotFound,
        UniversalBleErrorCode.serviceNotFound => BleErrorKind.serviceNotFound,
        UniversalBleErrorCode.characteristicNotFound => BleErrorKind.characteristicNotFound,
        UniversalBleErrorCode.connectionFailed ||
        UniversalBleErrorCode.connectionRejected ||
        UniversalBleErrorCode.connectionLimitExceeded ||
        UniversalBleErrorCode.connectionTerminated ||
        UniversalBleErrorCode.deviceDisconnected => BleErrorKind.connectionFailed,
        _ => operation == 'connect' ? BleErrorKind.connectionFailed : BleErrorKind.operationFailed,
      };
    } else if (error is PlatformException || operation == 'connect') {
      kind = operation == 'connect' ? BleErrorKind.connectionFailed : BleErrorKind.operationFailed;
    }
    return BleException(kind, '$operation: $error');
  }
}
