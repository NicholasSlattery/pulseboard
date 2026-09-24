import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/athlete.dart';
import '../models/hr_zones.dart';
import '../models/hr_zones.dart' as hr show percentOfMax;
import '../models/sensor_state.dart';
import '../utils/formatters.dart';
import 'athletes_provider.dart';
import 'sensors_provider.dart';

/// One card on the dashboard: an athlete with an assigned sensor, or a
/// connected sensor that nobody has been assigned to yet.
@immutable
class DashboardEntry {
  const DashboardEntry.athlete({required String this.athleteId, required this.sensorId});
  const DashboardEntry.unassigned({required this.sensorId}) : athleteId = null;

  final String? athleteId;
  final String sensorId;

  bool get isAssigned => athleteId != null;
  String get key => athleteId ?? 'sensor:$sensorId';

  @override
  bool operator ==(Object other) =>
      other is DashboardEntry && other.athleteId == athleteId && other.sensorId == sensorId;

  @override
  int get hashCode => Object.hash(athleteId, sensorId);
}

/// Cards to show, in display order. Only changes when the set of cards
/// changes - not on every heart-rate packet.
final dashboardEntriesProvider = Provider<List<DashboardEntry>>((ref) {
  final athletes = ref.watch(athletesProvider);
  final assignments = ref.watch(sensorAssignmentsProvider);
  final assignedSensorIds = assignments.keys.toSet();

  // Selecting a joined string (not a list) means this provider is only
  // re-evaluated when the set of active unassigned sensors changes.
  final unassignedKey = ref.watch(
    sensorLiveStatesProvider.select((states) {
      final ids = [
        for (final s in states.values)
          if (!assignedSensorIds.contains(s.sensorId) && _isActive(s.connection)) s.sensorId,
      ]..sort();
      return ids.join('|');
    }),
  );

  final athleteById = {for (final a in athletes) a.id: a};
  final assigned = <(Athlete, String)>[
    for (final e in assignments.entries)
      if (athleteById[e.value] != null) (athleteById[e.value]!, e.key),
  ]..sort((a, b) => naturalCompare(a.$1.displayName, b.$1.displayName));

  return [
    for (final (athlete, sensorId) in assigned)
      DashboardEntry.athlete(athleteId: athlete.id, sensorId: sensorId),
    if (unassignedKey.isNotEmpty)
      for (final id in unassignedKey.split('|')) DashboardEntry.unassigned(sensorId: id),
  ];
});

bool _isActive(SensorConnectionState c) =>
    c != SensorConnectionState.discovered &&
    c != SensorConnectionState.disconnected &&
    c != SensorConnectionState.failed;

/// Visual status of a card, derived from connection + freshness.
enum CardStatus {
  live,
  weakSignal,
  noSignal,
  noContact,
  connecting,
  reconnecting,
  disconnected,
  failed;

  String get label => switch (this) {
    CardStatus.live => 'CONNECTED',
    CardStatus.weakSignal => 'WEAK SIGNAL',
    CardStatus.noSignal => 'NO SIGNAL',
    CardStatus.noContact => 'NO SKIN CONTACT',
    CardStatus.connecting => 'CONNECTING',
    CardStatus.reconnecting => 'DISCONNECTED',
    CardStatus.disconnected => 'DISCONNECTED',
    CardStatus.failed => 'SENSOR ERROR',
  };
}

/// Everything a dashboard card shows. Pure data, computed by [CardData.from].
@immutable
class CardData {
  const CardData({
    required this.title,
    required this.status,
    this.bpm,
    this.dimmed = false,
    this.percentOfMax,
    this.zone,
    this.batteryPercent,
    this.detail,
    this.maxHr,
    this.isAssigned = true,
  });

  final String title;
  final CardStatus status;

  /// BPM to display, or null for "--". Never a stale value presented as live.
  final int? bpm;

  /// BPM is shown but greyed out (stale reading).
  final bool dimmed;
  final double? percentOfMax;
  final int? zone;
  final int? batteryPercent;

  /// Secondary status line, e.g. "Reconnecting…".
  final String? detail;
  final int? maxHr;
  final bool isAssigned;

  bool get hasMaxHr => maxHr != null;

  static CardData from({
    required Athlete? athlete,
    required SensorLiveState? sensor,
    required String sensorId,
    required MaxHrFormula formula,
    required ZoneModel zones,
  }) {
    final title =
        athlete?.displayName ??
        sensor?.name ??
        'Sensor ${sensorId.length > 4 ? sensorId.substring(sensorId.length - 4) : sensorId}';
    final maxHr = athlete?.effectiveMaxHr(formula);
    final bpm = sensor?.displayBpm;
    final pct = bpm == null ? null : hr.percentOfMax(bpm, maxHr);

    final status = _status(sensor);
    return CardData(
      title: title,
      status: status,
      bpm: bpm,
      dimmed: sensor?.isStale ?? false,
      percentOfMax: pct,
      zone: pct == null ? null : zones.zoneForPercent(pct),
      batteryPercent: sensor?.batteryPercent,
      detail: _detail(sensor, status),
      maxHr: maxHr,
      isAssigned: athlete != null,
    );
  }

  static CardStatus _status(SensorLiveState? s) {
    if (s == null) return CardStatus.disconnected;
    switch (s.connection) {
      case SensorConnectionState.receiving:
        if (s.freshness == SignalFreshness.lost || s.freshness == SignalFreshness.none) {
          return s.noSkinContact ? CardStatus.noContact : CardStatus.noSignal;
        }
        if (s.noSkinContact && s.freshness == SignalFreshness.stale) return CardStatus.noContact;
        return s.freshness == SignalFreshness.stale ? CardStatus.weakSignal : CardStatus.live;
      case SensorConnectionState.connecting:
      case SensorConnectionState.connected:
      case SensorConnectionState.subscribing:
        return CardStatus.connecting;
      case SensorConnectionState.reconnecting:
        return CardStatus.reconnecting;
      case SensorConnectionState.failed:
        return CardStatus.failed;
      case SensorConnectionState.discovered:
      case SensorConnectionState.disconnected:
        return CardStatus.disconnected;
    }
  }

  static String? _detail(SensorLiveState? s, CardStatus status) {
    return switch (status) {
      CardStatus.reconnecting =>
        s?.error == 'Waiting for Bluetooth' ? 'Waiting for Bluetooth' : 'Reconnecting…',
      CardStatus.connecting =>
        s?.connection == SensorConnectionState.subscribing ? 'Waiting for data…' : null,
      CardStatus.noSignal => 'Last reading too old',
      CardStatus.failed => s?.error,
      CardStatus.disconnected => 'Tap to connect',
      _ => null,
    };
  }
}
