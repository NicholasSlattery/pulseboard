import 'package:flutter/foundation.dart';

import 'speedcoach_receiver.dart';

/// One stroke as received, for trends and sparklines.
@immutable
class StrokeSample {
  const StrokeSample({required this.at, this.rate, this.split, this.distancePerStroke});

  final DateTime at;
  final double? rate;
  final Duration? split;
  final double? distancePerStroke;
}

/// Where the boat is relative to the target split.
enum TargetCue { ahead, on, behind }

/// What the live screens show about the boat, derived from the SpeedCoach.
enum BoatPhase {
  /// Receiver not running (or this device can't host it).
  off,

  /// Advertising; no SpeedCoach has connected yet.
  waiting,

  /// Streaming, no piece running.
  idle,

  /// Piece running.
  rowing,

  /// Piece running but the SpeedCoach clock stopped.
  paused,

  /// No packet for more than [BoatMetrics.staleAfter].
  stale,

  /// No packet for more than [BoatMetrics.lostAfter].
  lost,
}

/// Values calculated in the app from the SpeedCoach stream (everything
/// marked CALC in the UI), plus the bits needed to judge freshness.
@immutable
class BoatMetrics {
  const BoatMetrics({
    this.strokes,
    this.averageRate,
    this.rollingSplit,
    this.trend,
    this.splits500 = const [],
    this.history = const [],
    this.elapsedChangedAt,
    this.cue,
  });

  static const staleAfter = Duration(seconds: 3);
  static const lostAfter = Duration(seconds: 15);
  static const pausedAfter = Duration(milliseconds: 2500);

  /// Strokes in the piece, unwrapped past the SpeedCoach's 8-bit counter.
  final int? strokes;

  /// Mean SpeedCoach rate over the strokes of the piece.
  final double? averageRate;

  /// Mean split of the last 5 strokes (drives the target cue).
  final Duration? rollingSplit;

  /// Mean split of the last 5 strokes minus the 5 before: negative = faster.
  final Duration? trend;

  /// Time for each completed 500 m, first 500 first.
  final List<Duration> splits500;

  /// Recent strokes, oldest first (about the last minute).
  final List<StrokeSample> history;

  /// Wall-clock time the SpeedCoach elapsed time last moved.
  final DateTime? elapsedChangedAt;

  /// Ahead / on / behind the target split, or null without a target.
  final TargetCue? cue;

  /// Best (fastest) completed 500 m, with its index.
  (int, Duration)? get best500 {
    if (splits500.isEmpty) return null;
    var best = 0;
    for (var i = 1; i < splits500.length; i++) {
      if (splits500[i] < splits500[best]) best = i;
    }
    return (best, splits500[best]);
  }

  /// Strokes of the last [window] for sparklines.
  List<StrokeSample> recent(DateTime now, [Duration window = const Duration(seconds: 60)]) => [
    for (final s in history)
      if (now.difference(s.at) <= window) s,
  ];
}

/// Phase of the boat block for [state] at [now].
BoatPhase boatPhase(SpeedCoachLiveState state, BoatMetrics metrics, DateTime now) {
  switch (state.status) {
    case SpeedCoachReceiverStatus.stopped:
    case SpeedCoachReceiverStatus.unsupported:
    case SpeedCoachReceiverStatus.error:
      return BoatPhase.off;
    case SpeedCoachReceiverStatus.starting:
    case SpeedCoachReceiverStatus.waiting:
    case SpeedCoachReceiverStatus.streaming:
      break;
  }
  final last = state.lastPacketAt;
  if (last == null) return BoatPhase.waiting;
  final age = now.difference(last);
  if (age > BoatMetrics.lostAfter) return BoatPhase.lost;
  if (age > BoatMetrics.staleAfter) return BoatPhase.stale;
  final elapsed = state.elapsed ?? Duration.zero;
  final changed = metrics.elapsedChangedAt;
  final clockRunning = changed != null && now.difference(changed) <= BoatMetrics.pausedAfter;
  if (!state.pieceRunning && !clockRunning) return BoatPhase.idle;
  if (elapsed > Duration.zero && !clockRunning) return BoatPhase.paused;
  return BoatPhase.rowing;
}

/// Turns the SpeedCoach stream into [BoatMetrics]. Pure: feed it states and
/// the current time.
class BoatTracker {
  BoatTracker({this.historyWindow = const Duration(seconds: 70)});

  final Duration historyWindow;

  BoatMetrics _metrics = const BoatMetrics();
  BoatMetrics get metrics => _metrics;

  int? _lastRawCount;
  int _wrapOffset = 0;
  final List<StrokeSample> _strokes = [];
  double _rateSum = 0;
  int _rateCount = 0;

  Duration? _lastElapsed;
  DateTime? _elapsedChangedAt;
  double? _lastDistance;
  Duration _lastMark = Duration.zero;
  final List<Duration> _splits500 = [];
  TargetCue? _cue;

