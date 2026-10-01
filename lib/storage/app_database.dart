import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

import '../app/app_info.dart';

final _log = Logger('Database');

/// Owns the SQLite connection and schema.
///
/// Uses the sqflite FFI factory on every platform (iOS, Windows, tests) so
/// there is exactly one database code path. Queries run on a background
/// isolate, so large inserts never block the UI thread.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 2;

  /// Opens (creating if needed) the on-device database file in the app's
  /// private Application Support directory.
  static Future<AppDatabase> openDefault() async {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, AppInfo.databaseFileName);
    _log.info('Opening database');
    return open(path);
  }

  /// Opens a database at [path]. Pass `inMemoryDatabasePath` in tests.
  static Future<AppDatabase> open(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactoryFfi;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: _migrate,
        // Each test gets its own fresh in-memory DB.
        singleInstance: path != inMemoryDatabasePath,
      ),
    );
    // WAL: readers don't block the writer and writes are cheaper. Not
    // supported for in-memory databases (returns 'memory'), which is fine.
    await db.rawQuery('PRAGMA journal_mode = WAL');
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE athletes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        nickname TEXT,
        age INTEGER,
        max_hr INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    // One sensor per athlete, one athlete per sensor. Deleting an athlete
    // leaves the sensor remembered but unassigned.
    batch.execute('''
      CREATE TABLE sensors (
        id TEXT PRIMARY KEY,
        name TEXT,
        athlete_id TEXT UNIQUE REFERENCES athletes(id) ON DELETE SET NULL,
        last_seen_at INTEGER,
        battery_percent INTEGER,
        created_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        name TEXT,
        zone_bounds TEXT NOT NULL DEFAULT '',
        recovered INTEGER NOT NULL DEFAULT 0
      )''');
    // Snapshot of athletes in a session: intentionally no FK to athletes so
    // history survives athlete deletion.
    batch.execute('''
      CREATE TABLE session_athletes (
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        athlete_id TEXT NOT NULL,
        athlete_name TEXT NOT NULL,
        sensor_id TEXT,
        max_hr INTEGER,
        PRIMARY KEY (session_id, athlete_id)
      )''');
    batch.execute('''
      CREATE TABLE hr_samples (
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        athlete_id TEXT NOT NULL,
        sensor_id TEXT NOT NULL,
        t INTEGER NOT NULL,
        bpm INTEGER NOT NULL,
        pct REAL,
        zone INTEGER,
        rr TEXT
      )''');
    batch.execute('CREATE INDEX idx_hr_samples_session ON hr_samples(session_id, athlete_id, t)');
    batch.execute('''
      CREATE TABLE connection_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        sensor_id TEXT NOT NULL,
        athlete_id TEXT,
        type TEXT NOT NULL,
        t INTEGER NOT NULL,
        detail TEXT
      )''');
    batch.execute('CREATE INDEX idx_connection_events_session ON connection_events(session_id, t)');
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
    _createSessionExtras(batch);
    await batch.commit(noResult: true);
    _log.info('Schema v$schemaVersion created');
  }

  /// v2: crew and boat data per session (lineup snapshot, seat changes,
  /// marks, SpeedCoach summary) as one JSON blob.
  static void _createSessionExtras(Batch batch) {
    batch.execute('''
      CREATE TABLE session_extras (
        session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
        data TEXT NOT NULL
      )''');
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    _log.info('Migrating schema $from -> $to');
    final batch = db.batch();
    if (from < 2) _createSessionExtras(batch);
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();
}
