import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/live_theme.dart';
import '../../models/app_settings.dart';
import '../../providers/boat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../speedcoach/boat_metrics.dart';
import '../../utils/rowing_format.dart';
import 'boat_view.dart';
import 'live_common.dart';
import 'live_widgets.dart';

/// Every SpeedCoach value in three tiers, the last minute of split and rate,
/// and the 500 m splits.
class BoatDataView extends ConsumerWidget {
  const BoatDataView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final landscape = c.maxWidth > c.maxHeight && c.maxHeight < 560;
        return Ticking(
          builder: (context, now) {
            final b = watchBoatView(ref, now);
            return landscape ? _Landscape(boat: b, now: now) : _Portrait(boat: b, now: now);
          },
        );
      },
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({required this.boat, required this.now});

  final BoatView boat;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final band = boat.band(p);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LiveStatusBar(showSerial: true),
          const SizedBox(height: 8),
          SizedBox(height: 128, child: _Heroes(boat: boat, size: 66)),
          if (band != null) ...[const SizedBox(height: 8), band],
          const SizedBox(height: 8),
          SizedBox(height: 78, child: _Tier2(boat: boat)),
          const SizedBox(height: 8),
          _Tier3(boat: boat, columns: 3),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: _Trends(boat: boat, now: now),
          ),
          const SizedBox(height: 8),
          Expanded(child: _Splits(boat: boat)),
          const SizedBox(height: 8),
          SizedBox(height: 64, child: _Controls(boat: boat)),
        ],
      ),
    );
  }
}

class _Landscape extends StatelessWidget {
  const _Landscape({required this.boat, required this.now});

  final BoatView boat;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final band = boat.band(p, height: 40, textSize: 15);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LiveStatusBar(showSerial: true),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _Heroes(boat: boat, size: 84)),
                      if (band != null) ...[const SizedBox(height: 8), band],
                      const SizedBox(height: 8),
                      SizedBox(height: 70, child: _Tier2(boat: boat)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Tier3(boat: boat, columns: 3, height: 48),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 84,
                        child: _Trends(boat: boat, now: now),
                      ),
                      const SizedBox(height: 8),
                      Expanded(child: _Splits(boat: boat)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 48, child: _Controls(boat: boat, vertical: false)),
        ],
      ),
    );
  }
}

class _Heroes extends StatelessWidget {
  const _Heroes({required this.boat, required this.size});

  final BoatView boat;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 145,
          child: MetricTile(
            size: TileSize.hero,
            label: 'SPLIT',
            unit: '/500m',
            unitInLabel: true,
            value: boat.split,
            valueSize: size,
            dimmed: boat.dimmed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 100,
          child: MetricTile(
            size: TileSize.hero,
            label: 'RATE',
            unit: 'spm',
            unitInLabel: true,
            value: boat.rate,
            valueSize: size,
            valueColor: p.rate,
            dimmed: boat.dimmed,
          ),
        ),
      ],
    );
  }
}

class _Tier2 extends StatelessWidget {
  const _Tier2({required this.boat});

  final BoatView boat;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: MetricTile(
            size: TileSize.large,
            label: 'DISTANCE',
            value: boat.distance,
            unit: 'm',
            dimmed: boat.dimmed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MetricTile(
            size: TileSize.large,
            label: 'ELAPSED',
            value: boat.elapsed,
            dimmed: boat.dimmed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MetricTile(
            size: TileSize.large,
            label: 'DIST / STROKE',
            value: boat.distancePerStroke,
            unit: 'm',
            dimmed: boat.dimmed,
          ),
        ),
      ],
    );
  }
}

class _Tier3 extends ConsumerWidget {
  const _Tier3({required this.boat, required this.columns, this.height = 54});

  final BoatView boat;
  final int columns;
  final double height;

