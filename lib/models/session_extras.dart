import 'package:flutter/foundation.dart';

/// Who sat in a seat when a session started.
@immutable
class SeatSnapshot {
  const SeatSnapshot({required this.seat, required this.athleteId, required this.name});

  /// 1 = bow.
  final int seat;
  final String athleteId;
  final String name;

  Map<String, Object?> toJson() => {'seat': seat, 'id': athleteId, 'name': name};

  static SeatSnapshot? fromJson(Object? j) {
    if (j is! Map || j['seat'] is! int || j['id'] is! String || j['name'] is! String) return null;
    return SeatSnapshot(
      seat: j['seat']! as int,
      athleteId: j['id']! as String,
      name: j['name']! as String,
    );
  }
}

/// A seat change made during a session (seat racing log).
@immutable
class SeatChange {
  const SeatChange({
    required this.time,
    required this.seat,
    this.fromName,
    this.toName,
    this.distanceMeters,
  });

  final DateTime time;
  final int seat;

  /// Who left / took the seat; null = empty.
  final String? fromName;
  final String? toName;

  /// SpeedCoach distance at the time, if streaming.
  final double? distanceMeters;

  Map<String, Object?> toJson() => {
    't': time.millisecondsSinceEpoch,
    'seat': seat,
    'from': fromName,
    'to': toName,
    'dist': distanceMeters,
  };

  static SeatChange? fromJson(Object? j) {
    if (j is! Map || j['t'] is! int || j['seat'] is! int) return null;
    return SeatChange(
      time: DateTime.fromMillisecondsSinceEpoch(j['t']! as int),
      seat: j['seat']! as int,
      fromName: j['from'] as String?,
      toName: j['to'] as String?,
      distanceMeters: (j['dist'] as num?)?.toDouble(),
    );
  }
}

/// A coach's Mark: app-side only, nothing is sent to the SpeedCoach.
@immutable
class SessionMark {
  const SessionMark({required this.time, this.distanceMeters, this.elapsed});

  final DateTime time;
  final double? distanceMeters;
  final Duration? elapsed;

  Map<String, Object?> toJson() => {
    't': time.millisecondsSinceEpoch,
    'dist': distanceMeters,
    'elapsedMs': elapsed?.inMilliseconds,
  };

  static SessionMark? fromJson(Object? j) {
    if (j is! Map || j['t'] is! int) return null;
    return SessionMark(
      time: DateTime.fromMillisecondsSinceEpoch(j['t']! as int),
      distanceMeters: (j['dist'] as num?)?.toDouble(),
      elapsed: j['elapsedMs'] is int ? Duration(milliseconds: j['elapsedMs']! as int) : null,
    );
  }
}

/// The boat's numbers for the last SpeedCoach piece in a session.
@immutable
class BoatSummary {
  const BoatSummary({
    this.distanceMeters,
    this.elapsed,
    this.averageSplit,
    this.averageRate,
    this.distancePerStroke,
    this.strokes,
    this.splits500 = const [],
    this.serial,
    this.pieceStartedAt,
  });

  final double? distanceMeters;
  final Duration? elapsed;
  final Duration? averageSplit;
  final double? averageRate;
  final double? distancePerStroke;
  final int? strokes;

  /// Time for each completed 500 m, first 500 first.
  final List<Duration> splits500;
  final String? serial;
  final DateTime? pieceStartedAt;

  bool get hasData => (distanceMeters ?? 0) > 0 || (elapsed ?? Duration.zero) > Duration.zero;

  Map<String, Object?> toJson() => {
    'dist': distanceMeters,
    'elapsedMs': elapsed?.inMilliseconds,
    'avgSplitMs': averageSplit?.inMilliseconds,
    'avgRate': averageRate,
    'dps': distancePerStroke,
    'strokes': strokes,
    'splits500': [for (final s in splits500) s.inMilliseconds],
    'serial': serial,
    'pieceStart': pieceStartedAt?.millisecondsSinceEpoch,
  };

  static BoatSummary? fromJson(Object? j) {
    if (j is! Map) return null;
    Duration? ms(Object? v) => v is int ? Duration(milliseconds: v) : null;
    return BoatSummary(
      distanceMeters: (j['dist'] as num?)?.toDouble(),
      elapsed: ms(j['elapsedMs']),
      averageSplit: ms(j['avgSplitMs']),
      averageRate: (j['avgRate'] as num?)?.toDouble(),
      distancePerStroke: (j['dps'] as num?)?.toDouble(),
      strokes: j['strokes'] as int?,
      splits500: [
        if (j['splits500'] is List)
          for (final v in j['splits500'] as List)
            if (v is int) Duration(milliseconds: v),
      ],
      serial: j['serial'] as String?,
      pieceStartedAt: j['pieceStart'] is int
          ? DateTime.fromMillisecondsSinceEpoch(j['pieceStart']! as int)
          : null,
    );
  }
}

/// Crew and boat data recorded alongside a session's heart rates.
@immutable
class SessionExtras {
  const SessionExtras({
    this.lineupName,
    this.boatClass,
    this.seats = const [],
    this.coxName,
    this.seatChanges = const [],
    this.marks = const [],
    this.boat,
  });

  final String? lineupName;

  /// Boat class label, e.g. "8+".
  final String? boatClass;

  /// Seat order when the session started.
  final List<SeatSnapshot> seats;
  final String? coxName;
  final List<SeatChange> seatChanges;
  final List<SessionMark> marks;
  final BoatSummary? boat;

  /// Seat number of [athleteId] at the start of the session.
  int? seatOf(String athleteId) {
    for (final s in seats) {
      if (s.athleteId == athleteId) return s.seat;
    }
    return null;
  }

  SessionExtras copyWith({
    List<SeatSnapshot>? seats,
    List<SeatChange>? seatChanges,
    List<SessionMark>? marks,
    BoatSummary? Function()? boat,
  }) => SessionExtras(
    lineupName: lineupName,
    boatClass: boatClass,
    seats: seats ?? this.seats,
    coxName: coxName,
    seatChanges: seatChanges ?? this.seatChanges,
    marks: marks ?? this.marks,
    boat: boat != null ? boat() : this.boat,
  );

  Map<String, Object?> toJson() => {
    'lineup': lineupName,
    'boatClass': boatClass,
    'seats': [for (final s in seats) s.toJson()],
    'cox': coxName,
    'seatChanges': [for (final c in seatChanges) c.toJson()],
    'marks': [for (final m in marks) m.toJson()],
    'boat': boat?.toJson(),
  };

  factory SessionExtras.fromJson(Object? j) {
    if (j is! Map) return const SessionExtras();
    List<T> list<T>(Object? raw, T? Function(Object?) parse) => [
      if (raw is List)
        for (final e in raw) ?parse(e),
    ];
    return SessionExtras(
      lineupName: j['lineup'] as String?,
      boatClass: j['boatClass'] as String?,
      seats: list(j['seats'], SeatSnapshot.fromJson),
      coxName: j['cox'] as String?,
      seatChanges: list(j['seatChanges'], SeatChange.fromJson),
      marks: list(j['marks'], SessionMark.fromJson),
      boat: BoatSummary.fromJson(j['boat']),
    );
  }
}
