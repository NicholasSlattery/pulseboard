import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/app_settings.dart';
import 'package:pulseboard/models/hr_zones.dart';
import 'package:pulseboard/utils/formatters.dart';
import 'package:pulseboard/utils/grid_layout.dart';

void main() {
  group('DashboardGrid auto-fit', () {
    const ipadLandscape = Size(1100, 740);
    const phonePortrait = Size(406, 700);

    GridSpec auto(int n, Size s) =>
        DashboardGrid.compute(count: n, size: s, density: DashboardDensity.auto);

    test('one athlete gets one big card', () {
      final spec = auto(1, ipadLandscape);
      expect(spec.columns, 1);
      expect(spec.fitsOnScreen, isTrue);
      expect(spec.cardHeight, greaterThan(400));
    });

    test('8 and 12 athletes fit on an iPad without scrolling', () {
      for (final n in [4, 8, 12]) {
        final spec = auto(n, ipadLandscape);
        expect(spec.fitsOnScreen, isTrue, reason: '$n athletes');
        expect(spec.cardHeight, greaterThanOrEqualTo(DashboardGrid.minReadableHeight));
        expect(spec.columns * ((n / spec.columns).ceil()), greaterThanOrEqualTo(n));
      }
    });

    test('20+ athletes fall back to readable scrolling cards when needed', () {
      final spec = auto(24, phonePortrait);
      expect(spec.fitsOnScreen, isFalse);
      expect(spec.cardHeight, DashboardGrid.compactHeight);
      expect(spec.columns, 2);
    });

    test('never returns zero columns', () {
      expect(auto(5, const Size(50, 50)).columns, greaterThanOrEqualTo(1));
      expect(auto(0, ipadLandscape).columns, 1);
    });
  });

  group('DashboardGrid fixed densities', () {
    test('large and compact column counts', () {
      final large = DashboardGrid.compute(
        count: 10,
        size: const Size(1100, 740),
        density: DashboardDensity.large,
      );
      final compact = DashboardGrid.compute(
        count: 10,
        size: const Size(1100, 740),
        density: DashboardDensity.compact,
      );
      expect(large.columns, 3);
      expect(compact.columns, greaterThan(large.columns));
    });
  });

  group('displayPercent', () {
    test('floors so the number never contradicts the zone', () {
      expect(displayPercent(49.7), 49);
      expect(displayPercent(89.99), 89);
      expect(displayPercent(90.0), 90);
      // 117/195 is 60% mathematically; floating point must not show 59.
      expect(displayPercent(percentOfMax(117, 195)!), 60);
    });
  });

  group('Fmt', () {
    test('durations', () {
      expect(Fmt.duration(const Duration(seconds: 7)), '0:07');
      expect(Fmt.duration(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(Fmt.duration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(Fmt.durationWords(const Duration(minutes: 65)), '1 h 05 min');
    });

    test('natural sort', () {
      final names = ['Rower 10', 'rower 2', 'Rower 1', 'Ava'];
      names.sort(naturalCompare);
      expect(names, ['Ava', 'Rower 1', 'rower 2', 'Rower 10']);
    });

    test('short ids', () {
      expect(Fmt.shortId('ABC'), 'ABC');
      expect(Fmt.shortId('0123456789'), '…456789');
    });
  });
}
