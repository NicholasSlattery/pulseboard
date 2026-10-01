import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/live_theme.dart';
import '../../speedcoach/boat_metrics.dart';

/// Gives the live views their palette.
class LiveScope extends InheritedWidget {
  const LiveScope({super.key, required this.palette, required super.child});

  final LivePalette palette;

  static LivePalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiveScope>()?.palette ?? LivePalette.water;

  @override
  bool updateShouldNotify(LiveScope oldWidget) => oldWidget.palette != palette;
}

/// Rebuilds [builder] every [period] with the current time, for ages and
/// staleness. Only the widgets inside rebuild.
class Ticking extends StatefulWidget {
  const Ticking({
    super.key,
    required this.builder,
    this.period = const Duration(milliseconds: 500),
  });

  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration period;

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.period, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, clock.now());
}

enum TileSize { hero, large, compact }

/// The one number tile of the live views: hero (split, rate), large (tier 2)
/// and compact (tier 3). Values scale down instead of clipping on small
/// phones; tabular figures keep them from jittering.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.size,
    required this.label,
    required this.value,
    this.unit,
    this.unitInLabel = false,
    this.valueColor,
    this.calculated = false,
    this.dimmed = false,
    this.valueSize,
    this.background,
    this.foreground,
  });

  final TileSize size;
  final String label;
  final String value;
  final String? unit;

  /// Shows the unit at the right of the label row (hero style) instead of
  /// after the value.
  final bool unitInLabel;
  final Color? valueColor;

  /// Adds the CALC tag: value is computed in the app, not sent by the
  /// SpeedCoach.
  final bool calculated;

  /// Stale data: numbers drop to 28% opacity so nobody trusts them.
  final bool dimmed;
  final double? valueSize;
  final Color? background;

  /// Overrides label and value colour (target tile).
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final (radius, pad, labelSize, numSize, unitSize) = switch (size) {
      TileSize.hero => (16.0, const EdgeInsets.fromLTRB(12, 9, 12, 10), 12.0, 66.0, 12.0),
      TileSize.large => (12.0, const EdgeInsets.fromLTRB(10, 8, 10, 9), 11.0, 32.0, 13.0),
      TileSize.compact => (12.0, const EdgeInsets.fromLTRB(9, 6, 9, 7), 10.5, 24.0, 11.0),
    };
    final fg = foreground;
    final labelColor = fg ?? p.lo;
    final compact = size == TileSize.compact;
    return Semantics(
      label: '$label ${value == RowDash.value ? 'no data' : value}${unit == null ? '' : ' $unit'}',
      excludeSemantics: true,
      child: Container(
        padding: pad,
        decoration: BoxDecoration(
          color: background ?? (compact ? p.tileCompact : p.tile),
          borderRadius: BorderRadius.circular(radius),
          border: compact && background == null ? Border.all(color: p.line) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: LiveType.label(
                        labelSize,
                        labelColor,
                        weight: fg != null ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (calculated) ...[const SizedBox(width: 5), const CalcTag()],
                if (unitInLabel && unit != null) ...[
                  const Spacer(),
                  Text(unit!, style: LiveType.body(labelSize, labelColor)),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Opacity(
              opacity: dimmed ? 0.28 : 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      style: LiveType.number(valueSize ?? numSize, fg ?? valueColor ?? p.hi),
                    ),
                    if (!unitInLabel && unit != null) ...[
                      const SizedBox(width: 3),
                      Text(unit!, style: LiveType.body(unitSize, fg ?? p.lo)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder used by tiles for "no data".
abstract final class RowDash {
  static const value = '--';
}

/// Small outlined "CALC" tag for app-computed values.
class CalcTag extends StatelessWidget {
  const CalcTag({super.key});

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        border: Border.all(color: p.lo),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('CALC', style: LiveType.label(8.5, p.lo, weight: FontWeight.w700)),
    );
  }
}

/// Coloured dot + caps label for the status bar.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, required this.label, this.size = 12});

  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size * 0.75,
          height: size * 0.75,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: size * 0.5),
        Text(label, style: LiveType.label(size, color, weight: FontWeight.w700)),
      ],
    );
  }
}

