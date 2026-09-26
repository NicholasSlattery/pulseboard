import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../providers/settings_provider.dart';
import '../../providers/speedcoach_provider.dart';
import '../../speedcoach/speedcoach_protocol.dart';
import '../../speedcoach/speedcoach_receiver.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// Experimental: receive live data from an NK SpeedCoach by acting as
/// NK LiNK Logbook.
class SpeedCoachScreen extends ConsumerStatefulWidget {
  const SpeedCoachScreen({super.key});

  @override
  ConsumerState<SpeedCoachScreen> createState() => _SpeedCoachScreenState();
}

class _SpeedCoachScreenState extends ConsumerState<SpeedCoachScreen> {
  late final TextEditingController _boatName = TextEditingController(
    text: ref.read(settingsProvider).speedCoachBoatName,
  );
  final _shareKey = GlobalKey();

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

  Future<void> _sharePackets() async {
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
    final state = ref.watch(speedCoachStateProvider);
    final serial = ref.watch(settingsProvider.select((s) => s.speedCoachSerial));
    final controller = ref.read(speedCoachStateProvider.notifier);
    final receiver = ref.read(speedCoachReceiverProvider);
    final theme = Theme.of(context);
    final running =
        state.status == SpeedCoachReceiverStatus.waiting ||
        state.status == SpeedCoachReceiverStatus.streaming ||
        state.status == SpeedCoachReceiverStatus.starting;
    final (statusText, statusColor) = switch (state.status) {
      SpeedCoachReceiverStatus.stopped => ('Stopped', AppColors.neutral),
      SpeedCoachReceiverStatus.starting => ('Starting…', AppColors.warning),
      SpeedCoachReceiverStatus.waiting => ('Waiting for SpeedCoach', AppColors.warning),
      SpeedCoachReceiverStatus.streaming => ('Receiving data', AppColors.connected),
      SpeedCoachReceiverStatus.unsupported => ('Not supported on this device', AppColors.danger),
      SpeedCoachReceiverStatus.error => ('Error', AppColors.danger),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('SpeedCoach (experimental)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to connect', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Close NK LiNK Logbook (it must not be streaming).\n'
                    '2. Tap Start below and keep PulseBoard open.\n'
                    '3. On the SpeedCoach: Live Streaming > Phone Pairing > Find New '
                    '(the first time), or just turn Live Streaming on once paired.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Experimental: NK does not publish this protocol. Elapsed time and stroke '
                    'count are decoded; stroke rate is calculated from stroke timing; split and '
                    'distance are not decoded yet.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          StatusLabel(color: statusColor, label: statusText.toUpperCase(), fontSize: 14),
          if (state.advertisedName != null && running)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Advertising as "${state.advertisedName}"'
                '${state.advertisedName == SpeedCoachNames.pairing ? ' (pairing)' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(state.error!, style: const TextStyle(color: AppColors.danger)),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!running)
                FilledButton.icon(
                  onPressed: () => controller.start(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                )
              else
                OutlinedButton.icon(
                  onPressed: controller.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              OutlinedButton.icon(
                onPressed: () => controller.start(pairNew: true),
                icon: const Icon(Icons.add_link),
                label: const Text('Pair a new SpeedCoach'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.speed),
            title: Text(serial == null ? 'No SpeedCoach paired yet' : 'Paired SpeedCoach $serial'),
            subtitle: const Text('Remembered automatically when a SpeedCoach connects'),
            trailing: serial == null
                ? null
                : TextButton(onPressed: controller.forgetSpeedCoach, child: const Text('Forget')),
          ),
          TextField(
            controller: _boatName,
            decoration: const InputDecoration(
              labelText: 'Boat name',
              helperText: 'Sent to the SpeedCoach, like the Boat ID in NK LiNK',
            ),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _saveBoatName(),
            onEditingComplete: _saveBoatName,
          ),
          const SizedBox(height: 20),
          _LiveValues(state: state),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Raw packets (${receiver.packetLog.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
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
                onPressed: _sharePackets,
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => setState(receiver.clearPacketLog),
              ),
            ],
          ),
          for (final pkt in receiver.packetLog.reversed.take(40))
            Text(
              '${Fmt.time(pkt.time)}:${pkt.time.second.toString().padLeft(2, '0')}  '
              '${pkt.suffix}  ${pkt.hex}',
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontFamilyFallback: ['Consolas', 'Courier New'],
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveValues extends StatelessWidget {
  const _LiveValues({required this.state});

  final SpeedCoachLiveState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(String label, String value, {String? note}) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1)),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                ),
              ),
              if (note != null) Text(note, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
    final live = state.isStreaming;
    final rate = live && state.strokeRate != null ? state.strokeRate!.round().toString() : '--';
    final elapsed = state.elapsed;
    final elapsedText = !live || elapsed == null
        ? '--'
        : '${Fmt.duration(elapsed)}.${(elapsed.inMilliseconds % 1000 ~/ 100)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            tile('RATE', rate, note: state.isIdle && live ? 'paused' : 'calculated'),
            tile('STROKES', live && state.strokeCount != null ? '${state.strokeCount}' : '--'),
            tile('TIME', elapsedText),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (state.serial != null) 'SpeedCoach ${state.serial}',
            '${state.packetsReceived} packets',
            if (state.lastPacketAt != null)
              'last ${clock.now().difference(state.lastPacketAt!).inSeconds}s ago',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
