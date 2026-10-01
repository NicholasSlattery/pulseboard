import 'package:flutter/material.dart';

import '../models/app_settings.dart';

/// Colour tokens of the live (on-the-water) screens. "On the water" is the
/// default; "Daylight" is for direct sun. Neither reuses the HR zone
/// colours, which only appear as zone badges and %max bars.
@immutable
class LivePalette {
  const LivePalette({
    required this.brightness,
    required this.bg,
    required this.tile,
    required this.tileCompact,
    required this.line,
    required this.track,
    required this.hi,
    required this.mid,
    required this.lo,
    required this.rate,
    required this.ahead,
    required this.aheadBg,
    required this.behind,
    required this.behindBg,
    required this.onTarget,
    required this.onTargetBg,
    required this.ok,
    required this.warn,
    required this.warnBg,
    required this.danger,
    required this.dangerBg,
    required this.btn,
    required this.btnText,
    required this.primary,
    required this.onPrimary,
    required this.neutral,
  });

  final Brightness brightness;
  final Color bg;
  final Color tile;
  final Color tileCompact;
  final Color line;
  final Color track;
  final Color hi;
  final Color mid;
  final Color lo;
  final Color rate;
  final Color ahead;
  final Color aheadBg;
  final Color behind;
  final Color behindBg;
  final Color onTarget;
  final Color onTargetBg;
  final Color ok;
  final Color warn;
  final Color warnBg;
  final Color danger;
  final Color dangerBg;
  final Color btn;
  final Color btnText;
  final Color primary;
  final Color onPrimary;
  final Color neutral;

  static const water = LivePalette(
    brightness: Brightness.dark,
    bg: Color(0xFF07090B),
    tile: Color(0xFF12171B),
    tileCompact: Color(0xFF0C1013),
    line: Color(0xFF242D34),
    track: Color(0xFF232B31),
    hi: Color(0xFFFFFFFF),
    mid: Color(0xFFB4C0CA),
    lo: Color(0xFF8795A1),
    rate: Color(0xFFFFC23D),
    ahead: Color(0xFF7DBEFF),
    aheadBg: Color(0xFF0E2438),
    behind: Color(0xFFFF8C7F),
    behindBg: Color(0xFF3A1512),
    onTarget: Color(0xFFFFFFFF),
    onTargetBg: Color(0xFF1E262C),
    ok: Color(0xFF46C981),
    warn: Color(0xFFF5B82E),
    warnBg: Color(0xFF33270A),
    danger: Color(0xFFFF7A6B),
    dangerBg: Color(0xFF3A1512),
    btn: Color(0xFF1A2126),
    btnText: Color(0xFFFFFFFF),
    primary: Color(0xFFFFC23D),
    onPrimary: Color(0xFF1A1200),
    neutral: Color(0xFF3A444C),
  );

  static const daylight = LivePalette(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    tile: Color(0xFFEDF1F4),
    tileCompact: Color(0xFFFFFFFF),
    line: Color(0xFFCFD8DE),
    track: Color(0xFFD9E1E6),
    hi: Color(0xFF05090C),
    mid: Color(0xFF34414B),
    lo: Color(0xFF4F5D68),
    rate: Color(0xFF07587C),
    ahead: Color(0xFF1A5DAB),
    aheadBg: Color(0xFFDCEBFB),
    behind: Color(0xFFB42F24),
    behindBg: Color(0xFFFBE3E0),
    onTarget: Color(0xFF05090C),
    onTargetBg: Color(0xFFE2E8EC),
    ok: Color(0xFF1E7F47),
    warn: Color(0xFF7A5300),
    warnBg: Color(0xFFFCEFCB),
    danger: Color(0xFFB42F24),
    dangerBg: Color(0xFFFBE3E0),
    btn: Color(0xFFE2E8EC),
    btnText: Color(0xFF05090C),
    primary: Color(0xFF07587C),
    onPrimary: Color(0xFFFFFFFF),
    neutral: Color(0xFFB7C2CA),
  );

  static LivePalette of(LiveTheme theme) => theme == LiveTheme.daylight ? daylight : water;
}

/// Live-view type. Numbers are heavy with tabular figures so changing digits
/// never shift; labels are small, caps, letter-spaced.
abstract final class LiveType {
  static TextStyle number(double size, Color color, {FontWeight weight = FontWeight.w800}) =>
      TextStyle(
        fontSize: size,
        height: 0.95,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle label(double size, Color color, {FontWeight weight = FontWeight.w600}) =>
      TextStyle(
        fontSize: size,
        height: 1.1,
        fontWeight: weight,
        color: color,
        letterSpacing: size * 0.11,
      );

  static TextStyle body(double size, Color color, {FontWeight weight = FontWeight.w600}) =>
      TextStyle(fontSize: size, height: 1.2, fontWeight: weight, color: color);
}
