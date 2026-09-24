import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/known_sensor.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import 'sensor_actions_sheet.dart';
import 'sensor_status.dart';

/// One row in the sensor list. Rebuilds only for its own sensor.
class SensorTile extends ConsumerWidget {
  const SensorTile({super.key, required this.sensorId, this.known});

  final String sensorId;
  final KnownSensor? known;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(sensorLiveProvider(sensorId));
    final athlete = known?.athleteId == null
        ? null
        : ref.watch(athleteByIdProvider(known!.athleteId!));
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = sensorStatusOf(live);
    final name = live?.name ?? known?.name;
    final hr = live?.advertisesHeartRate ?? known != null;
    final bpm = live?.displayBpm;
    final battery = live?.batteryPercent ?? known?.batteryPercent;

    return ListTile(
      onTap: () => showSensorActionsSheet(context, sensorId),
      leading: CircleAvatar(
        backgroundColor: (athlete != null
            ? AppColors.connected
            : theme.colorScheme.surfaceContainerHighest),
        foregroundColor: athlete != null ? Colors.white : theme.colorScheme.onSurfaceVariant,
        child: Icon(hr ? Icons.favorite : Icons.bluetooth),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name ?? 'Unnamed sensor',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontStyle: name == null ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (athlete != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.person, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                athlete.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusLabel(color: statusColor, label: statusLabel, fontSize: 11),
            Text('ID ${Fmt.shortId(sensorId)}', style: theme.textTheme.bodySmall),
            if (live?.rssi != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SignalBars(rssi: live!.rssi, height: 11),
                  Text('${live.rssi} dBm', style: theme.textTheme.bodySmall),
                ],
              ),
            if (hr)
              Text(
                'HR service',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.connected),
              )
            else
              Text('No HR service advertised', style: theme.textTheme.bodySmall),
            if (battery != null) BatteryIndicator(percent: battery, size: 11),
          ],
        ),
      ),
      trailing: bpm == null
          ? const Icon(Icons.chevron_right)
          : Text(
              '$bpm',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: live!.isStale ? theme.disabledColor : null,
              ),
            ),
    );
  }
}
