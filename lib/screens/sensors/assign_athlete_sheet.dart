import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/athlete.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../athletes/athlete_form.dart';

Future<void> showAssignAthleteSheet(BuildContext context, String sensorId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AssignAthleteSheet(sensorId: sensorId),
  );
}

/// Pick (or create) the athlete wearing [sensorId].
class AssignAthleteSheet extends ConsumerWidget {
  const AssignAthleteSheet({super.key, required this.sensorId});

  final String sensorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athletes = ref.watch(athletesProvider);
    final knownSensors = ref.watch(knownSensorsProvider);
    final formula = ref.watch(settingsProvider.select((s) => s.maxHrFormula));
    final sensorByAthlete = {
      for (final s in knownSensors)
        if (s.athleteId != null) s.athleteId!: s,
    };
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Who is wearing this strap?', style: theme.textTheme.titleLarge),
                ),
                FilledButton.icon(
                  onPressed: () => _createAndAssign(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('New athlete'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Sensor ${Fmt.shortId(sensorId, 8)}', style: theme.textTheme.bodySmall),
          ),
          const Divider(),
          Expanded(
            child: athletes.isEmpty
                ? const EmptyState(
                    icon: Icons.group_add_outlined,
                    title: 'No athletes yet',
                    message: 'Create the first athlete with “New athlete”.',
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: athletes.length,
                    itemBuilder: (context, i) {
                      final a = athletes[i];
                      final current = sensorByAthlete[a.id];
                      final isThis = current?.id == sensorId;
                      final maxHr = a.effectiveMaxHr(formula);
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(a.displayName.characters.first.toUpperCase()),
                        ),
                        title: Text(a.displayName),
                        subtitle: Text(
                          [
                            maxHr == null
                                ? 'No max HR'
                                : 'Max HR $maxHr${a.hasManualMaxHr ? '' : ' (est.)'}',
                            if (current != null && !isThis)
                              'has ${current.name ?? 'another sensor'}',
                            if (isThis) 'current',
                          ].join(' · '),
                        ),
                        trailing: isThis
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                        onTap: isThis
                            ? null
                            : () => _assign(context, ref, a, hasOtherSensor: current != null),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    Athlete athlete, {
    required bool hasOtherSensor,
  }) async {
    if (hasOtherSensor) {
      final ok = await confirmAction(
        context,
        title: 'Move ${athlete.displayName}?',
        message:
            '${athlete.displayName} is assigned to another sensor. '
            'Move them to this sensor? The other sensor will become unassigned.',
        confirmLabel: 'Move',
        destructive: false,
      );
      if (!ok) return;
    }
    await ref.read(sensorActionsProvider).assign(sensorId: sensorId, athleteId: athlete.id);
    if (context.mounted) {
      Navigator.pop(context);
      showSnack(context, 'Assigned to ${athlete.displayName}');
    }
  }

  Future<void> _createAndAssign(BuildContext context, WidgetRef ref) async {
    final athlete = await openAthleteEditor(context);
    if (athlete == null) return;
    await ref.read(sensorActionsProvider).assign(sensorId: sensorId, athleteId: athlete.id);
    if (context.mounted) {
      Navigator.pop(context);
      showSnack(context, 'Assigned to ${athlete.displayName}');
    }
  }
}
