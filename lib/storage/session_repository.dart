import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../models/session_extras.dart';
import '../models/training_session.dart';
import 'app_database.dart';

final _log = Logger('SessionRepo');

/// A session plus lightweight aggregate info for history lists.
class SessionListItem {
  const SessionListItem({
    required this.session,
    required this.athleteCount,
    required this.sampleCount,
  });

  final TrainingSession session;
  final int athleteCount;
  final int sampleCount;
}

/// Persistence for sessions, their athletes, HR samples and connection
/// events. Samples are written in batches by the recorder, never one row per
/// transaction.
class SessionRepository {
  SessionRepository(this._database);

  final AppDatabase _database;
  final _changes = StreamController<void>.broadcast();

  /// Fires when the list of sessions changes (created, ended, deleted).
  Stream<void> get changes => _changes.stream;

  Database get _db => _database.db;

  Future<void> createSession(TrainingSession session) async {
    await _db.insert('sessions', session.toRow());
    _changes.add(null);
  }

  Future<void> endSession(String sessionId, DateTime endedAt, {bool recovered = false}) async {
    await _db.update(
      'sessions',
      {'ended_at': endedAt.millisecondsSinceEpoch, 'recovered': recovered ? 1 : 0},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    _changes.add(null);
  }

  Future<void> renameSession(String sessionId, String? name) async {
    await _db.update(
      'sessions',
      {'name': (name == null || name.trim().isEmpty) ? null : name.trim()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    _changes.add(null);
  }

  Future<void> upsertSessionAthlete(SessionAthlete athlete) async {
    await _db.insert(
      'session_athletes',
      athlete.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Writes a batch of samples and events in one transaction.
  Future<void> writeBatch({
    required List<HeartRateSample> samples,
    required List<SessionConnectionEvent> events,
  }) async {
    if (samples.isEmpty && events.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final s in samples) {
        batch.insert('hr_samples', s.toRow());
      }
      for (final e in events) {
        batch.insert('connection_events', e.toRow());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<TrainingSession?> getSession(String id) async {
    final rows = await _db.query('sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : TrainingSession.fromRow(rows.first);
  }

  Future<List<SessionListItem>> listSessions() async {
    final rows = await _db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM session_athletes a WHERE a.session_id = s.id) AS athlete_count,
        (SELECT COUNT(*) FROM hr_samples h WHERE h.session_id = s.id) AS sample_count
      FROM sessions s
      ORDER BY s.started_at DESC
    ''');
    return rows
        .map(
          (r) => SessionListItem(
            session: TrainingSession.fromRow(r),
            athleteCount: r['athlete_count']! as int,
            sampleCount: r['sample_count']! as int,
          ),
        )
        .toList(growable: false);
  }

  Future<List<SessionAthlete>> getSessionAthletes(String sessionId) async {
    final rows = await _db.query(
      'session_athletes',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'athlete_name COLLATE NOCASE ASC',
    );
    return rows.map(SessionAthlete.fromRow).toList(growable: false);
  }

  /// All samples for one athlete in time order.
  Future<List<HeartRateSample>> getSamplesForAthlete(String sessionId, String athleteId) async {
    final rows = await _db.query(
      'hr_samples',
      where: 'session_id = ? AND athlete_id = ?',
      whereArgs: [sessionId, athleteId],
      orderBy: 't ASC',
    );
    return rows.map(HeartRateSample.fromRow).toList(growable: false);
  }

  /// Pages through every sample of a session in insertion (= chronological)
  /// order without loading the whole session into memory.
  Stream<List<HeartRateSample>> streamSamples(String sessionId, {int pageSize = 5000}) async* {
    var lastRowId = 0;
    while (true) {
      final rows = await _db.rawQuery(
        'SELECT rowid AS rid, * FROM hr_samples WHERE session_id = ? AND rowid > ? '
        'ORDER BY rowid ASC LIMIT ?',
        [sessionId, lastRowId, pageSize],
      );
      if (rows.isEmpty) return;
      lastRowId = rows.last['rid']! as int;
      yield rows.map(HeartRateSample.fromRow).toList(growable: false);
      if (rows.length < pageSize) return;
    }
  }

  Future<List<SessionConnectionEvent>> getEvents(String sessionId) async {
    final rows = await _db.query(
      'connection_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 't ASC, id ASC',
    );
    return rows.map(SessionConnectionEvent.fromRow).toList(growable: false);
  }

  /// Crew and boat data recorded with a session (empty if none).
  Future<SessionExtras> getExtras(String sessionId) async {
    final rows = await _db.query(
      'session_extras',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return const SessionExtras();
    try {
      return SessionExtras.fromJson(jsonDecode(rows.first['data']! as String));
    } on FormatException catch (e) {
      _log.warning('Corrupt session extras for $sessionId: $e');
      return const SessionExtras();
    }
  }

  Future<void> saveExtras(String sessionId, SessionExtras extras) async {
    await _db.insert('session_extras', {
      'session_id': sessionId,
      'data': jsonEncode(extras.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSession(String sessionId) async {
    await _db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    _changes.add(null);
  }

  /// Closes sessions left open by an app crash/kill, using the last sample
  /// (or the start time) as the end time. Returns how many were recovered.
  Future<int> recoverUnfinishedSessions() async {
    final open = await _db.query('sessions', where: 'ended_at IS NULL');
    for (final row in open) {
      final session = TrainingSession.fromRow(row);
      final last = await _db.rawQuery('SELECT MAX(t) AS t FROM hr_samples WHERE session_id = ?', [
        session.id,
      ]);
      final lastT = last.first['t'] as int?;
      final end = lastT == null ? session.startedAt : DateTime.fromMillisecondsSinceEpoch(lastT);
      await endSession(session.id, end, recovered: true);
      _log.warning('Recovered unfinished session ${session.id}');
    }
    return open.length;
  }

  Future<void> dispose() => _changes.close();
}
