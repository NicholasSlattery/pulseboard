import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../models/session_extras.dart';
import '../../providers/core_providers.dart';
import '../../providers/session_provider.dart';
import '../../session/csv_exporter.dart';
import '../../session/session_stats.dart';
import '../../utils/formatters.dart';
import '../../utils/rowing_format.dart';
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
          final extras = s.extras;
          // Seat order when the crew was set, else by name.
          final stats = [...s.stats]
            ..sort((a, b) {
              final sa = extras.seatOf(a.athleteId) ?? -1;
              final sb = extras.seatOf(b.athleteId) ?? -1;
              return sb.compareTo(sa);
            });
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(Fmt.dateTime(session.startedAt), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  if (extras.lineupName != null)
                    '${extras.boatClass == null ? '' : '${extras.boatClass} · '}${extras.lineupName}',
                  'Duration ${Fmt.duration(session.duration())}',
                  '${s.athletes.length} athlete${s.athletes.length == 1 ? '' : 's'}',
                  if (session.recovered) 'recovered after the app closed unexpectedly',
                ].join(' · '),
              ),
              const SizedBox(height: 16),
              if (extras.boat != null) ...[
                CrewBoatSummary(boat: extras.boat!),
                const SizedBox(height: 12),
              ],
              if (extras.seats.isNotEmpty && s.stats.isNotEmpty) ...[
                CrewHrTable(summary: s),
                const SizedBox(height: 12),
              ],
              if (extras.seatChanges.isNotEmpty || extras.marks.isNotEmpty) ...[
                _CrewLog(extras: extras),
                const SizedBox(height: 12),
              ],
              if (s.stats.isEmpty && extras.boat == null)
                const EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'No athletes in this session',
                  message: '',
                ),
              for (final stats in stats) ...[
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

/// Boat numbers of the last SpeedCoach piece.
class CrewBoatSummary extends StatelessWidget {
  const CrewBoatSummary({super.key, required this.boat});

  final BoatSummary boat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = boat.splits500.isEmpty ? null : boat.splits500.reduce((a, b) => a <= b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rowing, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Boat', style: theme.textTheme.titleLarge)),
                if (boat.serial != null)
                  Text('SC ${boat.serial}', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Stat(label: 'DISTANCE', value: RowFmt.distance(boat.distanceMeters), unit: 'm'),
                _Stat(label: 'TIME', value: RowFmt.elapsed(boat.elapsed), unit: ''),
                _Stat(label: 'AVG SPLIT', value: RowFmt.split(boat.averageSplit), unit: '/500m'),
                _Stat(label: 'AVG RATE', value: RowFmt.averageRate(boat.averageRate), unit: 'spm'),
                _Stat(
                  label: 'DIST / STROKE',
                  value: RowFmt.meters1(boat.distancePerStroke),
                  unit: boat.strokes == null ? 'm' : 'm · ${boat.strokes} strokes',
                ),
                if (best != null) _Stat(label: 'BEST 500', value: RowFmt.split(best), unit: ''),
              ],
            ),
            if (boat.splits500.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('500 m splits', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (var i = 0; i < boat.splits500.length; i++)
                _SplitBar(
                  mark: RowFmt.thousands((i + 1) * 500),
                  split: boat.splits500[i],
                  best: best!,
                  worst: boat.splits500.reduce((a, b) => a >= b ? a : b),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({
    required this.mark,
    required this.split,
    required this.best,
    required this.worst,
  });

  final String mark;
  final Duration split;
  final Duration best;
  final Duration worst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBest = split == best;
    // Bar = speed: the fastest 500 is the longest bar.
    final range = (worst - best).inMilliseconds;
    final f = range == 0 ? 1.0 : 0.6 + 0.4 * (worst - split).inMilliseconds / range;
    final color = isBest ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text(mark, style: theme.textTheme.bodyMedium)),
          SizedBox(
            width: 72,
            child: Text(
              RowFmt.split(split),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isBest ? theme.colorScheme.primary : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: f,
                minHeight: 10,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              isBest ? 'BEST' : '',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heart rate by seat: average, max and time in zones per rower.
class CrewHrTable extends StatelessWidget {
  const CrewHrTable({super.key, required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extras = summary.extras;
    final byId = {for (final st in summary.stats) st.athleteId: st};
    final rows = [...extras.seats]..sort((a, b) => b.seat.compareTo(a.seat));
    TextStyle? head() => theme.textTheme.labelSmall?.copyWith(letterSpacing: 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Crew heart rate by seat', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(width: 34, child: Text('SEAT', style: head(), softWrap: false)),
                const SizedBox(width: 8),
                Expanded(child: Text('ROWER', style: head())),
                SizedBox(
                  width: 40,
                  child: Text('AVG', style: head(), textAlign: TextAlign.right),
                ),
                SizedBox(
                  width: 40,
                  child: Text('MAX', style: head(), textAlign: TextAlign.right),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 96, child: Text('TIME IN ZONE', style: head())),
              ],
            ),
            for (final seat in rows) ...[
              const Divider(height: 12),
              _CrewHrRow(seat: seat.seat, name: seat.name, stats: byId[seat.athleteId]),
            ],
          ],
        ),
      ),
    );
  }
}

class _CrewHrRow extends StatelessWidget {
  const _CrewHrRow({required this.seat, required this.name, required this.stats});

  final int seat;
  final String name;
  final AthleteSessionStats? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = stats;
    const tabular = [FontFeature.tabularFigures()];
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '$seat',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              st == null || !st.hasData ? '--' : '${st.averageHr}',
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: tabular,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              st == null || !st.hasData ? '--' : '${st.maxHr}',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: tabular),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            height: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: st == null || !st.hasData
                  ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                  : Row(
                      children: [
                        for (var z = 0; z < st.timeInZone.length; z++)
                          if (st.fractionInZone(z) > 0)
                            Expanded(
                              flex: (st.fractionInZone(z) * 1000).round().clamp(1, 1000),
                              child: ColoredBox(color: AppColors.zone(z)),
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

/// Seat changes and marks made during the session.
class _CrewLog extends StatelessWidget {
  const _CrewLog({required this.extras});

  final SessionExtras extras;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = <(DateTime, String)>[
      for (final c in extras.seatChanges)
        (
          c.time,
          'Seat ${c.seat}: ${c.toName ?? 'empty'}'
              '${c.fromName == null ? '' : ' (was ${c.fromName})'}'
              '${c.distanceMeters == null ? '' : ' at ${RowFmt.distance(c.distanceMeters)} m'}',
        ),
      for (final m in extras.marks)
        (
          m.time,
          'Mark${m.distanceMeters == null ? '' : ' at ${RowFmt.distance(m.distanceMeters)} m'}'
              '${m.elapsed == null ? '' : ' · ${RowFmt.elapsed(m.elapsed)}'}',
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seat changes and marks', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final (t, text) in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${Fmt.time(t)}:${t.second.toString().padLeft(2, '0')}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
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
