import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/sensor_state.dart';
import '../utils/app_logger.dart';
import 'core_providers.dart';
import 'sensors_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';

final _log = Logger('Effects');

/// Wires state changes to side effects in ONE place, so widgets stay free of
/// imperative plumbing. Watched once by the root widget.
///
/// * settings -> Bluetooth manager timing/reconnect + log verbosity
/// * remembered/assigned sensors -> keep those straps connected
/// * roster changes during a session -> recorder
/// * observed sensor names/battery -> persisted for known sensors
/// * session + keep-awake preference -> screen wakelock
final appEffectsProvider = Provider<void>((ref) {
  final manager = ref.read(bluetoothManagerProvider);

  // Settings -> Bluetooth + logging.
  void applySettings(AppSettings s) {
    manager.updateSettings(
      autoReconnect: s.autoReconnect,
      staleAfter: s.staleAfter,
      signalLostAfter: s.effectiveSignalLostAfter,
      verbose: s.verboseLogging,
    );
    AppLogger.setVerbose(s.verboseLogging);
  }

  applySettings(ref.read(settingsProvider));
  ref.listen(settingsProvider, (_, next) => applySettings(next));

  // Assigned sensors are kept connected. Only runs once Bluetooth has been
  // initialised (after the first-launch explanation screen).
  void syncAssigned() {
    if (!ref.read(bluetoothStatusProvider).initialized) return;
    final sensors = ref.read(knownSensorsProvider);
    manager.syncAssignedSensors({
      for (final s in sensors)
        if (s.athleteId != null) s.id: s.name,
    });
  }

  ref.listen(knownSensorsProvider, (_, _) => syncAssigned());
  ref.listen(bluetoothStatusProvider.select((s) => s.initialized), (_, initialized) {
    if (initialized) syncAssigned();
  });
  syncAssigned();

  // Keep the recorder's sensor -> athlete mapping current mid-session.
  ref.listen(rosterProvider, (_, roster) {
    final recorder = ref.read(sessionRecorderProvider);
    if (recorder.active != null) unawaited(recorder.updateRoster(roster));
  });

  // Persist names and battery levels seen for remembered sensors.
  final persisted = <String, (String?, int?)>{};
  ref.listen<Map<String, SensorLiveState>>(sensorLiveStatesProvider, (_, states) {
    final known = {for (final s in ref.read(knownSensorsProvider)) s.id: s};
    final repo = ref.read(sensorRepositoryProvider);
    for (final state in states.values) {
      final k = known[state.sensorId];
      if (k == null) continue;
      final observed = (state.name, state.batteryPercent);
      final previous = persisted[state.sensorId] ?? (k.name, k.batteryPercent);
      if (observed == previous || (state.name == null && state.batteryPercent == null)) continue;
      persisted[state.sensorId] = observed;
      unawaited(
        repo
            .updateObserved(
              state.sensorId,
              name: state.name,
              batteryPercent: state.batteryPercent,
              seenAt: DateTime.now(),
            )
            .catchError((Object e) => _log.warning('Persisting sensor info failed: $e')),
      );
    }
  });

  // Screen wakelock.
  void applyWakelock() {
    final mode = ref.read(settingsProvider).keepAwake;
    final sessionActive = ref.read(activeSessionProvider) != null;
    final enable = switch (mode) {
      KeepAwakeMode.never => false,
      KeepAwakeMode.duringSession => sessionActive,
      KeepAwakeMode.always => true,
    };
    unawaited(
      WakelockPlus.toggle(
        enable: enable,
      ).catchError((Object e) => _log.warning('Wakelock unavailable: $e')),
    );
  }

  ref.listen(settingsProvider.select((s) => s.keepAwake), (_, _) => applyWakelock());
  ref.listen(activeSessionProvider, (_, _) => applyWakelock());
  applyWakelock();
});
