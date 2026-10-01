import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/hr_zones.dart';
import '../models/session_extras.dart';
import '../models/training_session.dart';
import '../session/session_recorder.dart';
import '../session/session_stats.dart';
import 'athletes_provider.dart';
import 'core_providers.dart';
import 'sensors_provider.dart';
import 'settings_provider.dart';

/// The session currently being recorded, or null.
class ActiveSessionController extends Notifier<TrainingSession?> {
  @override
  TrainingSession? build() {
    final recorder = ref.watch(sessionRecorderProvider);
    final sub = recorder.activeChanges.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return recorder.active;
  }

  Future<TrainingSession> start() {
    final settings = ref.read(settingsProvider);
    return ref
        .read(sessionRecorderProvider)
        .start(roster: ref.read(rosterProvider), zones: settings.zoneModel);
  }

  Future<TrainingSession?> stop() => ref.read(sessionRecorderProvider).stop();
}

final activeSessionProvider = NotifierProvider<ActiveSessionController, TrainingSession?>(
  ActiveSessionController.new,
);

/// Who is wearing which sensor right now, with their effective max HR.
final rosterProvider = Provider<List<RosterEntry>>((ref) {
  final athletes = ref.watch(athletesProvider);
  final assignments = ref.watch(sensorAssignmentsProvider);
  final formula = ref.watch(settingsProvider.select((s) => s.maxHrFormula));
  final byId = {for (final a in athletes) a.id: a};
  return [
    for (final entry in assignments.entries)
      if (byId[entry.value] != null)
        RosterEntry(
          athleteId: entry.value,
          athleteName: byId[entry.value]!.name,
          sensorId: entry.key,
          maxHr: byId[entry.value]!.effectiveMaxHr(formula),
        ),
  ];
});

/// Everything the session summary screen shows.
class SessionSummary {
  const SessionSummary({
    required this.session,
    required this.athletes,
    required this.stats,
    this.extras = const SessionExtras(),
  });

  final TrainingSession session;
  final List<SessionAthlete> athletes;
  final List<AthleteSessionStats> stats;

  /// Lineup and SpeedCoach data recorded with the session.
  final SessionExtras extras;

  int get zoneCount => session.zoneLowerBounds.isEmpty
      ? ZoneModel.standard.zoneCount
      : session.zoneLowerBounds.length;

  List<double> get zoneBounds => session.zoneLowerBounds.isEmpty
      ? ZoneModel.standard.lowerBoundsPercent
      : session.zoneLowerBounds;
}

/// Loads a session and computes per-athlete statistics. Uses the zone model
/// stored with the session so history stays correct if settings change.
final sessionSummaryProvider = FutureProvider.autoDispose.family<SessionSummary?, String>((
  ref,
  sessionId,
) async {
  final repo = ref.watch(sessionRepositoryProvider);
  final session = await repo.getSession(sessionId);
  if (session == null) return null;
  final athletes = await repo.getSessionAthletes(sessionId);
  final events = await repo.getEvents(sessionId);
  final zoneCount = session.zoneLowerBounds.isEmpty
      ? ZoneModel.standard.zoneCount
      : session.zoneLowerBounds.length;
  final stats = <AthleteSessionStats>[
    for (final a in athletes)
      SessionStatsCalculator.compute(
        athlete: a,
        sessionStart: session.startedAt,
        samples: await repo.getSamplesForAthlete(sessionId, a.athleteId),
        events: events,
        zoneCount: zoneCount,
      ),
  ];
  final extras = await repo.getExtras(sessionId);
  return SessionSummary(session: session, athletes: athletes, stats: stats, extras: extras);
});

/// Session history, refreshed whenever sessions change.
final sessionHistoryProvider = StreamProvider((ref) async* {
  final repo = ref.watch(sessionRepositoryProvider);
  yield await repo.listSessions();
  await for (final _ in repo.changes) {
    yield await repo.listSessions();
  }
});
