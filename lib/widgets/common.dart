import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Friendly placeholder for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured zone pill that always shows the zone number (colour is never the
/// only signal).
class ZoneBadge extends StatelessWidget {
  const ZoneBadge({super.key, required this.zone, this.fontSize = 14, this.compact = false});

  final int zone;
  final double fontSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.6, vertical: fontSize * 0.2),
      decoration: BoxDecoration(
        color: AppColors.zone(zone),
        borderRadius: BorderRadius.circular(fontSize),
      ),
      child: Text(
        compact ? 'Z$zone' : 'ZONE $zone',
        style: TextStyle(
          color: AppColors.onZone(zone),
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Small coloured dot + label.
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.color, required this.label, this.fontSize = 12});

  final Color color;
  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: fontSize * 0.75,
          height: fontSize * 0.75,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: fontSize * 0.45),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Battery icon with percentage.
class BatteryIndicator extends StatelessWidget {
  const BatteryIndicator({super.key, required this.percent, this.size = 14});

  final int percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color? color;
    if (percent <= 15) {
      icon = Icons.battery_alert;
      color = AppColors.danger;
    } else if (percent <= 40) {
      icon = Icons.battery_3_bar;
      color = AppColors.warning;
    } else if (percent <= 80) {
      icon = Icons.battery_5_bar;
      color = null;
    } else {
      icon = Icons.battery_full;
      color = null;
    }
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: 'Battery $percent percent',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: size * 1.2, color: fg),
          const SizedBox(width: 2),
          Text(
            '$percent%',
            style: TextStyle(fontSize: size, color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Four-bar signal strength from RSSI (dBm).
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.rssi, this.height = 14});

  final int? rssi;
  final double height;

  /// 0-4 bars. Typical BLE: > -60 excellent, < -90 barely usable.
  static int barsFor(int? rssi) {
    if (rssi == null) return 0;
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final bars = barsFor(rssi);
    final on = bars >= 3 ? AppColors.connected : (bars == 2 ? AppColors.warning : AppColors.danger);
    final off = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      label: rssi == null ? 'Signal unknown' : 'Signal $bars of 4, $rssi dBm',
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: height / 3.5,
                height: height * (i + 1) / 4,
                margin: EdgeInsets.only(right: height / 10),
                decoration: BoxDecoration(
                  color: i < bars ? on : off,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows a confirmation dialog; resolves to true when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
