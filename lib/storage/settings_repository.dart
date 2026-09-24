import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../models/app_settings.dart';
import 'app_database.dart';

final _log = Logger('Settings');

/// Stores [AppSettings] as a JSON blob in the key/value `settings` table.
class SettingsRepository {
  SettingsRepository(this._database);

  final AppDatabase _database;
  static const _key = 'app_settings';

  Future<AppSettings> load() async {
    final rows = await _database.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [_key],
      limit: 1,
    );
    if (rows.isEmpty) return const AppSettings();
    try {
      final decoded = jsonDecode(rows.first['value']! as String);
      if (decoded is Map<String, Object?>) return AppSettings.fromJson(decoded);
    } on FormatException catch (e) {
      _log.warning('Corrupt settings, using defaults: $e');
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    await _database.db.insert('settings', {
      'key': _key,
      'value': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
