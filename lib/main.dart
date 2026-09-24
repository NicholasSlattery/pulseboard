import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app/app.dart';
import 'app/app_info.dart';
import 'app/theme.dart';
import 'bluetooth/ble_adapter.dart';
import 'bluetooth/simulated_ble_adapter.dart';
import 'bluetooth/universal_ble_adapter.dart';
import 'providers/core_providers.dart';
import 'storage/app_database.dart';
import 'storage/athlete_repository.dart';
import 'storage/sensor_repository.dart';
import 'storage/session_repository.dart';
import 'storage/settings_repository.dart';
import 'utils/app_logger.dart';

final _log = Logger('Main');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init();

  // Log (never crash on) unexpected errors. They show up in
  // Settings > Diagnostics.
  FlutterError.onError = (details) {
    _log.severe('Flutter error: ${details.exceptionAsString()}', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log.severe('Uncaught error', error, stack);
    return true;
  };

  runApp(const _Bootstrap());
}

/// Loads the database and initial state, then starts the real app. Shows a
/// clear error instead of crashing if local storage cannot be opened.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppBootstrap> _future = _load();

  static Future<AppBootstrap> _load() async {
    _log.info('Starting ${AppInfo.name}${AppInfo.useSimulator ? ' (SIMULATOR)' : ''}');
    final database = await AppDatabase.openDefault();
    final recovered = await SessionRepository(database).recoverUnfinishedSessions();
    final settings = await SettingsRepository(database).load();
    final athletes = await AthleteRepository(database).getAll();
    final sensors = await SensorRepository(database).getAll();
    final BleAdapter adapter = AppInfo.useSimulator ? SimulatedBleAdapter() : UniversalBleAdapter();
    AppLogger.setVerbose(settings.verboseLogging);
    return AppBootstrap(
      database: database,
      adapter: adapter,
      settings: settings,
      athletes: athletes,
      sensors: sensors,
      recoveredSessions: recovered,
      isSimulated: AppInfo.useSimulator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppBootstrap>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return ProviderScope(
            overrides: [bootstrapProvider.overrideWithValue(snapshot.data!)],
            child: const PulseBoardApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                          const SizedBox(height: 16),
                          const Text(
                            'Could not open local storage',
                            style: TextStyle(fontSize: 20),
                          ),
                          const SizedBox(height: 8),
                          Text('${snapshot.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => setState(() => _future = _load()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}
