import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/app_settings.dart';
import 'package:pulseboard/providers/settings_provider.dart';

import '../support/fake_ble_adapter.dart';
import '../support/fake_peripheral.dart';
import '../support/test_app.dart';

List<int> u32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

/// Live status (...0103): position, distance (cm), elapsed (ms).
List<int> statusPacket(int ms, {int distanceCm = 0}) => [
  0xee, 0xaa, 0xf5, 0x17, 0xbb, 0xda, 0x1d, 0xcb, ...u32(distanceCm), 0, 0, 0, 0, ...u32(ms), //
];

/// Stroke (...0203): rate x2, speed cm/s, distance/stroke cm, avg speed cm/s, count.
List<int> strokePacket(
  int count, {
  int rate2 = 60,
  int speed = 250,
  int dps = 120,
  int avg = 200,
}) => [
  rate2, 0xFF, speed & 0xFF, speed >> 8, 0, 0, dps & 0xFF, dps >> 8, 0, 0, avg & 0xFF, avg >> 8, //
  0, 0, count, 0, 0, 0, 0, 0,
];

void main() {
  setUpAll(loadRealFonts);

  testWidgets('SpeedCoach: pair from Settings, then crew, boat data and simple views', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final peripheral = FakePeripheral();
    final bootstrap = await buildTestBootstrap(
      tester,
      FakeBleAdapter(),
      peripheral: peripheral,
      settings: const AppSettings(bluetoothIntroSeen: true, targetSplit: Duration(seconds: 200)),
    );
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.text('Settings'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text('Pairing, boat name and raw packets (experimental)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pairing, boat name and raw packets (experimental)'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Connect in three steps'), findsOneWidget);
    await screenshot(tester, '11_speedcoach_setup');

    await tester.scrollUntilVisible(
      find.text('Start'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(peripheral.advertisedName, 'NK LiNKp');
    expect(find.text('Waiting for SpeedCoach'), findsOneWidget);
    expect(find.text('NK LiNKp (pairing)'), findsOneWidget);
    await screenshot(tester, '12_speedcoach_waiting');

    // The SpeedCoach connects, identifies itself and starts rowing at 30 spm.
    peripheral.write('1005', '2226780'.codeUnits);
    for (var i = 0; i < 6; i++) {
      peripheral.write('0203', strokePacket(40 + i));
      peripheral.write('0103', statusPacket(90000 + i * 2000, distanceCm: 30000 + i * 500));
      await pumpFor(tester, const Duration(seconds: 2), step: const Duration(milliseconds: 500));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await pumpFor(tester, const Duration(milliseconds: 200));

    expect(find.text('Receiving data'), findsOneWidget);
    expect(find.text('Paired SpeedCoach 2226780'), findsOneWidget);
    expect(find.text('30'), findsOneWidget); // SpeedCoach rate
    expect(find.text('3:20.0'), findsOneWidget); // split for 250 cm/s
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(settingsProvider).speedCoachSerial, '2226780');

    // Back on Live, the ready check shows the SpeedCoach; start a session.
    await tester.pageBack();
    await pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.text('Live'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('SpeedCoach 2226780'), findsOneWidget);
    await tester.tap(find.text('Start session'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Row on: a realistic piece at 28.5 spm, 1:58.5, crossing 500 m.
    var distance = 30250;
    var ms = 100000;
    for (var i = 0; i < 14; i++) {
      final speed = 422 + (i % 3) - 1;
      distance += speed * 2;
      ms += 2000;
      peripheral.write('0203', strokePacket(46 + i, rate2: 57, speed: speed, dps: 960, avg: 420));
      peripheral.write('0103', statusPacket(ms, distanceCm: distance));
      await pumpFor(tester, const Duration(seconds: 2), step: const Duration(milliseconds: 500));
    }
    await pumpFor(tester, const Duration(milliseconds: 200));

    await screenshot(tester, '13_crew_with_speedcoach');
    expect(find.text('SC RECEIVING'), findsOneWidget);
    expect(find.text('28.5'), findsOneWidget);
    expect(find.text('9.6'), findsOneWidget); // distance per stroke
    expect(find.text('HEART RATE · BPM'), findsOneWidget);
    await screenshot(tester, '13_crew_with_speedcoach');

    await tester.tap(find.text('Boat data'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('AVG RATE'), findsOneWidget);
    expect(find.text('500 M SPLITS'), findsOneWidget);
    expect(find.text('59'), findsOneWidget); // strokes (raw count)
    expect(find.textContaining('AHEAD'), findsOneWidget); // target 3:20 vs ~1:58
    await screenshot(tester, '14_boat_data_portrait');

    await tester.tap(find.text('Simple'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('Full data'), findsOneWidget);
    expect(find.text('ELAPSED'), findsOneWidget);
    await screenshot(tester, '15_simple_portrait');

    // Data stops: numbers stay but are flagged, never shown as live.
    await pumpFor(tester, const Duration(seconds: 5), step: const Duration(milliseconds: 500));
    expect(find.text('NO DATA'), findsWidgets);
    await screenshot(tester, '16_simple_stale');

    tester.view.physicalSize = const Size(844, 390);
    await pumpFor(tester, const Duration(milliseconds: 300));
    await screenshot(tester, '17_simple_landscape');
    await tester.tap(find.text('Full data'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await screenshot(tester, '18_crew_landscape_speedcoach');

    container.read(settingsProvider); // keep container alive
    await disposeApp(tester, bootstrap);
  });
}
