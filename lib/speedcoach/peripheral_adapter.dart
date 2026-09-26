import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:universal_ble/universal_ble.dart';

final _log = Logger('SpeedCoach.Peripheral');

/// Called for every write a remote device makes to one of our
/// characteristics. [characteristicUuid] is lower-case 128-bit.
typedef PeripheralWriteHandler =
    void Function(String deviceId, String characteristicUuid, Uint8List value);

/// Returns the value to answer a remote read with.
typedef PeripheralReadHandler = Uint8List Function(String deviceId, String characteristicUuid);

/// The small slice of "act as a Bluetooth peripheral" the SpeedCoach receiver
/// needs. Implemented with universal_ble on devices and by a fake in tests.
abstract interface class PeripheralAdapter {
  /// Whether this platform can advertise a custom local name (iOS: yes,
  /// Windows: no), which the SpeedCoach needs to find the receiver.
  bool get supportsLocalName;

  /// Waits until the peripheral role is powered on. Returns false if it is
  /// off, unauthorised or unsupported.
  Future<bool> waitUntilReady({Duration timeout = const Duration(seconds: 5)});

  /// Publishes a primary service whose characteristics are all readable and
  /// writable.
  Future<void> addService(String serviceUuid, List<String> characteristicUuids);

  Future<void> removeService(String serviceUuid);

  Future<void> startAdvertising({required String serviceUuid, required String localName});

  Future<void> stopAdvertising();

  void setHandlers({
    required PeripheralWriteHandler onWrite,
    required PeripheralReadHandler onRead,
  });

  void clearHandlers();
}

/// [PeripheralAdapter] backed by universal_ble's peripheral API
/// (CBPeripheralManager on iOS).
class UniversalBlePeripheralAdapter implements PeripheralAdapter {
  /// CoreBluetooth lets an app choose the advertised local name; Windows
  /// does not (it can only advertise the service UUID).
  @override
  bool get supportsLocalName =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Future<bool> waitUntilReady({Duration timeout = const Duration(seconds: 5)}) async {
    if (!BleCapabilities.supportsPeripheralApi) return false;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        final state = await UniversalBlePeripheral.getAvailabilityState();
        if (state == PeripheralReadinessState.ready) return true;
        if (state == PeripheralReadinessState.unsupported ||
            state == PeripheralReadinessState.unauthorized) {
          _log.warning('Peripheral role not available: ${state.name}');
          return false;
        }
      } catch (e) {
        _log.fine('getAvailabilityState failed: $e');
      }
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Future<void> addService(String serviceUuid, List<String> characteristicUuids) {
    return UniversalBlePeripheral.addService(
      BlePeripheralService(
        uuid: serviceUuid,
        characteristics: [
          for (final c in characteristicUuids)
            BlePeripheralCharacteristic(
              uuid: c,
              properties: const [
                CharacteristicProperty.read,
                CharacteristicProperty.write,
                CharacteristicProperty.writeWithoutResponse,
              ],
              permissions: const [
                PeripheralAttributePermission.readable,
                PeripheralAttributePermission.writeable,
              ],
            ),
        ],
      ),
      timeout: const Duration(seconds: 10),
    );
  }

  @override
  Future<void> removeService(String serviceUuid) async {
    try {
      await UniversalBlePeripheral.removeService(serviceUuid);
    } catch (e) {
      _log.fine('removeService failed: $e');
    }
  }

  @override
  Future<void> startAdvertising({required String serviceUuid, required String localName}) =>
      UniversalBlePeripheral.startAdvertising(services: [serviceUuid], localName: localName);

  @override
  Future<void> stopAdvertising() async {
    try {
      await UniversalBlePeripheral.stopAdvertising();
    } catch (e) {
      _log.fine('stopAdvertising failed: $e');
    }
  }

  @override
  void setHandlers({
    required PeripheralWriteHandler onWrite,
    required PeripheralReadHandler onRead,
  }) {
    UniversalBlePeripheral.setWriteRequestHandlers((deviceId, characteristicId, offset, value) {
      if (offset != 0) {
        _log.warning('Write with offset $offset to $characteristicId (long write) - ignored');
        return PeripheralWriteRequestResult();
      }
      onWrite(deviceId, characteristicId.toLowerCase(), value ?? Uint8List(0));
      return PeripheralWriteRequestResult();
    });
    UniversalBlePeripheral.setReadRequestHandlers((deviceId, characteristicId, offset, value) {
      return PeripheralReadRequestResult(value: onRead(deviceId, characteristicId.toLowerCase()));
    });
  }

  @override
  void clearHandlers() {
    UniversalBlePeripheral.setWriteRequestHandlers(null);
    UniversalBlePeripheral.setReadRequestHandlers(null);
  }
}
