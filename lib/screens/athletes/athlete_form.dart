import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/athlete.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// Opens the athlete editor. Creates a new athlete when [athlete] is null.
/// Resolves to the saved athlete, or null if cancelled/deleted.
Future<Athlete?> openAthleteEditor(BuildContext context, {Athlete? athlete}) {
  return Navigator.of(context).push<Athlete>(
    MaterialPageRoute(
      fullscreenDialog: athlete == null,
      builder: (_) => AthleteEditScreen(athlete: athlete),
    ),
  );
}

class AthleteEditScreen extends ConsumerStatefulWidget {
  const AthleteEditScreen({super.key, this.athlete});

  final Athlete? athlete;

  @override
  ConsumerState<AthleteEditScreen> createState() => _AthleteEditScreenState();
}

class _AthleteEditScreenState extends ConsumerState<AthleteEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _nickname;
  late final TextEditingController _age;
  late final TextEditingController _maxHr;
  late final TextEditingController _notes;
  bool _saving = false;

  bool get _isNew => widget.athlete == null;

  @override
  void initState() {
    super.initState();
    final a = widget.athlete;
    _name = TextEditingController(text: a?.name ?? '');
    _nickname = TextEditingController(text: a?.nickname ?? '');
    _age = TextEditingController(text: a?.age?.toString() ?? '');
    _maxHr = TextEditingController(text: a?.maxHrOverride?.toString() ?? '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _age.addListener(_refresh);
    _maxHr.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in [_name, _nickname, _age, _maxHr, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _validateRange(String? v, int min, int max, String what) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null || n < min || n > max) return '$what must be $min–$max';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final controller = ref.read(athletesProvider.notifier);
    final age = int.tryParse(_age.text.trim());
    final maxHr = int.tryParse(_maxHr.text.trim());
    String? blankToNull(String s) => s.trim().isEmpty ? null : s.trim();
    try {
      final Athlete saved;
      if (_isNew) {
        saved = await controller.create(
          name: _name.text,
          nickname: _nickname.text,
          age: age,
          maxHrOverride: maxHr,
          notes: _notes.text,
        );
      } else {
        saved = widget.athlete!.copyWith(
          name: _name.text.trim(),
          nickname: () => blankToNull(_nickname.text),
          age: () => age,
          maxHrOverride: () => maxHr,
          notes: () => blankToNull(_notes.text),
        );
        await controller.save(saved);
      }
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Could not save athlete: $e');
      }
    }
  }

  Future<void> _delete() async {
    final a = widget.athlete!;
    final ok = await confirmAction(
      context,
      title: 'Delete ${a.displayName}?',
      message:
          'The athlete is removed and their sensor becomes unassigned. '
          'Recorded sessions keep their data.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await ref.read(athletesProvider.notifier).delete(a.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final formula = ref.watch(settingsProvider.select((s) => s.maxHrFormula));
    final age = int.tryParse(_age.text.trim());
    final manual = int.tryParse(_maxHr.text.trim());
    final estimate = age == null ? null : formula.estimate(age);
    final sensorId = _isNew ? null : ref.watch(sensorIdForAthleteProvider(widget.athlete!.id));
    final sensorName = sensorId == null
        ? null
        : ref.watch(sensorLiveProvider(sensorId))?.name ??
              ref.watch(
                knownSensorsProvider.select((l) {
                  for (final s in l) {
                    if (s.id == sensorId) return s.name;
                  }
                  return null;
                }),
              );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New athlete' : 'Edit athlete'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nickname,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nickname (optional)',
                helperText: 'Shown on the dashboard instead of the name',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Age'),
                    validator: (v) => _validateRange(v, 5, 100, 'Age'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _maxHr,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Max HR (manual)',
                      suffixText: 'bpm',
                    ),
                    validator: (v) => _validateRange(v, 100, 240, 'Max HR'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              manual != null
                  ? 'Using manual max HR: $manual bpm'
                  : estimate != null
                  ? 'Estimated max HR: $estimate bpm (${formula.label}). Enter a tested value for accuracy.'
                  : 'No max HR: % of max and zones will not be shown. Enter age or max HR.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sensors),
                title: const Text('Assigned sensor'),
                subtitle: Text(
                  sensorId == null
                      ? 'None — assign one from the Sensors tab'
                      : '${sensorName ?? 'Unnamed sensor'} (${Fmt.shortId(sensorId)})',
                ),
                trailing: sensorId == null
                    ? null
                    : TextButton(
                        onPressed: () => ref.read(sensorActionsProvider).unassign(sensorId),
                        child: const Text('Unassign'),
                      ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete athlete'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
