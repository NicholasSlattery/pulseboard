import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../providers/core_providers.dart';
import '../../providers/session_provider.dart';
import '../../session/csv_exporter.dart';
import '../../session/session_stats.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/hr_chart.dart';

final _log = Logger('Summary');

class SessionSummaryScreen extends ConsumerStatefulWidget {
  const SessionSummaryScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends ConsumerState<SessionSummaryScreen> {
  final _exportKey = GlobalKey();
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = await CsvExporter(
        ref.read(sessionRepositoryProvider),
      ).exportSession(widget.sessionId, dir);
      // iPad requires an anchor rect for the share popover.
      final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Heart-rate session export',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e, st) {
      _log.warning('CSV export failed', e, st);
      if (mounted) showSnack(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'Delete session?',
      message: 'All heart-rate data of this session will be permanently removed from this device.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    await ref.read(sessionRepositoryProvider).deleteSession(widget.sessionId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(sessionSummaryProvider(widget.sessionId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session summary'),
        actions: [
          IconButton(
            key: _exportKey,
            tooltip: 'Export CSV',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Delete session',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            EmptyState(icon: Icons.error_outline, title: 'Could not load session', message: '$e'),
        data: (s) {
          if (s == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Session not found',
              message: '',
            );
          }
          final session = s.session;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(Fmt.dateTime(session.startedAt), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  'Duration ${Fmt.duration(session.duration())}',
                  '${s.athletes.length} athlete${s.athletes.length == 1 ? '' : 's'}',
                  if (session.recovered) 'recovered after the app closed unexpectedly',
                ].join(' · '),
              ),
              const SizedBox(height: 16),
              if (s.stats.isEmpty)
                const EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'No athletes in this session',
                  message: '',
                ),
              for (final stats in s.stats) ...[
                _AthleteSummaryCard(
                  stats: stats,
                  maxHr: s.athletes.firstWhere((a) => a.athleteId == stats.athleteId).maxHr,
                  sessionDuration: session.duration(),
                  zoneBounds: s.zoneBounds,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AthleteSummaryCard extends StatelessWidget {
  const _AthleteSummaryCard({
    required this.stats,
    required this.maxHr,
    required this.sessionDuration,
    required this.zoneBounds,
  });

  final AthleteSessionStats stats;
  final int? maxHr;
  final Duration sessionDuration;
  final List<double> zoneBounds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(stats.athleteName, style: theme.textTheme.titleLarge)),
                if (stats.interruptions > 0)
                  Chip(
                    avatar: const Icon(Icons.link_off, size: 16),
                    label: Text(
                      '${stats.interruptions} dropout${stats.interruptions == 1 ? '' : 's'}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (!stats.hasData)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No heart-rate data was recorded for this athlete.'),
              )
            else ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Stat(label: 'AVG', value: '${stats.averageHr}', unit: 'bpm'),
                  _Stat(label: 'MAX', value: '${stats.maxHr}', unit: 'bpm'),
                  _Stat(label: 'MIN', value: '${stats.minHr}', unit: 'bpm'),
                  _Stat(label: 'RECORDED', value: Fmt.duration(stats.recordedDuration), unit: ''),
                ],
              ),
              const SizedBox(height: 16),
              Text('Time in zones', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (var z = stats.timeInZone.length - 1; z >= 0; z--)
                _ZoneBar(zone: z, duration: stats.timeInZone[z], fraction: stats.fractionInZone(z)),
              if (stats.timeWithoutZone > Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${Fmt.duration(stats.timeWithoutZone)} without zone (no max HR set)',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              HrChart(
                points: stats.timeline,
                duration: sessionDuration,
                maxHr: maxHr,
                zoneBoundsPercent: zoneBounds,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1)),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(unit, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ],
    );
  }
}

class _ZoneBar extends StatelessWidget {
  const _ZoneBar({required this.zone, required this.duration, required this.fraction});

  final int zone;
  final Duration duration;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              zone == 0 ? '< Z1' : 'Z$zone',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 14,
                color: AppColors.zone(zone),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 104,
            child: Text(
              '${Fmt.duration(duration)}  ${Fmt.percent(fraction)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}
