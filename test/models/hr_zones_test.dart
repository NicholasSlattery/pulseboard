import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/athlete.dart';
import 'package:pulseboard/models/hr_zones.dart';

void main() {
  const zones = ZoneModel.standard;

  group('ZoneModel.zoneForPercent exact boundaries', () {
    final cases = <double, int>{
      0: 0,
      49.9: 0,
      50: 1,
      59.9: 1,
      60: 2,
      69.9: 2,
      70: 3,
      79.9: 3,
      80: 4,
      89.9: 4,
      90: 5,
      99.9: 5,
      100: 5,
      112: 5,
    };
    cases.forEach((pct, zone) {
      test('$pct% -> zone $zone', () => expect(zones.zoneForPercent(pct), zone));
    });
  });

  group('ZoneModel.zoneForHeartRate', () {
    test('exact boundary with floating-point division is not pushed down', () {
      // 117 / 195 = 0.6 exactly in math, but not in binary floating point.
      expect(zones.zoneForHeartRate(117, 195), 2);
      expect(zones.zoneForHeartRate(116, 195), 1);
      // 70% of 190 = 133
      expect(zones.zoneForHeartRate(133, 190), 3);
      expect(zones.zoneForHeartRate(132, 190), 2);
      // 90% of 200 = 180
      expect(zones.zoneForHeartRate(180, 200), 5);
      expect(zones.zoneForHeartRate(179, 200), 4);
    });

    test('returns null without a max HR', () {
      expect(zones.zoneForHeartRate(150, null), isNull);
      expect(zones.zoneForHeartRate(150, 0), isNull);
    });
  });

  group('ZoneModel configuration', () {
    test('custom 3-zone model', () {
      const custom = ZoneModel([60, 75, 88]);
      expect(custom.zoneCount, 3);
      expect(custom.zoneForPercent(74.9), 1);
      expect(custom.zoneForPercent(75), 2);
      expect(custom.zoneForPercent(95), 3);
    });

    test('range labels', () {
      expect(zones.rangeLabel(1), '50–60%');
      expect(zones.rangeLabel(5), '90%+');
      expect(zones.rangeLabel(0), '');
      expect(const ZoneModel([55.5, 70]).rangeLabel(1), '55.5–70%');
    });

    test('validation', () {
      expect(ZoneModel.validate([50, 60, 70, 80, 90]), isNull);
      expect(ZoneModel.validate([]), isNotNull);
      expect(ZoneModel.validate([50, 50, 70]), isNotNull);
      expect(ZoneModel.validate([60, 50]), isNotNull);
      expect(ZoneModel.validate([0, 50]), isNotNull);
    });
  });

  group('Max HR', () {
    test('formulas', () {
      expect(MaxHrFormula.fox.estimate(25), 195);
      expect(MaxHrFormula.tanaka.estimate(25), 191); // 208 - 17.5 = 190.5 -> 191
      expect(MaxHrFormula.gellish.estimate(40), 179);
    });

    Athlete athlete({int? age, int? maxHr}) => Athlete(
      id: 'x',
      name: 'Test',
      age: age,
      maxHrOverride: maxHr,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('manual override wins over age estimate', () {
      expect(athlete(age: 25, maxHr: 201).effectiveMaxHr(MaxHrFormula.fox), 201);
    });

    test('age estimate used when no override', () {
      expect(athlete(age: 20).effectiveMaxHr(MaxHrFormula.fox), 200);
    });

    test('null when neither age nor override is known', () {
      expect(athlete().effectiveMaxHr(MaxHrFormula.fox), isNull);
    });
  });
}
