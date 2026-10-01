import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../providers/speedcoach_provider.dart';
import '../../speedcoach/speedcoach_protocol.dart';
import '../../speedcoach/speedcoach_receiver.dart';
import '../../utils/formatters.dart';
import '../../utils/rowing_format.dart';
import '../../widgets/common.dart';
import '../live/targets_dialog.dart';

/// Experimental: receive live data from an NK SpeedCoach by acting as
/// NK LiNK Logbook.
class SpeedCoachScreen extends ConsumerWidget {
  const SpeedCoachScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(speedCoachStateProvider);
    final waiting =
        (state.status == SpeedCoachReceiverStatus.waiting ||
            state.status == SpeedCoachReceiverStatus.starting) &&
        state.packetsReceived == 0;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('SpeedCoach'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Experimental',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      body: waiting ? _Waiting(state: state) : _Setup(state: state),
    );
  }
}

(String, Color) _statusOf(SpeedCoachLiveState s) => switch (s.status) {
  SpeedCoachReceiverStatus.stopped => ('Not started', AppColors.neutral),
  SpeedCoachReceiverStatus.starting => ('Starting…', AppColors.warning),
  SpeedCoachReceiverStatus.waiting =>
    s.packetsReceived == 0
        ? ('Waiting for SpeedCoach', AppColors.warning)
        : ('No data · last update ${_age(s)}', AppColors.warning),
  SpeedCoachReceiverStatus.streaming => ('Receiving data', AppColors.connected),
  SpeedCoachReceiverStatus.unsupported => ('Not supported on this device', AppColors.danger),
  SpeedCoachReceiverStatus.error => ('Error', AppColors.danger),
};

String _age(SpeedCoachLiveState s) {
  final last = s.lastPacketAt;
  if (last == null) return '';
  return '${DateTime.now().difference(last).inSeconds} s ago';
}

bool _running(SpeedCoachLiveState s) =>
    s.status == SpeedCoachReceiverStatus.waiting ||
    s.status == SpeedCoachReceiverStatus.streaming ||
    s.status == SpeedCoachReceiverStatus.starting;

class _Setup extends ConsumerStatefulWidget {
  const _Setup({required this.state});

  final SpeedCoachLiveState state;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  late final TextEditingController _boatName = TextEditingController(
    text: ref.read(settingsProvider).speedCoachBoatName,
  );

  @override
  void dispose() {
    _boatName.dispose();
    super.dispose();
  }

  Future<void> _saveBoatName() async {
    final name = _boatName.text.trim();
    if (name.isEmpty) return;
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(speedCoachBoatName: name));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final serial = settings.speedCoachSerial;
    final controller = ref.read(speedCoachStateProvider.notifier);
    final running = _running(state);
    final (statusText, statusColor) = _statusOf(state);
    TextStyle? section() =>
        theme.textTheme.labelLarge?.copyWith(letterSpacing: 0.8, color: scheme.onSurfaceVariant);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusText,
                style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(state.error!, style: const TextStyle(color: AppColors.danger)),
          ),
        if (state.isStreaming) ...[const SizedBox(height: 12), _LiveStrip(state: state)],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connect in three steps', style: theme.textTheme.titleMedium),
              const SizedBox(height: 14),
              const _Step(n: 1, text: 'Close NK LiNK Logbook on this phone.'),
              const _Step(n: 2, text: 'Tap Start and keep PulseBoard open.'),
              const _Step(
                n: 3,
                text: 'On the SpeedCoach, choose Live Streaming › Phone Pairing › Find New.',
                note: 'First time only. Once paired, just switch Live Streaming on.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _boatName,
          decoration: const InputDecoration(
            labelText: 'Boat name',
            helperText: 'Sent to the SpeedCoach when you start.',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _saveBoatName(),
          onEditingComplete: _saveBoatName,
        ),
        const SizedBox(height: 22),
        Text('PAIRED SPEEDCOACH', style: section()),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
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
                      serial == null ? 'No SpeedCoach paired yet' : 'Paired SpeedCoach $serial',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      'Remembered automatically when a SpeedCoach connects',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (serial != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: controller.forgetSpeedCoach,
                  child: const Text('Forget'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => controller.start(pairNew: true),
          icon: const Icon(Icons.add),
          label: const Text('Pair a new SpeedCoach'),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: Text('TARGETS', style: section())),
            Text(
              'Optional',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(targetsSummary(settings)),
          subtitle: const Text('With a target split, the live views show ahead, on or behind.'),
          trailing: TextButton(
            onPressed: () => showTargetsDialog(context, ref),
            child: const Text('Edit'),
          ),
        ),
        const SizedBox(height: 14),
        Text('OPEN IN', style: section()),
        const SizedBox(height: 10),
        SegmentedButton<LiveViewMode>(
          segments: [
            for (final m in LiveViewMode.values) ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {settings.liveViewMode},
          showSelectedIcon: false,
          onSelectionChanged: (v) =>
              ref.read(settingsProvider.notifier).edit((s) => s.copyWith(liveViewMode: v.first)),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: running
              ? OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: controller.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18),
                  ),
                  onPressed: () => controller.start(),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start'),
                ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Advanced · raw packets'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const RawPacketsScreen())),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text, this.note});

  final int n;
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: theme.textTheme.bodyLarge),
                  if (note != null)
                    Text(
                      note!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick check that data is arriving: the decoded values in one row.
class _LiveStrip extends StatelessWidget {
  const _LiveStrip({required this.state});

  final SpeedCoachLiveState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget value(String label, String v, String unit) => Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1)),
          FittedBox(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(unit, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            value('RATE', RowFmt.rate(state.strokeRate), 'spm'),
            value('SPLIT', RowFmt.split(state.split), '/500m'),
            value('DISTANCE', RowFmt.distance(state.distanceMeters), 'm'),
            value('STROKES', state.strokeCount?.toString() ?? RowFmt.dash, ''),
          ],
        ),
      ),
    );
  }
}

