import 'dart:io';

import 'package:path/path.dart' as p;

import '../app/app_info.dart';
import '../models/heart_rate_measurement.dart';
import '../models/training_session.dart';
import '../storage/session_repository.dart';

/// Writes session samples as RFC 4180 CSV (comma separated, CRLF line
/// endings, fields quoted when needed) - opens cleanly in Excel, Google
/// Sheets, Numbers and pandas.
///
/// Columns:
/// * `timestamp` - ISO 8601 UTC with milliseconds
/// * `elapsed_s` - seconds since session start (3 decimals)
/// * `session_id`, `athlete_name`, `athlete_id`, `sensor_id`
/// * `heart_rate_bpm`
/// * `percent_max_hr` - empty when the athlete had no max HR
/// * `zone` - 0 = below zone 1, empty when no max HR
/// * `rr_interval_ms` - RR intervals in ms (1 decimal); multiple intervals in
///   one notification are separated by spaces
class CsvExporter {
  CsvExporter(this._repository);

  final SessionRepository _repository;

  static const List<String> header = [
    'timestamp',
    'elapsed_s',
    'session_id',
    'athlete_name',
    'athlete_id',
    'sensor_id',
    'heart_rate_bpm',
    'percent_max_hr',
    'zone',
    'rr_interval_ms',
  ];

  /// Writes the CSV into [directory] and returns the file. Streams rows
  /// page by page so multi-hour sessions don't need to fit in memory.
  Future<File> exportSession(String sessionId, Directory directory) async {
    final session = await _repository.getSession(sessionId);
    if (session == null) throw StateError('Session $sessionId not found');
    final athletes = {
      for (final a in await _repository.getSessionAthletes(sessionId)) a.athleteId: a,
    };

    final file = File(p.join(directory.path, fileNameFor(session)));
    final sink = file.openWrite();
    try {
      sink.write(formatRow(header));
      await for (final page in _repository.streamSamples(sessionId)) {
        final buffer = StringBuffer();
        for (final s in page) {
          buffer.write(formatSample(s, session, athletes[s.athleteId]?.athleteName ?? ''));
        }
        sink.write(buffer);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  }

  static String fileNameFor(TrainingSession session) {
    final t = session.startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${AppInfo.exportFilePrefix}_${t.year}-${two(t.month)}-${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}.csv';
  }

  static String formatSample(HeartRateSample s, TrainingSession session, String athleteName) {
    final elapsed = s.timestamp.difference(session.startedAt).inMilliseconds / 1000.0;
    return formatRow([
      s.timestamp.toUtc().toIso8601String(),
      elapsed.toStringAsFixed(3),
      s.sessionId,
      athleteName,
      s.athleteId,
      s.sensorId,
      s.bpm.toString(),
      s.percentOfMax?.toStringAsFixed(1) ?? '',
      s.zone?.toString() ?? '',
      s.rrIntervals1024
          .map((rr) => HeartRateMeasurement.rrToMilliseconds(rr).toStringAsFixed(1))
          .join(' '),
    ]);
  }

  static String formatRow(List<String> fields) => '${fields.map(escape).join(',')}\r\n';

  /// Quotes a field if it contains a comma, quote, CR or LF, or starts with
  /// a character spreadsheets would interpret as a formula.
  static String escape(String field) {
    var value = field;
    // Guard against CSV/formula injection via athlete names.
    if (value.isNotEmpty && '=+-@'.contains(value[0]) && double.tryParse(value) == null) {
      value = "'$value";
    }
    final needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
