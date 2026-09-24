import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/athlete.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';
import 'athlete_form.dart';

class AthletesScreen extends ConsumerWidget {
  const AthletesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athletes = ref.watch(athletesProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Athletes (${athletes.length})')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAthleteEditor(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add athlete'),
      ),
      body: athletes.isEmpty
          ? const EmptyState(
              icon: Icons.groups_outlined,
              title: 'No athletes yet',
              message: 'Add your athletes here, or create them while assigning a sensor.',
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: athletes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _AthleteTile(athlete: athletes[i]),
            ),
    );
  }
}

class _AthleteTile extends ConsumerWidget {
  const _AthleteTile({required this.athlete});

  final Athlete athlete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formula = ref.watch(settingsProvider.select((s) => s.maxHrFormula));
    final sensorId = ref.watch(sensorIdForAthleteProvider(athlete.id));
    final live = sensorId == null ? null : ref.watch(sensorLiveProvider(sensorId));
    final maxHr = athlete.effectiveMaxHr(formula);
    final details = <String>[
      if (athlete.nickname != null) '“${athlete.nickname}”',
      if (athlete.age != null) '${athlete.age} y',
      maxHr == null ? 'No max HR' : 'Max $maxHr${athlete.hasManualMaxHr ? '' : ' (est.)'}',
    ];
    return ListTile(
      onTap: () => openAthleteEditor(context, athlete: athlete),
      leading: CircleAvatar(child: Text(athlete.name.characters.first.toUpperCase())),
      title: Text(athlete.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(details.join(' · ')),
      trailing: sensorId == null
          ? const Chip(label: Text('No sensor'), visualDensity: VisualDensity.compact)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sensors,
                  size: 18,
                  color: live?.displayBpm != null ? AppColors.connected : AppColors.neutral,
                ),
                const SizedBox(width: 4),
                Text(
                  live?.displayBpm?.toString() ?? '--',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
    );
  }
}
