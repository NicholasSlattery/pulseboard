import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/hr_zones.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// Large, glanceable live card for one athlete (or an unassigned strap).
///
/// Watches only its own athlete + sensor, so a packet from another strap
/// never rebuilds this card.
class AthleteCard extends ConsumerStatefulWidget {
  const AthleteCard({super.key, required this.entry, this.onTap});

  final DashboardEntry entry;
  final VoidCallback? onTap;

  @override
  ConsumerState<AthleteCard> createState() => _AthleteCardState();
}

class _AthleteCardState extends ConsumerState<AthleteCard> {
  int? _zone;
  DateTime? _zoneSince;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final athlete = entry.athleteId == null
        ? null
        : ref.watch(athleteByIdProvider(entry.athleteId!));
    final sensor = ref.watch(sensorLiveProvider(entry.sensorId));
    final formula = ref.watch(settingsProvider.select((s) => s.maxHrFormula));
    final zones = ref.watch(settingsProvider.select((s) => s.zoneModel));
    final showTimeInZone = ref.watch(settingsProvider.select((s) => s.showTimeInZone));

    final data = CardData.from(
      athlete: athlete,
      sensor: sensor,
      sensorId: entry.sensorId,
      formula: formula,
      zones: zones,
    );

    // Track how long the athlete has been in the current zone.
    final now = clock.now();
    if (data.zone != _zone) {
      _zone = data.zone;
      _zoneSince = data.zone == null ? null : now;
    }
    final inZoneFor = (_zoneSince != null && showTimeInZone) ? now.difference(_zoneSince!) : null;

    return RepaintBoundary(
      child: Semantics(
        button: widget.onTap != null,
        label: _semanticLabel(data),
        excludeSemantics: true,
        child: _CardBody(data: data, inZoneFor: inZoneFor, onTap: widget.onTap),
      ),
    );
  }

  static String _semanticLabel(CardData d) {
    final parts = <String>[d.title];
    parts.add(d.bpm == null ? 'no heart rate' : '${d.bpm} beats per minute');
    if (d.percentOfMax != null) parts.add('${displayPercent(d.percentOfMax!)} percent of max');
    if (d.zone != null) parts.add('zone ${d.zone}');
    parts.add(d.status.label.toLowerCase());
    if (d.dimmed) parts.add('reading is stale');
    return parts.join(', ');
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.data, required this.inZoneFor, this.onTap});

  final CardData data;
  final Duration? inZoneFor;
  final VoidCallback? onTap;

  Color _statusColor() => switch (data.status) {
    CardStatus.live => AppColors.connected,
    CardStatus.weakSignal || CardStatus.noContact || CardStatus.connecting => AppColors.warning,
    CardStatus.noSignal || CardStatus.reconnecting || CardStatus.failed => AppColors.danger,
    CardStatus.disconnected => AppColors.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final live = data.bpm != null && !data.dimmed;
    final zoneColor = live && data.zone != null ? AppColors.zone(data.zone) : null;
    final statusColor = _statusColor();

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 200.0;
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
        final scale = min(h / 200, w / 290).clamp(0.55, 2.4);

        final muted = scheme.onSurfaceVariant.withValues(alpha: 0.7);
        final bpmColor = data.bpm == null
            ? muted
            : (data.dimmed ? scheme.onSurfaceVariant.withValues(alpha: 0.55) : scheme.onSurface);

        return Material(
          color: Color.alphaBlend(
            (zoneColor ?? Colors.transparent).withValues(alpha: 0.16),
            scheme.surfaceContainerHigh,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
                  zoneColor ??
                  (data.status == CardStatus.live
                      ? scheme.outlineVariant
                      : statusColor.withValues(alpha: 0.6)),
              width: zoneColor != null ? 3 : 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14 * scale, 10 * scale, 14 * scale, 10 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + battery
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20 * scale,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: data.isAssigned ? scheme.onSurface : muted,
                          ),
                        ),
                      ),
                      if (data.batteryPercent != null)
                        BatteryIndicator(percent: data.batteryPercent!, size: 12 * scale),
                    ],
                  ),
                  // BPM
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            data.bpm?.toString() ?? '--',
                            style: TextStyle(
                              fontSize: 84 * scale,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              color: bpmColor,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          SizedBox(width: 6 * scale),
                          Text(
                            'BPM',
                            style: TextStyle(
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // % max + zone
                  SizedBox(
                    height: 26 * scale,
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _percentText(),
                              style: TextStyle(
                                fontSize: 17 * scale,
                                fontWeight: FontWeight.w700,
                                color: data.percentOfMax == null ? muted : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        if (data.zone != null && data.bpm != null)
                          FittedBox(
                            child: ZoneBadge(zone: data.zone!, fontSize: 15 * scale),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 6 * scale),
                  // Status + time in zone
                  Row(
                    children: [
                      Expanded(
                        child: StatusLabel(
                          color: statusColor,
                          label: data.detail == null
                              ? data.status.label
                              : '${data.status.label} · ${data.detail}',
                          fontSize: 12 * scale,
                        ),
                      ),
                      if (inZoneFor != null && data.zone != null && live)
                        Text(
                          '${Fmt.duration(inZoneFor!)} in Z${data.zone}',
                          style: TextStyle(
                            fontSize: 12 * scale,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _percentText() {
    if (!data.isAssigned) return 'UNASSIGNED · TAP TO ASSIGN';
    if (!data.hasMaxHr) return 'SET MAX HR';
    if (data.percentOfMax == null) return data.maxHr == null ? '' : 'MAX HR ${data.maxHr}';
    return '${displayPercent(data.percentOfMax!)}% MAX';
  }
}
