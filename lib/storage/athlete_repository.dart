import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/athlete.dart';
import '../utils/formatters.dart';
import 'app_database.dart';

/// CRUD for athletes. Emits the full list on every change (the list is small,
/// tens of rows at most).
class AthleteRepository {
  AthleteRepository(this._database);

  final AppDatabase _database;
  final _changes = StreamController<List<Athlete>>.broadcast();
  static const _uuid = Uuid();

  Stream<List<Athlete>> get changes => _changes.stream;

  Future<List<Athlete>> getAll() async {
    final rows = await _database.db.query('athletes');
    return rows.map(Athlete.fromRow).toList()..sort((a, b) => naturalCompare(a.name, b.name));
  }

  Future<Athlete?> getById(String id) async {
    final rows = await _database.db.query('athletes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Athlete.fromRow(rows.first);
  }

  Future<Athlete> create({
    required String name,
    String? nickname,
    int? age,
    int? maxHrOverride,
    String? notes,
  }) async {
    final now = DateTime.now();
    final athlete = Athlete(
      id: _uuid.v4(),
      name: name.trim(),
      nickname: _blankToNull(nickname),
      age: age,
      maxHrOverride: maxHrOverride,
      notes: _blankToNull(notes),
      createdAt: now,
      updatedAt: now,
    );
    await _database.db.insert('athletes', athlete.toRow());
    await _emit();
    return athlete;
  }

  Future<void> update(Athlete athlete) async {
    final updated = athlete.copyWith(updatedAt: DateTime.now());
    await _database.db.update(
      'athletes',
      updated.toRow(),
      where: 'id = ?',
      whereArgs: [athlete.id],
    );
    await _emit();
  }

  /// Deletes the athlete. Their sensor (if any) stays remembered but becomes
  /// unassigned (ON DELETE SET NULL). Past sessions keep their snapshot.
  Future<void> delete(String id) async {
    await _database.db.delete('athletes', where: 'id = ?', whereArgs: [id]);
    await _emit();
  }

  Future<void> _emit() async {
    if (!_changes.hasListener) return;
    _changes.add(await getAll());
  }

  static String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<void> dispose() => _changes.close();
}
