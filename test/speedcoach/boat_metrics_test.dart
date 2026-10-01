import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/speedcoach/boat_metrics.dart';
import 'package:pulseboard/speedcoach/speedcoach_receiver.dart';

SpeedCoachLiveState sc({
  int? strokes,
  double? rate,
  double split = 120,
  double? distance,
  int? elapsedMs,
  bool running = true,
  DateTime? last,
  SpeedCoachReceiverStatus status = SpeedCoachReceiverStatus.streaming,
}) => SpeedCoachLiveState(
  status: status,
  strokeCount: strokes,
  strokeRate: rate,
  split: Duration(milliseconds: (split * 1000).round()),
  distanceMeters: distance,
  elapsed: elapsedMs == null ? null : Duration(milliseconds: elapsedMs),
  pieceRunning: running,
  lastPacketAt: last,
  packetsReceived: 1,
);

void main() {
  final t0 = DateTime(2026, 9, 30, 7);

  test('unwraps the 8-bit stroke counter and averages the rate', () {
    final tracker = BoatTracker();
    var m = tracker.update(sc(strokes: 254, rate: 28), t0);
    m = tracker.update(sc(strokes: 255, rate: 29), t0.add(const Duration(seconds: 2)));
    m = tracker.update(sc(strokes: 0, rate: 30), t0.add(const Duration(seconds: 4)));
    m = tracker.update(sc(strokes: 1, rate: 29), t0.add(const Duration(seconds: 6)));
    expect(m.strokes, 257);
    expect(m.averageRate, closeTo(29, 0.001));
  });

  test('trend compares the last 5 strokes with the 5 before', () {
    final tracker = BoatTracker();
    late BoatMetrics m;
    for (var i = 0; i < 10; i++) {
      // 2:00 for five strokes, then 1:59.
      m = tracker.update(
        sc(strokes: i, rate: 28, split: i < 5 ? 120 : 119),
        t0.add(Duration(seconds: i * 2)),
      );
    }
    expect(m.trend, const Duration(seconds: -1));
    expect(m.rollingSplit, const Duration(seconds: 119));
  });

  test('records each completed 500 m by interpolating the crossing', () {
    final tracker = BoatTracker();
    tracker.update(sc(distance: 480, elapsedMs: 116000), t0);
    var m = tracker.update(
      sc(distance: 520, elapsedMs: 126000),
      t0.add(const Duration(seconds: 10)),
    );
    expect(m.splits500, [const Duration(seconds: 121)]);
    m = tracker.update(sc(distance: 1010, elapsedMs: 245000), t0.add(const Duration(seconds: 130)));
    expect(m.splits500.length, 2);
    expect(m.splits500[1].inMilliseconds, closeTo(121571, 5));
    expect(m.best500!.$1, 0);
  });

  test('target cue has hysteresis so it does not flicker', () {
    final tracker = BoatTracker();
    const target = Duration(seconds: 120);
    BoatMetrics row(double split, int i) => tracker.update(
      sc(strokes: i, rate: 28, split: split),
      t0.add(Duration(seconds: i * 2)),
      targetSplit: target,
    );
    var m = row(119.0, 0); // 1.0 s faster
    expect(m.cue, TargetCue.ahead);
    for (var i = 1; i <= 5; i++) {
      m = row(119.6, i); // 0.4 s faster: inside the band but within hysteresis
    }
    expect(m.cue, TargetCue.ahead);
    for (var i = 6; i <= 10; i++) {
      m = row(119.8, i); // 0.2 s faster
    }
    expect(m.cue, TargetCue.on);
    for (var i = 11; i <= 15; i++) {
      m = row(120.8, i);
    }
    expect(m.cue, TargetCue.behind);
  });

  test('a piece reset clears the tracker', () {
    final tracker = BoatTracker();
    tracker.update(sc(strokes: 10, rate: 28, distance: 600, elapsedMs: 140000), t0);
    final m = tracker.update(
      sc(strokes: 0, distance: 0, elapsedMs: 0, running: false),
      t0.add(const Duration(seconds: 2)),
    );
    expect(m.splits500, isEmpty);
    expect(m.averageRate, isNull);
  });

  group('phase', () {
    test('rowing, paused, idle, stale and lost', () {
      final tracker = BoatTracker();
      tracker.update(sc(elapsedMs: 1000, last: t0), t0);
      var m = tracker.update(sc(elapsedMs: 2000, last: t0), t0.add(const Duration(seconds: 1)));
      final now = t0.add(const Duration(seconds: 1));
      expect(boatPhase(sc(elapsedMs: 2000, last: now), m, now), BoatPhase.rowing);

      // Clock stopped for 3 s while packets keep coming: paused.
      final later = now.add(const Duration(seconds: 3));
      m = tracker.update(sc(elapsedMs: 2000, last: later), later);
      expect(boatPhase(sc(elapsedMs: 2000, last: later), m, later), BoatPhase.paused);
      expect(boatPhase(sc(elapsedMs: 2000, last: later, running: false), m, later), BoatPhase.idle);
      expect(boatPhase(sc(last: later), m, later.add(const Duration(seconds: 4))), BoatPhase.stale);
      expect(boatPhase(sc(last: later), m, later.add(const Duration(seconds: 20))), BoatPhase.lost);
      expect(boatPhase(const SpeedCoachLiveState(), m, later), BoatPhase.off);
      expect(
        boatPhase(const SpeedCoachLiveState(status: SpeedCoachReceiverStatus.waiting), m, later),
        BoatPhase.waiting,
      );
    });
  });
}