  /// With a distance or time target, "left" takes the Avg speed slot.
  MetricTile _fifth(AppSettings s) {
    final st = boat.state;
    switch (s.targetKind) {
      case TargetKind.distance:
        final d = st.distanceMeters;
        return MetricTile(
          size: TileSize.compact,
          label: 'DIST LEFT',
          value: d == null || boat.phase == BoatPhase.idle
              ? RowFmt.dash
              : RowFmt.distance((s.targetDistanceMeters - d).clamp(0, double.infinity)),
          unit: 'm',
          calculated: true,
          dimmed: boat.dimmed,
        );
      case TargetKind.time:
        final e = st.elapsed;
        final left = e == null ? null : s.targetTime - e;
        return MetricTile(
          size: TileSize.compact,
          label: 'TIME LEFT',
          value: left == null || boat.phase == BoatPhase.idle
              ? RowFmt.dash
              : RowFmt.elapsed(left.isNegative ? Duration.zero : left),
          calculated: true,
          dimmed: boat.dimmed,
        );
      case TargetKind.none:
        return MetricTile(
          size: TileSize.compact,
          label: 'AVG SPEED',
          value: boat.averageSpeed,
          unit: 'm/s',
          dimmed: boat.dimmed,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final settings = ref.watch(settingsProvider);
    final tiles = [
      MetricTile(
        size: TileSize.compact,
        label: 'AVG SPLIT',
        value: boat.averageSplit,
        dimmed: boat.dimmed,
      ),
      MetricTile(
        size: TileSize.compact,
        label: 'SPEED',
        value: boat.speed,
        unit: 'm/s',
        dimmed: boat.dimmed,
      ),
      MetricTile(
        size: TileSize.compact,
        label: 'STROKES',
        value: boat.strokes,
        dimmed: boat.dimmed,
      ),
      MetricTile(
        size: TileSize.compact,
        label: 'AVG RATE',
        value: boat.averageRate,
        unit: 'spm',
        valueColor: p.rate,
        calculated: true,
        dimmed: boat.dimmed,
      ),
      _fifth(settings),
      MetricTile(
        size: TileSize.compact,
        label: 'TREND',
        value: boat.trend,
        unit: boat.trend == RowFmt.dash ? null : 's',
        valueColor: boat.trendColor(p),
        calculated: true,
        dimmed: boat.dimmed,
      ),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += columns) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = i; j < i + columns && j < tiles.length; j++) ...[
                if (j > i) const SizedBox(width: 6),
                Expanded(child: tiles[j]),
              ],
            ],
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Last 60 s of split (inverted: faster is up) and rate on one time axis.
class _Trends extends StatelessWidget {
  const _Trends({required this.boat, required this.now});

  final BoatView boat;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final strokes = boat.metrics.recent(now);
    final empty = strokes.length < 2;
    Widget line(String label, List<double?> values, Color color, {bool invert = false}) => Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: LiveType.label(11, p.mid))),
        Expanded(
          child: Sparkline(values: values, color: color, invert: invert),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('LAST 60 S', style: LiveType.label(10.5, p.lo)),
              const SizedBox(width: 6),
              const CalcTag(),
              const Spacer(),
              Text('SPLIT: FASTER ↑ · NOW', style: LiveType.label(10.5, p.lo)),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: empty
                ? Center(
                    child: Text(
                      'Trends start on the first stroke',
                      style: LiveType.body(14, p.mid),
                    ),
                  )
                : Opacity(
                    opacity: boat.dimmed ? 0.28 : 1,
                    child: Column(
                      children: [
                        Expanded(
                          child: line(
                            'SPLIT',
                            [for (final s in strokes) s.split?.inMilliseconds.toDouble()],
                            p.hi,
                            invert: true,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Expanded(child: line('RATE', [for (final s in strokes) s.rate], p.rate)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Completed 500 m splits, newest first, with the gap to the piece average.
class _Splits extends StatelessWidget {
  const _Splits({required this.boat});

  final BoatView boat;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final splits = boat.metrics.splits500;
    final avg = boat.state.averageSplit;
    final rows = <Widget>[];
    // The 500 in progress, using the current average split.
    final distance = boat.state.distanceMeters ?? 0;
    if (boat.phase != BoatPhase.idle && distance > splits.length * 500 && avg != null) {
      rows.add(
        _row(p, RowFmt.thousands((splits.length + 1) * 500), RowFmt.split(avg), 'so far', p.lo),
      );
    }
    for (var i = splits.length - 1; i >= 0; i--) {
      final delta = avg == null ? null : splits[i] - avg;
      rows.add(
        _row(
          p,
          RowFmt.thousands((i + 1) * 500),
          RowFmt.split(splits[i]),
          delta == null ? '' : RowFmt.signedSeconds(delta),
          delta != null && delta.isNegative ? p.ahead : p.mid,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('500 M SPLITS', style: LiveType.label(10.5, p.lo)),
              const SizedBox(width: 6),
              const CalcTag(),
              const Spacer(),
              Text('NEWEST FIRST · VS AVG', style: LiveType.label(10.5, p.lo)),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text('No splits yet', style: LiveType.body(14, p.mid)))
                : Opacity(
                    opacity: boat.dimmed ? 0.28 : 1,
                    child: ListView(padding: EdgeInsets.zero, children: rows),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(LivePalette p, String mark, String split, String delta, Color deltaColor) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(mark, style: LiveType.body(14, p.mid))),
          const SizedBox(width: 12),
          Text(split, style: LiveType.number(26, p.hi)),
          const Spacer(),
          Text(delta, style: LiveType.body(15, deltaColor, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Hold to stop · Crew · Simple · Mark, or Reconnect when the SpeedCoach is
/// lost.
class _Controls extends ConsumerWidget {
  const _Controls({required this.boat, this.vertical = true});

  final BoatView boat;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final mode = ref.read(liveViewModeProvider.notifier);
    final stop = HoldToStopButton(
      vertical: vertical,
      fontSize: vertical ? 15 : 13,
      onStop: () => stopCrewSession(context, ref),
    );
    if (boat.phase == BoatPhase.lost) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: LiveButton(
              icon: Icons.refresh_rounded,
              label: 'Reconnect',
              vertical: false,
              fontSize: 20,
              background: p.primary,
              color: p.onPrimary,
              onPressed: () => reconnectSpeedCoach(ref),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: stop),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: stop),
        const SizedBox(width: 8),
        Expanded(
          child: LiveButton(
            icon: Icons.groups_outlined,
            label: 'Crew',
            vertical: vertical,
            fontSize: vertical ? 15 : 13,
            onPressed: () => mode.show(LiveViewMode.crew),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LiveButton(
            icon: Icons.view_agenda_outlined,
            label: 'Simple',
            vertical: vertical,
            fontSize: vertical ? 15 : 13,
            onPressed: () => mode.show(LiveViewMode.simple),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LiveButton(
            icon: Icons.flag_outlined,
            label: 'Mark',
            vertical: vertical,
            fontSize: vertical ? 15 : 13,
            onPressed: () => markNow(context, ref),
          ),
        ),
      ],
    );
  }
}
