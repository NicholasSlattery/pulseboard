/// Formats rowing values the way the SpeedCoach shows them. Null always
/// becomes a dash, never 0 or blank.
abstract final class RowFmt {
  static const dash = '--';
  static const splitDash = '--:--';

  /// 1:58.4 (m:ss.t).
  static String split(Duration? d) {
    if (d == null || d <= Duration.zero) return splitDash;
    final tenths = (d.inMilliseconds / 100).round();
    final m = tenths ~/ 600;
    final s = (tenths % 600) ~/ 10;
    return '$m:${s.toString().padLeft(2, '0')}.${tenths % 10}';
  }

  /// 7:12.3, or 1:07:12.3 past an hour.
  static String elapsed(Duration? d) {
    if (d == null) return dash;
    final tenths = d.inMilliseconds ~/ 100;
    final h = tenths ~/ 36000;
    final m = (tenths % 36000) ~/ 600;
    final s = (tenths % 600) ~/ 10;
    final ss = s.toString().padLeft(2, '0');
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:$ss.${tenths % 10}'
        : '$m:$ss.${tenths % 10}';
  }

  /// 28.5 -> "28.5", 28.0 -> "28".
  static String rate(double? spm) {
    if (spm == null) return dash;
    return spm == spm.roundToDouble() ? spm.toStringAsFixed(0) : spm.toStringAsFixed(1);
  }

  /// Average rate: always one decimal (28.1).
  static String averageRate(double? spm) => spm == null ? dash : spm.toStringAsFixed(1);

  /// 1,240 (whole metres with a thousands separator).
  static String distance(double? meters) => meters == null ? dash : thousands(meters.round());

  static String thousands(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// 9.6 (one decimal).
  static String meters1(double? m) => m == null ? dash : m.toStringAsFixed(1);

  /// Boat speed in m/s from a split: 4.23.
  static String speed(Duration? split) {
    if (split == null || split <= Duration.zero) return dash;
    return (500 / (split.inMilliseconds / 1000)).toStringAsFixed(2);
  }

  /// Seconds with one decimal, no sign: 0.6.
  static String seconds1(Duration d) => (d.inMilliseconds.abs() / 1000).toStringAsFixed(1);

  /// Signed seconds: +0.7 / −0.2.
  static String signedSeconds(Duration d) {
    final v = d.inMilliseconds / 1000;
    final s = v.abs().toStringAsFixed(1);
    if (s == '0.0') return '0.0';
    return v < 0 ? '−$s' : '+$s';
  }

  /// Parses "1:59.0", "1:59" or "119" (seconds) into a split.
  static Duration? parseSplit(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(?:(\d+):)?(\d{1,2}(?:\.\d)?)$').firstMatch(t);
    if (m == null) return null;
    final minutes = int.tryParse(m.group(1) ?? '0') ?? 0;
    final seconds = double.tryParse(m.group(2)!) ?? 0;
    if (m.group(1) != null && seconds >= 60) return null;
    final ms = ((minutes * 60 + seconds) * 1000).round();
    return ms > 0 ? Duration(milliseconds: ms) : null;
  }

  /// Parses "20:00" or "20" (minutes) into a duration.
  static Duration? parseClock(String text) {
    final t = text.trim();
    final m = RegExp(r'^(\d+)(?::(\d{1,2}))?$').firstMatch(t);
    if (m == null) return null;
    if (m.group(2) == null) {
      final minutes = int.parse(m.group(1)!);
      return minutes > 0 ? Duration(minutes: minutes) : null;
    }
    final s = int.parse(m.group(2)!);
    if (s >= 60) return null;
    final d = Duration(minutes: int.parse(m.group(1)!), seconds: s);
    return d > Duration.zero ? d : null;
  }
}
