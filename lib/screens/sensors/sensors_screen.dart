import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bluetooth/ble_adapter.dart';
import '../../models/known_sensor.dart';
import '../../models/sensor_state.dart';
import '../../providers/sensors_provider.dart';
import '../../widgets/bluetooth_status_banner.dart';
import '../../widgets/common.dart';
import 'sensor_tile.dart';

/// Lightweight descriptor used to build the sensor list sections without
/// rebuilding the list for every RSSI/HR update (tiles update themselves).
typedef _Row = ({String id, bool active, bool hr, String? name});

class SensorsScreen extends ConsumerStatefulWidget {
  const SensorsScreen({super.key});

  @override
  ConsumerState<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends ConsumerState<SensorsScreen> {
  bool _allDevices = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(bluetoothStatusProvider);
    final known = ref.watch(knownSensorsProvider);
    final knownIds = known.map((k) => k.id).toSet();
    final actions = ref.read(sensorActionsProvider);

    final rowsKey = ref.watch(
      sensorLiveStatesProvider.select((states) {
        final parts = <String>[];
        for (final s in states.values) {
          if (knownIds.contains(s.sensorId)) continue;
          final active =
              s.connection != SensorConnectionState.discovered &&
              s.connection != SensorConnectionState.disconnected;
          parts.add(
            '${s.sensorId}\u0001${active ? 1 : 0}\u0001${s.advertisesHeartRate ? 1 : 0}\u0001${s.name ?? ''}',
          );
        }
        parts.sort();
        return parts.join('\u0002');
      }),
    );
    final rows = <_Row>[
      if (rowsKey.isNotEmpty)
        for (final p in rowsKey.split('\u0002'))
          () {
            final f = p.split('\u0001');
            return (
              id: f[0],
              active: f[1] == '1',
              hr: f[2] == '1',
              name: f[3].isEmpty ? null : f[3],
            );
          }(),
    ];

    final assigned = known.where((k) => k.isAssigned).toList()
      ..sort((a, b) => (a.name ?? a.id).compareTo(b.name ?? b.id));
    final rememberedUnassigned = known.where((k) => !k.isAssigned).toList();
    final activeUnknown = rows.where((r) => r.active).toList();
    final nearby = rows.where((r) => !r.active).toList()
      ..sort((a, b) {
        if (a.hr != b.hr) return a.hr ? -1 : 1;
        return (a.name ?? '~${a.id}').compareTo(b.name ?? '~${b.id}');
      });

    final ready = status.availability == BleAvailability.poweredOn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensors'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => setState(() => _allDevices = !_allDevices),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'all',
                checked: _allDevices,
                child: const Text('Show all Bluetooth devices'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const BluetoothStatusBanner(),
          _ScanPanel(
            scanning: status.isScanning,
            enabled: ready,
            allDevices: _allDevices,
            error: status.scanError,
            onScan: () => actions.startScan(allDevices: _allDevices),
            onStop: actions.stopScan,
          ),
          Expanded(
            child:
                (assigned.isEmpty &&
                    rememberedUnassigned.isEmpty &&
                    activeUnknown.isEmpty &&
                    nearby.isEmpty)
                ? EmptyState(
                    icon: Icons.bluetooth_searching,
                    title: status.isScanning ? 'Looking for straps…' : 'No sensors yet',
                    message: status.isScanning
                        ? 'Put the strap on (most straps only wake up with skin contact) and keep it close to this device.'
                        : 'Tap Scan to find nearby heart-rate straps. Wet the strap electrodes and wear it so it wakes up.',
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (assigned.isNotEmpty) ...[
                        _Header('Assigned (${assigned.length})'),
                        for (final k in assigned)
                          SensorTile(key: ValueKey(k.id), sensorId: k.id, known: k),
                      ],
                      if (activeUnknown.isNotEmpty || rememberedUnassigned.isNotEmpty) ...[
                        const _Header('Unassigned'),
                        for (final KnownSensor k in rememberedUnassigned)
                          SensorTile(key: ValueKey(k.id), sensorId: k.id, known: k),
                        for (final r in activeUnknown)
                          SensorTile(key: ValueKey(r.id), sensorId: r.id),
                      ],
                      if (nearby.isNotEmpty) ...[
                        _Header('Nearby (${nearby.length})'),
                        for (final r in nearby) SensorTile(key: ValueKey(r.id), sensorId: r.id),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({
    required this.scanning,
    required this.enabled,
    required this.allDevices,
    required this.error,
    required this.onScan,
    required this.onStop,
  });

  final bool scanning;
  final bool enabled;
  final bool allDevices;
  final String? error;
  final VoidCallback onScan;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scanning
                          ? (allDevices
                                ? 'Scanning all devices…'
                                : 'Scanning for heart-rate straps…')
                          : 'Not scanning',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      error ??
                          (scanning
                              ? 'Stops automatically after 30 seconds to save battery.'
                              : 'Assigned sensors reconnect automatically - no scan needed.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: error != null ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              scanning
                  ? OutlinedButton.icon(
                      onPressed: onStop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop scan'),
                    )
                  : FilledButton.icon(
                      onPressed: enabled ? onScan : null,
                      icon: const Icon(Icons.search),
                      label: const Text('Scan'),
                    ),
            ],
          ),
        ),
        SizedBox(height: 3, child: scanning ? const LinearProgressIndicator() : null),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
