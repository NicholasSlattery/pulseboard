import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/app_settings.dart';
import 'package:pulseboard/models/hr_zones.dart';
import 'package:pulseboard/models/training_session.dart';
import 'package:pulseboard/storage/app_database.dart';
import 'package:pulseboard/storage/athlete_repository.dart';
import 'package:pulseboard/storage/sensor_repository.dart';
import 'package:pulseboard/storage/session_repository.dart';
import 'package:pulseboard/storage/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase database;
  late AthleteRepository athletes;
  late SensorRepository sensors;
  late SessionRepository sessions;

  setUp(() async {
    database = await AppDatabase.open(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    athletes = AthleteRepository(database);
    sensors = SensorRepository(database);
    sessions = SessionRepository(database);
  });

  tearDown(() => database.close());

  group('athletes', () {
    test('create, update, list sorted by name, delete', () async {
      final b = await athletes.create(name: '  Bea  ', age: 20);
      await athletes.create(name: 'adam', maxHrOverride: 190, nickname: ' ');
      final all = await athletes.getAll();
      expect(all.map((a) => a.name), ['adam', 'Bea']);
      expect(all.first.nickname, isNull, reason: 'blank nickname stored as null');

      await athletes.update(b.copyWith(maxHrOverride: () => 199));
      expect((await athletes.getById(b.id))!.maxHrOverride, 199);

      await athletes.delete(b.id);
      expect((await athletes.getAll()).length, 1);
    });
  });

  group('sensor assignments', () {
    test('assignment survives reopening (persisted)', () async {
      final a = await athletes.create(name: 'Nicholas', maxHrOverride: 195);
      await sensors.assign(sensorId: 'H10-ABC', athleteId: a.id, sensorName: 'Polar H10 ABC123');
      final s = await sensors.getById('H10-ABC');
      expect(s!.athleteId, a.id);
      expect(s.name, 'Polar H10 ABC123');
    });

    test('assigning a new sensor moves the athlete off the old one', () async {
      final a = await athletes.create(name: 'A');
      await sensors.assign(sensorId: 'S1', athleteId: a.id);
      await sensors.assign(sensorId: 'S2', athleteId: a.id);
      expect((await sensors.getById('S1'))!.athleteId, isNull);
      expect((await sensors.getById('S2'))!.athleteId, a.id);
    });

    test('reassigning a sensor to a different athlete', () async {
      final a = await athletes.create(name: 'A');
      final b = await athletes.create(name: 'B');
      await sensors.assign(sensorId: 'S1', athleteId: a.id);
      await sensors.assign(sensorId: 'S1', athleteId: b.id);
      expect((await sensors.getById('S1'))!.athleteId, b.id);
    });

    test('deleting an athlete keeps the sensor but unassigns it', () async {
      final a = await athletes.create(name: 'A');
      await sensors.assign(sensorId: 'S1', athleteId: a.id);
      await athletes.delete(a.id);
      final s = await sensors.getById('S1');
      expect(s, isNotNull);
      expect(s!.athleteId, isNull);
    });

    test('forget removes the sensor', () async {
      await sensors.remember(sensorId: 'S9', sensorName: 'x');
      await sensors.remember(sensorId: 'S9', sensorName: 'y'); // no-op
      expect((await sensors.getById('S9'))!.name, 'x');
      await sensors.forget('S9');
      expect(await sensors.getById('S9'), isNull);
    });
  });

  group('sessions', () {
    test('batch write, read back, stream pages and cascade delete', () async {
      final session = TrainingSession(id: 's1', startedAt: DateTime(2026, 1, 1, 6));
      await sessions.createSession(session);
      await sessions.upsertSessionAthlete(
        const SessionAthlete(sessionId: 's1', athleteId: 'a', athleteName: 'A', maxHr: 190),
      );
      final samples = [
        for (var i = 0; i < 12000; i++)
          HeartRateSample(
            sessionId: 's1',
            athleteId: 'a',
            sensorId: 'S1',
            timestamp: DateTime(2026, 1, 1, 6).add(Duration(seconds: i)),
            bpm: 100 + i % 80,
            percentOfMax: 50,
            zone: 1,
            rrIntervals1024: i.isEven ? const [800, 810] : const [],
          ),
      ];
      await sessions.writeBatch(samples: samples, events: const []);

      final forAthlete = await sessions.getSamplesForAthlete('s1', 'a');
      expect(forAthlete.length, 12000);
      expect(forAthlete.first.rrIntervals1024, [800, 810]);
      expect(forAthlete[1].rrIntervals1024, isEmpty);

      var streamed = 0;
      var pages = 0;
      await for (final page in sessions.streamSamples('s1', pageSize: 5000)) {
        streamed += page.length;
        pages++;
      }
      expect(streamed, 12000);
      expect(pages, 3);

      final list = await sessions.listSessions();
      expect(list.single.sampleCount, 12000);
      expect(list.single.athleteCount, 1);

      await sessions.deleteSession('s1');
      expect(await sessions.getSamplesForAthlete('s1', 'a'), isEmpty);
    });

    test('unfinished sessions are recovered using the last sample time', () async {
      final start = DateTime(2026, 1, 1, 6);
      await sessions.createSession(TrainingSession(id: 'crash', startedAt: start));
      await sessions.writeBatch(
        samples: [
          HeartRateSample(
            sessionId: 'crash',
            athleteId: 'a',
            sensorId: 'S',
            timestamp: start.add(const Duration(minutes: 42)),
            bpm: 150,
          ),
        ],
        events: const [],
      );
      expect(await sessions.recoverUnfinishedSessions(), 1);
      final s = await sessions.getSession('crash');
      expect(s!.endedAt, start.add(const Duration(minutes: 42)));
      expect(s.recovered, isTrue);
    });
  });

  group('settings', () {
    test('round-trips and tolerates corrupt values', () async {
      final repo = SettingsRepository(database);
      expect(await repo.load(), const AppSettings());
      const custom = AppSettings(
        zoneModel: ZoneModel([55, 65, 75, 85, 92]),
        maxHrFormula: MaxHrFormula.tanaka,
        staleAfter: Duration(seconds: 8),
        keepAwake: KeepAwakeMode.always,
      );
      await repo.save(custom);
      expect(await repo.load(), custom);

      final decoded = AppSettings.fromJson({
        'zoneLowerBounds': [90, 10],
        'maxHrFormula': 'nonsense',
        'staleAfterMs': -5,
      });
      expect(decoded.zoneModel, ZoneModel.standard);
      expect(decoded.maxHrFormula, MaxHrFormula.fox);
      expect(decoded.staleAfter, const Duration(seconds: 5));
    });
  });
}
