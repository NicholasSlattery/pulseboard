import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_info.dart';
import '../app/theme.dart';
import '../bluetooth/ble_adapter.dart';
import '../providers/sensors_provider.dart';

/// Explains Bluetooth problems (off, permission denied, unsupported) at the
/// top of a screen. Renders nothing when Bluetooth is fine.
class BluetoothStatusBanner extends ConsumerWidget {
  const BluetoothStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(bluetoothStatusProvider);
    if (!status.initialized) return const SizedBox.shrink();

    final (
      IconData icon,
      Color color,
      String title,
      String message,
      bool showSettings,
    ) = switch (status.availability) {
      BleAvailability.poweredOn => (Icons.check, AppColors.connected, '', '', false),
      BleAvailability.poweredOff => (
        Icons.bluetooth_disabled,
        AppColors.danger,
        'Bluetooth is off',
        'Turn on Bluetooth in Control Centre or Settings. Sensors will reconnect automatically.',
        false,
      ),
      BleAvailability.unauthorized => (
        Icons.block,
        AppColors.danger,
        'Bluetooth permission denied',
        '${AppInfo.name} needs Bluetooth to read heart-rate straps. '
            'Open Settings → ${AppInfo.name} and allow Bluetooth.',
        true,
      ),
      BleAvailability.unsupported => (
        Icons.error_outline,
        AppColors.danger,
        'Bluetooth LE not supported',
        'This device cannot connect to Bluetooth heart-rate sensors.',
        false,
      ),
      BleAvailability.resetting || BleAvailability.unknown => (
        Icons.bluetooth_searching,
        AppColors.warning,
        'Starting Bluetooth…',
        'Waiting for the Bluetooth radio.',
        false,
      ),
    };
    if (status.availability == BleAvailability.poweredOn) return const SizedBox.shrink();

    return Material(
      color: color.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (showSettings && defaultTargetPlatform == TargetPlatform.iOS)
              TextButton(
                onPressed: () => launchUrl(Uri.parse('app-settings:')),
                child: const Text('Settings'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown whenever simulated sensors are in use.
class SimulatedDataBanner extends StatelessWidget {
  const SimulatedDataBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.purple.withValues(alpha: 0.18),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: Colors.purple),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'SIMULATED DATA — built with PULSEBOARD_SIMULATOR. Not real heart rates.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.purple, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
