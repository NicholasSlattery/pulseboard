import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../providers/core_providers.dart';
import '../providers/effects.dart';
import '../providers/settings_provider.dart';
import '../screens/bluetooth_intro_screen.dart';
import '../screens/home_shell.dart';
import 'app_info.dart';
import 'theme.dart';

final _log = Logger('App');

/// Root widget (inside the ProviderScope).
class PulseBoardApp extends ConsumerStatefulWidget {
  const PulseBoardApp({super.key});

  @override
  ConsumerState<PulseBoardApp> createState() => _PulseBoardAppState();
}

class _PulseBoardAppState extends ConsumerState<PulseBoardApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _log.info('App resumed');
        unawaited(ref.read(bluetoothManagerProvider).onAppResumed());
      },
      // Persist buffered session samples whenever we might be suspended or
      // killed.
      onInactive: _flushSession,
      onHide: _flushSession,
      onPause: _flushSession,
    );
    if (ref.read(settingsProvider).bluetoothIntroSeen) {
      unawaited(ref.read(bluetoothManagerProvider).initialize());
    }
  }

  void _flushSession() => unawaited(ref.read(sessionRecorderProvider).flush());

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _completeIntro() async {
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(bluetoothIntroSeen: true));
    await ref.read(bluetoothManagerProvider).initialize();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appEffectsProvider);
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final introSeen = ref.watch(settingsProvider.select((s) => s.bluetoothIntroSeen));

    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: introSeen ? const HomeShell() : BluetoothIntroScreen(onContinue: _completeIntro),
    );
  }
}
