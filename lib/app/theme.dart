import 'package:flutter/material.dart';

/// Colours and themes. Zone colours are always paired with the zone number
/// in the UI; colour is never the only signal.
abstract final class AppColors {
  static const Color seed = Color(0xFF0B6E99);

  static const Color connected = Color(0xFF2E9E5B);
  static const Color warning = Color(0xFFE0A100);
  static const Color danger = Color(0xFFD64545);
  static const Color neutral = Color(0xFF7A8794);
  static const Color info = Color(0xFF3B82C4);

  /// Index 0 = below zone 1.
  static const List<Color> zones = [
    Color(0xFF5F6B76), // below zone 1
    Color(0xFF8FA3B3), // Z1 very light - grey
    Color(0xFF2F80ED), // Z2 light - blue
    Color(0xFF27AE60), // Z3 moderate - green
    Color(0xFFF2994A), // Z4 hard - orange
    Color(0xFFEB3B3B), // Z5 maximum - red
  ];

  static Color zone(int? zone) {
    if (zone == null) return neutral;
    if (zone < zones.length) return zones[zone.clamp(0, zones.length - 1)];
    return zones.last;
  }

  /// Readable text colour on top of a zone colour.
  static Color onZone(int? zone) =>
      ThemeData.estimateBrightnessForColor(AppColors.zone(zone)) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}
