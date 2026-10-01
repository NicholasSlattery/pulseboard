import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/live_theme.dart';
import '../../app/theme.dart';
import '../../models/app_settings.dart';
import '../../models/hr_zones.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/boat_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/lineup_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../providers/settings_provider.dart';
import '../../speedcoach/boat_metrics.dart';
import '../../widgets/common.dart';
import '../sensors/sensor_actions_sheet.dart';
import '../speedcoach/speedcoach_screen.dart';
import 'boat_view.dart';
import 'live_common.dart';
import 'live_widgets.dart';
import 'seats_sheet.dart';

/// Default live view while recording: the SpeedCoach first, then every
/// rower's heart rate in seat order.
class CrewView extends ConsumerWidget {
  const CrewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seats = ref.watch(crewSeatsProvider);
    return LayoutBuilder(
      builder: (context, c) {
        final landscape = c.maxWidth > c.maxHeight && c.maxHeight < 560;
        return landscape ? _Landscape(seats: seats) : _Portrait(seats: seats);
      },
    );
  }
}

class _Portrait extends ConsumerWidget {
  const _Portrait({required this.seats});

  final List<CrewSeat> seats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final big = seats.length <= 4 && seats.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          const LiveStatusBar(),
          const SizedBox(height: 8),
          _BoatBlock(heroHeight: big ? 120 : 112, heroSize: big ? 66 : 62),
          const SizedBox(height: 8),
          _CrewHeader(seats: seats),
          const SizedBox(height: 6),
          Expanded(
            child: _SeatList(seats: seats, big: big),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 60, child: _Controls()),
        ],
      ),
    );
  }
}

class _Landscape extends ConsumerWidget {
  const _Landscape({required this.seats});

