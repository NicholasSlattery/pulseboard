import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../models/connection_event.dart';
import '../models/heart_rate_reading.dart';
import '../models/sensor_state.dart';
import 'ble_adapter.dart';
import 'heart_rate_sensor_connection.dart';
import 'reconnect_policy.dart';

final _log = Logger('BLE.Manager');

/// Global (not per-sensor) Bluetooth status.
@immutable
class BluetoothStatus {
  const BluetoothStatus({
    this.initialized = false,
    this.availability = BleAvailability.unknown,
    this.isScanning = false,
    this.scanAllDevices = false,
    this.scanError,
  });

  final bool initialized;
  final BleAvailability availability;
  final bool isScanning;
  final bool scanAllDevices;
  final String? scanError;

  BluetoothStatus copyWith({
    bool? initialized,
    BleAvailability? availability,
    bool? isScanning,
    bool? scanAllDevices,
    String? Function()? scanError,
  }) => BluetoothStatus(
    initialized: initialized ?? this.initialized,
    availability: availability ?? this.availability,
    isScanning: isScanning ?? this.isScanning,
    scanAllDevices: scanAllDevices ?? this.scanAllDevices,
    scanError: scanError != null ? scanError() : this.scanError,
  );

  @override
  bool operator ==(Object other) =>
      other is BluetoothStatus &&
      other.initialized == initialized &&
      other.availability == availability &&
      other.isScanning == isScanning &&
      other.scanAllDevices == scanAllDevices &&
      other.scanError == scanError;

  @override
  int get hashCode => Object.hash(initialized, availability, isScanning, scanAllDevices, scanError);
}

/// Owns scanning, host Bluetooth state and the collection of
/// [HeartRateSensorConnection]s - one per strap, all independent.
///
/// The UI never talks to BLE directly; it calls methods here and observes
/// [sensors] / [status]. Sensor state emissions are coalesced (at most one
/// every [emitInterval]) so twenty straps notifying at 1 Hz don't cause
/// twenty rebuild passes per second. Readings and events are delivered
/// immediately on their own streams for recording.
class BluetoothManager {
  BluetoothManager({
    required BleAdapter adapter,
    ReconnectPolicy? policy,
    SensorConnectionConfig config = const SensorConnectionConfig(),
    Duration staleAfter = const Duration(seconds: 5),
    Duration signalLostAfter = const Duration(seconds: 15),
    this.emitInterval = const Duration(milliseconds: 100),
    this.defaultScanDuration = const Duration(seconds: 30),
  }) : _adapter = adapter,
       _policy = policy ?? ReconnectPolicy(),
       _config = config,
       _staleAfter = staleAfter,
       _signalLostAfter = signalLostAfter;

  final BleAdapter _adapter;
  final ReconnectPolicy _policy;
  SensorConnectionConfig _config;
  Duration _staleAfter;
  Duration _signalLostAfter;
  final Duration emitInterval;
  final Duration defaultScanDuration;

  final Map<String, HeartRateSensorConnection> _connections = {};

  /// Devices seen in scans that have no connection object (never connected).
  final Map<String, SensorLiveState> _discoveredOnly = {};

  /// Sensors the user explicitly disconnected this run. They are not
  /// auto-connected again until the user connects them manually.
  final Set<String> _userDisconnected = {};

  final _sensorsController = StreamController<Map<String, SensorLiveState>>.broadcast();
  final _statusController = StreamController<BluetoothStatus>.broadcast();
  final _readingsController = StreamController<HeartRateReading>.broadcast();
  final _eventsController = StreamController<ConnectionEvent>.broadcast();

  Map<String, SensorLiveState> _sensors = const {};
  BluetoothStatus _status = const BluetoothStatus();

  StreamSubscription<BleAvailability>? _availabilitySub;
  StreamSubscription<BleAdvertisement>? _adSub;
  Timer? _emitTimer;
  Timer? _freshnessTimer;
  Timer? _scanStopTimer;
  bool _disposed = false;

  // --- Observables -----------------------------------------------------------

  Map<String, SensorLiveState> get sensors => _sensors;
  Stream<Map<String, SensorLiveState>> get sensorsStream => _sensorsController.stream;

  BluetoothStatus get status => _status;
  Stream<BluetoothStatus> get statusStream => _statusController.stream;

  /// Every valid HR reading from every sensor, in arrival order.
  Stream<HeartRateReading> get readings => _readingsController.stream;

  /// Connection lifecycle events from every sensor.
  Stream<ConnectionEvent> get events => _eventsController.stream;

  bool get _bluetoothReady => _status.availability.isReady;

  // --- Lifecycle ------------------------------------------------------------

