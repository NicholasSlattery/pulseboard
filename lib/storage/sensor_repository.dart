import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../models/known_sensor.dart';
import 'app_database.dart';

/// Remembered sensors and their athlete assignments.
class SensorRepository {
  SensorRepository(this._database);

  final AppDatabase _database;
  final _changes = StreamController<List<KnownSensor>>.broadcast();

  Stream<List<KnownSensor>> get changes => _changes.stream;

  Future<List<KnownSensor>> getAll() async {
    final rows = await _database.db.query('sensors', orderBy: 'created_at ASC');
    return rows.map(KnownSensor.fromRow).toList(growable: false);
  }

  Future<KnownSensor?> getById(String id) async {
    final rows = await _database.db.query('sensors', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : KnownSensor.fromRow(rows.first);
  }

  /// Assigns [sensorId] to [athleteId], remembering the sensor if new.
  ///
  /// Any sensor previously assigned to the athlete is unassigned in the same
  /// transaction, keeping the one-to-one relationship intact.
  Future<void> assign({
    required String sensorId,
    required String athleteId,
    String? sensorName,
  }) async {
    await _database.db.transaction((txn) async {
      await txn.update(
        'sensors',
        {'athlete_id': null},
        where: 'athlete_id = ? AND id != ?',
        whereArgs: [athleteId, sensorId],
      );
      final existing = await txn.query('sensors', where: 'id = ?', whereArgs: [sensorId], limit: 1);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (existing.isEmpty) {
        await txn.insert('sensors', {
          'id': sensorId,
          'name': sensorName,
          'athlete_id': athleteId,
          'last_seen_at': now,
          'created_at': now,
        });
      } else {
        await txn.update(
          'sensors',
          {
            'athlete_id': athleteId,
            if (sensorName != null && sensorName.isNotEmpty) 'name': sensorName,
          },
          where: 'id = ?',
          whereArgs: [sensorId],
        );
      }
    });
    await _emit();
  }

  /// Remembers a sensor without assigning it (no-op if already known).
  Future<void> remember({required String sensorId, String? sensorName}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.db.insert('sensors', {
      'id': sensorId,
      'name': sensorName,
      'last_seen_at': now,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _emit();
  }

  Future<void> unassign(String sensorId) async {
    await _database.db.update(
      'sensors',
      {'athlete_id': null},
      where: 'id = ?',
      whereArgs: [sensorId],
    );
    await _emit();
  }

  /// Forgets the sensor entirely.
  Future<void> forget(String sensorId) async {
    await _database.db.delete('sensors', where: 'id = ?', whereArgs: [sensorId]);
    await _emit();
  }

  /// Updates metadata observed while connected. Does not emit a change event
  /// (called frequently and irrelevant to assignment logic).
  Future<void> updateObserved(
    String sensorId, {
    String? name,
    int? batteryPercent,
    DateTime? seenAt,
  }) async {
    final values = <String, Object?>{
      if (name != null && name.isNotEmpty) 'name': name,
      'battery_percent': ?batteryPercent,
      if (seenAt != null) 'last_seen_at': seenAt.millisecondsSinceEpoch,
    };
    if (values.isEmpty) return;
    await _database.db.update('sensors', values, where: 'id = ?', whereArgs: [sensorId]);
  }

  Future<void> _emit() async {
    if (!_changes.hasListener) return;
    _changes.add(await getAll());
  }

  Future<void> dispose() => _changes.close();
}
