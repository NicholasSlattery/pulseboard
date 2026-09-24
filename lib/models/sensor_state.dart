import 'package:flutter/foundation.dart';

import 'heart_rate_measurement.dart';

/// Per-sensor connection state machine states.
///
/// ```text
///  discovered/disconnected --connect--> connecting --link up--> connected
///  connected --services ok--> subscribing --first packet--> receiving
///  (connected|subscribing|receiving) --link lost--> reconnecting --backoff--> connecting
///  connecting --timeout/error--> reconnecting (or disconnected if auto-reconnect is off)
///  any --user disconnect--> disconnected
///  connected --not a HR sensor--> failed
/// ```
enum SensorConnectionState {
  /// Seen in a scan, never asked to connect.
  discovered,

  /// A connection attempt is in progress.
  connecting,

  /// Link is up; discovering GATT services.
  connected,

  /// Enabling Heart Rate Measurement notifications / waiting for the first
  /// packet.
  subscribing,

  /// Notifications are flowing.
  receiving,

  /// Link was lost (or an attempt failed); waiting to retry with backoff.
  reconnecting,

  /// Not connected and not trying to connect.
  disconnected,

  /// Gave up: e.g. the device has no Heart Rate Service. Needs user action.
  failed;

  /// True while a physical link is up.
  bool get isLinkUp => this == connected || this == subscribing || this == receiving;

  /// True when the app wants this sensor connected and is working on it.
  bool get isTrying =>
      this == connecting || this == connected || this == subscribing || this == reconnecting;
}

/// How recent the last heart-rate reading is.
enum SignalFreshness {
  /// No reading yet in this connection.
  none,

  /// Last reading is within the stale timeout. Display normally.
  fresh,

  /// Last reading is older than the stale timeout: show it greyed out with a
  /// signal warning.
  stale,

  /// Last reading is older than the signal-lost timeout: show "--".
  lost,
}

/// Immutable snapshot of everything the UI needs to know about one sensor.
@immutable
class SensorLiveState {
  const SensorLiveState({
    required this.sensorId,
    this.name,
    this.connection = SensorConnectionState.discovered,
    this.rssi,
    this.advertisesHeartRate = false,
    this.batteryPercent,
    this.bpm,
    this.lastReadingAt,
    this.contact = SensorContact.notSupported,
    this.freshness = SignalFreshness.none,
    this.lastAdvertisementAt,
    this.error,
    this.reconnectAttempt = 0,
    this.nextReconnectAt,
    this.connectedSince,
    this.hasEverReceived = false,
    this.isSystemConnected = false,
  });

  final String sensorId;
  final String? name;
  final SensorConnectionState connection;
  final int? rssi;

  /// True if Heart Rate Service 0x180D was seen in the advertisement or in
  /// GATT discovery.
  final bool advertisesHeartRate;
  final int? batteryPercent;

  /// Last valid BPM received on the current connection. Use [displayBpm] in
  /// the UI; this raw field may be old.
  final int? bpm;
  final DateTime? lastReadingAt;
  final SensorContact contact;
  final SignalFreshness freshness;
  final DateTime? lastAdvertisementAt;

  /// Human-readable description of the most recent problem, if any.
  final String? error;
  final int reconnectAttempt;
  final DateTime? nextReconnectAt;
  final DateTime? connectedSince;

  /// Whether this sensor has ever delivered HR data during this app run.
  final bool hasEverReceived;

  /// The OS reports this device as already connected (possibly by another
  /// app) - it will not show up in scans.
  final bool isSystemConnected;

  /// The BPM that may be shown as current: only while receiving and not
  /// past the signal-lost timeout. Never returns an old value as current.
  int? get displayBpm {
    if (connection != SensorConnectionState.receiving) return null;
    if (freshness == SignalFreshness.fresh || freshness == SignalFreshness.stale) {
      return bpm;
    }
    return null;
  }

  bool get isStale => displayBpm != null && freshness == SignalFreshness.stale;

  bool get noSkinContact =>
      connection == SensorConnectionState.receiving && contact == SensorContact.notDetected;

  SensorLiveState copyWith({
    String? Function()? name,
    SensorConnectionState? connection,
    int? Function()? rssi,
    bool? advertisesHeartRate,
    int? Function()? batteryPercent,
    int? Function()? bpm,
    DateTime? Function()? lastReadingAt,
    SensorContact? contact,
    SignalFreshness? freshness,
    DateTime? Function()? lastAdvertisementAt,
    String? Function()? error,
    int? reconnectAttempt,
    DateTime? Function()? nextReconnectAt,
    DateTime? Function()? connectedSince,
    bool? hasEverReceived,
    bool? isSystemConnected,
  }) {
    return SensorLiveState(
      sensorId: sensorId,
      name: name != null ? name() : this.name,
      connection: connection ?? this.connection,
      rssi: rssi != null ? rssi() : this.rssi,
      advertisesHeartRate: advertisesHeartRate ?? this.advertisesHeartRate,
      batteryPercent: batteryPercent != null ? batteryPercent() : this.batteryPercent,
      bpm: bpm != null ? bpm() : this.bpm,
      lastReadingAt: lastReadingAt != null ? lastReadingAt() : this.lastReadingAt,
      contact: contact ?? this.contact,
      freshness: freshness ?? this.freshness,
      lastAdvertisementAt: lastAdvertisementAt != null
          ? lastAdvertisementAt()
          : this.lastAdvertisementAt,
      error: error != null ? error() : this.error,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      nextReconnectAt: nextReconnectAt != null ? nextReconnectAt() : this.nextReconnectAt,
      connectedSince: connectedSince != null ? connectedSince() : this.connectedSince,
      hasEverReceived: hasEverReceived ?? this.hasEverReceived,
      isSystemConnected: isSystemConnected ?? this.isSystemConnected,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SensorLiveState &&
      other.sensorId == sensorId &&
      other.name == name &&
      other.connection == connection &&
      other.rssi == rssi &&
      other.advertisesHeartRate == advertisesHeartRate &&
      other.batteryPercent == batteryPercent &&
      other.bpm == bpm &&
      other.lastReadingAt == lastReadingAt &&
      other.contact == contact &&
      other.freshness == freshness &&
      other.lastAdvertisementAt == lastAdvertisementAt &&
      other.error == error &&
      other.reconnectAttempt == reconnectAttempt &&
      other.nextReconnectAt == nextReconnectAt &&
      other.connectedSince == connectedSince &&
      other.hasEverReceived == hasEverReceived &&
      other.isSystemConnected == isSystemConnected;

  @override
  int get hashCode => Object.hash(
    sensorId,
    name,
    connection,
    rssi,
    advertisesHeartRate,
    batteryPercent,
    bpm,
    lastReadingAt,
    contact,
    freshness,
    lastAdvertisementAt,
    error,
    reconnectAttempt,
    nextReconnectAt,
    connectedSince,
    hasEverReceived,
    isSystemConnected,
  );
}
