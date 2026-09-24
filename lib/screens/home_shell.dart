import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/navigation_provider.dart';
import 'athletes/athletes_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'sensors/sensors_screen.dart';
import 'sessions/sessions_screen.dart';
import 'settings/settings_screen.dart';

/// Top-level navigation: bottom bar on phones, side rail on wide screens
/// (iPad, landscape phones). Tabs are kept alive in an IndexedStack so the
/// dashboard doesn't rebuild from scratch when switching.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _destinations = [
    (HomeTab.dashboard, Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (HomeTab.sensors, Icons.sensors_outlined, Icons.sensors, 'Sensors'),
    (HomeTab.athletes, Icons.groups_outlined, Icons.groups, 'Athletes'),
    (HomeTab.sessions, Icons.history_outlined, Icons.history, 'Sessions'),
    (HomeTab.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabProvider);
    final index = HomeTab.values.indexOf(tab);
    void select(int i) => ref.read(homeTabProvider.notifier).go(HomeTab.values[i]);

    const pages = [
      DashboardScreen(),
      SensorsScreen(),
      AthletesScreen(),
      SessionsScreen(),
      SettingsScreen(),
    ];
    final body = IndexedStack(index: index, children: pages);
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
