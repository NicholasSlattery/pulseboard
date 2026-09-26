import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pulseboard/app/app.dart';
import 'package:pulseboard/models/app_settings.dart';
import 'package:pulseboard/providers/core_providers.dart';
import 'package:pulseboard/speedcoach/peripheral_adapter.dart';
import 'package:pulseboard/storage/app_database.dart';
import 'package:pulseboard/storage/athlete_repository.dart';
import 'package:pulseboard/storage/sensor_repository.dart';
import 'package:pulseboard/storage/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_ble_adapter.dart';

/// Builds an in-memory database seeded by [seed], plus a bootstrap for the
/// real app widget wired to [adapter].
Future<AppBootstrap> buildTestBootstrap(
  WidgetTester tester,
  FakeBleAdapter adapter, {
  AppSettings settings = const AppSettings(bluetoothIntroSeen: true),
  Future<void> Function(AthleteRepository athletes, SensorRepository sensors)? seed,
  PeripheralAdapter? peripheral,
}) async {
  late AppBootstrap bootstrap;
  await tester.runAsync(() async {
    final db = await AppDatabase.open(inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
    final athletes = AthleteRepository(db);
    final sensors = SensorRepository(db);
    await SettingsRepository(db).save(settings);
    if (seed != null) await seed(athletes, sensors);
    bootstrap = AppBootstrap(
      database: db,
      adapter: adapter,
      settings: settings,
      athletes: await athletes.getAll(),
      sensors: await sensors.getAll(),
      peripheralAdapter: peripheral,
    );
  });
  return bootstrap;
}

Widget testApp(AppBootstrap bootstrap) => ProviderScope(
  overrides: [bootstrapProvider.overrideWithValue(bootstrap)],
  child: const PulseBoardApp(),
);

/// Pumps frames for [duration] in small steps so periodic timers and
/// coalesced emissions run.
Future<void> pumpFor(
  WidgetTester tester,
  Duration duration, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Unmounts the app so providers dispose and cancel their timers.
Future<void> disposeApp(WidgetTester tester, AppBootstrap bootstrap) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() => bootstrap.database.close());
}

// --- Optional screenshots for visual review -------------------------------
//
// Run with: flutter test --dart-define=SCREENSHOT_DIR=C:/some/dir test/widget
// Real Roboto + Material Icons fonts are loaded from the Flutter SDK so the
// images look like the app (tests normally render text as boxes).

const _screenshotDir = String.fromEnvironment('SCREENSHOT_DIR');
bool _fontsLoaded = false;

Future<void> loadRealFonts() async {
  if (_screenshotDir.isEmpty || _fontsLoaded) return;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts');
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(p.join(dir, f)).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
  _fontsLoaded = true;
}

Future<void> screenshot(WidgetTester tester, String name) async {
  if (_screenshotDir.isEmpty) return;
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(p.join(_screenshotDir, '$name.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}
