import 'package:flutter/foundation.dart';

/// Formulas for estimating maximum heart rate from age.
enum MaxHrFormula {
  /// 220 - age (Fox). Simple, widely known, default.
  fox('220 − age'),

  /// 208 - 0.7 × age (Tanaka et al., 2001).
  tanaka('208 − 0.7 × age'),

  /// 207 - 0.7 × age (Gellish et al., 2007).
  gellish('207 − 0.7 × age');

  const MaxHrFormula(this.label);

  final String label;

  int estimate(int age) => switch (this) {
    MaxHrFormula.fox => 220 - age,
    MaxHrFormula.tanaka => (208 - 0.7 * age).round(),
    MaxHrFormula.gellish => (207 - 0.7 * age).round(),
  };
}

/// A configurable percentage-of-max-HR zone model.
///
/// [lowerBoundsPercent] holds the inclusive lower bound of each zone in
/// ascending order: zone N starts at `lowerBoundsPercent[N-1]` and extends up
/// to (but not including) the next zone's lower bound. The top zone is open
/// ended (e.g. 90-100%+). Values below the first bound are zone 0 ("below
/// zone 1"). The number of zones is simply the list length, so a 3- or 7-zone
/// model needs no architecture change.
@immutable
class ZoneModel {
  const ZoneModel(this.lowerBoundsPercent);

  /// Default five-zone model: 50/60/70/80/90 %.
  static const ZoneModel standard = ZoneModel([50, 60, 70, 80, 90]);

  final List<double> lowerBoundsPercent;

  int get zoneCount => lowerBoundsPercent.length;

  /// Tolerance used when comparing against bounds so that values which are
  /// mathematically exactly on a boundary (e.g. 117/195 = 60%) are not pushed
  /// into the lower zone by floating-point rounding.
  static const double _epsilon = 1e-9;

  /// Returns 0 (below zone 1) through [zoneCount].
  int zoneForPercent(double percentOfMax) {
    var zone = 0;
    for (var i = 0; i < lowerBoundsPercent.length; i++) {
      if (percentOfMax + _epsilon >= lowerBoundsPercent[i]) {
        zone = i + 1;
      } else {
        break;
      }
    }
    return zone;
  }

  /// Zone for a heart rate given a max HR, or null if max HR is unknown.
  int? zoneForHeartRate(int bpm, int? maxHr) {
    final pct = percentOfMax(bpm, maxHr);
    return pct == null ? null : zoneForPercent(pct);
  }

  /// Human-readable range for zone [zone] (1-based), e.g. "80–90%".
  String rangeLabel(int zone) {
    if (zone < 1 || zone > zoneCount) return '';
    final lo = _fmt(lowerBoundsPercent[zone - 1]);
    if (zone == zoneCount) return '$lo%+';
    return '$lo–${_fmt(lowerBoundsPercent[zone])}%';
  }

  /// Validates bounds: non-empty, strictly ascending, within 1-200 %.
  static String? validate(List<double> bounds) {
    if (bounds.isEmpty) return 'At least one zone is required.';
    for (var i = 0; i < bounds.length; i++) {
      if (bounds[i] <= 0 || bounds[i] >= 200) {
        return 'Zone ${i + 1} must be between 1% and 199%.';
      }
      if (i > 0 && bounds[i] <= bounds[i - 1]) {
        return 'Zone ${i + 1} must start above zone $i.';
      }
    }
    return null;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  bool operator ==(Object other) =>
      other is ZoneModel && listEquals(other.lowerBoundsPercent, lowerBoundsPercent);

  @override
  int get hashCode => Object.hashAll(lowerBoundsPercent);
}

/// Whole-number percentage for display. Floors (with the same tolerance as
/// zone lookup) so the shown value never contradicts the zone: 89.7% shows
/// as 89% next to "ZONE 4", never as 90%.
int displayPercent(double percentOfMax) => (percentOfMax + 1e-9).floor();

/// Percentage of max HR, or null when max HR is unknown or invalid.
double? percentOfMax(int bpm, int? maxHr) {
  if (maxHr == null || maxHr <= 0) return null;
  return bpm * 100.0 / maxHr;
}