/// A big flat button of the live views (icon above or beside its label).
class LiveButton extends StatelessWidget {
  const LiveButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.vertical = true,
    this.color,
    this.background,
    this.fontSize = 13,
    this.radius = 14,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool vertical;
  final Color? color;
  final Color? background;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final fg = color ?? p.btnText;
    final children = [
      Icon(icon, size: vertical ? 22 : 20, color: fg),
      SizedBox(width: vertical ? 0 : 8, height: vertical ? 2 : 0),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LiveType.body(fontSize, fg, weight: FontWeight.w700),
        ),
      ),
    ];
    return Material(
      color: background ?? p.btn,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onPressed,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: vertical
                ? Column(mainAxisSize: MainAxisSize.min, children: children)
                : Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// Stop that needs a deliberate 1 s hold: the ring fills while held, so a
/// wet hand or a bump can't end the session.
class HoldToStopButton extends StatefulWidget {
  const HoldToStopButton({
    super.key,
    required this.onStop,
    this.label = 'Hold to stop',
    this.vertical = true,
    this.fontSize = 13,
    this.radius = 14,
    this.showDuration = false,
  });

  final VoidCallback onStop;
  final String label;
  final bool vertical;
  final double fontSize;
  final double radius;
  final bool showDuration;

  @override
  State<HoldToStopButton> createState() => _HoldToStopButtonState();
}

class _HoldToStopButtonState extends State<HoldToStopButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      HapticFeedback.heavyImpact();
      _hold.value = 0;
      widget.onStop();
    }
  }

  void _release() {
    if (_hold.isAnimating && _hold.value < 1) {
      _hold.animateBack(0, duration: const Duration(milliseconds: 150));
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Hold for 1 second to stop'),
            duration: Duration(milliseconds: 1500),
          ),
        );
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final ring = AnimatedBuilder(
      animation: _hold,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.vertical ? 24 : 28),
        painter: _RingPainter(progress: _hold.value, color: p.danger),
      ),
    );
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.vertical ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          maxLines: 1,
          style: LiveType.body(widget.fontSize, p.danger, weight: FontWeight.w700),
        ),
        if (widget.showDuration)
          Text('1 second', style: LiveType.body(12, p.danger.withValues(alpha: 0.8))),
      ],
    );
    return Semantics(
      button: true,
      label: '${widget.label}, hold for one second',
      onLongPress: widget.onStop,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _hold.forward(from: _hold.value),
        onTapUp: (_) => _release(),
        onTapCancel: _release,
        child: Container(
          decoration: BoxDecoration(
            color: p.btn,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: p.danger, width: 2),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: widget.vertical
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [ring, const SizedBox(height: 2), label],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [ring, const SizedBox(width: 10), label],
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 1.5;
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = color.withValues(alpha: 0.35);
    canvas.drawCircle(c, r, stroke);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        stroke
          ..color = color
          ..strokeCap = StrokeCap.round,
      );
    }
    final side = r * 0.85;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: side, height: side),
        const Radius.circular(1.5),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

/// 60 s sparkline: 2 px line, dot on the latest point, 1 px baseline.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color, this.invert = false});

  /// Oldest first; nulls are gaps.
  final List<double?> values;
  final Color color;

  /// Plot higher values lower (split: faster is up).
  final bool invert;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    return CustomPaint(
      painter: _SparkPainter(values: values, color: color, base: p.line, invert: invert),
      size: Size.infinite,
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.color,
    required this.base,
    required this.invert,
  });

  final List<double?> values;
  final Color color;
  final Color base;
  final bool invert;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = base
        ..strokeWidth = 1,
    );
    final pts = [for (final v in values) ?v];
    if (pts.length < 2) return;
    var lo = pts.reduce(math.min);
    var hi = pts.reduce(math.max);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    double y(double v) {
      var f = (v - lo) / (hi - lo);
      if (invert) f = 1 - f;
      return 3 + (size.height - 6) * (1 - f);
    }

    final path = Path();
    Offset? last;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = 3 + (size.width - 6) * (values.length == 1 ? 1 : i / (values.length - 1));
      final o = Offset(x, y(v));
      if (last == null) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
      last = o;
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    if (last != null) canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color || old.invert != invert;
}

/// Full-width message band under the heroes: target cue, or the data state.
class StateBand extends StatelessWidget {
  const StateBand({
    super.key,
    required this.icon,
    required this.text,
    this.trailing,
    required this.foreground,
    required this.background,
    this.height = 44,
    this.textSize = 17,
    this.border,
  });

  final IconData? icon;
  final String text;
  final String? trailing;
  final Color foreground;
  final Color background;
  final double height;
  final double textSize;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: border == null ? null : Border.all(color: border!, width: 2),
      ),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, color: foreground, size: 22), const SizedBox(width: 8)],
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                style: LiveType.body(textSize, foreground, weight: FontWeight.w800),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: LiveType.body(
                14,
                foreground,
                weight: FontWeight.w700,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Text and colours for the target cue band.
(String, Color, Color) cueStyle(TargetCue cue, Duration? rolling, Duration target, LivePalette p) {
  final diff = rolling == null ? Duration.zero : target - rolling;
  final secs = (diff.inMilliseconds.abs() / 1000).toStringAsFixed(1);
  return switch (cue) {
    TargetCue.ahead => ('▲ AHEAD $secs s', p.ahead, p.aheadBg),
    TargetCue.on => ('◆ ON TARGET', p.onTarget, p.onTargetBg),
    TargetCue.behind => ('▼ BEHIND $secs s', p.behind, p.behindBg),
  };
}
