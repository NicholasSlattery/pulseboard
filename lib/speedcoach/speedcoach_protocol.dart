import 'package:flutter/foundation.dart';

/// NK SpeedCoach live-streaming protocol, as far as it has been decoded.
///
/// Rate, split and stroke count were verified stroke-by-stroke against a
/// video of the SpeedCoach display (9/9 strokes exact).
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

  /// ~5 Hz status: position, distance, elapsed time.
  static const String liveStatusSuffix = '0103';

  /// One write per stroke: rate, speed, stroke count, ...
  static const String strokeSuffix = '0203';

  /// Written when a piece starts: SpeedCoach local date/time.
  static const String pieceStartSuffix = '0100';

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

/// Piece start (characteristic ...0100): sent when a piece starts, with the
/// SpeedCoach's local date and time.
@immutable
class SpeedCoachPieceStart {
  const SpeedCoachPieceStart({required this.startedAt, required this.raw});

  /// Local wall-clock time on the SpeedCoach.
  final DateTime startedAt;
  final Uint8List raw;

  /// Layout: second, minute, hour, day, month, year (uint16 LE), then
  /// unknown bytes (byte 10 was 3 in every capture).
  static SpeedCoachPieceStart? parse(List<int> bytes) {
    if (bytes.length < 7) return null;
    final data = Uint8List.fromList(bytes);
    final year = data[5] | (data[6] << 8);
    if (data[0] > 59 || data[1] > 59 || data[2] > 23 || data[3] < 1 || data[3] > 31) return null;
    if (data[4] < 1 || data[4] > 12 || year < 2000 || year > 2100) return null;
    return SpeedCoachPieceStart(
      startedAt: DateTime(year, data[4], data[3], data[2], data[1], data[0]),
      raw: data,
    );
  }
}

/// Decoded live-status packet (characteristic ...0103, ~5 per second).
///
/// | bytes | meaning                                        |
/// |-------|------------------------------------------------|
/// | 0-3   | latitude, int32 LE, degrees x 1e-7             |
/// | 4-7   | longitude, int32 LE, degrees x 1e-7            |
/// | 8-11  | distance in the current piece, uint32 LE, cm   |
/// | 12-15 | always zero so far                             |
/// | 16-19 | elapsed piece time, uint32 LE, milliseconds    |
@immutable
class SpeedCoachStatusPacket {
  const SpeedCoachStatusPacket({
    required this.elapsed,
    required this.distanceMeters,
    required this.raw,
    this.latitude,
    this.longitude,
  });

  /// Elapsed time of the current piece. Pauses when the piece is paused.
  final Duration elapsed;

  /// Distance covered in the current piece (GPS).
  final double distanceMeters;

  /// Last GPS position, or null when the SpeedCoach reports none.
  final double? latitude;
  final double? longitude;
  final Uint8List raw;

  /// Distance and time are both zero: no piece running / piece was reset.
  bool get isReset => distanceMeters == 0 && elapsed == Duration.zero;

  static SpeedCoachStatusPacket? parse(List<int> bytes) {
    if (bytes.length != 20) return null;
    final data = Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);
    final lat = view.getInt32(0, Endian.little);
    final lon = view.getInt32(4, Endian.little);
    final hasPosition = lat != 0 || lon != 0;
    return SpeedCoachStatusPacket(
      elapsed: Duration(milliseconds: view.getUint32(16, Endian.little)),
      distanceMeters: view.getUint32(8, Endian.little) / 100,
      latitude: hasPosition ? lat / 1e7 : null,
      longitude: hasPosition ? lon / 1e7 : null,
      raw: data,
    );
  }
}

/// Decoded per-stroke packet (characteristic ...0203), one per stroke.
///
/// | bytes | meaning                                                  |
/// |-------|----------------------------------------------------------|
/// | 0     | stroke rate x 2 (so half-stroke resolution: 57 = 28.5)   |
/// | 1     | 0xFF in every capture (probably heart rate: none paired) |
/// | 2-3   | speed, uint16 LE, cm/s (FFFF = no speed)                 |
/// | 4-5   | FFFF when no piece is running, else 0                    |
/// | 6-7   | distance per stroke, uint16 LE, cm                       |
/// | 10-11 | average speed for the piece, uint16 LE, cm/s             |
/// | 14    | stroke count in the piece (uint8)                        |
///
/// Rate, split (from speed) and stroke count were verified stroke-by-stroke
/// against the SpeedCoach display.
@immutable
class SpeedCoachStrokePacket {
  const SpeedCoachStrokePacket({
    required this.strokeCount,
    required this.strokeRate,
    required this.pieceRunning,
    required this.raw,
    this.speedCmPerSecond,
    this.distancePerStrokeCm,
    this.averageSpeedCmPerSecond,
  });

  /// Strokes in the current piece (single byte on the wire, so it wraps at
  /// 256; treat it as a counter, not an absolute total).
  final int strokeCount;

  /// Strokes per minute, in steps of 0.5 like the SpeedCoach display.
  final double strokeRate;

  /// False when the SpeedCoach is not in a piece (bytes 4-5 = FF FF).
  final bool pieceRunning;

  /// Boat speed in cm/s, or null when the SpeedCoach has none.
  final int? speedCmPerSecond;
  final int? distancePerStrokeCm;
  final int? averageSpeedCmPerSecond;
  final Uint8List raw;

  /// No speed: the SpeedCoach sends FF FF when the boat is stopped / no GPS.
  bool get isIdle => speedCmPerSecond == null;

  /// Time per 500 m at the current speed.
  Duration? get split => splitFor(speedCmPerSecond);

  /// Average time per 500 m for the piece.
  Duration? get averageSplit => splitFor(averageSpeedCmPerSecond);

  /// 500 m at [cmPerSecond]: 50 000 / speed seconds.
  static Duration? splitFor(int? cmPerSecond) {
    if (cmPerSecond == null || cmPerSecond <= 0) return null;
    return Duration(milliseconds: (50000000 / cmPerSecond).round());
  }

  static SpeedCoachStrokePacket? parse(List<int> bytes) {
    if (bytes.length != 20) return null;
    final data = Uint8List.fromList(bytes);
    int? u16(int i) {
      final v = data[i] | (data[i + 1] << 8);
      return v == 0xFFFF ? null : v;
    }

    return SpeedCoachStrokePacket(
      strokeCount: data[14],
      strokeRate: data[0] / 2,
      pieceRunning: !(data[4] == 0xFF && data[5] == 0xFF),
      speedCmPerSecond: u16(2),
      distancePerStrokeCm: u16(6),
      averageSpeedCmPerSecond: u16(10),
      raw: data,
    );
  }
}
