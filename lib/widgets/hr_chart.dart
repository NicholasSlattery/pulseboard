import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../session/session_stats.dart';
import '../utils/formatters.dart';

/// Minimal HR-over-time line chart with zone-coloured background bands.
/// Hand-drawn with CustomPainter to avoid a charting dependency.
class HrChart extends StatelessWidget {
  const HrChart({
    super.key,
    required this.points,
    required this.duration,
    this.maxHr,
    this.zoneBoundsPercent = const [],
    this.height = 140,
  });

  final List<TimelinePoint> points;
  final Duration duration;
  final int? maxHr;
  final List<double> zoneBoundsPercent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(child: Text('Not enough data for a chart', style: theme.textTheme.bodySmall)),
      );
    }
    return Semantics(
      label: 'Heart rate chart',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _HrChartPainter(
            points: points,
            duration: duration,
            maxHr: maxHr,
            zoneBounds: zoneBoundsPercent,
            lineColor: theme.colorScheme.primary,
            gridColor: theme.colorScheme.outlineVariant,
            labelStyle: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _HrChartPainter extends CustomPainter {
  _HrChartPainter({
    required this.points,
    required this.duration,
    required this.maxHr,
    required this.zoneBounds,
    required this.lineColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<TimelinePoint> points;
  final Duration duration;
  final int? maxHr;
  final List<double> zoneBounds;
  final Color lineColor;
  final Color gridColor;
  final TextStyle labelStyle;

  static const double _leftPad = 30;
  static const double _bottomPad = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTRB(_leftPad, 4, size.width, size.height - _bottomPad);
    var minBpm = points.first.bpm;
    var maxBpm = points.first.bpm;
    for (final p in points) {
      if (p.bpm < minBpm) minBpm = p.bpm;
      if (p.bpm > maxBpm) maxBpm = p.bpm;
    }
    final lo = ((minBpm - 10) / 10).floor() * 10.0;
    final hi = ((maxBpm + 10) / 10).ceil() * 10.0;
    final totalMs = duration.inMilliseconds <= 0
        ? points.last.offset.inMilliseconds.toDouble()
        : duration.inMilliseconds.toDouble();

    double y(double bpm) => chart.bottom - (bpm - lo) / (hi - lo) * chart.height;
    double x(Duration offset) =>
        chart.left + (totalMs <= 0 ? 0 : offset.inMilliseconds / totalMs) * chart.width;

    // Zone bands.
    if (maxHr != null && zoneBounds.isNotEmpty) {
      for (var z = 0; z < zoneBounds.length; z++) {
        final from = maxHr! * zoneBounds[z] / 100;
        final to = z + 1 < zoneBounds.length ? maxHr! * zoneBounds[z + 1] / 100 : hi;
        final top = y(to.clamp(lo, hi));
        final bottom = y(from.clamp(lo, hi));
        if (bottom <= top) continue;
        canvas.drawRect(
          Rect.fromLTRB(chart.left, top, chart.right, bottom),
          Paint()..color = AppColors.zone(z + 1).withValues(alpha: 0.12),
        );
      }
    }

    // Horizontal grid + labels.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    final step = (hi - lo) > 80 ? 40.0 : 20.0;
    for (var v = lo; v <= hi; v += step) {
      canvas.drawLine(Offset(chart.left, y(v)), Offset(chart.right, y(v)), gridPaint);
      _text(canvas, v.toInt().toString(), Offset(0, y(v) - 6));
    }
    _text(canvas, '0:00', Offset(chart.left, chart.bottom + 2));
    final endLabel = Fmt.duration(Duration(milliseconds: totalMs.round()));
    _text(canvas, endLabel, Offset(chart.right - endLabel.length * 6.0, chart.bottom + 2));

    // Line.
    final path = Path()..moveTo(x(points.first.offset), y(points.first.bpm.toDouble()));
    for (final p in points.skip(1)) {
      path.lineTo(x(p.offset), y(p.bpm.toDouble()));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _text(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _HrChartPainter old) =>
      old.points != points || old.lineColor != lineColor || old.maxHr != maxHr;
}
