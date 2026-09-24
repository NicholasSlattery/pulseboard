import 'package:flutter/foundation.dart';

/// Connection lifecycle events worth recording in a session and in logs.
enum ConnectionEventType {
  /// Link established and HR notifications enabled.
  connected,

  /// First HR packet received after connecting.
  receiving,

  /// Link dropped unexpectedly (signal loss, strap asleep, out of range).
  lost,

  /// A reconnection attempt started.
  reconnectAttempt,

  /// A connection/reconnection attempt failed.
  attemptFailed,

  /// Connected but no data arrived for too long; link was recycled.
  dataTimeout,

  /// User asked to disconnect.
  userDisconnected,

  /// Gave up (e.g. device has no Heart Rate Service).
  failed;

  static ConnectionEventType fromName(String name) => ConnectionEventType.values.firstWhere(
    (e) => e.name == name,
    orElse: () => ConnectionEventType.failed,
  );
}

@immutable
class ConnectionEvent {
  const ConnectionEvent({
    required this.sensorId,
    required this.type,
    required this.timestamp,
    this.detail,
  });

  final String sensorId;
  final ConnectionEventType type;
  final DateTime timestamp;
  final String? detail;

  @override
  String toString() =>
      'ConnectionEvent(${type.name}, $sensorId${detail == null ? '' : ', $detail'})';
}
