import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../models/app_settings.dart';
import '../../models/hr_zones.dart';
import '../../providers/settings_provider.dart';
import 'about_screen.dart';
import 'diagnostics_screen.dart';
import 'zone_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    Future<void> pickEnum<T extends Enum>({
      required String title,
      required List<T> values,
      required T current,
      required String Function(T) label,
      required AppSettings Function(T) apply,
    }) async {
      final picked = await showDialog<T>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            RadioGroup<T>(
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
              child: Column(
                children: [
                  for (final v in values) RadioListTile<T>(value: v, title: Text(label(v))),
                ],
              ),
            ),
          ],
        ),
      );
      if (picked != null) await controller.save(apply(picked));
    }

    Future<void> pickSeconds({
      required String title,
      required List<int> choices,
      required Duration current,
      required AppSettings Function(Duration) apply,
    }) async {
      final picked = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            RadioGroup<int>(
              groupValue: current.inSeconds,
              onChanged: (v) => Navigator.pop(context, v),
              child: Column(
                children: [
                  for (final c in choices) RadioListTile<int>(value: c, title: Text('$c seconds')),
                ],
              ),
            ),
          ],
        ),
      );
      if (picked != null) await controller.save(apply(Duration(seconds: picked)));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Section('Heart rate'),
          ListTile(
            leading: const Icon(Icons.stacked_bar_chart),
            title: const Text('Heart-rate zones'),
            subtitle: Text(
              [
                for (var z = 1; z <= s.zoneModel.zoneCount; z++) 'Z$z ${s.zoneModel.rangeLabel(z)}',
              ].join('  '),
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const ZoneSettingsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.functions),
            title: const Text('Estimated max HR formula'),
            subtitle: Text('${s.maxHrFormula.label} — used when an athlete has no manual max HR'),
            onTap: () => pickEnum<MaxHrFormula>(
              title: 'Max HR formula',
              values: MaxHrFormula.values,
              current: s.maxHrFormula,
              label: (f) => f.label,
              apply: (f) => s.copyWith(maxHrFormula: f),
            ),
          ),
          const _Section('Connection'),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('Automatic reconnect'),
            subtitle: const Text('Retry dropped sensors with increasing delays (1 s → 30 s)'),
            value: s.autoReconnect,
            onChanged: (v) => controller.save(s.copyWith(autoReconnect: v)),
          ),
          ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: const Text('Stale reading after'),
            subtitle: Text('${s.staleAfter.inSeconds} s without data → BPM greyed out'),
            onTap: () => pickSeconds(
              title: 'Stale reading after',
              choices: AppSettings.staleChoicesSeconds,
              current: s.staleAfter,
              apply: (d) => s.copyWith(staleAfter: d),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.signal_cellular_nodata),
            title: const Text('Signal lost after'),
            subtitle: Text('${s.effectiveSignalLostAfter.inSeconds} s without data → “-- BPM”'),
            onTap: () => pickSeconds(
              title: 'Signal lost after',
              choices: AppSettings.lostChoicesSeconds,
              current: s.signalLostAfter,
              apply: (d) => s.copyWith(signalLostAfter: d),
            ),
          ),
          const _Section('Display'),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: const Text('Dashboard layout'),
            subtitle: Text(s.density.label),
            onTap: () => pickEnum<DashboardDensity>(
              title: 'Dashboard layout',
              values: DashboardDensity.values,
              current: s.density,
              label: (d) => switch (d) {
                DashboardDensity.auto => 'Auto-fit (all athletes on one screen)',
                DashboardDensity.large => 'Large cards',
                DashboardDensity.compact => 'Compact cards',
              },
              apply: (d) => s.copyWith(density: d),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.timelapse),
            title: const Text('Show time in current zone'),
            value: s.showTimeInZone,
            onChanged: (v) => controller.save(s.copyWith(showTimeInZone: v)),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(s.themeMode)),
            onTap: () => pickEnum<ThemeMode>(
              title: 'Theme',
              values: ThemeMode.values,
              current: s.themeMode,
              label: _themeLabel,
              apply: (m) => s.copyWith(themeMode: m),
            ),
          ),
          const _Section('Session'),
          ListTile(
            leading: const Icon(Icons.screen_lock_portrait),
            title: const Text('Keep screen awake'),
            subtitle: Text(s.keepAwake.label),
            onTap: () => pickEnum<KeepAwakeMode>(
              title: 'Keep screen awake',
              values: KeepAwakeMode.values,
              current: s.keepAwake,
              label: (m) => m.label,
              apply: (m) => s.copyWith(keepAwake: m),
            ),
          ),
          const _Section('Advanced'),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('Verbose logging'),
            subtitle: const Text('Log every heart-rate packet in the diagnostics log'),
            value: s.verboseLogging,
            onChanged: (v) => controller.save(s.copyWith(verboseLogging: v)),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Diagnostics log'),
            subtitle: const Text('Bluetooth events, for troubleshooting'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy & about'),
            subtitle: const Text('All data stays on this device'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppInfo.name} — ${AppInfo.tagline}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode m) => switch (m) {
    ThemeMode.system => 'Follow system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
