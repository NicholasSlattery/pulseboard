import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/connection_event.dart';
import 'package:pulseboard/models/training_session.dart';
import 'package:pulseboard/session/session_stats.dart';

void main() {
  final start = DateTime(2026, 9, 23, 6, 0, 0);
  const athlete = SessionAthlete(
    sessionId: 's',
    athleteId: 'a1',
    athleteName: 'Nicholas',
    sensorId: 'h10',
    maxHr: 200,
  );

  HeartRateSample sample(int secondsFromStart, int bpm, int? zone) => HeartRateSample(
    sessionId: 's',
    athleteId: 'a1',
    sensorId: 'h10',
    timestamp: start.add(Duration(seconds: secondsFromStart)),
    bpm: bpm,
    percentOfMax: bpm / 2,
    zone: zone,
  );

  AthleteSessionStats compute(
    List<HeartRateSample> samples, {
    List<SessionConnectionEvent> events = const [],
  }) => SessionStatsCalculator.compute(
    athlete: athlete,
    sessionStart: start,
    samples: samples,
    events: events,
    zoneCount: 5,
  );

  test('average, max and min HR', () {
    final stats = compute([
      sample(0, 100, 1),
      sample(1, 150, 3),
      sample(2, 170, 4),
      sample(3, 121, 2),
    ]);
    expect(stats.sampleCount, 4);
    expect(stats.averageHr, 135); // 541 / 4 = 135.25
    expect(stats.maxHr, 170);
    expect(stats.minHr, 100);
  });

  test('time in zones is attributed to the zone of the earlier sample', () {
    final stats = compute([
      sample(0, 120, 2), // covers 0-10s -> zone 2 (but capped by max gap)
      sample(4, 120, 2), // 4 s in zone 2
      sample(8, 165, 4), // 4 s in zone 4 until 12
      sample(12, 185, 5), // 2 s in zone 5 until 14
      sample(14, 185, 5), // last sample covers nothing
    ]);
    expect(stats.timeInZone[2], const Duration(seconds: 8));
    expect(stats.timeInZone[4], const Duration(seconds: 4));
    expect(stats.timeInZone[5], const Duration(seconds: 2));
    expect(stats.timeInZone[1], Duration.zero);
    expect(stats.recordedDuration, const Duration(seconds: 14));
    expect(stats.fractionInZone(2), closeTo(8 / 14, 1e-9));
    final total = stats.timeInZone.fold<Duration>(Duration.zero, (a, b) => a + b);
    expect(total, stats.recordedDuration);
  });

  test('gaps longer than the max sample gap are not counted as recorded time', () {
    final stats = compute([
      sample(0, 120, 2),
      sample(1, 120, 2),
      sample(60, 130, 2), // 59 s signal gap
      sample(61, 130, 2),
    ]);
    expect(stats.recordedDuration, const Duration(seconds: 2));
    expect(stats.timeInZone[2], const Duration(seconds: 2));
  });

  test('samples without zone are tracked separately', () {
    final stats = compute([sample(0, 100, null), sample(2, 100, null), sample(3, 100, 1)]);
    expect(stats.timeWithoutZone, const Duration(seconds: 3));
    expect(stats.recordedDuration, const Duration(seconds: 3));
  });

  test('unsorted input is handled', () {
    final stats = compute([sample(2, 100, 1), sample(0, 100, 1), sample(1, 100, 1)]);
    expect(stats.recordedDuration, const Duration(seconds: 2));
  });

  test('empty sample list', () {
    final stats = compute([]);
    expect(stats.hasData, isFalse);
    expect(stats.averageHr, isNull);
    expect(stats.recordedDuration, Duration.zero);
    expect(stats.fractionInZone(3), 0);
    expect(stats.timeline, isEmpty);
  });

  test('interruptions count only lost/data-timeout events of this athlete', () {
    SessionConnectionEvent ev(ConnectionEventType type, String? athleteId) =>
        SessionConnectionEvent(
          sessionId: 's',
          sensorId: 'h10',
          athleteId: athleteId,
          type: type,
          timestamp: start,
        );
    final stats = compute(
      [sample(0, 100, 1)],
      events: [
        ev(ConnectionEventType.lost, 'a1'),
        ev(ConnectionEventType.dataTimeout, 'a1'),
        ev(ConnectionEventType.connected, 'a1'),
        ev(ConnectionEventType.lost, 'someone-else'),
      ],
    );
    expect(stats.interruptions, 2);
  });

  test('timeline is downsampled to the limit', () {
    final samples = [for (var i = 0; i < 3600; i++) sample(i, 100 + i % 50, 1)];
    final stats = compute(samples);
    expect(stats.timeline.length, lessThanOrEqualTo(SessionStatsCalculator.maxTimelinePoints));
    expect(stats.timeline.first.offset, lessThan(const Duration(seconds: 10)));
    expect(stats.timeline.last.offset, greaterThan(const Duration(minutes: 59)));
  });
}
