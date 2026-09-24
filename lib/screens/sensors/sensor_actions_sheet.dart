import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/known_sensor.dart';
import '../../models/sensor_state.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import 'assign_athlete_sheet.dart';
import 'sensor_status.dart';

Future<void> showSensorActionsSheet(BuildContext context, String sensorId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SensorActionsSheet(sensorId: sensorId),
  );
}

/// Details + Connect / Disconnect / Assign / Forget for one sensor.
class SensorActionsSheet extends ConsumerWidget {
  const SensorActionsSheet({super.key, required this.sensorId});

  final String sensorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(sensorLiveProvider(sensorId));
    final known = ref.watch(
      knownSensorsProvider.select((list) {
        for (final s in list) {
          if (s.id == sensorId) return s;
        }
        return null;
      }),
    );
    final athlete = known?.athleteId == null
        ? null
        : ref.watch(athleteByIdProvider(known!.athleteId!));
    final actions = ref.read(sensorActionsProvider);
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = sensorStatusOf(live);
    final connection = live?.connection;
    final isActive =
        connection != null &&
        connection != SensorConnectionState.discovered &&
        connection != SensorConnectionState.disconnected &&
        connection != SensorConnectionState.failed;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              live?.name ?? known?.name ?? 'Unnamed sensor',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            StatusLabel(color: statusColor, label: statusLabel, fontSize: 13),
            if (live?.error != null && connection != SensorConnectionState.receiving) ...[
              const SizedBox(height: 8),
              Text(live!.error!, style: TextStyle(color: statusColor)),
            ],
            if (live?.isSystemConnected ?? false) ...[
              const SizedBox(height: 8),
              Text(
                'This strap is already connected to this phone (possibly by another app). '
                'It can still be used here.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Assigned to',
              value: athlete?.displayName ?? 'Nobody',
              emphasize: athlete != null,
            ),
            if (live?.displayBpm != null)
              _DetailRow(label: 'Heart rate', value: '${live!.displayBpm} bpm'),
            _DetailRow(
              label: 'Heart Rate Service',
              value: (live?.advertisesHeartRate ?? false) || known != null
                  ? 'Detected (0x180D)'
                  : 'Not advertised',
            ),
            if (live?.rssi != null) _DetailRow(label: 'Signal', value: '${live!.rssi} dBm'),
            if ((live?.batteryPercent ?? known?.batteryPercent) != null)
              _DetailRow(
                label: 'Battery',
                value: '${live?.batteryPercent ?? known!.batteryPercent}%',
              ),
            if (known?.lastSeenAt != null)
              _DetailRow(label: 'Last seen', value: Fmt.dateTime(known!.lastSeenAt!)),
            _DetailRow(
              label: 'Bluetooth ID',
              value: sensorId,
              monospace: true,
              onTap: () {
                Clipboard.setData(ClipboardData(text: sensorId));
                showSnack(context, 'Sensor ID copied');
              },
            ),
            const SizedBox(height: 20),
            if (isActive)
              OutlinedButton.icon(
                onPressed: () async {
                  await actions.disconnect(sensorId);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              )
            else
              FilledButton.icon(
                onPressed: () {
                  actions.connect(sensorId);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.link),
                label: Text(
                  connection == SensorConnectionState.failed ? 'Retry connection' : 'Connect',
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => showAssignAthleteSheet(context, sensorId),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(athlete == null ? 'Assign athlete' : 'Change athlete'),
            ),
            if (athlete != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await actions.unassign(sensorId);
                  if (context.mounted) showSnack(context, '${athlete.displayName} unassigned');
                },
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Unassign athlete'),
              ),
            ],
            if (known != null || isActive) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _forget(context, actions, known, athlete?.displayName),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Forget sensor'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _forget(
    BuildContext context,
    SensorActions actions,
    KnownSensor? known,
    String? athleteName,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: 'Forget this sensor?',
      message: athleteName == null
          ? 'The sensor will be disconnected and removed from this device.'
          : 'The sensor will be disconnected and $athleteName will no longer be linked to it. '
                'Past sessions are not affected.',
      confirmLabel: 'Forget',
    );
    if (!confirmed) return;
    await actions.forget(sensorId);
    if (context.mounted) Navigator.pop(context);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.monospace = false,
    this.onTap,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool monospace;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                  fontFamily: monospace ? 'Menlo' : null,
                  fontFamilyFallback: monospace ? const ['Consolas', 'Courier New'] : null,
                  fontSize: monospace ? 12 : null,
                ),
              ),
            ),
            if (onTap != null)
              Icon(Icons.copy, size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