  final List<CrewSeat> seats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final strokeFirst = ref.watch(lineupBookProvider.select((b) => b.strokeFirst));
    final lineup = ref.watch(activeLineupProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        children: [
          const LiveStatusBar(showSerial: true),
          const SizedBox(height: 8),
          const _LandscapeBoat(),
          const SizedBox(height: 8),
          Expanded(
            child: seats.isEmpty
                ? const _NoCrew()
                : LayoutBuilder(
                    builder: (context, c) {
                      final perRow = math.max(1, math.min(seats.length, 8));
                      final w = (c.maxWidth - 6 * (perRow - 1)) / perRow;
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < seats.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            SizedBox(
                              width: math.max(w, 92),
                              child: _SeatCard(seat: seats[i]),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                const _SeatsButton(height: 48),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      strokeFirst ? 'STROKE → BOW' : 'BOW → STROKE',
                      if (lineup != null)
                        '${lineup.name.toUpperCase()} · ${lineup.boatClass.label}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LiveType.label(12, p.lo),
                  ),
                ),
                const SizedBox(width: 460, child: _Controls(vertical: false)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Split + rate heroes and the tier-2 row; collapses to one Connect row
/// when no SpeedCoach is connected.
class _BoatBlock extends ConsumerWidget {
  const _BoatBlock({required this.heroHeight, required this.heroSize});

  final double heroHeight;
  final double heroSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    return Ticking(
      builder: (context, now) {
        final b = watchBoatView(ref, now);
        if (boatIsAbsent(b.phase)) return _ConnectRow(boat: b);
        return Column(
          children: [
            SizedBox(
              height: heroHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 145,
                    child: MetricTile(
                      size: TileSize.hero,
                      label: 'SPLIT',
                      unit: '/500m',
                      unitInLabel: true,
                      value: b.split,
                      valueSize: heroSize,
                      dimmed: b.dimmed,
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
                      value: b.rate,
                      valueSize: heroSize,
                      valueColor: p.rate,
                      dimmed: b.dimmed,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: MetricTile(
                      size: TileSize.compact,
                      label: 'DISTANCE',
                      value: b.distance,
                      unit: 'm',
                      background: p.tile,
                      dimmed: b.dimmed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      size: TileSize.compact,
                      label: 'ELAPSED',
                      value: b.elapsed,
                      background: p.tile,
                      dimmed: b.dimmed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      size: TileSize.compact,
                      label: 'DIST/STR',
                      value: b.distancePerStroke,
                      unit: 'm',
                      background: p.tile,
                      dimmed: b.dimmed,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _StateTile(boat: b)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fourth tier-2 tile: the data state when not rowing, else the target cue,
/// else the split trend.
class _StateTile extends StatelessWidget {
  const _StateTile({required this.boat});

  final BoatView boat;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    Widget tile(String label, String value, Color fg, Color bg, {String? unit}) => MetricTile(
      size: TileSize.compact,
      label: label,
      value: value,
      unit: unit,
      foreground: fg,
      background: bg,
    );
    switch (boat.phase) {
      case BoatPhase.idle:
        return tile('IDLE', 'START', p.hi, p.tile);
      case BoatPhase.paused:
        return tile('PIECE', 'PAUSED', p.warn, p.warnBg);
      case BoatPhase.stale:
        return tile('NO DATA', '${boat.age?.inSeconds ?? 0}', p.warn, p.warnBg, unit: 's');
      case BoatPhase.lost:
        return tile('LOST', '${boat.age?.inSeconds ?? 0}', p.danger, p.dangerBg, unit: 's');
      case BoatPhase.rowing:
      case BoatPhase.off:
      case BoatPhase.waiting:
        break;
    }
    final cue = boat.cue;
    if (cue != null) {
      final diff = boat.metrics.rollingSplit == null
          ? Duration.zero
          : boat.target! - boat.metrics.rollingSplit!;
      final secs = (diff.inMilliseconds.abs() / 1000).toStringAsFixed(1);
      return switch (cue) {
        TargetCue.ahead => tile('AHEAD', '▲$secs', p.ahead, p.aheadBg, unit: 's'),
        TargetCue.on => tile('TARGET', 'ON', p.onTarget, p.onTargetBg),
        TargetCue.behind => tile('BEHIND', '▼$secs', p.behind, p.behindBg, unit: 's'),
      };
    }
    return MetricTile(
      size: TileSize.compact,
      label: 'TREND',
      value: boat.trend,
      unit: boat.trend == '--' ? null : 's',
      valueColor: boat.trendColor(p),
      background: p.tile,
      calculated: true,
    );
  }
}

class _LandscapeBoat extends ConsumerWidget {
  const _LandscapeBoat();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    return Ticking(
      builder: (context, now) {
        final b = watchBoatView(ref, now);
        if (boatIsAbsent(b.phase)) return _ConnectRow(boat: b);
        return SizedBox(
          height: 124,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 238,
                child: MetricTile(
                  size: TileSize.hero,
                  label: 'SPLIT',
                  unit: '/500m',
                  unitInLabel: true,
                  value: b.split,
                  valueSize: 76,
                  dimmed: b.dimmed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 164,
                child: MetricTile(
                  size: TileSize.hero,
                  label: 'RATE',
                  unit: 'spm',
                  unitInLabel: true,
                  value: b.rate,
                  valueSize: 76,
                  valueColor: p.rate,
                  dimmed: b.dimmed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 330,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: MetricTile(
                              size: TileSize.large,
                              label: 'DISTANCE',
                              value: b.distance,
                              unit: 'm',
                              valueSize: 28,
                              dimmed: b.dimmed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: MetricTile(
                              size: TileSize.large,
                              label: 'ELAPSED',
                              value: b.elapsed,
                              valueSize: 28,
                              dimmed: b.dimmed,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: MetricTile(
                              size: TileSize.large,
                              label: 'DIST / STROKE',
                              value: b.distancePerStroke,
                              unit: 'm',
                              valueSize: 28,
                              dimmed: b.dimmed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: _StateTile(boat: b)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "SpeedCoach not connected · Connect": the seats take the space and the
/// app works as a plain heart-rate board.
class _ConnectRow extends ConsumerWidget {
  const _ConnectRow({required this.boat});

  final BoatView boat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final waiting = boat.phase == BoatPhase.waiting;
    return Material(
      color: p.tile,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SpeedCoachScreen())),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.rowing, color: waiting ? p.warn : p.lo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    waiting ? 'Waiting for SpeedCoach' : 'SpeedCoach not connected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LiveType.body(16, p.mid, weight: FontWeight.w700),
                  ),
                ),
                Text(
                  waiting ? 'Setup' : 'Connect',
                  style: LiveType.body(16, p.rate, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrewHeader extends ConsumerWidget {
  const _CrewHeader({required this.seats});

  final List<CrewSeat> seats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final lineup = ref.watch(activeLineupProvider);
    final strokeFirst = ref.watch(lineupBookProvider.select((b) => b.strokeFirst));
    final daylight = ref.watch(settingsProvider.select((s) => s.liveTheme)) == LiveTheme.daylight;
    final cox = lineup?.coxId == null ? null : ref.watch(athleteByIdProvider(lineup!.coxId!));
    final seated = seats.any((s) => s.seat != null);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  seated
                      ? 'CREW · ${strokeFirst ? 'STROKE → BOW' : 'BOW → STROKE'} · BPM'
                      : 'HEART RATE · BPM',
                  maxLines: 1,
                  style: LiveType.label(12, p.lo, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (lineup != null) '${lineup.boatClass.label} · ${lineup.name}',
                    if (cox != null) 'Cox ${cox.displayName}',
                    if (lineup == null || !seated) 'No lineup set',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LiveType.body(13, p.mid),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: daylight ? 'Switch to on the water theme' : 'Switch to daylight theme',
            child: SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: p.btn,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => toggleLiveTheme(ref),
                  child: Icon(
                    daylight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    color: p.btnText,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (seated) const _SeatsButton(height: 44),
        ],
      ),
    );
  }
}

class _SeatsButton extends ConsumerWidget {
  const _SeatsButton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    return SizedBox(
      height: height,
      child: Material(
        color: p.btn,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showSeatsSheet(context, palette: p),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert, color: p.btnText, size: 20),
                const SizedBox(width: 6),
                Text('Seats', style: LiveType.body(15, p.btnText, weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatList extends StatelessWidget {
  const _SeatList({required this.seats, required this.big});

  final List<CrewSeat> seats;
  final bool big;

  @override
  Widget build(BuildContext context) {
    if (seats.isEmpty) return const _NoCrew();
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 4.0;
        final fit = (c.maxHeight - gap * (seats.length - 1)) / seats.length;
        final h = fit.clamp(44.0, big ? 92.0 : 64.0);
        final scrolls = h * seats.length + gap * (seats.length - 1) > c.maxHeight + 0.5;
        return ListView.separated(
          padding: EdgeInsets.zero,
          physics: scrolls ? null : const NeverScrollableScrollPhysics(),
          itemCount: seats.length,
          separatorBuilder: (_, _) => const SizedBox(height: gap),
          itemBuilder: (context, i) => SizedBox(
            height: h,
            child: _SeatRow(key: ValueKey(seats[i].seat ?? seats[i].athleteId), seat: seats[i]),
          ),
        );
      },
    );
  }
}

class _NoCrew extends ConsumerWidget {
  const _NoCrew();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    return Center(
      child: Text(
        'No rowers yet.\nSet seats in Lineup and assign straps in Sensors.',
        textAlign: TextAlign.center,
        style: LiveType.body(15, p.mid),
      ),
    );
  }
}

/// What a seat shows, from the existing card rules.
@immutable
class _SeatData {
  const _SeatData({
    required this.status,
    required this.statusColor,
    required this.bpm,
    required this.zone,
    required this.bar,
    required this.dimmed,
  });

  final String status;
  final Color statusColor;
  final String bpm;
  final int? zone;

  /// %max bar fill, 0..1 (50% to 100% of max HR), or null for no bar.
  final double? bar;
  final bool dimmed;

  static _SeatData of(CrewSeat seat, CardData? d, LivePalette p) {
    if (seat.isEmpty) {
      return _SeatData(
        status: 'EMPTY',
        statusColor: p.lo,
        bpm: '--',
        zone: null,
        bar: null,
        dimmed: false,
      );
    }
    if (d == null) {
      return _SeatData(
        status: 'NO STRAP',
        statusColor: p.warn,
        bpm: '--',
        zone: null,
        bar: null,
        dimmed: false,
      );
    }
    final pct = d.percentOfMax;
    final bar = pct == null ? null : ((pct - 50) / 50).clamp(0.0, 1.0);
    final bpm = d.bpm?.toString() ?? '--';
    switch (d.status) {
      case CardStatus.live:
        return _SeatData(
          status: !d.hasMaxHr ? 'SET MAX HR' : (pct == null ? '' : '${displayPercent(pct)}%'),
          statusColor: !d.hasMaxHr ? p.warn : p.mid,
          bpm: bpm,
          zone: d.zone,
          bar: bar,
          dimmed: false,
        );
      case CardStatus.weakSignal:
        return _SeatData(
          status: 'WEAK SIGNAL',
          statusColor: p.warn,
          bpm: bpm,
          zone: d.zone,
          bar: bar,
          dimmed: true,
        );
      case CardStatus.noContact:
        return _SeatData(
          status: 'NO SKIN CONTACT',
          statusColor: p.warn,
          bpm: '--',
          zone: null,
          bar: null,
          dimmed: false,
        );
      case CardStatus.connecting:
        return _SeatData(
          status: 'CONNECTING',
          statusColor: p.warn,
          bpm: '--',
          zone: null,
          bar: null,
          dimmed: false,
        );
      case CardStatus.noSignal:
        return _SeatData(
          status: 'NO SIGNAL',
          statusColor: p.danger,
          bpm: '--',
          zone: null,
          bar: null,
          dimmed: false,
        );
      case CardStatus.reconnecting:
        return _SeatData(
          status: 'RECONNECTING',
          statusColor: p.danger,
          bpm: '--',
          zone: null,
          bar: null,
          dimmed: false,
        );
      case CardStatus.failed:
        return _SeatData(
          status: 'SENSOR ERROR',
          statusColor: p.danger,
          bpm: '--',
          zone: null,
          bar: null,
          dimmed: false,
        );
      case CardStatus.disconnected:
        return _SeatData(
          status: 'DISCONNECTED',
          statusColor: p.danger,
          bpm: '--',
          zone: null,
          bar: null,
          dimmed: false,
        );
    }
  }
}

/// Watches one seat's athlete and strap, so a packet from one strap only
/// rebuilds that row.
_SeatData _watchSeat(WidgetRef ref, CrewSeat seat, LivePalette p) {
  final id = seat.athleteId;
  if (id == null) return _SeatData.of(seat, null, p);
  final sensorId = ref.watch(sensorIdForAthleteProvider(id));
  if (sensorId == null) return _SeatData.of(seat, null, p);
  final data = CardData.from(
    athlete: ref.watch(athleteByIdProvider(id)),
    sensor: ref.watch(sensorLiveProvider(sensorId)),
    sensorId: sensorId,
    formula: ref.watch(settingsProvider.select((s) => s.maxHrFormula)),
    zones: ref.watch(settingsProvider.select((s) => s.zoneModel)),
  );
  return _SeatData.of(seat, data, p);
}

void _openSeat(BuildContext context, WidgetRef ref, CrewSeat seat) {
  final id = seat.athleteId;
  final sensorId = id == null ? null : ref.read(sensorIdForAthleteProvider(id));
  if (sensorId != null) {
    showSensorActionsSheet(context, sensorId);
  } else if (id != null) {
    showSnack(context, '${seat.name} has no strap. Assign one in Sensors.');
  }
}

class _SeatRow extends ConsumerWidget {
  const _SeatRow({super.key, required this.seat});

  final CrewSeat seat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final d = _watchSeat(ref, seat, p);
    return LayoutBuilder(
      builder: (context, c) {
        final s = (c.maxHeight / 48).clamp(0.9, 1.9);
        final zoneColor = d.zone == null ? p.neutral : AppColors.zone(d.zone);
        return Semantics(
          button: true,
          label: [
            if (seat.seat != null) 'Seat ${seat.seat}',
            seat.name,
            d.bpm == '--' ? 'no heart rate' : '${d.bpm} beats per minute',
            if (d.zone != null) 'zone ${d.zone}',
            d.status,
          ].join(', '),
          excludeSemantics: true,
          child: Material(
            color: p.tile,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openSeat(context, ref, seat),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: seat.seat == null
                          ? const SizedBox.shrink()
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${seat.seat}', style: LiveType.number(22 * s, p.hi)),
                                if (seat.role.isNotEmpty)
                                  FittedBox(
                                    child: Text(
                                      seat.role,
                                      style: LiveType.label(9, p.lo, weight: FontWeight.w700),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  seat.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: LiveType.body(
                                    17 * math.min(s, 1.2),
                                    seat.isEmpty ? p.lo : p.hi,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                d.status,
                                style: LiveType.label(11.5, d.statusColor, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _Bar(fill: d.bar, color: zoneColor, track: p.track, dimmed: d.dimmed),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 58 * s,
                      child: Opacity(
                        opacity: d.dimmed ? 0.35 : 1,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(d.bpm, style: LiveType.number(34 * s, p.hi)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ZoneChip(zone: d.zone, dimmed: d.dimmed, width: 38, height: 30),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Landscape seat card: one column per seat, first seat on the left.
class _SeatCard extends ConsumerWidget {
  const _SeatCard({required this.seat});

  final CrewSeat seat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final d = _watchSeat(ref, seat, p);
    final zoneColor = d.zone == null ? p.neutral : AppColors.zone(d.zone);
    final role = switch (seat.role) {
      'STROKE' => 'STR',
      'SEAT' => '',
      final r => r,
    };
    return Material(
      color: p.tile,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openSeat(context, ref, seat),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (seat.seat != null) Text('${seat.seat}', style: LiveType.number(22, p.hi)),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: LiveType.label(9, p.lo, weight: FontWeight.w700),
                    ),
                  ),
                  _ZoneChip(zone: d.zone, dimmed: d.dimmed, width: 30, height: 20, fontSize: 13),
                ],
              ),
              Text(
                seat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LiveType.body(13, seat.isEmpty ? p.lo : p.hi, weight: FontWeight.w700),
              ),
              Opacity(
                opacity: d.dimmed ? 0.35 : 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.bpm, style: LiveType.number(40, p.hi)),
                ),
              ),
              _Bar(fill: d.bar, color: zoneColor, track: p.track, dimmed: d.dimmed, height: 5),
              Text(
                d.status.endsWith('%') ? '${d.status} MAX' : d.status,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: LiveType.label(10, d.statusColor, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fill,
    required this.color,
    required this.track,
    required this.dimmed,
    this.height = 6,
  });

  final double? fill;
  final Color color;
  final Color track;
  final bool dimmed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            if (fill != null)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill,
                child: Opacity(
                  opacity: dimmed ? 0.35 : 1,
                  child: ColoredBox(color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Zone badge: colour plus the Z number, never colour alone.
class _ZoneChip extends StatelessWidget {
  const _ZoneChip({
    required this.zone,
    required this.dimmed,
    required this.width,
    required this.height,
    this.fontSize = 17,
  });

  final int? zone;
  final bool dimmed;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final z = zone;
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z == null ? p.neutral : AppColors.zone(z),
          borderRadius: BorderRadius.circular(height / 4),
        ),
        child: Text(
          z == null ? '--' : 'Z$z',
          style: LiveType.number(fontSize, z == null ? p.hi : AppColors.onZone(z)),
        ),
      ),
    );
  }
}

/// Hold to stop · Boat data · Simple · Mark.
class _Controls extends ConsumerWidget {
  const _Controls({this.vertical = true});

  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.read(liveViewModeProvider.notifier);
    Widget gap() => const SizedBox(width: 8);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: HoldToStopButton(
            vertical: vertical,
            label: vertical ? 'Hold to stop' : 'Hold stop',
            radius: vertical ? 14 : 12,
            onStop: () => stopCrewSession(context, ref),
          ),
        ),
        gap(),
        Expanded(
          child: LiveButton(
            icon: Icons.grid_view_rounded,
            label: 'Boat data',
            vertical: vertical,
            onPressed: () => mode.show(LiveViewMode.boat),
          ),
        ),
        gap(),
        Expanded(
          child: LiveButton(
            icon: Icons.view_agenda_outlined,
            label: 'Simple',
            vertical: vertical,
            onPressed: () => mode.show(LiveViewMode.simple),
          ),
        ),
        gap(),
        Expanded(
          child: LiveButton(
            icon: Icons.flag_outlined,
            label: 'Mark',
            vertical: vertical,
            onPressed: () => markNow(context, ref),
          ),
        ),
      ],
    );
  }
}
