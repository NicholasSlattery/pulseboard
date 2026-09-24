import 'package:flutter/foundation.dart';

import '../models/connection_event.dart';
import '../models/training_session.dart';

/// One point on a downsampled HR timeline.
@immutable
class TimelinePoint {
  const TimelinePoint(this.offset, this.bpm);

  /// Time since session start.
  final Duration offset;
  final int bpm;
}

/// Summary statistics for one athlete in one session.
@immutable
class AthleteSessionStats {
  const AthleteSessionStats({
    required this.athleteId,
    required this.athleteName,
    required this.sampleCount,
    required this.averageHr,
    required this.maxHr,
    required this.minHr,
    required this.recordedDuration,
    required this.timeInZone,
    required this.timeWithoutZone,
    required this.interruptions,
    required this.timeline,
  });

  final String athleteId;
  final String athleteName;
  final int sampleCount;

  /// Null when there are no samples.
  final int? averageHr;
  final int? maxHr;
  final int? minHr;

  /// Time covered by samples (gaps longer than
  /// [SessionStatsCalculator.maxSampleGap] are excluded).
  final Duration recordedDuration;

  /// Index 0 = below zone 1, index N = zone N.
  final List<Duration> timeInZone;

  /// Time covered by samples recorded without a known max HR.
  final Duration timeWithoutZone;

  /// Number of unexpected connection losses during the session.
  final int interruptions;
  final List<TimelinePoint> timeline;

  bool get hasData => sampleCount > 0;

  /// Fraction (0-1) of recorded time spent in [zone].
  double fractionInZone(int zone) {
    if (recordedDuration == Duration.zero || zone < 0 || zone >= timeInZone.length) return 0;
    return timeInZone[zone].inMilliseconds / recordedDuration.inMilliseconds;
  }
}

/// Pure functions computing per-athlete session statistics.
abstract final class SessionStatsCalculator {
  /// A sample "covers" the time until the next sample, up to this cap.
  /// Anything longer is a signal gap and is not counted as recorded time.
  static const Duration maxSampleGap = Duration(seconds: 5);

  /// Maximum number of points kept for the timeline chart.
  static const int maxTimelinePoints = 600;

  /// [samples] must belong to one athlete; they are sorted defensively.
  static AthleteSessionStats compute({
    required SessionAthlete athlete,
    required DateTime sessionStart,
    required List<HeartRateSample> samples,
    required List<SessionConnectionEvent> events,
    required int zoneCount,
  }) {
    final sorted = [...samples]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final zoneMs = List<int>.filled(zoneCount + 1, 0);
    var noZoneMs = 0;
    var recordedMs = 0;
    var sum = 0;
    int? maxHr;
    int? minHr;

    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      sum += s.bpm;
      maxHr = maxHr == null || s.bpm > maxHr ? s.bpm : maxHr;
      minHr = minHr == null || s.bpm < minHr ? s.bpm : minHr;

      if (i == sorted.length - 1) break;
      final gapMs = sorted[i + 1].timestamp.difference(s.timestamp).inMilliseconds;
      if (gapMs <= 0 || gapMs > maxSampleGap.inMilliseconds) continue;
      recordedMs += gapMs;
      final zone = s.zone;
      if (zone == null) {
        noZoneMs += gapMs;
      } else {
        zoneMs[zone.clamp(0, zoneCount)] += gapMs;
      }
    }

    final interruptions = events
        .where(
          (e) =>
              e.athleteId == athlete.athleteId &&
              (e.type == ConnectionEventType.lost || e.type == ConnectionEventType.dataTimeout),
        )
        .length;

    return AthleteSessionStats(
      athleteId: athlete.athleteId,
      athleteName: athlete.athleteName,
      sampleCount: sorted.length,
      averageHr: sorted.isEmpty ? null : (sum / sorted.length).round(),
      maxHr: maxHr,
      minHr: minHr,
      recordedDuration: Duration(milliseconds: recordedMs),
      timeInZone: zoneMs.map((ms) => Duration(milliseconds: ms)).toList(growable: false),
      timeWithoutZone: Duration(milliseconds: noZoneMs),
      interruptions: interruptions,
      timeline: downsample(sorted, sessionStart, maxTimelinePoints),
    );
  }

  /// Averages samples into at most [maxPoints] equal-count buckets.
  static List<TimelinePoint> downsample(
    List<HeartRateSample> sorted,
    DateTime sessionStart,
    int maxPoints,
  ) {
    if (sorted.isEmpty || maxPoints <= 0) return const [];
    final bucketSize = (sorted.length / maxPoints).ceil().clamp(1, sorted.length);
    final points = <TimelinePoint>[];
    for (var i = 0; i < sorted.length; i += bucketSize) {
      final end = (i + bucketSize).clamp(0, sorted.length);
      var sum = 0;
      for (var j = i; j < end; j++) {
        sum += sorted[j].bpm;
      }
      final mid = sorted[(i + end - 1) ~/ 2];
      points.add(TimelinePoint(mid.timestamp.difference(sessionStart), (sum / (end - i)).round()));
    }
    return points;
  }
}
