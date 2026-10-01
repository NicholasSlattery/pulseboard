import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/app_settings.dart';
import 'package:pulseboard/models/athlete.dart';
import 'package:pulseboard/models/lineup.dart';

import '../support/fake_ble_adapter.dart';
import '../support/test_app.dart';

/// Eight rowers named stroke to bow, seated 8..1.
const crewNames = [
  'Marcus T.',
  'Owen L.',
  'Diego R.',
  'Sam K.',
  'Jonah W.',
  'Chris P.',
  'Eli B.',
  'Ryan D.',
];

LineupBook eightLineup(List<Athlete> athletes) {
  final byName = {for (final a in athletes) a.name: a.id};
  final seats = [for (var seat = 1; seat <= 8; seat++) byName[crewNames[8 - seat]]];
  return LineupBook(
    lineups: [Lineup(id: 'A', name: 'Lineup A', boatClass: BoatClass.eight, seats: seats)],
    activeId: 'A',
  );
}

Future<void> holdToStop(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text('Hold to stop')));
  await pumpFor(tester, const Duration(milliseconds: 1200));
  await gesture.up();
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await pumpFor(tester, const Duration(seconds: 1));
}

Future<void> startSession(WidgetTester tester) async {
  await tester.tap(find.text('Start session'));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadRealFonts);

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('first launch explains Bluetooth before initialising it', (tester) async {
    await setSize(tester, const Size(390, 844));
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(tester, adapter, settings: const AppSettings());
    await tester.pumpWidget(testApp(bootstrap));
    await tester.pump();

    expect(find.text('Welcome to PulseBoard'), findsOneWidget);
    await screenshot(tester, '01_intro_phone');

    await tester.tap(find.text('Continue'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(find.text('No lineup yet'), findsOneWidget);
    expect(find.text('Start session'), findsOneWidget);
    await screenshot(tester, '02_live_ready_empty_phone');
    await disposeApp(tester, bootstrap);
  });

  testWidgets('crew screen shows every seat in order and never presents stale data as live', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await setSize(tester, const Size(390, 844));
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(
      tester,
      adapter,
      seed: (athletes, sensors) async {
        for (var i = 0; i < crewNames.length; i++) {
          final a = await athletes.create(name: crewNames[i], maxHrOverride: 195);
          await sensors.assign(sensorId: 'S$i', athleteId: a.id, sensorName: 'Polar H10 $i');
        }
      },
      lineups: eightLineup,
    );
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(adapter.subscribeCalls.toSet().length, 8);

    final bpms = [176, 181, 172, 168, 184, 163, 159, 171];
    for (var i = 0; i < 8; i++) {
      adapter.pushPacket('S$i', [0x16, bpms[i], 0x00, 0x03]);
    }
    await pumpFor(tester, const Duration(milliseconds: 300));

    // Ready check before Start.
    expect(find.text('8+ · Lineup A'), findsOneWidget);
    expect(find.text('8 of 8 straps live'), findsOneWidget);
    await screenshot(tester, '03_live_ready_check');

    await startSession(tester);
    for (var i = 0; i < 8; i++) {
      adapter.pushPacket('S$i', [0x16, bpms[i], 0x00, 0x03]);
    }
    await pumpFor(tester, const Duration(milliseconds: 300));

    // Full-screen crew view: no nav bar, seats stroke first.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('SpeedCoach not connected'), findsOneWidget);
    expect(find.text('HR 8/8 LIVE'), findsOneWidget);
    expect(find.text('Marcus T.'), findsOneWidget);
    expect(find.text('STROKE'), findsOneWidget);
    expect(find.text('BOW'), findsOneWidget);
    expect(find.text('176'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget); // 176 / 195
    expect(find.text('Z5'), findsWidgets);
    final strokeY = tester.getCenter(find.text('Marcus T.')).dy;
    final bowY = tester.getCenter(find.text('Ryan D.')).dy;
    expect(strokeY, lessThan(bowY));
    await screenshot(tester, '04_crew_live_portrait');

    // Bow's strap drops: no BPM, reconnecting.
    adapter.linkDown('S7');
    for (var i = 0; i < 7; i++) {
      adapter.pushPacket('S$i', [0x16, bpms[i] + 1, 0x00, 0x03]);
    }
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('171'), findsNothing);
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(find.text('HR 7/8 LIVE'), findsOneWidget);

    // Everyone else goes quiet: weak signal (dimmed), then no signal ("--").
    await pumpFor(tester, const Duration(seconds: 6), step: const Duration(milliseconds: 500));
    expect(find.text('WEAK SIGNAL'), findsWidgets);
    await screenshot(tester, '05_crew_live_weak_signal');
    await pumpFor(tester, const Duration(seconds: 10), step: const Duration(milliseconds: 500));
    expect(find.text('NO SIGNAL'), findsWidgets);
    expect(find.text('177'), findsNothing);

    // Landscape: one card per seat.
    await setSize(tester, const Size(844, 390));
    for (var i = 0; i < 7; i++) {
      adapter.pushPacket('S$i', [0x16, bpms[i], 0x00, 0x03]);
    }
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('176'), findsOneWidget);
    await screenshot(tester, '06_crew_live_landscape');
    await setSize(tester, const Size(390, 844));
    await pumpFor(tester, const Duration(milliseconds: 300));

    // Swap seats mid-session: Sam K. (5) <-> Chris P. (3).
    await tester.tap(find.text('Seats'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Seat 5, Sam K\.$')));
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text('Move Sam K.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Seat 3, Chris P\.$')));
    await pumpFor(tester, const Duration(milliseconds: 200));
    await screenshot(tester, '07_crew_swap_seats');
    await tester.tap(find.text('Swap seats'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Move Sam K.'), findsNothing);
    final samY = tester.getCenter(find.text('Sam K.')).dy;
    final chrisY = tester.getCenter(find.text('Chris P.')).dy;
    expect(samY, greaterThan(chrisY)); // Sam now in seat 3, below Chris in 5

    await holdToStop(tester);
    expect(find.text('Session summary'), findsOneWidget);
    expect(find.text('Crew heart rate by seat'), findsOneWidget);
    expect(find.text('Seat changes and marks'), findsOneWidget);
    await screenshot(tester, '08_session_summary_crew');
    semantics.dispose();

    await disposeApp(tester, bootstrap);
  });

  testWidgets('without a lineup the crew screen lists every strap, and stop needs a hold', (
    tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(
      tester,
      adapter,
      seed: (athletes, sensors) async {
        for (var i = 0; i < 6; i++) {
          final a = await athletes.create(name: 'Rower ${i + 1}', age: 18 + i);
          await sensors.assign(sensorId: 'R$i', athleteId: a.id);
        }
      },
    );
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.textContaining('6 rowers with straps'), findsOneWidget);

    await startSession(tester);
    for (var t = 0; t < 3; t++) {
      for (var i = 0; i < 6; i++) {
        adapter.pushHr('R$i', 130 + i * 4 + t);
      }
      await pumpFor(tester, const Duration(seconds: 1), step: const Duration(milliseconds: 250));
    }
    expect(find.text('HEART RATE · BPM'), findsOneWidget);
    expect(find.text('Rower 1'), findsOneWidget);
    expect(find.textContaining('REC 0:0'), findsOneWidget);

    // A quick tap does not stop the session.
    await tester.tap(find.text('Hold to stop'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Hold for 1 second to stop'), findsOneWidget);
    expect(find.text('Session summary'), findsNothing);
    await pumpFor(tester, const Duration(seconds: 2)); // hint snackbar goes away

    await holdToStop(tester);
    expect(find.text('Session summary'), findsOneWidget);
    expect(find.text('Rower 1'), findsOneWidget);
    expect(find.text('AVG'), findsWidgets);

    await disposeApp(tester, bootstrap);
  });

  testWidgets('lineup tab: create a lineup, seat rowers from the bench and save', (tester) async {
    await setSize(tester, const Size(390, 844));
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(
      tester,
      adapter,
      seed: (athletes, sensors) async {
        for (final n in ['Ava', 'Ben', 'Chloe', 'Dan', 'Eve']) {
          await athletes.create(name: n);
        }
      },
    );
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.text('Lineup'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Create lineup'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.text('4+'));
    await pumpFor(tester, const Duration(milliseconds: 200));
    for (final n in ['Ava', 'Ben', 'Chloe', 'Dan']) {
      await tester.scrollUntilVisible(find.widgetWithText(ActionChip, n), 200);
      await tester.tap(find.widgetWithText(ActionChip, n));
      await pumpFor(tester, const Duration(milliseconds: 150));
    }
    await tester.scrollUntilVisible(find.widgetWithText(ActionChip, 'Eve'), 200);
    await tester.tap(find.widgetWithText(ActionChip, 'Eve')); // fills the cox seat
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text('Save lineup'), findsOneWidget);
    expect(find.text('Everyone is in the boat.'), findsOneWidget);

    await tester.tap(find.text('Save lineup'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Saved'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ava'), -200);
    await screenshot(tester, '09_lineup_phone');

    await tester.tap(find.text('Live'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('4+ · Lineup A'), findsOneWidget);
    expect(find.text('0 of 4 straps live'), findsOneWidget);

    await disposeApp(tester, bootstrap);
  });

  testWidgets('sensors screen scans, lists HR straps and assigns an athlete', (tester) async {
    await setSize(tester, const Size(390, 844));
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(
      tester,
      adapter,
      seed: (athletes, sensors) async {
        await athletes.create(name: 'Nicholas', maxHrOverride: 195);
      },
    );
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.text('Sensors'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Scan'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(adapter.scanning, isTrue);

    adapter.advertise('H10-ABC123', name: 'Polar H10 ABC123', rssi: -55);
    adapter.advertise('TICKR-1', name: 'TICKR 8F21', rssi: -78);
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Polar H10 ABC123'), findsOneWidget);
    expect(find.text('TICKR 8F21'), findsOneWidget);
    await screenshot(tester, '10_sensors_scan_phone');

    await tester.tap(find.text('Polar H10 ABC123'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Assign athlete'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Nicholas').last);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(adapter.connectCalls, contains('H10-ABC123'));
    expect(find.text('Nicholas'), findsWidgets);
    expect(find.text('ASSIGNED (1)'), findsOneWidget);

    await disposeApp(tester, bootstrap);
  });
}
