import 'package:flutter/foundation.dart';

import 'hr_zones.dart';

/// An athlete. Identified by a stable internal UUID, never by name.
///
/// The athlete <-> sensor relationship is stored on the sensor side
/// (`KnownSensor.athleteId`) so either can be reassigned independently.
@immutable
class Athlete {
  const Athlete({
    required this.id,
    required this.name,
    this.nickname,
    this.age,
    this.maxHrOverride,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? nickname;
  final int? age;

  /// Manually configured max HR. Takes precedence over the age estimate.
  final int? maxHrOverride;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Name shown on the dashboard: nickname if set, else name.
  String get displayName =>
      (nickname != null && nickname!.trim().isNotEmpty) ? nickname!.trim() : name;

  /// Manual max HR if set, otherwise the formula estimate from age, otherwise
  /// null (percent/zone cannot be shown).
  int? effectiveMaxHr(MaxHrFormula formula) {
    if (maxHrOverride != null && maxHrOverride! > 0) return maxHrOverride;
    if (age != null && age! > 0) return formula.estimate(age!);
    return null;
  }

  bool get hasManualMaxHr => maxHrOverride != null && maxHrOverride! > 0;

  Athlete copyWith({
    String? name,
    String? Function()? nickname,
    int? Function()? age,
    int? Function()? maxHrOverride,
    String? Function()? notes,
    DateTime? updatedAt,
  }) {
    return Athlete(
      id: id,
      name: name ?? this.name,
      nickname: nickname != null ? nickname() : this.nickname,
      age: age != null ? age() : this.age,
      maxHrOverride: maxHrOverride != null ? maxHrOverride() : this.maxHrOverride,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'nickname': nickname,
    'age': age,
    'max_hr': maxHrOverride,
    'notes': notes,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory Athlete.fromRow(Map<String, Object?> row) => Athlete(
    id: row['id']! as String,
    name: row['name']! as String,
    nickname: row['nickname'] as String?,
    age: row['age'] as int?,
    maxHrOverride: row['max_hr'] as int?,
    notes: row['notes'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );

  @override
  bool operator ==(Object other) =>
      other is Athlete &&
      other.id == id &&
      other.name == name &&
      other.nickname == nickname &&
      other.age == age &&
      other.maxHrOverride == maxHrOverride &&
      other.notes == notes &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, nickname, age, maxHrOverride, notes, updatedAt);
}