  /// Starts observing Bluetooth. On iOS this is what triggers the permission
  /// prompt, so the UI calls it only after explaining why.
  Future<void> initialize() async {
    if (_status.initialized || _disposed) return;
    _log.info('Initializing Bluetooth');
    await _adapter.requestPermission();
    _setStatus(_status.copyWith(initialized: true));
    _availabilitySub = _adapter.availabilityChanges.listen(_onAvailability);
    _adSub = _adapter.advertisements.listen(_onAdvertisement);
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshFreshness());
    _onAvailability(await _adapter.getAvailability());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Stop every timer synchronously first (connection.dispose() cancels its
    // timers before its first await), then release subscriptions.
    _emitTimer?.cancel();
    _freshnessTimer?.cancel();
    _scanStopTimer?.cancel();
    final connections = _connections.values.toList();
    _connections.clear();
    final pending = <Future<void>>[for (final c in connections) c.dispose()];
    await _availabilitySub?.cancel();
    await _adSub?.cancel();
    await Future.wait(pending);
    await _sensorsController.close();
    await _statusController.close();
    await _readingsController.close();
    await _eventsController.close();
  }

  // --- Scanning ---------------------------------------------------------------

  /// Scans for heart-rate straps (or every BLE device with [allDevices]) for
  /// [duration], then stops automatically to save battery.
  Future<void> startScan({bool allDevices = false, Duration? duration}) async {
    if (_disposed) return;
    if (!_status.initialized) await initialize();
    if (!_bluetoothReady) {
      _setStatus(_status.copyWith(scanError: () => 'Bluetooth is not available'));
      return;
    }
    if (_status.isScanning) await stopScan();

    _discoveredOnly.clear();
    _scheduleEmit();
    _setStatus(
      _status.copyWith(isScanning: true, scanAllDevices: allDevices, scanError: () => null),
    );
    _log.info('Scan started (${allDevices ? 'all devices' : 'heart-rate only'})');

    // Straps already connected to the phone by another app don't advertise.
    unawaited(_addSystemConnectedDevices());

    try {
      await _adapter.startScan(heartRateOnly: !allDevices);
    } on BleException catch (e) {
      _log.warning('Scan failed: $e');
      _setStatus(_status.copyWith(isScanning: false, scanError: () => e.userMessage));
      return;
    }
    _scanStopTimer?.cancel();
    _scanStopTimer = Timer(duration ?? defaultScanDuration, () => unawaited(stopScan()));
  }

  Future<void> stopScan() async {
    _scanStopTimer?.cancel();
    _scanStopTimer = null;
    if (!_status.isScanning) return;
    await _adapter.stopScan();
    _setStatus(_status.copyWith(isScanning: false));
    _log.info('Scan stopped');
  }

  Future<void> _addSystemConnectedDevices() async {
    final devices = await _adapter.getSystemConnectedHeartRateDevices();
    for (final d in devices) {
      _onAdvertisement(d);
    }
  }

  // --- Connections ------------------------------------------------------------

  /// User asked to connect [sensorId].
  void connect(String sensorId) {
    if (_disposed) return;
    _userDisconnected.remove(sensorId);
    _connectionFor(sensorId).connect();
  }

  /// User asked to disconnect [sensorId]. It stays disconnected until the
  /// user connects it again.
  Future<void> disconnect(String sensorId) async {
    _userDisconnected.add(sensorId);
    await _connections[sensorId]?.disconnect();
  }

  /// Keeps connections in sync with remembered, assigned sensors: every
  /// assigned sensor is kept connected (unless the user disconnected it this
  /// run). Remembered sensor names seed the display before the first scan.
  void syncAssignedSensors(Map<String, String?> assignedSensorNames) {
    if (_disposed) return;
    for (final entry in assignedSensorNames.entries) {
      final id = entry.key;
      final existing = _connections[id];
      if (existing == null) {
        _connectionFor(id, nameHint: entry.value);
      }
      final conn = _connections[id]!;
      if (!conn.wanted &&
          !_userDisconnected.contains(id) &&
          conn.state.connection != SensorConnectionState.failed) {
        conn.connect();
      }
    }
  }

  /// Disconnects and drops all runtime state for [sensorId].
  Future<void> forget(String sensorId) async {
    _userDisconnected.remove(sensorId);
    final conn = _connections.remove(sensorId);
    _discoveredOnly.remove(sensorId);
    if (conn != null) {
      await conn.disconnect(userInitiated: false);
      await conn.dispose();
    }
    _scheduleEmit();
  }

  /// Applies changed preferences to every connection.
  void updateSettings({
    required bool autoReconnect,
    required Duration staleAfter,
    required Duration signalLostAfter,
    required bool verbose,
  }) {
    _staleAfter = staleAfter;
    _signalLostAfter = signalLostAfter;
    _config = _config.copyWith(autoReconnect: autoReconnect, verbose: verbose);
    for (final c in _connections.values) {
      c.updateConfig(_config);
    }
    _refreshFreshness();
  }

