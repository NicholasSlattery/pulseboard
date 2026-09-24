/// Small, dependency-free formatting helpers.
abstract final class Fmt {
  /// 0:07, 12:34, 1:02:03
  static String duration(Duration d) {
    final negative = d.isNegative;
    final abs = d.abs();
    final h = abs.inHours;
    final m = abs.inMinutes.remainder(60);
    final s = abs.inSeconds.remainder(60);
    final body = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
    return negative ? '-$body' : body;
  }

  /// "1 h 05 min", "12 min", "45 s"
  static String durationWords(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours} h ${d.inMinutes.remainder(60).toString().padLeft(2, '0')} min';
    }
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '${d.inSeconds} s';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "Tue 23 Sep 2026, 06:05"
  static String dateTime(DateTime t) =>
      '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} ${t.year}, ${time(t)}';

  /// "06:05"
  static String time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Last [n] characters of an id, prefixed with an ellipsis when shortened.
  static String shortId(String id, [int n = 6]) =>
      id.length <= n ? id : '…${id.substring(id.length - n)}';

  static String percent(double fraction) => '${(fraction * 100).round()}%';
}

final RegExp _chunk = RegExp(r'(\d+)|(\D+)');

/// Case-insensitive "natural" comparison: "Rower 2" < "Rower 10".
int naturalCompare(String a, String b) {
  final ca = _chunk.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final cb = _chunk.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ca.length && i < cb.length; i++) {
    final na = int.tryParse(ca[i]);
    final nb = int.tryParse(cb[i]);
    final c = (na != null && nb != null) ? na.compareTo(nb) : ca[i].compareTo(cb[i]);
    if (c != 0) return c;
  }
  return ca.length.compareTo(cb.length);
}
