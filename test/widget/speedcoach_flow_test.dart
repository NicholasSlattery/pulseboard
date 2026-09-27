import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/providers/settings_provider.dart';

import '../support/fake_ble_adapter.dart';
import '../support/fake_peripheral.dart';
import '../support/test_app.dart';

List<int> statusPacket(int ms) => [
  0xee, 0xaa, 0xf5, 0x17, 0xbb, 0xda, 0x1d, 0xcb, 0, 0, 0, 0, 0, 0, 0, 0, //
  ms & 0xFF, (ms >> 8) & 0xFF, (ms >> 16) & 0xFF, (ms >> 24) & 0xFF,
];

List<int> strokePacket(int count) => [
  60, 0xFF, 250 & 0xFF, 250 >> 8, 0, 0, 120, 0, 0, 0, 200, 0, 0, 0, count, 0, 0, 0, 0, 0, //
];

void main() {
  setUpAll(loadRealFonts);

  testWidgets('SpeedCoach receiver: start, receive strokes, remember serial, dashboard strip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final peripheral = FakePeripheral();
    final bootstrap = await buildTestBootstrap(tester, FakeBleAdapter(), peripheral: peripheral);
    await tester.pumpWidget(testApp(bootstrap));
    await pumpFor(tester, const Duration(milliseconds: 300));

    await tester.tap(find.text('Settings'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(find.text('SpeedCoach receiver'), 200);
    await tester.tap(find.text('SpeedCoach receiver'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('SpeedCoach (experimental)'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(peripheral.advertisedName, 'NK LiNKp');
    expect(find.text('WAITING FOR SPEEDCOACH'), findsOneWidget);

    // The SpeedCoach connects, identifies itself and starts rowing at 30 spm.
    peripheral.write('1005', '2226780'.codeUnits);
    for (var i = 0; i < 6; i++) {
      peripheral.write('0203', strokePacket(40 + i));
      peripheral.write('0103', statusPacket(90000 + i * 2000));
      await pumpFor(tester, const Duration(seconds: 2), step: const Duration(milliseconds: 500));
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await pumpFor(tester, const Duration(milliseconds: 200));

    expect(find.text('RECEIVING DATA'), findsOneWidget);
    expect(find.text('Paired SpeedCoach 2226780'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('RATE'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.pump();
    expect(find.text('30'), findsOneWidget); // SpeedCoach rate
    expect(find.text('3:20'), findsOneWidget); // split for 250 cm/s
    expect(find.text('45'), findsOneWidget); // stroke count
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(settingsProvider).speedCoachSerial, '2226780');
    await screenshot(tester, '12_speedcoach_receiver_phone');

    // Back on the dashboard, the live strip shows rate / time / strokes.
    await tester.pageBack();
    await pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.text('Dashboard'));
    peripheral.write('0203', strokePacket(46));
    peripheral.write('0103', statusPacket(102000));
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(find.text('SPEEDCOACH'), findsOneWidget);
    expect(find.textContaining('30 spm'), findsOneWidget);
    expect(find.textContaining('3:20 /500m'), findsOneWidget);
    await screenshot(tester, '13_dashboard_speedcoach_strip');

    // Next start advertises the remembered serial so that unit reconnects.
    container.read(settingsProvider); // keep container alive
    await disposeApp(tester, bootstrap);
  });
}
