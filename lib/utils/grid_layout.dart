import 'dart:math';
import 'dart:ui';

import '../models/app_settings.dart';

/// Result of the dashboard grid computation.
class GridSpec {
  const GridSpec({required this.columns, required this.cardHeight, required this.fitsOnScreen});

  final int columns;
  final double cardHeight;

  /// True when every card is visible without scrolling.
  final bool fitsOnScreen;

  @override
  String toString() =>
      'GridSpec($columns cols, ${cardHeight.toStringAsFixed(1)}h, fits: $fitsOnScreen)';
}

/// Chooses columns and card height for [count] athlete cards in [size].
///
/// * `auto` (coach tablet mode) searches every column count and picks the
///   one giving the biggest readable cards with everything on screen. If even
///   the best option would be too small to read, it falls back to scrolling.
/// * `large` / `compact` use fixed target sizes and scroll.
abstract final class DashboardGrid {
  static const double spacing = 12;
  static const double minReadableHeight = 128;
  static const double largeTargetWidth = 330;
  static const double largeHeight = 220;
  static const double compactTargetWidth = 180;
  static const double compactHeight = 156;

  /// Preferred card width/height ratio.
  static const double idealAspect = 1.45;

  static GridSpec compute({
    required int count,
    required Size size,
    required DashboardDensity density,
  }) {
    final width = max(0.0, size.width);
    final height = max(0.0, size.height);
    if (count <= 0 || width <= 0) {
      return const GridSpec(columns: 1, cardHeight: largeHeight, fitsOnScreen: true);
    }

    switch (density) {
      case DashboardDensity.large:
        return _fixed(count, width, height, largeTargetWidth, largeHeight);
      case DashboardDensity.compact:
        return _fixed(count, width, height, compactTargetWidth, compactHeight);
      case DashboardDensity.auto:
        break;
    }

    var bestColumns = 1;
    var bestHeight = 0.0;
    var bestScore = -1.0;
    for (var columns = 1; columns <= count; columns++) {
      final cardWidth = (width - spacing * (columns - 1)) / columns;
      if (cardWidth <= 0) break;
      final rows = (count / columns).ceil();
      final availableHeight = (height - spacing * (rows - 1)) / rows;
      // Don't stretch cards into tall slivers; cap by the ideal aspect.
      final cardHeight = min(availableHeight, cardWidth / idealAspect * 1.25);
      // Score by the size of a card of ideal aspect that fits the cell.
      final score = min(cardWidth / idealAspect, cardHeight);
      if (score > bestScore) {
        bestScore = score;
        bestColumns = columns;
        bestHeight = cardHeight;
      }
    }

    if (bestHeight >= minReadableHeight) {
      return GridSpec(columns: bestColumns, cardHeight: bestHeight, fitsOnScreen: true);
    }
    return _fixed(count, width, height, compactTargetWidth, compactHeight);
  }

  static GridSpec _fixed(
    int count,
    double width,
    double height,
    double targetWidth,
    double cardHeight,
  ) {
    final columns = max(1, ((width + spacing) / (targetWidth + spacing)).floor());
    final rows = (count / columns).ceil();
    final total = rows * cardHeight + (rows - 1) * spacing;
    return GridSpec(columns: columns, cardHeight: cardHeight, fitsOnScreen: total <= height);
  }
}
