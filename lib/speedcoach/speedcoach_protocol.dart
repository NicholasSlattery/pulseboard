import 'package:flutter/foundation.dart';

/// NK SpeedCoach live-streaming protocol, as far as it has been decoded.
///
/// NK does not publish this protocol. Everything here was worked out from a
/// Bluetooth capture of a SpeedCoach GPS Pro (firmware 2.25) streaming to NK
/// LiNK Logbook - see docs/SPEEDCOACH.md. Fields not listed are unknown.
///
/// Roles are the reverse of a heart-rate strap: the PHONE is the Bluetooth
/// peripheral (GATT server). It advertises [SpeedCoachUuids.service]; the
/// SpeedCoach (Live Streaming -> Phone Pairing -> Find New) scans for it,
/// connects, and WRITES its live data into the phone's characteristics.
abstract final class SpeedCoachUuids {
  static const String service = '3291ddee-0889-409c-b993-24ec00009970';

  /// All 18 characteristics NK LiNK exposes, in its order. Every one is
  /// readable and writable.
  static const List<String> suffixes = [
    '0100', '0101', '0201', '0301', '0102', '0202', '0302', '0402', '0502', //
    '0103', '0203', '0303', '0403', '0104', '0005', '1005', '2005', '0002',
  ];

  static String char(String suffix) => '3291ddee-0889-409c-b993-24ec${suffix}9970';

  /// ~5 Hz status: bytes 16-19 = elapsed piece time (ms).
  static const String liveStatusSuffix = '0103';

  /// One write per stroke: byte 14 = stroke count.
  static const String strokeSuffix = '0203';

  /// SpeedCoach writes its serial number (ASCII) here when it connects.
  static const String serialSuffix = '1005';

  /// SpeedCoach reads the boat name (ASCII) from here.
  static const String boatNameSuffix = '0005';

  /// SpeedCoach reads this every ~10 s; NK LiNK answers 01 00 00... while
  /// streaming is switched on.
  static const String streamControlSuffix = '2005';

  /// Returns the 4-hex-digit suffix if [uuid] is one of NK's characteristics.
  static String? suffixOf(String uuid) {
    final u = uuid.toLowerCase();
    if (!u.startsWith('3291ddee-0889-409c-b993-24ec') || u.length != 36) return null;
    if (!u.endsWith('9970')) return null;
    return u.substring(28, 32);
  }
}

/// Advertised local names used by NK LiNK.
abstract final class SpeedCoachNames {
  /// Name a phone advertises so a SpeedCoach doing "Find New" pairs with it.
  static const String pairing = 'NK LiNKp';
}

/// Decoded live-status packet (characteristic ...0103, ~5 per second).
@immutable
class SpeedCoachStatusPacket {
  const SpeedCoachStatusPacket({required this.elapsed, required this.raw});

  /// Elapsed time of the current piece. Pauses when the piece is paused.
  final Duration elapsed;

  /// Full packet. Bytes 0-7 look like the last GPS position; bytes 8-15 were
  /// all zero indoors (probably speed/distance). Not decoded yet.
  final Uint8List raw;

  static SpeedCoachStatusPacket? parse(List<int> bytes) {
    if (bytes.length != 20) return null;
    final data = Uint8List.fromList(bytes);
    final ms = ByteData.sublistView(data).getUint32(16, Endian.little);
    return SpeedCoachStatusPacket(
      elapsed: Duration(milliseconds: ms),
      raw: data,
    );
  }
}

/// Decoded per-stroke packet (characteristic ...0203).
@immutable
class SpeedCoachStrokePacket {
  const SpeedCoachStrokePacket({
    required this.strokeCount,
    required this.isIdle,
    required this.raw,
  });

  /// Strokes in the current piece (single byte on the wire, so it wraps at
  /// 256; callers should treat it as a counter, not an absolute total).
  final int strokeCount;

  /// The SpeedCoach sends a marker with bytes 2-3 and 6-7 = FF FF when the
  /// rower has stopped.
  final bool isIdle;
  final Uint8List raw;

  static SpeedCoachStrokePacket? parse(List<int> bytes) {
    if (bytes.length != 20) return null;
    final data = Uint8List.fromList(bytes);
    final idle = data[2] == 0xFF && data[3] == 0xFF && data[6] == 0xFF && data[7] == 0xFF;
    return SpeedCoachStrokePacket(strokeCount: data[14], isIdle: idle, raw: data);
  }
}

/// Estimates stroke rate from the arrival times of per-stroke packets.
///
/// The decoded protocol does not (yet) contain the SpeedCoach's own rate
/// field, so rate is calculated: 60 / median of the last few stroke
/// intervals. Bluetooth delivery jitter is tens of milliseconds, i.e. about
/// 1-2 % at rowing rates.
class StrokeRateEstimator {
  StrokeRateEstimator({this.window = 4, this.maxGap = const Duration(seconds: 10)});

  final int window;

  /// A pause longer than this starts a fresh estimate.
  final Duration maxGap;

  final List<Duration> _intervals = [];
  DateTime? _lastStrokeAt;
  int? _lastCount;

  /// Current estimate in strokes per minute, or null if unknown.
  double? get rate {
    if (_intervals.isEmpty) return null;
    final sorted = [..._intervals]..sort();
    final mid = sorted.length ~/ 2;
    final medianMs = sorted.length.isOdd
        ? sorted[mid].inMilliseconds.toDouble()
        : (sorted[mid - 1].inMilliseconds + sorted[mid].inMilliseconds) / 2;
    if (medianMs <= 0) return null;
    return 60000 / medianMs;
  }

  void addStroke(int count, DateTime at) {
    final lastAt = _lastStrokeAt;
    final lastCount = _lastCount;
    _lastStrokeAt = at;
    _lastCount = count;
    if (lastAt == null || lastCount == null) return;
    final gap = at.difference(lastAt);
    final advanced = (count - lastCount) & 0xFF;
    if (gap > maxGap || gap <= Duration.zero || advanced != 1) {
      // Pause, reset or missed strokes: start over.
      _intervals.clear();
      return;
    }
    _intervals.add(gap);
    if (_intervals.length > window) _intervals.removeAt(0);
  }

  void reset() {
    _intervals.clear();
    _lastStrokeAt = null;
    _lastCount = null;
  }
}
