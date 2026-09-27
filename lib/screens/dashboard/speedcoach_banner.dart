import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../providers/speedcoach_provider.dart';
import '../../speedcoach/speedcoach_receiver.dart';
import '../../utils/formatters.dart';
import '../speedcoach/speedcoach_screen.dart';

/// Thin strip on the dashboard showing live SpeedCoach data while the
/// experimental receiver is running. Hidden otherwise.
class SpeedCoachBanner extends ConsumerWidget {
  const SpeedCoachBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(speedCoachStateProvider);
    if (s.status != SpeedCoachReceiverStatus.waiting &&
        s.status != SpeedCoachReceiverStatus.streaming) {
      return const SizedBox.shrink();
    }
    final live = s.isStreaming;
    final parts = live
        ? [
            if (s.strokeRate != null) '${SpeedCoachFormat.rate(s.strokeRate!)} spm',
            if (s.split != null) '${Fmt.duration(s.split!)} /500m',
            if (s.distanceMeters != null) '${s.distanceMeters!.round()} m',
            if (s.elapsed != null) Fmt.duration(s.elapsed!),
          ]
        : ['waiting for SpeedCoach…'];
    final color = live ? AppColors.info : AppColors.warning;
    return Material(
      color: color.withValues(alpha: 0.14),
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SpeedCoachScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.rowing, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'SPEEDCOACH',
                style: TextStyle(fontWeight: FontWeight.w800, color: color, letterSpacing: 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    parts.join('  ·  '),
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
