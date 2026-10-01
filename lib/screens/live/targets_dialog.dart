import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';
import '../../utils/rowing_format.dart';

/// One-line description of the targets, e.g. "1:59.0 /500m · 2,000 m".
String targetsSummary(AppSettings s) {
  final parts = [
    if (s.targetSplit != null) '${RowFmt.split(s.targetSplit)} /500m',
    switch (s.targetKind) {
      TargetKind.none => null,
      TargetKind.distance => '${RowFmt.thousands(s.targetDistanceMeters)} m',
      TargetKind.time => RowFmt.elapsed(s.targetTime).replaceAll(RegExp(r'\.\d$'), ''),
    },
  ].whereType<String>();
  return parts.isEmpty ? 'None' : parts.join(' · ');
}

/// Edits the optional piece targets. With a target split, the live views
/// show ahead, on or behind.
Future<void> showTargetsDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(context: context, builder: (_) => const _TargetsDialog());
}

class _TargetsDialog extends ConsumerStatefulWidget {
  const _TargetsDialog();

  @override
  ConsumerState<_TargetsDialog> createState() => _TargetsDialogState();
}

class _TargetsDialogState extends ConsumerState<_TargetsDialog> {
  late final AppSettings _s = ref.read(settingsProvider);
  late TargetKind _kind = _s.targetKind;
  late final _split = TextEditingController(
    text: _s.targetSplit == null ? '' : RowFmt.split(_s.targetSplit),
  );
  late final _distance = TextEditingController(text: '${_s.targetDistanceMeters}');
  late final _time = TextEditingController(
    text: RowFmt.elapsed(_s.targetTime).replaceAll(RegExp(r'\.\d$'), ''),
  );
  String? _error;

  @override
  void dispose() {
    _split.dispose();
    _distance.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final splitText = _split.text.trim();
    final split = splitText.isEmpty ? null : RowFmt.parseSplit(splitText);
    if (splitText.isNotEmpty && split == null) {
      setState(() => _error = 'Split must look like 1:59.0');
      return;
    }
    var distance = _s.targetDistanceMeters;
    var time = _s.targetTime;
    if (_kind == TargetKind.distance) {
      final d = int.tryParse(_distance.text.replaceAll(RegExp(r'[,\s]'), ''));
      if (d == null || d <= 0) {
        setState(() => _error = 'Enter a distance in metres');
        return;
      }
      distance = d;
    }
    if (_kind == TargetKind.time) {
      final t = RowFmt.parseClock(_time.text);
      if (t == null) {
        setState(() => _error = 'Time must look like 20:00');
        return;
      }
      time = t;
    }
    await ref
        .read(settingsProvider.notifier)
        .edit(
          (s) => s.copyWith(
            targetSplit: () => split,
            targetKind: _kind,
            targetDistanceMeters: distance,
            targetTime: time,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Targets'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TargetKind>(
              segments: [
                for (final k in TargetKind.values) ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 16),
            if (_kind == TargetKind.distance)
              TextField(
                controller: _distance,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target distance (m)'),
              ),
            if (_kind == TargetKind.time)
              TextField(
                controller: _time,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Target time (mm:ss)'),
              ),
            if (_kind != TargetKind.none) const SizedBox(height: 12),
            TextField(
              controller: _split,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Target split (/500m)',
                hintText: '1:59.0',
                helperText: 'Optional. Live views show ahead, on or behind.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
