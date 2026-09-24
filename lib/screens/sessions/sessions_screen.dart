import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../providers/core_providers.dart';
import '../../providers/session_provider.dart';
import '../../storage/session_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import 'session_summary_screen.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(sessionHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, title: 'Could not load sessions', message: '$e'),
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.history,
                title: 'No sessions recorded',
                message: 'Start a session from the dashboard to record every athlete’s heart rate.',
              )
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _SessionTile(item: items[i]),
              ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.item});

  final SessionListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = item.session;
    final active = s.isActive;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: active ? AppColors.danger : null,
        foregroundColor: active ? Colors.white : null,
        child: Icon(active ? Icons.fiber_manual_record : Icons.timer_outlined),
      ),
      title: Text(s.name ?? Fmt.dateTime(s.startedAt)),
      subtitle: Text(
        [
          if (s.name != null) Fmt.dateTime(s.startedAt),
          active ? 'Recording…' : Fmt.durationWords(s.duration()),
          '${item.athleteCount} athlete${item.athleteCount == 1 ? '' : 's'}',
          if (s.recovered) 'recovered after app closed',
        ].join(' · '),
      ),
      trailing: active ? null : const Icon(Icons.chevron_right),
      onTap: active
          ? () => showSnack(context, 'Stop the session on the dashboard to see its summary.')
          : () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => SessionSummaryScreen(sessionId: s.id))),
      onLongPress: active
          ? null
          : () async {
              final ok = await confirmAction(
                context,
                title: 'Delete session?',
                message:
                    'All heart-rate data of this session will be permanently removed from this device.',
                confirmLabel: 'Delete',
              );
              if (ok) await ref.read(sessionRepositoryProvider).deleteSession(s.id);
            },
    );
  }
}
