import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../../app/theme.dart';
import '../../utils/app_logger.dart';
import '../../widgets/common.dart';

/// In-app log viewer. Lets you see what Bluetooth is doing on the phone
/// without Xcode or a Mac.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics log'),
        actions: [
          IconButton(
            tooltip: 'Copy log',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: AppLogger.dump()));
              showSnack(context, 'Log copied to clipboard');
            },
          ),
          const IconButton(
            tooltip: 'Clear log',
            icon: Icon(Icons.delete_sweep_outlined),
            onPressed: AppLogger.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppLogger.revision,
        builder: (context, _, _) {
          final entries = AppLogger.entries.reversed.toList();
          if (entries.isEmpty) {
            return const EmptyState(icon: Icons.receipt_long, title: 'Log is empty', message: '');
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final color = e.level >= Level.SEVERE
                  ? AppColors.danger
                  : e.level >= Level.WARNING
                  ? AppColors.warning
                  : null;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Text(
                  e.toString(),
                  style: TextStyle(
                    fontFamily: 'Menlo',
                    fontFamilyFallback: const ['Consolas', 'Courier New'],
                    fontSize: 11,
                    color: color,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
