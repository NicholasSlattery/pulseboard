import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/live_theme.dart';
import '../../models/app_settings.dart';
import '../../providers/boat_provider.dart';
import '../../speedcoach/boat_metrics.dart';
import 'boat_view.dart';
import 'live_common.dart';
import 'live_widgets.dart';

/// Split, rate, distance and elapsed, readable from across the boat. Extras:
/// the connection dot and, with a target split, the ahead/on/behind band.
/// No scrolling, lists or sparklines.
class SimpleView extends ConsumerWidget {
  const SimpleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final mode = ref.read(liveViewModeProvider.notifier);
    return LayoutBuilder(
      builder: (context, c) {
        final landscape = c.maxWidth > c.maxHeight && c.maxHeight < 560;
        return Ticking(
          builder: (context, now) {
            final b = watchBoatView(ref, now);
            final (dotLabel, dotColor) = switch (b.phase) {
              BoatPhase.rowing => ('LIVE', p.ok),
              BoatPhase.idle => ('LIVE · NO PIECE', p.ok),
              BoatPhase.paused => ('PAUSED', p.warn),
              BoatPhase.stale => ('NO DATA', p.warn),
              BoatPhase.lost => ('DISCONNECTED', p.danger),
              BoatPhase.waiting => ('WAITING FOR SPEEDCOACH', p.warn),
              BoatPhase.off => ('SPEEDCOACH OFF', p.lo),
            };
            final band = b.band(p, height: landscape ? 52 : 64, textSize: landscape ? 26 : 30);
            final numbers = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => mode.show(LiveViewMode.crew),
              child: Opacity(
                opacity: b.dimmed ? 0.28 : 1,
                child: landscape ? _LandscapeNumbers(boat: b) : _PortraitNumbers(boat: b),
              ),
            );
            final buttons = [
              Expanded(
                child: LiveButton(
                  icon: Icons.grid_view_rounded,
                  label: 'Full data',
                  vertical: false,
                  fontSize: 18,
                  radius: 18,
                  onPressed: () => mode.show(LiveViewMode.crew),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HoldToStopButton(
                  vertical: false,
                  fontSize: 18,
                  radius: 18,
                  showDuration: true,
                  onStop: () => stopCrewSession(context, ref),
                ),
              ),
            ];
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 24,
                    child: StatusDot(color: dotColor, label: dotLabel, size: 14),
                  ),
                  if (band != null) ...[const SizedBox(height: 12), band],
                  const SizedBox(height: 12),
                  Expanded(child: numbers),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: landscape ? 56 : 80,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.unit, required this.value, required this.color});

  final String label;
  final String unit;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: LiveType.label(16, p.lo, weight: FontWeight.w700)),
            const Spacer(),
            Text(unit, style: LiveType.body(16, p.lo, weight: FontWeight.w700)),
          ],
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: LiveType.number(140, color)),
          ),
        ),
      ],
    );
  }
}

class _Small extends StatelessWidget {
  const _Small({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LiveType.label(14, p.lo, weight: FontWeight.w700)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: LiveType.number(56, p.hi)),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: LiveType.body(18, p.lo, weight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PortraitNumbers extends StatelessWidget {
  const _PortraitNumbers({required this.boat});

  final BoatView boat;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Big(label: 'SPLIT', unit: '/500m', value: boat.split, color: p.hi),
        ),
        Divider(height: 20, color: p.line),
        Expanded(
          child: _Big(label: 'RATE', unit: 'spm', value: boat.rate, color: p.rate),
        ),
        Divider(height: 28, color: p.line),
        Row(
          children: [
            Expanded(
              child: _Small(label: 'DISTANCE', value: boat.distance, unit: 'm'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Small(label: 'ELAPSED', value: boat.elapsed),
            ),
          ],
        ),
      ],
    );
  }
}

class _LandscapeNumbers extends StatelessWidget {
  const _LandscapeNumbers({required this.boat});

  final BoatView boat;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _Big(label: 'SPLIT', unit: '/500m', value: boat.split, color: p.hi),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: _Big(label: 'RATE', unit: 'spm', value: boat.rate, color: p.rate),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Small(label: 'DISTANCE', value: boat.distance, unit: 'm'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Small(label: 'ELAPSED', value: boat.elapsed),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
