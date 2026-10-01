import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/lineup.dart';
import '../utils/formatters.dart';
import 'athletes_provider.dart';
import 'core_providers.dart';
import 'crew_session_provider.dart';
import 'session_provider.dart';

/// Saved lineups. Changes to the lineup in use during a session are logged
/// with the session (seat racing).
class LineupController extends Notifier<LineupBook> {
  static const _uuid = Uuid();

  @override
  LineupBook build() => ref.read(bootstrapProvider).lineups;

  Future<void> _save(LineupBook next) async {
    if (next == state) return;
    state = next;
    await ref.read(lineupRepositoryProvider).save(next);
  }

  Future<Lineup> create({required String name, BoatClass? boatClass}) async {
    final lineup = Lineup.empty(id: _uuid.v4(), name: name, boatClass: boatClass);
    await _save(state.put(lineup).copyWith(activeId: () => lineup.id));
    return lineup;
  }

  Future<void> select(String id) => _save(state.copyWith(activeId: () => id));

  Future<void> delete(String id) {
    final rest = [
      for (final l in state.lineups)
        if (l.id != id) l,
    ];
    return _save(
      LineupBook(
        lineups: List.unmodifiable(rest),
        activeId: state.activeId == id ? (rest.isEmpty ? null : rest.first.id) : state.activeId,
        strokeFirst: state.strokeFirst,
      ),
    );
  }

  Future<void> setStrokeFirst(bool strokeFirst) => _save(state.copyWith(strokeFirst: strokeFirst));

  /// Saves [lineup]. If it is the lineup in use and a session is running,
  /// every seat that changed is logged.
  Future<void> save(Lineup lineup) async {
    Lineup? before;
    for (final l in state.lineups) {
      if (l.id == lineup.id) before = l;
    }
    await _save(state.put(lineup));
    if (before != null &&
        ref.read(activeSessionProvider) != null &&
        state.active?.id == lineup.id) {
      await ref.read(crewSessionProvider.notifier).logSeatChanges(before, lineup);
    }
  }

  /// The lineup in use, creating a first one if none exists.
  Future<Lineup> ensureActive() async {
    final active = state.active;
    if (active != null) return active;
    return create(name: 'Lineup A');
  }
}

final lineupBookProvider = NotifierProvider<LineupController, LineupBook>(LineupController.new);

/// The lineup in use, with deleted athletes dropped.
final activeLineupProvider = Provider<Lineup?>((ref) {
  final lineup = ref.watch(lineupBookProvider.select((b) => b.active));
  if (lineup == null) return null;
  final ids = ref.watch(athletesProvider.select((list) => {for (final a in list) a.id}));
  return lineup.prune(ids);
});

/// One row on the live crew screen.
@immutable
class CrewSeat {
  const CrewSeat({this.seat, required this.role, this.athleteId, required this.name});

  /// 1 = bow; null for a rower who is not in the lineup.
  final int? seat;

  /// STROKE, BOW, SEAT, SCULL, or empty.
  final String role;
  final String? athleteId;
  final String name;

  bool get isEmpty => athleteId == null;

  @override
  bool operator ==(Object other) =>
      other is CrewSeat &&
      other.seat == seat &&
      other.role == role &&
      other.athleteId == athleteId &&
      other.name == name;

  @override
  int get hashCode => Object.hash(seat, role, athleteId, name);
}

/// Live screen rows, always by seat (never by name or HR) so rows stay put.
/// Without a lineup, everyone with an assigned strap is listed by name.
final crewSeatsProvider = Provider<List<CrewSeat>>((ref) {
  final lineup = ref.watch(activeLineupProvider);
  final strokeFirst = ref.watch(lineupBookProvider.select((b) => b.strokeFirst));
  final athletes = ref.watch(athletesProvider);
  final byId = {for (final a in athletes) a.id: a};

  if (lineup != null && !lineup.isEmpty) {
    final rows = [
      for (var n = 1; n <= lineup.seatCount; n++)
        CrewSeat(
          seat: n,
          role: lineup.roleOf(n),
          athleteId: lineup.seats[n - 1],
          name: lineup.seats[n - 1] == null
              ? 'Empty seat'
              : (byId[lineup.seats[n - 1]]?.displayName ?? 'Unknown'),
        ),
    ];
    return strokeFirst ? rows.reversed.toList(growable: false) : rows;
  }

  final roster = ref.watch(rosterProvider);
  final named = [
    for (final r in roster)
      if (byId[r.athleteId] != null) byId[r.athleteId]!,
  ]..sort((a, b) => naturalCompare(a.displayName, b.displayName));
  return [for (final a in named) CrewSeat(role: '', athleteId: a.id, name: a.displayName)];
});
