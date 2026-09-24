import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/connection_event.dart';
import 'package:pulseboard/models/heart_rate_measurement.dart';
import 'package:pulseboard/models/heart_rate_reading.dart';
import 'package:pulseboard/models/hr_zones.dart';
import 'package:pulseboard/session/csv_exporter.dart';
import 'package:pulseboard/session/session_recorder.dart';
import 'package:pulseboard/storage/app_database.dart';
import 'package:pulseboard/storage/session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase database;
  late SessionRepository repo;
  late StreamController<HeartRateReading> readings;
  late StreamController<ConnectionEvent> events;
  late SessionRecorder recorder;

  setUp(() async {
    database = await AppDatabase.open(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    repo = SessionRepository(database);
    readings = StreamController<HeartRateReading>.broadcast(sync: true);
    events = StreamController<ConnectionEvent>.broadcast(sync: true);
    recorder = SessionRecorder(
      repository: repo,
      readings: readings.stream,
      events: events.stream,
      flushInterval: const Duration(hours: 1), // flush manually in tests
    );
  });

  tearDown(() async {
    await recorder.dispose();
    await readings.close();
    await events.close();
    await database.close();
  });

  HeartRateReading reading(String sensor, DateTime t, int bpm, {List<int> rr = const []}) =>
      HeartRateReading(
        sensorId: sensor,
        timestamp: t,
        measurement: HeartRateMeasurement(
          bpm: bpm,
          contact: SensorContact.detected,
          is16BitValue: false,
          rrIntervals1024: rr,
        ),
      );

  test('records samples for rostered athletes only, with zone and percent', () async {
    final session = await recorder.start(
      roster: const [
        RosterEntry(athleteId: 'a', athleteName: 'Nicholas', sensorId: 'S1', maxHr: 200),
        RosterEntry(athleteId: 'b', athleteName: 'No Max', sensorId: 'S2'),
      ],
      zones: ZoneModel.standard,
    );
    final t0 = session.startedAt;
    readings.add(reading('S1', t0.add(const Duration(seconds: 1)), 170, rr: [700]));
    readings.add(reading('S2', t0.add(const Duration(seconds: 1)), 120));
    readings.add(reading('UNASSIGNED', t0.add(const Duration(seconds: 1)), 99));
    events.add(ConnectionEvent(sensorId: 'S1', type: ConnectionEventType.lost, timestamp: t0));
    events.add(
      ConnectionEvent(sensorId: 'S1', type: ConnectionEventType.reconnectAttempt, timestamp: t0),
    );

    await recorder.flush();
    final a = await repo.getSamplesForAthlete(session.id, 'a');
    expect(a.single.bpm, 170);
    expect(a.single.percentOfMax, 85.0);
    expect(a.single.zone, 4);
    expect(a.single.rrIntervals1024, [700]);

    final b = await repo.getSamplesForAthlete(session.id, 'b');
    expect(b.single.zone, isNull);
    expect(b.single.percentOfMax, isNull);

    final evs = await repo.getEvents(session.id);
    expect(evs.single.type, ConnectionEventType.lost, reason: 'attempts are not recorded');
    expect(evs.single.athleteId, 'a');

    final ended = await recorder.stop();
    expect(ended!.endedAt, isNotNull);
    expect(recorder.active, isNull);
    expect((await repo.getSessionAthletes(session.id)).length, 2);
  });

  test('ignores readings when no session is active', () async {
    readings.add(reading('S1', DateTime.now(), 150));
    final session = await recorder.start(roster: const [], zones: ZoneModel.standard);
    await recorder.stop();
    expect(await repo.getSamplesForAthlete(session.id, 'a'), isEmpty);
  });

  test('CSV export has header, escaping and expected values', () async {
    final session = await recorder.start(
      roster: const [
        RosterEntry(athleteId: 'a', athleteName: 'Smith, "Nick"', sensorId: 'S1', maxHr: 200),
      ],
      zones: ZoneModel.standard,
    );
    readings.add(
      reading(
        'S1',
        session.startedAt.add(const Duration(milliseconds: 1500)),
        150,
        rr: [1024, 512],
      ),
    );
    await recorder.stop();

    final dir = await Directory.systemTemp.createTemp('pulseboard_test');
    try {
      final file = await CsvExporter(repo).exportSession(session.id, dir);
      final lines = (await file.readAsString()).split('\r\n');
      expect(lines[0], CsvExporter.header.join(','));
      final row = lines[1];
      expect(row, contains(',1.500,'));
      expect(row, contains('"Smith, ""Nick"""'));
      expect(row, contains(',150,75.0,3,1000.0 500.0'));
      expect(lines.length, 3); // header, row, trailing empty
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('CSV escaping guards against formula injection', () {
    expect(CsvExporter.escape('=SUM(A1)'), "'=SUM(A1)");
    expect(CsvExporter.escape('-12.5'), '-12.5');
    expect(CsvExporter.escape('plain'), 'plain');
    expect(CsvExporter.escape('a\nb'), '"a\nb"');
  });
}
