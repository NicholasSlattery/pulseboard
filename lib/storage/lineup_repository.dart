import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../models/lineup.dart';
import 'app_database.dart';

final _log = Logger('Lineups');

/// Stores the [LineupBook] as a JSON blob in the key/value `settings` table.
/// Lineups are small (a few ids per boat), so one row is plenty.
class LineupRepository {
  LineupRepository(this._database);

  final AppDatabase _database;
  static const _key = 'lineups';

  Future<LineupBook> load() async {
    final rows = await _database.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [_key],
      limit: 1,
    );
    if (rows.isEmpty) return LineupBook.empty;
    try {
      return LineupBook.fromJson(jsonDecode(rows.first['value']! as String));
    } on FormatException catch (e) {
      _log.warning('Corrupt lineups, starting empty: $e');
      return LineupBook.empty;
    }
  }

  Future<void> save(LineupBook book) async {
    await _database.db.insert('settings', {
      'key': _key,
      'value': jsonEncode(book.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
