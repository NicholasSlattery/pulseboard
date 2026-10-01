import 'package:flutter/foundation.dart';

/// Rowing boat classes the lineup editor knows.
enum BoatClass {
  eight('8+', 8, cox: true),
  four('4+', 4, cox: true),
  quad('4x', 4),
  double('2x', 2),
  single('1x', 1);

  const BoatClass(this.label, this.seats, {this.cox = false});

  final String label;
  final int seats;
  final bool cox;

  static BoatClass fromName(Object? name) =>
      BoatClass.values.firstWhere((b) => b.name == name, orElse: () => BoatClass.eight);
}

/// A saved crew: who sits in which seat. Seat 1 is bow, seat n is stroke.
///
/// Straps stay linked to athletes (`KnownSensor.athleteId`), not seats, so
/// moving a rower moves their strap with them.
@immutable
class Lineup {
  const Lineup({
    required this.id,
    required this.name,
    required this.boatClass,
    required this.seats,
    this.coxId,
  });

  /// An empty lineup for [boatClass].
  factory Lineup.empty({required String id, required String name, BoatClass? boatClass}) {
    final b = boatClass ?? BoatClass.eight;
    return Lineup(id: id, name: name, boatClass: b, seats: List.filled(b.seats, null));
  }

  final String id;
  final String name;
  final BoatClass boatClass;

  /// Athlete id per seat; index 0 is seat 1 (bow). Always [BoatClass.seats]
  /// long.
  final List<String?> seats;
  final String? coxId;

  int get seatCount => seats.length;

  /// Seat number (1-based) of [athleteId], or null.
  int? seatOf(String athleteId) {
    final i = seats.indexOf(athleteId);
    return i < 0 ? null : i + 1;
  }

  bool contains(String athleteId) => seats.contains(athleteId) || coxId == athleteId;

  Iterable<String> get athleteIds => seats.whereType<String>();

  bool get isEmpty => seats.every((s) => s == null);

  /// "STROKE", "BOW" or "SEAT" for seat [n] (1-based).
  String roleOf(int n) {
    if (seatCount == 1) return 'SCULL';
    if (n == seatCount) return 'STROKE';
    if (n == 1) return 'BOW';
    return 'SEAT';
  }

  Lineup copyWith({
    String? name,
    BoatClass? boatClass,
    List<String?>? seats,
    String? Function()? coxId,
  }) {
    final b = boatClass ?? this.boatClass;
    var s = List<String?>.of(seats ?? this.seats);
    if (s.length != b.seats) {
      // Changing boat class keeps the bow-end seats and drops the rest.
      s = [for (var i = 0; i < b.seats; i++) i < s.length ? s[i] : null];
    }
    return Lineup(
      id: id,
      name: name ?? this.name,
      boatClass: b,
      seats: List.unmodifiable(s),
      coxId: b.cox ? (coxId != null ? coxId() : this.coxId) : null,
    );
  }

  /// Puts [athleteId] in seat [n] (1-based), swapping with whoever is there.
  Lineup placeInSeat(String? athleteId, int n) {
    final s = List<String?>.of(seats);
    final from = athleteId == null ? -1 : s.indexOf(athleteId);
    final displaced = s[n - 1];
    if (from >= 0) s[from] = displaced;
    s[n - 1] = athleteId;
    final cox = coxId == athleteId ? null : coxId;
    return Lineup(
      id: id,
      name: name,
      boatClass: boatClass,
      seats: List.unmodifiable(s),
      coxId: cox,
    );
  }

  /// Swaps the occupants of seats [a] and [b] (1-based).
  Lineup swapSeats(int a, int b) {
    final s = List<String?>.of(seats);
    final t = s[a - 1];
    s[a - 1] = s[b - 1];
    s[b - 1] = t;
    return copyWith(seats: s);
  }

  /// Removes [athleteId] from the boat (seat or cox).
  Lineup remove(String athleteId) => copyWith(
    seats: [for (final s in seats) s == athleteId ? null : s],
    coxId: coxId == athleteId ? () => null : null,
  );

  /// Drops athletes that no longer exist.
  Lineup prune(Set<String> existing) => copyWith(
    seats: [for (final s in seats) s != null && existing.contains(s) ? s : null],
    coxId: coxId != null && !existing.contains(coxId) ? () => null : null,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'boat': boatClass.name,
    'seats': seats,
    'cox': coxId,
  };

  static Lineup? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final boat = BoatClass.fromName(json['boat']);
    final raw = json['seats'] is List ? json['seats'] as List : const <Object?>[];
    final seats = [
      for (var i = 0; i < boat.seats; i++)
        i < raw.length && raw[i] is String ? raw[i] as String : null,
    ];
    return Lineup(
      id: id,
      name: name,
      boatClass: boat,
      seats: List.unmodifiable(seats),
      coxId: boat.cox && json['cox'] is String ? json['cox'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Lineup &&
      other.id == id &&
      other.name == name &&
      other.boatClass == boatClass &&
      listEquals(other.seats, seats) &&
      other.coxId == coxId;

  @override
  int get hashCode => Object.hash(id, name, boatClass, Object.hashAll(seats), coxId);
}

/// All saved lineups, which one is in use, and the live-screen seat order.
@immutable
class LineupBook {
  const LineupBook({this.lineups = const [], this.activeId, this.strokeFirst = true});

  static const empty = LineupBook();

  final List<Lineup> lineups;
  final String? activeId;

  /// Live screen lists stroke seat first (default) or bow first.
  final bool strokeFirst;

  Lineup? get active {
    for (final l in lineups) {
      if (l.id == activeId) return l;
    }
    return lineups.isEmpty ? null : lineups.first;
  }

  LineupBook copyWith({List<Lineup>? lineups, String? Function()? activeId, bool? strokeFirst}) =>
      LineupBook(
        lineups: lineups ?? this.lineups,
        activeId: activeId != null ? activeId() : this.activeId,
        strokeFirst: strokeFirst ?? this.strokeFirst,
      );

  /// Replaces (or adds) [lineup].
  LineupBook put(Lineup lineup) {
    final i = lineups.indexWhere((l) => l.id == lineup.id);
    final next = List<Lineup>.of(lineups);
    if (i < 0) {
      next.add(lineup);
    } else {
      next[i] = lineup;
    }
    return copyWith(lineups: List.unmodifiable(next));
  }

  Map<String, Object?> toJson() => {
    'lineups': [for (final l in lineups) l.toJson()],
    'active': activeId,
    'strokeFirst': strokeFirst,
  };

  factory LineupBook.fromJson(Object? json) {
    if (json is! Map) return empty;
    final raw = json['lineups'] is List ? json['lineups'] as List : const <Object?>[];
    return LineupBook(
      lineups: List.unmodifiable(raw.map(Lineup.fromJson).whereType<Lineup>()),
      activeId: json['active'] is String ? json['active'] as String : null,
      strokeFirst: json['strokeFirst'] is bool ? json['strokeFirst']! as bool : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LineupBook &&
      listEquals(other.lineups, lineups) &&
      other.activeId == activeId &&
      other.strokeFirst == strokeFirst;

  @override
  int get hashCode => Object.hash(Object.hashAll(lineups), activeId, strokeFirst);
}
