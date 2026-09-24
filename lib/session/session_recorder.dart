import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_event.dart';
import '../models/heart_rate_reading.dart';
import '../models/hr_zones.dart';
import '../models/training_session.dart';
import '../storage/session_repository.dart';

final _log = Logger('Session');

/// An athlete taking part in the running session, as the recorder sees them.
@immutable
class RosterEntry {
  const RosterEntry({
    required this.athleteId,
    required this.athleteName,
    required this.sensorId,
    this.maxHr,
  });

  final String athleteId;
  final String athleteName;
  final String sensorId;
  final int? maxHr;

  @override
  bool operator ==(Object other) =>
      other is RosterEntry &&
      other.athleteId == athleteId &&
      other.athleteName == athleteName &&
      other.sensorId == sensorId &&
      other.maxHr == maxHr;

  @override
  int get hashCode => Object.hash(athleteId, athleteName, sensorId, maxHr);
}

/// Records HR samples and connection events for the active session.
///
/// Samples are buffered in memory and written in one transaction every
/// [flushInterval] (and on stop / when the app is backgrounded), so a
/// multi-hour session with 20 athletes costs one small batched write every
/// few seconds instead of a write per reading.
class SessionRecorder {
  SessionRecorder({
    required SessionRepository repository,
    required Stream<HeartRateReading> readings,
    required Stream<ConnectionEvent> events,
    this.flushInterval = const Duration(seconds: 5),
  }) : _repository = repository {
    _readingSub = readings.listen(_onReading);
    _eventSub = events.listen(_onEvent);
  }

  final SessionRepository _repository;
  final Duration flushInterval;
  static const _uuid = Uuid();

  late final StreamSubscription<HeartRateReading> _readingSub;
  late final StreamSubscription<ConnectionEvent> _eventSub;
  final _activeController = StreamController<TrainingSession?>.broadcast();

  TrainingSession? _active;
  ZoneModel _zones = ZoneModel.standard;

  /// sensorId -> roster entry.
  Map<String, RosterEntry> _bySensor = const {};
  final Set<String> _persistedAthletes = {};

  final List<HeartRateSample> _pendingSamples = [];
  final List<SessionConnectionEvent> _pendingEvents = [];
  Timer? _flushTimer;
  Future<void> _flushChain = Future.value();
  int _recordedSamples = 0;

  TrainingSession? get active => _active;
  Stream<TrainingSession?> get activeChanges => _activeController.stream;
  int get recordedSamples => _recordedSamples;

  Future<TrainingSession> start({
    required List<RosterEntry> roster,
    required ZoneModel zones,
  }) async {
    if (_active != null) return _active!;
    final session = TrainingSession(
      id: _uuid.v4(),
      startedAt: clock.now(),
      zoneLowerBounds: zones.lowerBoundsPercent,
    );
    await _repository.createSession(session);
    _active = session;
    _zones = zones;
    _persistedAthletes.clear();
    _recordedSamples = 0;
    await updateRoster(roster);
    _flushTimer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
    _log.info('Session started with ${roster.length} athletes');
    _activeController.add(session);
    return session;
  }

  /// Updates who is wearing which sensor (e.g. a strap assigned mid-session).
  Future<void> updateRoster(List<RosterEntry> roster) async {
    _bySensor = {for (final r in roster) r.sensorId: r};
    final session = _active;
    if (session == null) return;
    for (final r in roster) {
      await _persistAthlete(session, r);
    }
  }

  Future<TrainingSession?> stop() async {
    final session = _active;
    if (session == null) return null;
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    final ended = session.copyWith(endedAt: () => clock.now());
    await _repository.endSession(session.id, ended.endedAt!);
    _active = null;
    _bySensor = const {};
    _log.info('Session stopped: $_recordedSamples samples');
    _activeController.add(null);
    return ended;
  }

  /// Writes buffered data. Calls are serialised; on failure the data stays
  /// buffered and is retried on the next flush.
  Future<void> flush() {
    _flushChain = _flushChain.then((_) => _flushNow());
    return _flushChain;
  }

  Future<void> _flushNow() async {
    if (_pendingSamples.isEmpty && _pendingEvents.isEmpty) return;
    final samples = List.of(_pendingSamples);
    final events = List.of(_pendingEvents);
    _pendingSamples.clear();
    _pendingEvents.clear();
    try {
      await _repository.writeBatch(samples: samples, events: events);
      _recordedSamples += samples.length;
    } catch (e, st) {
      _log.severe('Failed to write session batch; will retry', e, st);
      _pendingSamples.insertAll(0, samples);
      _pendingEvents.insertAll(0, events);
    }
  }

  Future<void> _persistAthlete(TrainingSession session, RosterEntry r) async {
    if (!_persistedAthletes.add(r.athleteId)) return;
    await _repository.upsertSessionAthlete(
      SessionAthlete(
        sessionId: session.id,
        athleteId: r.athleteId,
        athleteName: r.athleteName,
        sensorId: r.sensorId,
        maxHr: r.maxHr,
      ),
    );
  }

  void _onReading(HeartRateReading reading) {
    final session = _active;
    if (session == null || !reading.isValid) return;
    final athlete = _bySensor[reading.sensorId];
    if (athlete == null) return; // unassigned strap: not part of the session
    final pct = percentOfMax(reading.bpm, athlete.maxHr);
    _pendingSamples.add(
      HeartRateSample(
        sessionId: session.id,
        athleteId: athlete.athleteId,
        sensorId: reading.sensorId,
        timestamp: reading.timestamp,
        bpm: reading.bpm,
        percentOfMax: pct == null ? null : double.parse(pct.toStringAsFixed(1)),
        zone: pct == null ? null : _zones.zoneForPercent(pct),
        rrIntervals1024: reading.measurement.rrIntervals1024,
      ),
    );
  }

  void _onEvent(ConnectionEvent event) {
    final session = _active;
    if (session == null) return;
    const recorded = {
      ConnectionEventType.connected,
      ConnectionEventType.receiving,
      ConnectionEventType.lost,
      ConnectionEventType.dataTimeout,
      ConnectionEventType.userDisconnected,
      ConnectionEventType.failed,
    };
    if (!recorded.contains(event.type)) return;
    _pendingEvents.add(
      SessionConnectionEvent(
        sessionId: session.id,
        sensorId: event.sensorId,
        athleteId: _bySensor[event.sensorId]?.athleteId,
        type: event.type,
        timestamp: event.timestamp,
        detail: event.detail,
      ),
    );
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await flush();
    await _readingSub.cancel();
    await _eventSub.cancel();
    await _activeController.close();
  }
}
