import 'dart:typed_data';

import 'package:pulseboard/speedcoach/peripheral_adapter.dart';
import 'package:pulseboard/speedcoach/speedcoach_protocol.dart';

/// Scriptable in-memory [PeripheralAdapter]: tests play the SpeedCoach by
/// calling [write] and [read].
class FakePeripheral implements PeripheralAdapter {
  FakePeripheral({this.supportsLocalName = true});

  @override
  final bool supportsLocalName;
  bool ready = true;
  final List<String> addedServices = [];
  List<String> addedCharacteristics = [];
  String? advertisedName;
  int stopAdvertisingCalls = 0;
  PeripheralWriteHandler? onWrite;
  PeripheralReadHandler? onRead;

  void write(String suffix, List<int> bytes) =>
      onWrite!('SC', SpeedCoachUuids.char(suffix), Uint8List.fromList(bytes));

  Uint8List read(String suffix) => onRead!('SC', SpeedCoachUuids.char(suffix));

  @override
  Future<bool> waitUntilReady({Duration timeout = const Duration(seconds: 5)}) async => ready;

  @override
  Future<void> addService(String serviceUuid, List<String> characteristicUuids) async {
    addedServices.add(serviceUuid);
    addedCharacteristics = characteristicUuids;
  }

  @override
  Future<void> removeService(String serviceUuid) async => addedServices.remove(serviceUuid);

  @override
  Future<void> startAdvertising({required String serviceUuid, required String localName}) async {
    advertisedName = localName;
  }

  @override
  Future<void> stopAdvertising() async {
    stopAdvertisingCalls++;
    advertisedName = null;
  }

  @override
  void setHandlers({
    required PeripheralWriteHandler onWrite,
    required PeripheralReadHandler onRead,
  }) {
    this.onWrite = onWrite;
    this.onRead = onRead;
  }

  @override
  void clearHandlers() {
    onWrite = null;
    onRead = null;
  }
}