class _Waiting extends ConsumerWidget {
  const _Waiting({required this.state});

  final SpeedCoachLiveState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = state.advertisedName ?? SpeedCoachNames.pairing;
    Widget ring(double size, Color color, Widget child) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: child,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.info, width: 2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Waiting · ${state.packetsReceived} packets',
              style: theme.textTheme.titleSmall?.copyWith(color: AppColors.info),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: ring(
            200,
            scheme.primary.withValues(alpha: 0.15),
            ring(
              144,
              scheme.primary.withValues(alpha: 0.35),
              CircleAvatar(
                radius: 44,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.bluetooth_searching, size: 40),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Waiting for SpeedCoach',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'PulseBoard is advertising as',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              name == SpeedCoachNames.pairing ? '$name (pairing)' : name,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On the SpeedCoach', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              const _WaitRow(
                label: 'First time',
                text: 'Live Streaming › Phone Pairing › Find New',
              ),
              const SizedBox(height: 8),
              const _WaitRow(label: 'Paired before', text: 'Switch Live Streaming on'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Keep PulseBoard open while it waits.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            onPressed: ref.read(speedCoachStateProvider.notifier).stop,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

class _WaitRow extends StatelessWidget {
  const _WaitRow({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// The raw packet log, for protocol decoding work.
class RawPacketsScreen extends ConsumerStatefulWidget {
  const RawPacketsScreen({super.key});

  @override
  ConsumerState<RawPacketsScreen> createState() => _RawPacketsScreenState();
}

class _RawPacketsScreenState extends ConsumerState<RawPacketsScreen> {
  final _shareKey = GlobalKey();

  Future<void> _share() async {
    final receiver = ref.read(speedCoachReceiverProvider);
    if (receiver.packetLog.isEmpty) {
      showSnack(context, 'No packets received yet.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, 'speedcoach_packets_${DateTime.now().millisecondsSinceEpoch}.csv'),
    );
    await file.writeAsString(receiver.packetLogCsv());
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(speedCoachStateProvider); // refresh as packets arrive
    final receiver = ref.read(speedCoachReceiverProvider);
    final packets = receiver.packetLog.reversed.take(200).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('Raw packets (${receiver.packetLog.length})'),
        actions: [
          IconButton(
            tooltip: 'Copy CSV',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: receiver.packetLogCsv()));
              showSnack(context, 'Packets copied');
            },
          ),
          IconButton(
            key: _shareKey,
            tooltip: 'Share CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: _share,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => setState(receiver.clearPacketLog),
          ),
        ],
      ),
      body: packets.isEmpty
          ? const EmptyState(
              icon: Icons.data_object,
              title: 'No packets yet',
              message: 'Start the receiver and switch Live Streaming on at the SpeedCoach.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: packets.length,
              itemBuilder: (context, i) {
                final pkt = packets[i];
                return Text(
                  '${Fmt.time(pkt.time)}:${pkt.time.second.toString().padLeft(2, '0')}  '
                  '${pkt.suffix}  ${pkt.hex}',
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontFamilyFallback: ['Consolas', 'Courier New'],
                    fontSize: 11,
                  ),
                );
              },
            ),
    );
  }
}