  void reset() {
    _lastRawCount = null;
    _wrapOffset = 0;
    _strokes.clear();
    _rateSum = 0;
    _rateCount = 0;
    _lastElapsed = null;
    _elapsedChangedAt = null;
    _lastDistance = null;
    _lastMark = Duration.zero;
    _splits500.clear();
    _cue = null;
    _metrics = const BoatMetrics();
  }

  /// Processes a new receiver state. Returns the updated metrics.
  BoatMetrics update(SpeedCoachLiveState s, DateTime now, {Duration? targetSplit}) {
    if (s.status == SpeedCoachReceiverStatus.stopped) {
      if (_lastElapsed != null || _lastRawCount != null) reset();
      return _metrics;
    }

    // Piece reset: distance and time back to zero.
    final isReset = s.distanceMeters == 0 && s.elapsed == Duration.zero;
    if (isReset && ((_lastDistance ?? 0) > 0 || (_lastElapsed ?? Duration.zero) > Duration.zero)) {
      reset();
    }

    // Clock movement (pause detection) and 500 m crossings.
    final elapsed = s.elapsed;
    final distance = s.distanceMeters;
    if (elapsed != null && elapsed != _lastElapsed) {
      if (_lastElapsed != null && elapsed > _lastElapsed!) _elapsedChangedAt = now;
      _record500s(distance, elapsed);
      _lastElapsed = elapsed;
      if (distance != null) _lastDistance = distance;
    }

    // A new stroke packet: the 8-bit counter changed.
    final raw = s.strokeCount;
    if (raw != null && raw != _lastRawCount) {
      if (_lastRawCount != null && raw < _lastRawCount! && _lastRawCount! - raw > 128) {
        _wrapOffset += 256;
      }
      _lastRawCount = raw;
      _strokes.add(
        StrokeSample(
          at: now,
          rate: s.strokeRate,
          split: s.split,
          distancePerStroke: s.distancePerStrokeMeters,
        ),
      );
      if (s.pieceRunning && s.strokeRate != null) {
        _rateSum += s.strokeRate!;
        _rateCount++;
      }
      while (_strokes.isNotEmpty && now.difference(_strokes.first.at) > historyWindow) {
        _strokes.removeAt(0);
      }
    }

    final rolling = _meanSplit(_tail(5));
    _cue = _nextCue(_cue, rolling, targetSplit);
    final prev = _meanSplit(_tail(10).take(5).toList());
    _metrics = BoatMetrics(
      strokes: raw == null ? null : raw + _wrapOffset,
      averageRate: _rateCount == 0 ? null : _rateSum / _rateCount,
      rollingSplit: rolling,
      trend: rolling == null || prev == null || _tail(10).length < 10 ? null : rolling - prev,
      splits500: List.unmodifiable(_splits500),
      history: List.unmodifiable(_strokes),
      elapsedChangedAt: _elapsedChangedAt,
      cue: _cue,
    );
    return _metrics;
  }

  List<StrokeSample> _tail(int n) =>
      _strokes.length <= n ? List.of(_strokes) : _strokes.sublist(_strokes.length - n);

  static Duration? _meanSplit(List<StrokeSample> strokes) {
    final splits = [for (final s in strokes) ?s.split];
    if (splits.isEmpty) return null;
    final total = splits.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return Duration(milliseconds: total ~/ splits.length);
  }

  void _record500s(double? distance, Duration elapsed) {
    final d0 = _lastDistance;
    final t0 = _lastElapsed;
    if (distance == null || d0 == null || t0 == null || distance <= d0 || elapsed <= t0) return;
    var next = (_splits500.length + 1) * 500.0;
    while (distance >= next) {
      if (next > d0) {
        final f = (next - d0) / (distance - d0);
        final at = t0 + (elapsed - t0) * f;
        _splits500.add(at - _lastMark);
        _lastMark = at;
      }
      next += 500;
    }
  }

  /// ON within ±0.5 s of target, with 0.2 s hysteresis so it doesn't flicker.
  static TargetCue? _nextCue(TargetCue? current, Duration? rolling, Duration? target) {
    if (rolling == null || target == null) return null;
    // Positive = faster than target.
    final diff = (target - rolling).inMilliseconds / 1000;
    const band = 0.5;
    const hysteresis = 0.2;
    switch (current) {
      case TargetCue.ahead:
        if (diff > band - hysteresis) return TargetCue.ahead;
      case TargetCue.behind:
        if (diff < -(band - hysteresis)) return TargetCue.behind;
      case TargetCue.on:
        if (diff.abs() <= band + hysteresis) return TargetCue.on;
      case null:
        break;
    }
    if (diff > band) return TargetCue.ahead;
    if (diff < -band) return TargetCue.behind;
    return TargetCue.on;
  }
}
