import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/theme.dart';
import '../../providers/core_providers.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/formatters.dart';
import '../../utils/grid_layout.dart';
import '../../widgets/bluetooth_status_banner.dart';
import '../../widgets/common.dart';
import '../sensors/sensor_actions_sheet.dart';
import '../sessions/session_summary_screen.dart';
import 'athlete_card.dart';
import 'speedcoach_banner.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(dashboardEntriesProvider);
    final density = ref.watch(settingsProvider.select((s) => s.density));
    final simulated = ref.watch(bootstrapProvider.select((b) => b.isSimulated));
    final session = ref.watch(activeSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppInfo.name),
        actions: [const Padding(padding: EdgeInsets.only(right: 12), child: _SessionButton())],
      ),
      body: Column(
        children: [
          if (simulated) const SimulatedDataBanner(),
          const BluetoothStatusBanner(),
          if (session != null) _RecordingBar(startedAt: session.startedAt),
          const SpeedCoachBanner(),
          Expanded(
            child: entries.isEmpty
                ? EmptyState(
                    icon: Icons.monitor_heart_outlined,
                    title: 'No athletes on the board yet',
                    message:
                        'Scan for heart-rate straps, then assign each one to an athlete. '
                        'Assigned athletes appear here with their live heart rate.',
                    action: FilledButton.icon(
                      onPressed: () => ref.read(homeTabProvider.notifier).go(HomeTab.sensors),
                      icon: const Icon(Icons.sensors),
                      label: const Text('Set up sensors'),
                    ),
                  )
                : SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(DashboardGrid.spacing),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final spec = DashboardGrid.compute(
                            count: entries.length,
                            size: constraints.biggest,
                            density: density,
                          );
                          return GridView.builder(
                            physics: spec.fitsOnScreen
                                ? const NeverScrollableScrollPhysics()
                                : const AlwaysScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: spec.columns,
                              mainAxisExtent: spec.cardHeight,
                              crossAxisSpacing: DashboardGrid.spacing,
                              mainAxisSpacing: DashboardGrid.spacing,
                            ),
                            itemCount: entries.length,
                            itemBuilder: (context, i) {
                              final entry = entries[i];
                              return AthleteCard(
                                key: ValueKey(entry.key),
                                entry: entry,
                                onTap: () => showSensorActionsSheet(context, entry.sensorId),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionButton extends ConsumerWidget {
  const _SessionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider);
    if (session == null) {
      return FilledButton.icon(
        onPressed: () => _start(context, ref),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start session'),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
      ),
      onPressed: () => _stop(context, ref),
      icon: const Icon(Icons.stop),
      label: const Text('Stop'),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    if (ref.read(rosterProvider).isEmpty) {
      showSnack(context, 'Assign at least one sensor to an athlete before starting a session.');
      return;
    }
    try {
      await ref.read(activeSessionProvider.notifier).start();
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not start session: $e');
    }
  }

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Stop session?',
      message: 'Recording stops and the session summary opens. Sensors stay connected.',
      confirmLabel: 'Stop session',
    );
    if (!confirmed || !context.mounted) return;
    final ended = await ref.read(activeSessionProvider.notifier).stop();
    if (ended == null || !context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => SessionSummaryScreen(sessionId: ended.id)));
  }
}

/// Red "recording" strip with a ticking elapsed time. Only this small widget
/// rebuilds every second.
class _RecordingBar extends StatefulWidget {
  const _RecordingBar({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = clock.now().difference(widget.startedAt);
    return Material(
      color: AppColors.danger.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record, color: AppColors.danger, size: 16),
            const SizedBox(width: 8),
            const Text(
              'RECORDING',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              Fmt.duration(elapsed),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
