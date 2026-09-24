import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/app_settings.dart';
import 'package:pulseboard/screens/dashboard/athlete_card.dart';

import '../support/fake_ble_adapter.dart';
import '../support/test_app.dart';

void main() {
  setUpAll(loadRealFonts);

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('first launch explains Bluetooth before initialising it', (tester) async {
    await setSize(tester, const Size(430, 932));
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(tester, adapter, settings: const AppSettings());
    await tester.pumpWidget(testApp(bootstrap));
    await tester.pump();

    expect(find.text('Welcome to PulseBoard'), findsOneWidget);
    await screenshot(tester, '01_intro_phone');

    await tester.tap(find.text('Continue'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(find.text('No athletes on the board yet'), findsOneWidget);
    await screenshot(tester, '02_dashboard_empty_phone');
    await disposeApp(tester, bootstrap);
  });

  testWidgets('dashboard shows live HR per athlete and never presents stale data as live', (
    tester,
  ) async {
    await setSize(tester, const Size(1180, 820)); // iPad landscape
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(
      tester,
      adapter,
      seed: (athletes, sensors) async {
        final names = ['Nicholas', 'Ava', 'Ben', 'Chloe', 'Dan', 'Eve', 'Finn', 'Grace'];
        for (var i = 0; i < names.length; i++) {
          final a = await athletes.create(name: names[i], maxHrOverride: 190 + i);
          await sensors.assign(sensorId: 'S$i', athleteId: a.id, sensorName: 'Polar H10 $i');
        }
      },
    );
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // All eight straps connected and subscribed.
    expect(adapter.subscribeCalls.toSet().length, 8);
    expect(find.byType(AthleteCard), findsNWidgets(8));

    final bpms = [172, 95, 128, 140, 155, 181, 110, 163];
    for (var i = 0; i < 8; i++) {
      adapter.pushPacket('S$i', [0x16, bpms[i], 0x00, 0x03]); // contact ok + RR
    }
    await pumpFor(tester, const Duration(milliseconds: 300));

    expect(find.text('NICHOLAS'), findsOneWidget);
    expect(find.text('172'), findsOneWidget);
    expect(find.text('90% MAX'), findsOneWidget); // 172 / 190 = 90.5% (floored)
    expect(find.text('ZONE 5'), findsWidgets);
    await screenshot(tester, '03_dashboard_ipad_live');

    // Nicholas' strap drops: DISCONNECTED immediately, no BPM.
    adapter.linkDown('S0');
    for (var i = 1; i < 8; i++) {
      adapter.pushPacket('S$i', [0x16, bpms[i] + 1, 0x00, 0x03]);
    }
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('172'), findsNothing);
    expect(find.textContaining('DISCONNECTED'), findsOneWidget);
    await screenshot(tester, '04_dashboard_ipad_one_disconnected');

    // Everyone else goes quiet for 6 s -> weak signal (greyed), 16 s -> "--".
    await pumpFor(tester, const Duration(seconds: 6), step: const Duration(milliseconds: 500));
    expect(find.textContaining('WEAK SIGNAL'), findsWidgets);
    await pumpFor(tester, const Duration(seconds: 10), step: const Duration(milliseconds: 500));
    expect(find.textContaining('NO SIGNAL'), findsWidgets);
    expect(find.text('96'), findsNothing); // Ava's last value no longer shown
    await screenshot(tester, '05_dashboard_ipad_signal_lost');

    await disposeApp(tester, bootstrap);
  });

  testWidgets('phone layout fits 12 athletes and session can be started and stopped', (
    tester,
  ) async {
    await setSize(tester, const Size(430, 932));
    final adapter = FakeBleAdapter();
    final bootstrap = await buildTestBootstrap(
      tester,
      adapter,
      seed: (athletes, sensors) async {
        for (var i = 0; i < 12; i++) {
          final a = await athletes.create(name: 'Rower ${i + 1}', age: 18 + i);
          await sensors.assign(sensorId: 'R$i', athleteId: a.id);
        }
      },
    );
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 500));
    for (var i = 0; i < 12; i++) {
      adapter.pushHr('R$i', 120 + i * 5);
    }
    await pumpFor(tester, const Duration(milliseconds: 300));
    await screenshot(tester, '06_dashboard_phone_12');

    await tester.tap(find.text('Start session'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('RECORDING'), findsOneWidget);

    for (var t = 0; t < 5; t++) {
      for (var i = 0; i < 12; i++) {
        adapter.pushHr('R$i', 130 + i * 4 + t);
      }
      await pumpFor(tester, const Duration(seconds: 1), step: const Duration(milliseconds: 250));
    }
    await screenshot(tester, '07_dashboard_phone_recording');

    await tester.tap(find.text('Stop'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Stop session'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Session summary'), findsOneWidget);
    expect(find.text('Rower 1'), findsOneWidget);
    expect(find.text('AVG'), findsWidgets);
    await screenshot(tester, '08_session_summary_phone');

    await disposeApp(tester, bootstrap);
  });

  testWidgets('sensors screen scans, lists HR straps and assigns an athlete', (tester) async {
    await setSize(tester, const Size(430, 932));
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
    await screenshot(tester, '09_sensors_scan_phone');

    await tester.tap(find.text('Polar H10 ABC123'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await screenshot(tester, '10_sensor_sheet_phone');
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
    await screenshot(tester, '11_sensors_assigned_phone');

    await disposeApp(tester, bootstrap);
  });
}
