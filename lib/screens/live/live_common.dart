import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/live_theme.dart';
import '../../models/app_settings.dart';
import '../../providers/boat_provider.dart';
import '../../models/sensor_state.dart';
import '../../providers/crew_session_provider.dart';
import '../../providers/lineup_provider.dart';
import '../../providers/sensors_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/speedcoach_provider.dart';
import '../../speedcoach/boat_metrics.dart';
import '../../utils/formatters.dart';
import '../../utils/rowing_format.dart';
import '../../widgets/common.dart';
import '../sessions/session_summary_screen.dart';
import 'boat_view.dart';
import 'live_widgets.dart';

/// The boat view at [now] (watch from inside a [Ticking]).
BoatView watchBoatView(WidgetRef ref, DateTime now) => BoatView.from(
  ref.watch(speedCoachStateProvider),
  ref.watch(boatMetricsProvider),
  now,
  targetSplit: ref.watch(settingsProvider.select((s) => s.targetSplit)),
);

/// (live straps, seated rowers) for the status bar.
final crewHrLiveProvider = Provider<(int, int)>((ref) {
  final seats = ref.watch(crewSeatsProvider);
  final assignments = ref.watch(sensorAssignmentsProvider);
  final sensorFor = {for (final e in assignments.entries) e.value: e.key};
  final ids = [
    for (final s in seats)
      if (s.athleteId != null) sensorFor[s.athleteId],
  ];
  final live = ref.watch(
    sensorLiveStatesProvider.select((states) {
      var n = 0;
      for (final id in ids) {
        if (id == null) continue;
        final st = states[id];
        if (st != null &&
            st.connection == SensorConnectionState.receiving &&
            st.freshness == SignalFreshness.fresh &&
            !st.noSkinContact) {
          n++;
        }
      }
      return n;
    }),
  );
  return (live, ids.length);
});

/// Top status line: SpeedCoach state left; HR n/m live and recording time
/// right.
class LiveStatusBar extends ConsumerWidget {
  const LiveStatusBar({super.key, this.showSerial = false});

  final bool showSerial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = LiveScope.of(context);
    final session = ref.watch(activeSessionProvider);
    final (live, total) = ref.watch(crewHrLiveProvider);
    return SizedBox(
      height: 24,
      child: Ticking(
        builder: (context, now) {
          final boat = watchBoatView(ref, now);
          final (conn, connColor) = boat.connection(p);
          final serial = boat.state.serial;
          final extra = [
            boat.pieceLabel,
            if (showSerial && boat.connected && serial != null) 'SC $serial · ${boat.ageText}',
          ].where((s) => s.isNotEmpty).join('  ');
          return Row(
            children: [
              StatusDot(color: connColor, label: conn),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  extra,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: LiveType.label(12, boat.dimmed ? connColor : p.mid),
                ),
              ),
              if (total > 0)
                Text(
                  'HR $live/$total LIVE',
                  style: LiveType.label(12, live == total ? p.ok : p.warn, weight: FontWeight.w700),
                ),
              if (session != null) ...[
                const SizedBox(width: 10),
                StatusDot(
                  color: p.danger,
                  label: 'REC ${Fmt.duration(now.difference(session.startedAt))}',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Holds the stop: saves the SpeedCoach summary, ends the session and opens
/// the summary.
Future<void> stopCrewSession(BuildContext context, WidgetRef ref) async {
  // Read everything first: this widget is gone once the session ends.
  final navigator = Navigator.of(context);
  final crew = ref.read(crewSessionProvider.notifier);
  final mode = ref.read(liveViewModeProvider.notifier);
  final defaultMode = ref.read(settingsProvider).liveViewMode;
  final id = await crew.stop();
  mode.show(defaultMode);
  if (id == null) return;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => SessionSummaryScreen(sessionId: id)),
  );
}

Future<void> markNow(BuildContext context, WidgetRef ref) async {
  final crew = ref.read(crewSessionProvider.notifier);
  final mark = await crew.mark();
  if (!context.mounted || mark == null) return;
  final where = mark.distanceMeters == null
      ? Fmt.time(mark.time)
      : '${RowFmt.distance(mark.distanceMeters)} m';
  showSnack(context, 'Marked at $where');
}

/// Reconnect: restart the receiver so the SpeedCoach can find us again.
Future<void> reconnectSpeedCoach(WidgetRef ref) =>
    ref.read(speedCoachStateProvider.notifier).start();

/// Flips the live screens between On the water and Daylight.
Future<void> toggleLiveTheme(WidgetRef ref) => ref
    .read(settingsProvider.notifier)
    .edit(
      (s) => s.copyWith(
        liveTheme: s.liveTheme == LiveTheme.water ? LiveTheme.daylight : LiveTheme.water,
      ),
    );

/// The phases where the SpeedCoach block has nothing to show.
bool boatIsAbsent(BoatPhase phase) => phase == BoatPhase.off || phase == BoatPhase.waiting;
