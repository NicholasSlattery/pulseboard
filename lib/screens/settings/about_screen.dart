import 'package:flutter/material.dart';

import '../../app/app_info.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget para(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(text, style: theme.textTheme.titleMedium),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & about')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppInfo.name, style: theme.textTheme.headlineSmall),
          Text(AppInfo.tagline, style: theme.textTheme.bodySmall),
          heading('Your data stays on this device'),
          para(
            'Athletes, sensor assignments, settings and every recorded session are stored only in '
            'a private database on this iPhone/iPad. ${AppInfo.name} has no account, no server, '
            'no cloud sync, no analytics, no advertising and no tracking SDKs.',
          ),
          para(
            'Data leaves the device only when you explicitly export a session as CSV and choose '
            'where to send it in the share sheet.',
          ),
          para('Deleting the app deletes all of its data.'),
          heading('Bluetooth'),
          para(
            'Bluetooth is used only to connect to heart-rate sensors using the standard '
            'Bluetooth Heart Rate Service (0x180D). The app does not use location.',
          ),
          heading('Not a medical device'),
          para(
            'Heart-rate readings and zones are for training guidance only and must not be used '
            'for medical diagnosis or treatment.',
          ),
          heading('Open source'),
          para('Licensed under the MIT License. Bluetooth via universal_ble (BSD-3-Clause).'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => showLicensePage(context: context, applicationName: AppInfo.name),
            child: const Text('Open-source licences'),
          ),
        ],
      ),
    );
  }
}
