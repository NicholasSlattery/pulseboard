import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../models/lineup.dart';
import '../models/session_extras.dart';
import 'athletes_provider.dart';
import 'boat_provider.dart';
import 'core_providers.dart';
import 'lineup_provider.dart';
import 'session_provider.dart';
import 'speedcoach_provider.dart';

final _log = Logger('CrewSession');

/// Crew and boat data of the running session: the lineup when it started,
/// seat changes, marks and (at the end) the SpeedCoach summary. Null when no
/// session is running.
class CrewSessionController extends Notifier<SessionExtras?> {
  @override
  SessionExtras? build() {
    ref.listen(activeSessionProvider, (_, session) {
      if (session == null) state = null;
    });
    return null;
  }

  /// Starts recording heart rate and SpeedCoach together.
  Future<void> start() async {
    await ref.read(activeSessionProvider.notifier).start();
    final lineup = ref.read(activeLineupProvider);
    final names = {for (final a in ref.read(athletesProvider)) a.id: a.displayName};
    final extras = SessionExtras(
      lineupName: lineup?.name,
      boatClass: lineup?.boatClass.label,
      seats: [
        if (lineup != null)
          for (var n = 1; n <= lineup.seatCount; n++)
            if (lineup.seats[n - 1] != null)
              SeatSnapshot(
                seat: n,
                athleteId: lineup.seats[n - 1]!,
                name: names[lineup.seats[n - 1]] ?? 'Unknown',
              ),
      ],
      coxName: lineup?.coxId == null ? null : names[lineup!.coxId],
    );
    state = extras;
    await _persist();
  }

  /// Saves the boat summary and stops recording. Returns the session id.
  Future<String?> stop() async {
    final session = ref.read(activeSessionProvider);
    if (session == null) return null;
    final boat = _boatSummary();
    if (boat != null && state != null) {
      state = state!.copyWith(boat: () => boat);
      await _persist();
    }
    final ended = await ref.read(activeSessionProvider.notifier).stop();
    return ended?.id;
  }

  /// Logs the current time and distance. Nothing is sent to the SpeedCoach.
  Future<SessionMark?> mark() async {
    final current = state;
    if (current == null) return null;
    final sc = ref.read(speedCoachStateProvider);
    final mark = SessionMark(
      time: clock.now(),
      distanceMeters: sc.isStreaming ? sc.distanceMeters : null,
      elapsed: sc.isStreaming ? sc.elapsed : null,
    );
    state = current.copyWith(marks: [...current.marks, mark]);
    await _persist();
    return mark;
  }

  /// Records every seat whose occupant differs between [before] and [after].
  Future<void> logSeatChanges(Lineup before, Lineup after) async {
    final current = state;
    if (current == null) return;
    final names = {for (final a in ref.read(athletesProvider)) a.id: a.displayName};
    final sc = ref.read(speedCoachStateProvider);
    final now = clock.now();
    final changes = <SeatChange>[
      for (var n = 1; n <= after.seatCount; n++)
        if (n > before.seatCount || before.seats[n - 1] != after.seats[n - 1])
          SeatChange(
            time: now,
            seat: n,
            fromName: n > before.seatCount ? null : names[before.seats[n - 1]],
            toName: names[after.seats[n - 1]],
            distanceMeters: sc.isStreaming ? sc.distanceMeters : null,
          ),
    ];
    if (changes.isEmpty) return;
    state = current.copyWith(seatChanges: [...current.seatChanges, ...changes]);
    await _persist();
  }

  BoatSummary? _boatSummary() {
    final sc = ref.read(speedCoachStateProvider);
    final m = ref.read(boatMetricsProvider);
    if (sc.lastPacketAt == null) return null;
    final strokes = m.strokes;
    final distance = sc.distanceMeters;
    final summary = BoatSummary(
      distanceMeters: distance,
      elapsed: sc.elapsed,
      averageSplit: sc.averageSplit,
      averageRate: m.averageRate,
      distancePerStroke: strokes != null && strokes > 0 && distance != null
          ? distance / strokes
          : null,
      strokes: strokes,
      splits500: m.splits500,
      serial: sc.serial,
      pieceStartedAt: sc.pieceStartedAt,
    );
    return summary.hasData ? summary : null;
  }

  Future<void> _persist() async {
    final session = ref.read(activeSessionProvider);
    final extras = state;
    if (session == null || extras == null) return;
    try {
      await ref.read(sessionRepositoryProvider).saveExtras(session.id, extras);
    } catch (e, st) {
      _log.warning('Saving crew data failed', e, st);
    }
  }
}

final crewSessionProvider = NotifierProvider<CrewSessionController, SessionExtras?>(
  CrewSessionController.new,
);
