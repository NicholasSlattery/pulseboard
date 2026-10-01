import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/boat_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/crew_session_provider.dart';
import '../../providers/lineup_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/speedcoach_provider.dart';
import '../../speedcoach/speedcoach_receiver.dart';
import '../../widgets/bluetooth_status_banner.dart';
import '../../widgets/common.dart';
import '../../widgets/strap_status.dart';
import '../speedcoach/speedcoach_screen.dart';
import 'targets_dialog.dart';

/// The Live tab before Start: a ready check of the SpeedCoach, each seat's
/// strap and the targets.
class ReadyView extends ConsumerWidget {
  const ReadyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simulated = ref.watch(bootstrapProvider.select((b) => b.isSimulated));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              'Not recording',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (simulated) const SimulatedDataBanner(),
          const BluetoothStatusBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 20, maxWidth: 560),
                    child: const IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SpeedCoachCard(),
                          SizedBox(height: 12),
                          _LineupCard(),
                          SizedBox(height: 12),
                          _TargetsCard(),
                          SizedBox(height: 24),
                          Spacer(),
                          _StartButton(),
                          SizedBox(height: 8),
                          _StartCaption(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _SpeedCoachCard extends ConsumerWidget {
  const _SpeedCoachCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = ref.watch(speedCoachStateProvider);
    final serial = s.serial ?? ref.watch(settingsProvider.select((x) => x.speedCoachSerial));
    final (text, color) = switch (s.status) {
      SpeedCoachReceiverStatus.stopped => ('Not started', AppColors.neutral),
      SpeedCoachReceiverStatus.starting => ('Starting…', AppColors.warning),
      SpeedCoachReceiverStatus.waiting => ('Waiting for SpeedCoach', AppColors.warning),
      SpeedCoachReceiverStatus.streaming => (
        s.pieceRunning ? 'Receiving · piece running' : 'Receiving · no piece running',
        AppColors.connected,
      ),
      SpeedCoachReceiverStatus.unsupported => ('Not supported on this device', AppColors.danger),
      SpeedCoachReceiverStatus.error => ('Error · ${s.error ?? ''}', AppColors.danger),
    };
    return _ReadyCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.speed, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serial == null ? 'SpeedCoach' : 'SpeedCoach $serial',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _Dot(color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const SpeedCoachScreen())),
            child: const Text('Setup'),
          ),
        ],
      ),
    );
  }
}

(Color, String?) _strapState(WidgetRef ref, String athleteId) {
  final s = watchStrapStatus(ref, athleteId);
  return (s.color, s.problem);
}

class _LineupCard extends ConsumerWidget {
  const _LineupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lineup = ref.watch(activeLineupProvider);
    final strokeFirst = ref.watch(lineupBookProvider.select((b) => b.strokeFirst));
    final names = {for (final a in ref.watch(athletesProvider)) a.id: a.displayName};
    void editSeats() => ref.read(homeTabProvider.notifier).go(HomeTab.lineup);

    if (lineup == null || lineup.isEmpty) {
      final roster = ref.watch(rosterProvider);
      return _ReadyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No lineup yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              roster.isEmpty
                  ? 'Set the crew in Lineup, then assign each rower a strap in Sensors.'
                  : '${roster.length} rower${roster.length == 1 ? '' : 's'} with straps. '
                        'Seat them in Lineup to show the crew in seat order.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: editSeats,
              icon: const Icon(Icons.format_list_numbered),
              label: const Text('Set up lineup'),
            ),
          ],
        ),
      );
    }

    final order = [for (var n = 1; n <= lineup.seatCount; n++) n];
    final seats = strokeFirst ? order.reversed.toList() : order;
    final states = <int, (Color, String?)>{
      for (final n in order)
        if (lineup.seats[n - 1] != null) n: _strapState(ref, lineup.seats[n - 1]!),
    };
    final seated = states.length;
    final live = states.values.where((s) => s.$1 == AppColors.connected).length;
    final problems = [
      for (final n in seats)
        if (states[n]?.$2 != null)
          '${lineup.roleOf(n) == 'SEAT' ? 'Seat $n' : _title(lineup.roleOf(n))} · '
              '${names[lineup.seats[n - 1]]} ${states[n]!.$2}',
      for (final n in seats)
        if (lineup.seats[n - 1] == null) 'Seat $n is empty',
    ];
    final cox = lineup.coxId == null ? null : names[lineup.coxId];

    return _ReadyCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${lineup.boatClass.label} · ${lineup.name}',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '$live of $seated straps live',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: live == seated ? const Color(0xFF1E6B3F) : const Color(0xFF7A5300),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(onPressed: editSeats, child: const Text('Edit seats')),
            ],
          ),
          const SizedBox(height: 12),
          for (var r = 0; r < seats.length; r += 4) ...[
            if (r > 0) const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = r; i < r + 4; i++) ...[
                    if (i > r) const SizedBox(width: 8),
                    Expanded(
                      child: i >= seats.length
                          ? const SizedBox.shrink()
                          : _SeatTile(
                              seat: seats[i],
                              name: lineup.seats[seats[i] - 1] == null
                                  ? 'Empty'
                                  : (names[lineup.seats[seats[i] - 1]] ?? '?'),
                              color: states[seats[i]]?.$1 ?? Colors.transparent,
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: _Dot(problems.isEmpty ? AppColors.connected : AppColors.danger),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (problems.isEmpty)
                      'Every seat has a live strap.'
                    else
                      '${problems.join('. ')}.',
                    if (lineup.boatClass.cox)
                      cox == null ? 'No cox set.' : 'Cox $cox: HR not shown.',
                  ].join(' '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _title(String role) => role[0] + role.substring(1).toLowerCase();
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({required this.seat, required this.name, required this.color});

  final int seat;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bad = color == AppColors.danger;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: bad ? AppColors.danger.withValues(alpha: 0.10) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: bad ? AppColors.danger.withValues(alpha: 0.45) : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                '$seat',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              _Dot(color),
            ],
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _TargetsCard extends ConsumerWidget {
  const _TargetsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    return _ReadyCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Targets',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  targetsSummary(settings),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () => showTargetsDialog(context, ref), child: const Text('Edit')),
        ],
      ),
    );
  }
}

class _StartButton extends ConsumerWidget {
  const _StartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 60,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18),
        ),
        onPressed: () => _start(context, ref),
        icon: const Icon(Icons.play_arrow_rounded, size: 26),
        label: const Text('Start session'),
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final sc = ref.read(speedCoachStateProvider).status;
    final speedCoachOn =
        sc == SpeedCoachReceiverStatus.streaming || sc == SpeedCoachReceiverStatus.waiting;
    if (ref.read(rosterProvider).isEmpty && !speedCoachOn) {
      showSnack(context, 'Assign a strap to a rower in Sensors, or start the SpeedCoach first.');
      return;
    }
    try {
      ref.read(liveViewModeProvider.notifier).show(ref.read(settingsProvider).liveViewMode);
      await ref.read(crewSessionProvider.notifier).start();
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not start session: $e');
    }
  }
}

class _StartCaption extends ConsumerWidget {
  const _StartCaption();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sc = ref.watch(speedCoachStateProvider.select((s) => s.status));
    final withBoat =
        sc == SpeedCoachReceiverStatus.streaming || sc == SpeedCoachReceiverStatus.waiting;
    return Text(
      withBoat ? 'Records heart rate and SpeedCoach together.' : 'Records heart rate.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}
