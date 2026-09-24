import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bluetooth/bluetooth_manager.dart';
import '../models/known_sensor.dart';
import '../models/sensor_state.dart';
import 'core_providers.dart';

/// Remembered sensors (persisted), kept in sync with the database.
class KnownSensorsController extends Notifier<List<KnownSensor>> {
  @override
  List<KnownSensor> build() {
    final repo = ref.watch(sensorRepositoryProvider);
    final sub = repo.changes.listen((list) => state = list);
    ref.onDispose(sub.cancel);
    return ref.read(bootstrapProvider).sensors;
  }
}

final knownSensorsProvider = NotifierProvider<KnownSensorsController, List<KnownSensor>>(
  KnownSensorsController.new,
);

/// sensorId -> athleteId for assigned sensors.
final sensorAssignmentsProvider = Provider<Map<String, String>>((ref) {
  final sensors = ref.watch(knownSensorsProvider);
  return {
    for (final s in sensors)
      if (s.athleteId != null) s.id: s.athleteId!,
  };
});

/// The sensor assigned to an athlete, if any.
final sensorIdForAthleteProvider = Provider.family<String?, String>((ref, athleteId) {
  return ref.watch(
    knownSensorsProvider.select((list) {
      for (final s in list) {
        if (s.athleteId == athleteId) return s.id;
      }
      return null;
    }),
  );
});

/// Live state of every sensor the Bluetooth manager knows about.
class SensorLiveStatesController extends Notifier<Map<String, SensorLiveState>> {
  @override
  Map<String, SensorLiveState> build() {
    final manager = ref.watch(bluetoothManagerProvider);
    final sub = manager.sensorsStream.listen((next) => state = next);
    ref.onDispose(sub.cancel);
    return manager.sensors;
  }
}

final sensorLiveStatesProvider =
    NotifierProvider<SensorLiveStatesController, Map<String, SensorLiveState>>(
      SensorLiveStatesController.new,
    );

/// Live state of ONE sensor. Widgets watch this so a packet from one strap
/// only rebuilds that strap's card.
final sensorLiveProvider = Provider.family<SensorLiveState?, String>((ref, sensorId) {
  return ref.watch(sensorLiveStatesProvider.select((m) => m[sensorId]));
});

class BluetoothStatusController extends Notifier<BluetoothStatus> {
  @override
  BluetoothStatus build() {
    final manager = ref.watch(bluetoothManagerProvider);
    final sub = manager.statusStream.listen((next) => state = next);
    ref.onDispose(sub.cancel);
    return manager.status;
  }
}

final bluetoothStatusProvider = NotifierProvider<BluetoothStatusController, BluetoothStatus>(
  BluetoothStatusController.new,
);

/// User-level sensor operations. Widgets call these; they never touch BLE
/// or the database directly.
class SensorActions {
  SensorActions(this._ref);

  final Ref _ref;

  BluetoothManager get _manager => _ref.read(bluetoothManagerProvider);

  Future<void> startScan({bool allDevices = false}) => _manager.startScan(allDevices: allDevices);

  Future<void> stopScan() => _manager.stopScan();

  void connect(String sensorId) => _manager.connect(sensorId);

  Future<void> disconnect(String sensorId) => _manager.disconnect(sensorId);

  /// Assigns the sensor to the athlete (moving the athlete off any previous
  /// sensor) and makes sure it is connected.
  Future<void> assign({required String sensorId, required String athleteId}) async {
    final name = _manager.sensors[sensorId]?.name;
    await _ref
        .read(sensorRepositoryProvider)
        .assign(sensorId: sensorId, athleteId: athleteId, sensorName: name);
    _manager.connect(sensorId);
  }

  Future<void> unassign(String sensorId) => _ref.read(sensorRepositoryProvider).unassign(sensorId);

  /// Disconnects and removes the sensor from memory and storage.
  Future<void> forget(String sensorId) async {
    await _manager.forget(sensorId);
    await _ref.read(sensorRepositoryProvider).forget(sensorId);
  }
}

final sensorActionsProvider = Provider<SensorActions>(SensorActions.new);
