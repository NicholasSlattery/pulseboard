import 'package:flutter/foundation.dart';

import 'connection_event.dart';

/// A recorded workout.
@immutable
class TrainingSession {
  const TrainingSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.name,
    this.zoneLowerBounds = const [],
    this.recovered = false,
  });

  final String id;
  final DateTime startedAt;

  /// Null while the session is running.
  final DateTime? endedAt;
  final String? name;

  /// The zone model in effect when the session was recorded, so historical
  /// summaries stay correct if zone settings change later.
  final List<double> zoneLowerBounds;

  /// True if the app was killed mid-session and the end time was
  /// reconstructed from the last recorded sample on the next launch.
  final bool recovered;

  bool get isActive => endedAt == null;

  Duration duration([DateTime? now]) => (endedAt ?? now ?? DateTime.now()).difference(startedAt);

  TrainingSession copyWith({
    DateTime? Function()? endedAt,
    String? Function()? name,
    bool? recovered,
  }) {
    return TrainingSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt != null ? endedAt() : this.endedAt,
      name: name != null ? name() : this.name,
      zoneLowerBounds: zoneLowerBounds,
      recovered: recovered ?? this.recovered,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'started_at': startedAt.millisecondsSinceEpoch,
    'ended_at': endedAt?.millisecondsSinceEpoch,
    'name': name,
    'zone_bounds': zoneLowerBounds.join(','),
    'recovered': recovered ? 1 : 0,
  };

  factory TrainingSession.fromRow(Map<String, Object?> row) {
    final bounds = (row['zone_bounds'] as String? ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(double.tryParse)
        .whereType<double>()
        .toList(growable: false);
    return TrainingSession(
      id: row['id']! as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at']! as int),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['ended_at']! as int),
      name: row['name'] as String?,
      zoneLowerBounds: bounds,
      recovered: (row['recovered'] as int? ?? 0) != 0,
    );
  }
}

/// Snapshot of an athlete as they were when they joined a session. Keeps
/// history intact even if the athlete is later renamed or deleted.
@immutable
class SessionAthlete {
  const SessionAthlete({
    required this.sessionId,
    required this.athleteId,
    required this.athleteName,
    this.sensorId,
    this.maxHr,
  });

  final String sessionId;
  final String athleteId;
  final String athleteName;
  final String? sensorId;
  final int? maxHr;

  Map<String, Object?> toRow() => {
    'session_id': sessionId,
    'athlete_id': athleteId,
    'athlete_name': athleteName,
    'sensor_id': sensorId,
    'max_hr': maxHr,
  };

  factory SessionAthlete.fromRow(Map<String, Object?> row) => SessionAthlete(
    sessionId: row['session_id']! as String,
    athleteId: row['athlete_id']! as String,
    athleteName: row['athlete_name']! as String,
    sensorId: row['sensor_id'] as String?,
    maxHr: row['max_hr'] as int?,
  );
}

/// One recorded heart-rate sample.
@immutable
class HeartRateSample {
  const HeartRateSample({
    required this.sessionId,
    required this.athleteId,
    required this.sensorId,
    required this.timestamp,
    required this.bpm,
    this.percentOfMax,
    this.zone,
    this.rrIntervals1024 = const [],
  });

  final String sessionId;
  final String athleteId;
  final String sensorId;
  final DateTime timestamp;
  final int bpm;
  final double? percentOfMax;
  final int? zone;

  /// Raw RR intervals in 1/1024 s units (lossless).
  final List<int> rrIntervals1024;

  Map<String, Object?> toRow() => {
    'session_id': sessionId,
    'athlete_id': athleteId,
    'sensor_id': sensorId,
    't': timestamp.millisecondsSinceEpoch,
    'bpm': bpm,
    'pct': percentOfMax,
    'zone': zone,
    'rr': rrIntervals1024.isEmpty ? null : rrIntervals1024.join(','),
  };

  factory HeartRateSample.fromRow(Map<String, Object?> row) {
    final rr = row['rr'] as String?;
    return HeartRateSample(
      sessionId: row['session_id']! as String,
      athleteId: row['athlete_id']! as String,
      sensorId: row['sensor_id']! as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['t']! as int),
      bpm: row['bpm']! as int,
      percentOfMax: (row['pct'] as num?)?.toDouble(),
      zone: row['zone'] as int?,
      rrIntervals1024: rr == null || rr.isEmpty
          ? const []
          : rr.split(',').map(int.tryParse).whereType<int>().toList(growable: false),
    );
  }
}

/// A connection event recorded during a session.
@immutable
class SessionConnectionEvent {
  const SessionConnectionEvent({
    required this.sessionId,
    required this.sensorId,
    this.athleteId,
    required this.type,
    required this.timestamp,
    this.detail,
  });

  final String sessionId;
  final String sensorId;
  final String? athleteId;
  final ConnectionEventType type;
  final DateTime timestamp;
  final String? detail;

  Map<String, Object?> toRow() => {
    'session_id': sessionId,
    'sensor_id': sensorId,
    'athlete_id': athleteId,
    'type': type.name,
    't': timestamp.millisecondsSinceEpoch,
    'detail': detail,
  };

  factory SessionConnectionEvent.fromRow(Map<String, Object?> row) => SessionConnectionEvent(
    sessionId: row['session_id']! as String,
    sensorId: row['sensor_id']! as String,
    athleteId: row['athlete_id'] as String?,
    type: ConnectionEventType.fromName(row['type']! as String),
    timestamp: DateTime.fromMillisecondsSinceEpoch(row['t']! as int),
    detail: row['detail'] as String?,
  );
}
