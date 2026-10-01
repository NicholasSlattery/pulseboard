import 'package:flutter/material.dart';

import '../../app/live_theme.dart';
import '../../speedcoach/boat_metrics.dart';
import '../../speedcoach/speedcoach_receiver.dart';
import '../../utils/rowing_format.dart';
import 'live_widgets.dart';

/// Everything the live views show about the boat, as display strings.
/// Applies the state rules once: null -> dash; idle and paused blank the
/// per-stroke values; stale and lost keep the last values but dim them.
@immutable
class BoatView {
  const BoatView._({
    required this.phase,
    required this.state,
    required this.metrics,
    required this.age,
    required this.target,
  });

  factory BoatView.from(
    SpeedCoachLiveState state,
    BoatMetrics metrics,
    DateTime now, {
    Duration? targetSplit,
  }) {
    final last = state.lastPacketAt;
    return BoatView._(
      phase: boatPhase(state, metrics, now),
      state: state,
      metrics: metrics,
      age: last == null ? null : now.difference(last),
      target: targetSplit,
    );
  }

  final BoatPhase phase;
  final SpeedCoachLiveState state;
  final BoatMetrics metrics;

  /// Time since the last SpeedCoach packet.
  final Duration? age;
  final Duration? target;

  bool get connected => phase != BoatPhase.off && phase != BoatPhase.waiting;
  bool get dimmed => phase == BoatPhase.stale || phase == BoatPhase.lost;
  bool get _strokeBlank => phase == BoatPhase.idle || phase == BoatPhase.paused;
  bool get _pieceBlank => phase == BoatPhase.idle;

  String get split => _strokeBlank ? RowFmt.splitDash : RowFmt.split(state.split);
  String get rate => _strokeBlank ? RowFmt.dash : RowFmt.rate(state.strokeRate);
  String get distance => _pieceBlank ? RowFmt.dash : RowFmt.distance(state.distanceMeters);
  String get elapsed => _pieceBlank ? RowFmt.dash : RowFmt.elapsed(state.elapsed);
  String get distancePerStroke =>
      _strokeBlank ? RowFmt.dash : RowFmt.meters1(state.distancePerStrokeMeters);
  String get averageSplit => _pieceBlank ? RowFmt.splitDash : RowFmt.split(state.averageSplit);
  String get speed => _strokeBlank ? RowFmt.dash : RowFmt.speed(state.split);
  String get averageSpeed => _pieceBlank ? RowFmt.dash : RowFmt.speed(state.averageSplit);
  String get strokes => _pieceBlank || metrics.strokes == null ? RowFmt.dash : '${metrics.strokes}';
  String get averageRate => _pieceBlank ? RowFmt.dash : RowFmt.averageRate(metrics.averageRate);

  /// Split trend over the last 10 strokes: ▼ = split dropping (faster).
  String get trend {
    final t = metrics.trend;
    if (_strokeBlank || t == null) return RowFmt.dash;
    if (t.inMilliseconds.abs() < 50) return '0.0';
    return '${t.isNegative ? '▼' : '▲'}${RowFmt.seconds1(t)}';
  }

  Color trendColor(LivePalette p) {
    final t = metrics.trend;
    if (_strokeBlank || t == null || t.inMilliseconds.abs() < 50) return p.hi;
    return t.isNegative ? p.ahead : p.behind;
  }

  /// Ahead / on / behind, only while rowing with a target set.
  TargetCue? get cue => phase == BoatPhase.rowing && target != null ? metrics.cue : null;

  String get ageText {
    final a = age;
    if (a == null) return '';
    if (a < const Duration(seconds: 10)) return '${(a.inMilliseconds / 1000).toStringAsFixed(1)} s';
    return '${a.inSeconds} s';
  }

  /// Status-bar connection label and colour.
  (String, Color) connection(LivePalette p) => switch (phase) {
    BoatPhase.off => ('SC OFF', p.lo),
    BoatPhase.waiting => ('SC WAITING', p.warn),
    BoatPhase.stale => ('SC NO DATA', p.warn),
    BoatPhase.lost => ('SC DISCONNECTED', p.danger),
    _ => ('SC RECEIVING', p.ok),
  };

  String get pieceLabel => switch (phase) {
    BoatPhase.rowing => 'PIECE ON',
    BoatPhase.idle => 'IDLE',
    BoatPhase.paused => 'PAUSED',
    _ => '',
  };

  /// The band under the heroes in the Boat data and Simple views, or null.
  Widget? band(LivePalette p, {double height = 44, double textSize = 17}) {
    switch (phase) {
      case BoatPhase.idle:
        return StateBand(
          icon: Icons.play_arrow_rounded,
          text: 'Start a piece on the SpeedCoach',
          foreground: p.hi,
          background: p.tile,
          border: p.hi,
          height: height,
          textSize: textSize,
        );
      case BoatPhase.paused:
        return StateBand(
          icon: Icons.pause_rounded,
          text: 'PIECE PAUSED',
          trailing: 'time held at ${RowFmt.elapsed(state.elapsed)}',
          foreground: p.warn,
          background: p.warnBg,
          height: height,
          textSize: textSize,
        );
      case BoatPhase.stale:
        return StateBand(
          icon: Icons.warning_amber_rounded,
          text: 'NO DATA',
          trailing: 'last update ${age?.inSeconds ?? 0} s ago',
          foreground: p.warn,
          background: p.warnBg,
          height: height,
          textSize: textSize,
        );
      case BoatPhase.lost:
        return StateBand(
          icon: Icons.link_off_rounded,
          text: 'DISCONNECTED',
          trailing: 'last update ${age?.inSeconds ?? 0} s ago',
          foreground: p.danger,
          background: p.dangerBg,
          height: height,
          textSize: textSize,
        );
      case BoatPhase.rowing:
        final c = cue;
        if (c == null) return null;
        final (text, fg, bg) = cueStyle(c, metrics.rollingSplit, target!, p);
        return StateBand(
          icon: null,
          text: text,
          trailing: 'TARGET ${RowFmt.split(target)}',
          foreground: fg,
          background: bg,
          height: height,
          textSize: textSize,
        );
      case BoatPhase.off:
      case BoatPhase.waiting:
        return null;
    }
  }
}
