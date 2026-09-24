import 'package:flutter/material.dart';

import '../app/app_info.dart';

/// First-launch explanation shown BEFORE iOS displays its Bluetooth
/// permission prompt, so the coach knows why it appears.
class BluetoothIntroScreen extends StatelessWidget {
  const BluetoothIntroScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget point(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(28),
              children: [
                Icon(Icons.monitor_heart, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Welcome to ${AppInfo.name}',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Watch your whole team’s heart rate live from one screen.',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                point(
                  Icons.bluetooth,
                  'Bluetooth access',
                  'Next, iOS will ask for Bluetooth permission. It is needed to connect to your '
                      'athletes’ chest straps (Polar, Garmin, Wahoo, COROS, Coospo, Magene and other '
                      'standard Bluetooth heart-rate monitors).',
                ),
                point(
                  Icons.lock_outline,
                  'Private by design',
                  'No account, no cloud, no tracking. Everything stays on this device unless you '
                      'export a session yourself.',
                ),
                point(
                  Icons.screen_lock_portrait_outlined,
                  'Keep the app open during practice',
                  'For reliable live data keep ${AppInfo.name} in the foreground. The screen stays '
                      'awake automatically while a session is recording.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
