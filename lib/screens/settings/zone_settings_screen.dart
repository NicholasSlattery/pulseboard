import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/hr_zones.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';

/// Edit the lower bound (% of max HR) of each zone.
class ZoneSettingsScreen extends ConsumerStatefulWidget {
  const ZoneSettingsScreen({super.key});

  @override
  ConsumerState<ZoneSettingsScreen> createState() => _ZoneSettingsScreenState();
}

class _ZoneSettingsScreenState extends ConsumerState<ZoneSettingsScreen> {
  late List<TextEditingController> _controllers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(ref.read(settingsProvider).zoneModel);
  }

  void _load(ZoneModel model) {
    _controllers = [
      for (final b in model.lowerBoundsPercent)
        TextEditingController(text: b == b.roundToDouble() ? b.toInt().toString() : b.toString()),
    ];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<double>? _parse() {
    final values = <double>[];
    for (final c in _controllers) {
      final v = double.tryParse(c.text.trim());
      if (v == null) return null;
      values.add(v);
    }
    return values;
  }

  Future<void> _save() async {
    final values = _parse();
    final error = values == null ? 'Every zone needs a number.' : ZoneModel.validate(values);
    setState(() => _error = error);
    if (error != null) return;
    await ref
        .read(settingsProvider.notifier)
        .edit((s) => s.copyWith(zoneModel: ZoneModel(values!)));
    if (mounted) {
      showSnack(context, 'Zones saved');
      Navigator.pop(context);
    }
  }

  void _reset() {
    setState(() {
      for (final c in _controllers) {
        c.dispose();
      }
      _load(ZoneModel.standard);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart-rate zones'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('Defaults')),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Each zone starts at the given percentage of the athlete’s max HR and ends where '
            'the next zone starts. The top zone has no upper limit. Heart rates below zone 1 '
            'are shown as zone 0. Past sessions keep the zones they were recorded with.',
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _controllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ZoneBadge(zone: i + 1),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _controllers[i],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: const InputDecoration(
                        labelText: 'Starts at',
                        suffixText: '% of max',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
