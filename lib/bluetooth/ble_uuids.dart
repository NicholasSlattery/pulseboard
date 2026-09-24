/// Bluetooth SIG assigned numbers used by the app, as lower-case 128-bit
/// UUID strings (the form every platform layer normalises to).
abstract final class BleUuids {
  /// Heart Rate Service (0x180D).
  static final String heartRateService = fromShort(0x180D);

  /// Heart Rate Measurement characteristic (0x2A37) - notify only.
  static final String heartRateMeasurement = fromShort(0x2A37);

  /// Body Sensor Location characteristic (0x2A38) - optional read.
  static final String bodySensorLocation = fromShort(0x2A38);

  /// Battery Service (0x180F).
  static final String batteryService = fromShort(0x180F);

  /// Battery Level characteristic (0x2A19) - uint8 percentage.
  static final String batteryLevel = fromShort(0x2A19);

  static const String _baseSuffix = '-0000-1000-8000-00805f9b34fb';

  /// Expands a 16-bit assigned number to the full Bluetooth base UUID.
  static String fromShort(int value) => '${value.toRadixString(16).padLeft(8, '0')}$_baseSuffix';

  /// Normalises any UUID representation ("180D", "0x180d", "0000180D-...",
  /// or 32 hex chars without dashes) to lower-case 128-bit form. Returns the
  /// trimmed lower-case input unchanged if it is not recognisable.
  static String normalize(String uuid) {
    var s = uuid.trim().toLowerCase();
    if (s.startsWith('0x')) s = s.substring(2);
    if (s.length == 4 || s.length == 8) {
      final value = int.tryParse(s, radix: 16);
      if (value != null) {
        return '${s.padLeft(8, '0')}$_baseSuffix';
      }
    }
    if (s.length == 32 && !s.contains('-')) {
      return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
          '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
    }
    return s;
  }

  static bool equal(String a, String b) => normalize(a) == normalize(b);
}