  /// Called when the app returns to the foreground. iOS may have suspended
  /// us long enough for links to go quiet; recycle any that did.
  Future<void> onAppResumed() async {
    if (!_status.initialized || _disposed) return;
    _log.info('App resumed - verifying connections');
    final availability = await _adapter.getAvailability();
    _onAvailability(availability);
    for (final c in _connections.values.toList()) {
      await c.recycleIfIdle(_signalLostAfter);
    }
    _refreshFreshness();
  }

  HeartRateSensorConnection _connectionFor(String sensorId, {String? nameHint}) {
    final existing = _connections[sensorId];
    if (existing != null) return existing;
    final discovered = _discoveredOnly.remove(sensorId);
    final initial = (discovered ?? SensorLiveState(sensorId: sensorId, name: nameHint));
    final conn = HeartRateSensorConnection(
      sensorId: sensorId,
      adapter: _adapter,
      policy: _policy,
      config: _config,
      initialState: initial.name == null && nameHint != null
          ? initial.copyWith(name: () => nameHint)
          : initial,
      bluetoothReady: _bluetoothReady,
      knownHeartRateSensor: nameHint != null || (discovered?.advertisesHeartRate ?? false),
      onStateChanged: (_) => _scheduleEmit(),
      onReading: (r) {
        if (!_readingsController.isClosed) _readingsController.add(r);
      },
      onEvent: (e) {
        if (!_eventsController.isClosed) _eventsController.add(e);
      },
    );
    _connections[sensorId] = conn;
    _scheduleEmit();
    return conn;
  }

  // --- Event handlers ---------------------------------------------------------

  void _onAvailability(BleAvailability availability) {
    if (_disposed || availability == _status.availability) return;
    _log.info('Bluetooth availability: ${availability.name}');
    final ready = availability.isReady;
    final wasScanning = _status.isScanning;
    _setStatus(
      _status.copyWith(availability: availability, isScanning: ready ? _status.isScanning : false),
    );
    if (!ready && wasScanning) _scanStopTimer?.cancel();
    for (final c in _connections.values) {
      c.onBluetoothAvailability(ready);
    }
  }

  void _onAdvertisement(BleAdvertisement ad) {
    if (_disposed) return;
    final conn = _connections[ad.deviceId];
    if (conn != null) {
      conn.onAdvertisement(ad);
      return;
    }
    // In heart-rate mode, only keep devices that advertise 0x180D (the OS
    // usually filters already; this guards platforms that don't).
    if (!_status.scanAllDevices && !ad.advertisesHeartRate && !ad.isSystemConnected) return;

    final previous =
        _discoveredOnly[ad.deviceId] ??
        SensorLiveState(sensorId: ad.deviceId, connection: SensorConnectionState.discovered);
    _discoveredOnly[ad.deviceId] = previous.copyWith(
      name: ad.name != null ? () => ad.name : null,
      rssi: ad.rssi != null ? () => ad.rssi : null,
      advertisesHeartRate: previous.advertisesHeartRate || ad.advertisesHeartRate,
      lastAdvertisementAt: () => ad.timestamp,
      isSystemConnected: previous.isSystemConnected || ad.isSystemConnected,
    );
    if (previous.lastAdvertisementAt == null) {
      _log.info(
        'Sensor discovered: ${_shortId(ad.deviceId)} '
        '(${ad.advertisesHeartRate ? 'HR service' : 'no HR service advertised'})',
      );
    }
    _scheduleEmit();
  }

  void _refreshFreshness() {
    final now = clock.now();
    for (final c in _connections.values) {
      c.refreshFreshness(now, _staleAfter, _signalLostAfter);
    }
  }

  // --- Emission ---------------------------------------------------------------

  void _scheduleEmit() {
    if (_disposed || _emitTimer != null) return;
    _emitTimer = Timer(emitInterval, _emitNow);
  }

  void _emitNow() {
    _emitTimer = null;
    if (_disposed) return;
    final next = <String, SensorLiveState>{
      ..._discoveredOnly,
      for (final c in _connections.values) c.sensorId: c.state,
    };
    _sensors = Map.unmodifiable(next);
    _sensorsController.add(_sensors);
  }

  /// Emits pending sensor state immediately (tests and shutdown).
  @visibleForTesting
  void flushEmit() {
    _emitTimer?.cancel();
    _emitNow();
  }

  void _setStatus(BluetoothStatus next) {
    if (next == _status || _disposed) return;
    _status = next;
    _statusController.add(next);
  }

  static String _shortId(String id) => id.length > 8 ? '…${id.substring(id.length - 8)}' : id;
}
