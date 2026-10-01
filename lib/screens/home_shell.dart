import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/navigation_provider.dart';
import '../providers/session_provider.dart';
import 'lineup/lineup_screen.dart';
import 'live/live_screen.dart';
import 'sensors/sensors_screen.dart';
import 'sessions/sessions_screen.dart';
import 'settings/settings_screen.dart';

/// Top-level navigation: bottom bar on phones, side rail on wide screens
/// (iPad, landscape phones). Tabs are kept alive in an IndexedStack so the
/// live screen doesn't rebuild from scratch when switching. While a session
/// is recording, the Live tab goes full screen.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _destinations = [
    (HomeTab.live, Icons.monitor_heart_outlined, Icons.monitor_heart, 'Live'),
    (HomeTab.lineup, Icons.format_list_numbered, Icons.format_list_numbered, 'Lineup'),
    (HomeTab.sensors, Icons.sensors_outlined, Icons.sensors, 'Sensors'),
    (HomeTab.sessions, Icons.history_outlined, Icons.history, 'Sessions'),
    (HomeTab.settings, Icons.tune_outlined, Icons.tune, 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabProvider);
    final recording = ref.watch(activeSessionProvider.select((s) => s != null));
    final index = HomeTab.values.indexOf(tab);
    void select(int i) => ref.read(homeTabProvider.notifier).go(HomeTab.values[i]);

    const pages = [
      LiveScreen(),
      LineupScreen(),
      SensorsScreen(),
      SessionsScreen(),
      SettingsScreen(),
    ];
    final body = IndexedStack(index: index, children: pages);
    if (recording && tab == HomeTab.live) return Scaffold(body: body);

    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.$2),
                    selectedIcon: Icon(d.$3),
                    label: Text(d.$4),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: d.$4),
        ],
      ),
    );
  }
}
