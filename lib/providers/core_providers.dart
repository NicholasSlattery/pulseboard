import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bluetooth/ble_adapter.dart';
import '../bluetooth/bluetooth_manager.dart';
import '../bluetooth/heart_rate_sensor_connection.dart';
import '../models/app_settings.dart';
import '../models/athlete.dart';
import '../models/known_sensor.dart';
import '../models/lineup.dart';
import '../session/session_recorder.dart';
import '../speedcoach/peripheral_adapter.dart';
import '../storage/app_database.dart';
import '../storage/athlete_repository.dart';
import '../storage/lineup_repository.dart';
import '../storage/sensor_repository.dart';
import '../storage/session_repository.dart';
import '../storage/settings_repository.dart';

/// Everything loaded before the first frame (see main.dart). Injected with
/// `bootstrapProvider.overrideWithValue(...)`.
class AppBootstrap {
  const AppBootstrap({
    required this.database,
    required this.adapter,
    required this.settings,
    required this.athletes,
    required this.sensors,
    this.lineups = LineupBook.empty,
    this.recoveredSessions = 0,
    this.isSimulated = false,
    this.peripheralAdapter,
  });

  final AppDatabase database;
  final BleAdapter adapter;
  final AppSettings settings;
  final List<Athlete> athletes;
  final List<KnownSensor> sensors;
  final LineupBook lineups;

  /// Sessions that were left open by a crash and closed on this launch.
  final int recoveredSessions;
  final bool isSimulated;

  /// Overrides the Bluetooth peripheral used by the SpeedCoach receiver
  /// (tests). Null uses universal_ble.
  final PeripheralAdapter? peripheralAdapter;
}

final bootstrapProvider = Provider<AppBootstrap>(
  (ref) => throw UnimplementedError('bootstrapProvider must be overridden in main()'),
);

final databaseProvider = Provider<AppDatabase>((ref) => ref.watch(bootstrapProvider).database);

final athleteRepositoryProvider = Provider<AthleteRepository>((ref) {
  final repo = AthleteRepository(ref.watch(databaseProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final sensorRepositoryProvider = Provider<SensorRepository>((ref) {
  final repo = SensorRepository(ref.watch(databaseProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final repo = SessionRepository(ref.watch(databaseProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final lineupRepositoryProvider = Provider<LineupRepository>(
  (ref) => LineupRepository(ref.watch(databaseProvider)),
);

/// The single Bluetooth manager. Initial settings come from the bootstrap;
/// later changes are pushed in by the settings effect (see effects.dart).
final bluetoothManagerProvider = Provider<BluetoothManager>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  final s = bootstrap.settings;
  final manager = BluetoothManager(
    adapter: bootstrap.adapter,
    config: SensorConnectionConfig(autoReconnect: s.autoReconnect, verbose: s.verboseLogging),
    staleAfter: s.staleAfter,
    signalLostAfter: s.effectiveSignalLostAfter,
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final sessionRecorderProvider = Provider<SessionRecorder>((ref) {
  final manager = ref.watch(bluetoothManagerProvider);
  final recorder = SessionRecorder(
    repository: ref.watch(sessionRepositoryProvider),
    readings: manager.readings,
    events: manager.events,
  );
  ref.onDispose(recorder.dispose);
  return recorder;
});
