import 'package:flutter/foundation.dart';

/// A heart-rate sensor the app remembers across restarts.
///
/// [id] is the platform BLE identifier. On iOS this is the CoreBluetooth
/// peripheral UUID: stable for a given iPhone/iPad + strap pair, but different
/// on every other iPhone and it can change if the strap rotates its address
/// (rare for chest straps) or iOS Bluetooth state is reset. On Windows and
/// Android it is the MAC address.
@immutable
class KnownSensor {
  const KnownSensor({
    required this.id,
    this.name,
    this.athleteId,
    this.lastSeenAt,
    this.batteryPercent,
    required this.createdAt,
  });

  final String id;

  /// Last advertised/GATT name, e.g. "Polar H10 ABC123".
  final String? name;

  /// Assigned athlete, or null when the sensor is remembered but unassigned.
  final String? athleteId;
  final DateTime? lastSeenAt;
  final int? batteryPercent;
  final DateTime createdAt;

  bool get isAssigned => athleteId != null;

  KnownSensor copyWith({
    String? Function()? name,
    String? Function()? athleteId,
    DateTime? Function()? lastSeenAt,
    int? Function()? batteryPercent,
  }) {
    return KnownSensor(
      id: id,
      name: name != null ? name() : this.name,
      athleteId: athleteId != null ? athleteId() : this.athleteId,
      lastSeenAt: lastSeenAt != null ? lastSeenAt() : this.lastSeenAt,
      batteryPercent: batteryPercent != null ? batteryPercent() : this.batteryPercent,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'athlete_id': athleteId,
    'last_seen_at': lastSeenAt?.millisecondsSinceEpoch,
    'battery_percent': batteryPercent,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory KnownSensor.fromRow(Map<String, Object?> row) => KnownSensor(
    id: row['id']! as String,
    name: row['name'] as String?,
    athleteId: row['athlete_id'] as String?,
    lastSeenAt: row['last_seen_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['last_seen_at']! as int),
    batteryPercent: row['battery_percent'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );

  @override
  bool operator ==(Object other) =>
      other is KnownSensor &&
      other.id == id &&
      other.name == name &&
      other.athleteId == athleteId &&
      other.lastSeenAt == lastSeenAt &&
      other.batteryPercent == batteryPercent;

  @override
  int get hashCode => Object.hash(id, name, athleteId, lastSeenAt, batteryPercent);
}
