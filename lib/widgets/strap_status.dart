import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../models/sensor_state.dart';
import '../providers/sensors_provider.dart';

/// Strap state of one athlete for setup screens.
@immutable
class StrapStatus {
  const StrapStatus({required this.color, this.problem, this.sensorName, this.battery});

  /// Dot colour: connected, warning, danger or neutral (no strap).
  final Color color;

  /// Short problem text ("reconnecting", "no strap"), or null when live.
  final String? problem;
  final String? sensorName;
  final int? battery;

  bool get isLive => problem == null;

  /// "Polar H10 · 82% battery", or the sensor name and the problem.
  String get description {
    if (problem == 'no strap') return 'No strap';
    final name = sensorName ?? 'Strap';
    if (problem != null) return '$name · $problem';
    return battery == null ? name : '$name · $battery% battery';
  }
}

/// Watches the strap assigned to [athleteId].
StrapStatus watchStrapStatus(WidgetRef ref, String athleteId) {
  final sensorId = ref.watch(sensorIdForAthleteProvider(athleteId));
  if (sensorId == null) {
    return const StrapStatus(color: AppColors.neutral, problem: 'no strap');
  }
  final known = ref.watch(
    knownSensorsProvider.select((list) {
      for (final s in list) {
        if (s.id == sensorId) return (s.name, s.batteryPercent);
      }
      return (null, null);
    }),
  );
  final s = ref.watch(sensorLiveProvider(sensorId));
  final name = s?.name ?? known.$1;
  final battery = s?.batteryPercent ?? known.$2;
  StrapStatus st(Color c, [String? problem]) =>
      StrapStatus(color: c, problem: problem, sensorName: name, battery: battery);
  if (s == null) return st(AppColors.danger, 'not connected');
  switch (s.connection) {
    case SensorConnectionState.receiving:
      if (s.noSkinContact) return st(AppColors.warning, 'no skin contact');
      return switch (s.freshness) {
        SignalFreshness.fresh => st(AppColors.connected),
        SignalFreshness.stale => st(AppColors.warning, 'weak signal'),
        SignalFreshness.none || SignalFreshness.lost => st(AppColors.danger, 'no signal'),
      };
    case SensorConnectionState.connecting:
    case SensorConnectionState.connected:
    case SensorConnectionState.subscribing:
      return st(AppColors.warning, 'connecting');
    case SensorConnectionState.reconnecting:
      return st(AppColors.danger, 'reconnecting');
    case SensorConnectionState.failed:
      return st(AppColors.danger, 'sensor error');
    case SensorConnectionState.discovered:
    case SensorConnectionState.disconnected:
      return st(AppColors.danger, 'not connected');
  }
}
