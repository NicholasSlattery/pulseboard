import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/sensor_state.dart';

/// Human-readable label and colour for a sensor's connection state, used in
/// the sensor list and the sensor sheet.
(String, Color) sensorStatusOf(SensorLiveState? s) {
  if (s == null) return ('NOT SEEN', AppColors.neutral);
  return switch (s.connection) {
    SensorConnectionState.discovered =>
      s.isSystemConnected ? ('CONNECTED TO PHONE', AppColors.info) : ('NEARBY', AppColors.info),
    SensorConnectionState.connecting => ('CONNECTING…', AppColors.warning),
    SensorConnectionState.connected => ('DISCOVERING…', AppColors.warning),
    SensorConnectionState.subscribing => ('WAITING FOR DATA', AppColors.warning),
    SensorConnectionState.receiving => switch (s.freshness) {
      SignalFreshness.fresh => ('RECEIVING', AppColors.connected),
      SignalFreshness.stale => ('WEAK SIGNAL', AppColors.warning),
      SignalFreshness.lost || SignalFreshness.none =>
        s.noSkinContact ? ('NO SKIN CONTACT', AppColors.warning) : ('NO SIGNAL', AppColors.danger),
    },
    SensorConnectionState.reconnecting => ('RECONNECTING…', AppColors.danger),
    SensorConnectionState.disconnected => ('DISCONNECTED', AppColors.neutral),
    SensorConnectionState.failed => ('FAILED', AppColors.danger),
  };
}
