import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';

import '../models/connection_event.dart';
import '../models/heart_rate_reading.dart';
import '../models/sensor_state.dart';
import 'ble_adapter.dart';
import 'ble_uuids.dart';
import 'heart_rate_parser.dart';
import 'reconnect_policy.dart';

final _log = Logger('BLE.Sensor');

/// Timing configuration for one sensor connection.
class SensorConnectionConfig {
  const SensorConnectionConfig({
    this.autoReconnect = true,
    this.connectTimeout = const Duration(seconds: 20),
    this.gattTimeout = const Duration(seconds: 10),
    this.noDataTimeout = const Duration(seconds: 30),
    this.watchdogInterval = const Duration(seconds: 5),
    this.rssiInterval = const Duration(seconds: 10),
    this.batteryInterval = const Duration(minutes: 5),
    this.verbose = false,
  });

  final bool autoReconnect;
  final Duration connectTimeout;
  final Duration gattTimeout;

  /// If subscribed but no packet (valid or not) arrives for this long, the
  /// link is assumed to be a zombie (common after iOS suspends the app) and
  /// is torn down and re-established.
  final Duration noDataTimeout;
  final Duration watchdogInterval;
  final Duration rssiInterval;
  final Duration batteryInterval;

  /// Log every HR packet.
  final bool verbose;

  SensorConnectionConfig copyWith({bool? autoReconnect, bool? verbose}) => SensorConnectionConfig(
    autoReconnect: autoReconnect ?? this.autoReconnect,
    connectTimeout: connectTimeout,
    gattTimeout: gattTimeout,
    noDataTimeout: noDataTimeout,
    watchdogInterval: watchdogInterval,
    rssiInterval: rssiInterval,
    batteryInterval: batteryInterval,
    verbose: verbose ?? this.verbose,
  );
}

/// Owns everything about ONE heart-rate strap: its link, GATT setup,
/// notification stream, freshness and reconnect behaviour.
///
/// Instances are fully independent; [BluetoothManager] holds a collection of
/// them. Nothing here assumes there is only one strap.
///
/// Concurrency model: every asynchronous continuation captures the current
/// [_epoch] and bails out if it changed in the meantime (user disconnected,
/// link lost, Bluetooth turned off...). That makes it safe for BLE events to
/// arrive in any order.
class HeartRateSensorConnection {
  HeartRateSensorConnection({
    required this.sensorId,
    required BleAdapter adapter,
    required void Function(HeartRateSensorConnection) onStateChanged,
    required void Function(HeartRateReading) onReading,
    required void Function(ConnectionEvent) onEvent,
    ReconnectPolicy? policy,
    SensorConnectionConfig config = const SensorConnectionConfig(),
    SensorLiveState? initialState,
    bool bluetoothReady = true,
    bool knownHeartRateSensor = false,
  }) : _adapter = adapter,
       _onStateChanged = onStateChanged,
       _onReading = onReading,
       _onEvent = onEvent,
       _policy = policy ?? ReconnectPolicy(),
       _config = config,
       _bluetoothReady = bluetoothReady,
       _knownHeartRateSensor = knownHeartRateSensor,
       _state = (initialState ?? SensorLiveState(sensorId: sensorId)).copyWith(
         connection: SensorConnectionState.disconnected,
       ) {
    _linkSub = _adapter
        .connectionChanges(sensorId)
        .listen(
          _onLinkChange,
          onError: (Object e) => _log.warning('[$_short] link stream error: $e'),
        );
  }

  final String sensorId;
  final BleAdapter _adapter;
  final void Function(HeartRateSensorConnection) _onStateChanged;
  final void Function(HeartRateReading) _onReading;
  final void Function(ConnectionEvent) _onEvent;
  final ReconnectPolicy _policy;
  SensorConnectionConfig _config;

  SensorLiveState _state;
  SensorLiveState get state => _state;

  /// Whether the app wants this sensor connected.
  bool get wanted => _wanted;
  bool _wanted = false;

  bool _bluetoothReady;
  bool _knownHeartRateSensor;
  bool _connectInFlight = false;
  bool _disposed = false;
  int _epoch = 0;
  int _retryAttempt = 0;
  int _malformedPackets = 0;
  DateTime? _lastPacketAt;
  DateTime? _subscribedAt;

  StreamSubscription<bool>? _linkSub;
  StreamSubscription<List<int>>? _dataSub;
  Timer? _retryTimer;
  Timer? _watchdogTimer;
  Timer? _rssiTimer;
  Timer? _batteryTimer;
  bool _hasBatteryService = false;

  String get _short => sensorId.length > 8 ? sensorId.substring(sensorId.length - 8) : sensorId;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Ask for this sensor to be connected (and kept connected).
  void connect() {
    if (_disposed) return;
    _wanted = true;
    if (_state.connection.isLinkUp || _connectInFlight) return;
    _retryAttempt = 0;
    _cancelRetryTimer();
    unawaited(_attempt());
  }

  /// Disconnect and stop reconnecting.
  Future<void> disconnect({bool userInitiated = true}) async {
    if (_disposed) return;
    final wasActive =
        _state.connection != SensorConnectionState.disconnected &&
        _state.connection != SensorConnectionState.discovered;
    _wanted = false;
    _epoch++;
    _connectInFlight = false;
    _cancelRetryTimer();
    _stopLinkTimers();
    _cancelDataSub();
    _update(
      (s) => s.copyWith(
        connection: SensorConnectionState.disconnected,
        freshness: SignalFreshness.none,
        nextReconnectAt: () => null,
        reconnectAttempt: 0,
        connectedSince: () => null,
        error: () => null,
      ),
    );
    if (wasActive) {
      _log.info('[$_short] Disconnecting (${userInitiated ? 'user' : 'app'})');
      if (userInitiated) _emit(ConnectionEventType.userDisconnected);
    }
    await _adapter.disconnect(sensorId);
  }

  /// Called for every advertisement from this device while scanning.
  void onAdvertisement(BleAdvertisement ad) {
    if (_disposed) return;
    _update(
      (s) => s.copyWith(
        name: ad.name != null ? () => ad.name : null,
        rssi: ad.rssi != null ? () => ad.rssi : null,
        advertisesHeartRate: s.advertisesHeartRate || ad.advertisesHeartRate,
        lastAdvertisementAt: () => ad.timestamp,
        isSystemConnected: ad.isSystemConnected,
      ),
    );
    // The strap is advertising, so it is reachable right now: skip the rest
    // of the backoff wait.
    if (_wanted &&
        _state.connection == SensorConnectionState.reconnecting &&
        _retryTimer != null &&
        !_connectInFlight) {
      _log.info('[$_short] Seen advertising while waiting to reconnect - retrying now');
      _cancelRetryTimer();
      unawaited(_attempt());
    }
  }

  /// Host Bluetooth turned on/off.
  void onBluetoothAvailability(bool ready) {
    if (_disposed || ready == _bluetoothReady) return;
    _bluetoothReady = ready;
    if (!ready) {
      final wasLinkUp = _state.connection.isLinkUp;
      _epoch++;
      _connectInFlight = false;
      _cancelRetryTimer();
      _stopLinkTimers();
      _cancelDataSub();
      if (wasLinkUp) _emit(ConnectionEventType.lost, 'Bluetooth turned off');
      _update(
        (s) => s.copyWith(
          connection: _wanted
              ? SensorConnectionState.reconnecting
              : SensorConnectionState.disconnected,
          freshness: SignalFreshness.none,
          error: () => _wanted ? 'Waiting for Bluetooth' : null,
          nextReconnectAt: () => null,
          connectedSince: () => null,
        ),
      );
    } else if (_wanted && !_state.connection.isLinkUp && !_connectInFlight) {
      _log.info('[$_short] Bluetooth back on - reconnecting');
      _retryAttempt = 0;
      _cancelRetryTimer();
      unawaited(_attempt());
    }
  }

  void updateConfig(SensorConnectionConfig config) {
    final reconnectTurnedOn = config.autoReconnect && !_config.autoReconnect;
    _config = config;
    if (reconnectTurnedOn && _wanted && _state.connection == SensorConnectionState.disconnected) {
      connect();
    }
  }

  /// Re-evaluates signal freshness. Returns true if it changed.
  bool refreshFreshness(DateTime now, Duration staleAfter, Duration lostAfter) {
    final SignalFreshness next;
    final last = _state.lastReadingAt;
    if (_state.connection != SensorConnectionState.receiving || last == null) {
      next = SignalFreshness.none;
    } else {
      final age = now.difference(last);
      next = age <= staleAfter
          ? SignalFreshness.fresh
          : (age <= lostAfter ? SignalFreshness.stale : SignalFreshness.lost);
    }
    if (next == _state.freshness) return false;
    if (next == SignalFreshness.stale || next == SignalFreshness.lost) {
      _log.info('[$_short] Signal ${next.name}');
    }
    _update((s) => s.copyWith(freshness: next));
    return true;
  }

  /// Forces a fresh connection. Used when returning from background, where
  /// iOS may have left links in a zombie state.
  Future<void> recycleIfIdle(Duration maxSilence) async {
    if (_disposed || !_wanted) return;
    if (_state.connection == SensorConnectionState.reconnecting && !_connectInFlight) {
      _cancelRetryTimer();
      _retryAttempt = 0;
      unawaited(_attempt());
      return;
    }
    if (_state.connection.isLinkUp) {
      final last = _lastPacketAt ?? _subscribedAt;
      if (last == null || clock.now().difference(last) > maxSilence) {
        _log.info('[$_short] No recent data after resume - recycling link');
        _emit(ConnectionEventType.dataTimeout, 'No data after returning to app');
        await _teardownAndRetry('No data after returning to app');
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _cancelRetryTimer();
    _stopLinkTimers();
    _cancelDataSub();
    await _linkSub?.cancel();
    _linkSub = null;
  }

  // ---------------------------------------------------------------------------
  // Connection sequence
  // ---------------------------------------------------------------------------

  Future<void> _attempt() async {
    if (_disposed || !_wanted || _connectInFlight) return;
    if (!_bluetoothReady) {
      _update(
        (s) => s.copyWith(
          connection: SensorConnectionState.reconnecting,
          error: () => 'Waiting for Bluetooth',
          nextReconnectAt: () => null,
        ),
      );
      return;
    }

    final epoch = ++_epoch;
    _connectInFlight = true;
    final isRetry = _retryAttempt > 0;
    _update(
      (s) => s.copyWith(connection: SensorConnectionState.connecting, nextReconnectAt: () => null),
    );
    _log.info('[$_short] ${isRetry ? 'Reconnect attempt $_retryAttempt' : 'Connecting'}');
    if (isRetry) _emit(ConnectionEventType.reconnectAttempt, 'attempt $_retryAttempt');

    try {
      await _adapter.connect(sensorId, timeout: _config.connectTimeout);
    } catch (e) {
      _connectInFlight = false;
      if (_isStale(epoch)) return;
      final message = e is BleException ? e.userMessage : 'Connection failed';
      _log.warning('[$_short] Connect failed: $e');
      _emit(ConnectionEventType.attemptFailed, e is BleException ? e.kind.name : '$e');
      // CoreBluetooth keeps connection requests pending forever; cancel it so
      // we don't end up with an unexpected link later.
      await _teardownAndRetry(message);
      return;
    }
    _connectInFlight = false;

    if (_disposed) return;
    if (!_wanted) {
      // User disconnected while we were connecting.
      await _adapter.disconnect(sensorId);
      return;
    }
    if (_isStale(epoch)) return;
    await _setUpGatt(epoch);
  }

  Future<void> _setUpGatt(int epoch) async {
    _log.info('[$_short] Connected');
    _update(
      (s) => s.copyWith(
        connection: SensorConnectionState.connected,
        connectedSince: () => clock.now(),
        error: () => null,
      ),
    );

    try {
      final profile = await _adapter.discoverServices(sensorId, timeout: _config.gattTimeout);
      if (_isStale(epoch)) return;

      if (!profile.hasCharacteristic(BleUuids.heartRateService, BleUuids.heartRateMeasurement)) {
        if (_knownHeartRateSensor) {
          // It delivered HR before, so this is most likely an incomplete GATT
          // discovery; treat as transient.
          throw const BleException(
            BleErrorKind.serviceNotFound,
            'HR service missing on known HR sensor',
          );
        }
        await _fail(
          profile.hasService(BleUuids.heartRateService)
              ? const BleException(BleErrorKind.characteristicNotFound, 'no 0x2A37')
              : const BleException(BleErrorKind.serviceNotFound, 'no 0x180D'),
        );
        return;
      }
      _log.info('[$_short] Heart Rate Service found');
      _knownHeartRateSensor = true;
      _hasBatteryService = profile.hasCharacteristic(
        BleUuids.batteryService,
        BleUuids.batteryLevel,
      );

      _update(
        (s) => s.copyWith(connection: SensorConnectionState.subscribing, advertisesHeartRate: true),
      );

      // Listen before enabling notifications so the first packet is not lost.
      _cancelDataSub();
      _dataSub = _adapter
          .characteristicValues(sensorId, BleUuids.heartRateMeasurement)
          .listen(_onPacket, onError: (Object e) => _log.warning('[$_short] HR stream error: $e'));
      await _adapter.subscribe(
        sensorId,
        BleUuids.heartRateService,
        BleUuids.heartRateMeasurement,
        timeout: _config.gattTimeout,
      );
      if (_isStale(epoch)) return;

      _subscribedAt = clock.now();
      _lastPacketAt = null;
      _log.info('[$_short] Subscribed to Heart Rate Measurement');
      _emit(ConnectionEventType.connected);
      _startLinkTimers(epoch);
      if (_hasBatteryService) unawaited(_readBattery(epoch));
    } catch (e) {
      if (_isStale(epoch)) return;
      final message = e is BleException ? e.userMessage : 'Sensor setup failed';
      _log.warning('[$_short] GATT setup failed: $e');
      _emit(ConnectionEventType.attemptFailed, 'setup: ${e is BleException ? e.kind.name : e}');
      await _teardownAndRetry(message);
    }
  }

  void _onPacket(List<int> bytes) {
    if (_disposed) return;
    final measurement = HeartRateParser.tryParse(bytes);
    if (measurement == null) {
      _malformedPackets++;
      // Log the first few and then every 50th to avoid log spam.
      if (_malformedPackets <= 3 || _malformedPackets % 50 == 0) {
        _log.warning('[$_short] Malformed HR packet #$_malformedPackets (${bytes.length} bytes)');
      }
      return;
    }

    final now = clock.now();
    _lastPacketAt = now;
    final valid = measurement.hasValidHeartRate;
    if (_config.verbose) {
      _log.fine('[$_short] HR ${measurement.bpm} contact=${measurement.contact.name}');
    }

    if (_state.connection != SensorConnectionState.receiving) {
      _log.info('[$_short] Receiving heart rate');
      _retryAttempt = 0;
      _emit(ConnectionEventType.receiving);
    }

    _update(
      (s) => s.copyWith(
        connection: SensorConnectionState.receiving,
        bpm: valid ? () => measurement.bpm : null,
        lastReadingAt: valid ? () => now : null,
        freshness: valid ? SignalFreshness.fresh : null,
        contact: measurement.contact,
        hasEverReceived: true,
        reconnectAttempt: 0,
        nextReconnectAt: () => null,
        error: () => null,
      ),
    );

    if (valid) {
      _onReading(HeartRateReading(sensorId: sensorId, timestamp: now, measurement: measurement));
    }
  }

  // ---------------------------------------------------------------------------
  // Link loss, retry, failure
  // ---------------------------------------------------------------------------

  void _onLinkChange(bool up) {
    if (_disposed) return;
    if (up) {
      if (!_wanted) {
        _log.info('[$_short] Unexpected link up while not wanted - disconnecting');
        unawaited(_adapter.disconnect(sensorId));
        return;
      }
      // connect() is awaiting this event and will continue the sequence.
      if (_connectInFlight || _state.connection.isLinkUp) return;
      // Link came up on its own (e.g. a pending OS-level request completed).
      _log.info('[$_short] Link restored by OS - setting up');
      _cancelRetryTimer();
      unawaited(_setUpGatt(++_epoch));
      return;
    }

    // Link down. During an attempt, the attempt's error path handles it.
    if (_connectInFlight || !_state.connection.isLinkUp) return;
    _log.warning('[$_short] Sensor disconnected unexpectedly');
    _emit(ConnectionEventType.lost, 'Connection lost');

    // Leave the "link up" states synchronously so the UI shows DISCONNECTED
    // immediately and duplicate link-down events are ignored.
    final epoch = ++_epoch;
    _stopLinkTimers();
    _update(
      (s) => s.copyWith(
        connection: SensorConnectionState.reconnecting,
        freshness: SignalFreshness.none,
        error: () => 'Connection lost',
        nextReconnectAt: () => null,
        connectedSince: () => null,
      ),
    );
    _cancelDataSub();
    if (!_isStale(epoch)) _scheduleRetry('Connection lost');
  }

  /// Tears the link down (cancelling any pending request) and schedules a
  /// retry. State is moved off "link up" first so the resulting link-down
  /// event is not mistaken for an unexpected disconnect.
  Future<void> _teardownAndRetry(String reason) async {
    final epoch = ++_epoch;
    _stopLinkTimers();
    _cancelDataSub();
    _update(
      (s) => s.copyWith(
        connection: SensorConnectionState.reconnecting,
        freshness: SignalFreshness.none,
        error: () => reason,
        nextReconnectAt: () => null,
        connectedSince: () => null,
      ),
    );
    await _adapter.disconnect(sensorId);
    if (_isStale(epoch)) return;
    _scheduleRetry(reason);
  }

  void _scheduleRetry(String reason) {
    _cancelRetryTimer();
    if (!_wanted) {
      _update(
        (s) => s.copyWith(
          connection: SensorConnectionState.disconnected,
          freshness: SignalFreshness.none,
          nextReconnectAt: () => null,
          connectedSince: () => null,
        ),
      );
      return;
    }
    if (!_config.autoReconnect) {
      _log.info('[$_short] Auto-reconnect disabled; staying disconnected');
      _update(
        (s) => s.copyWith(
          connection: SensorConnectionState.disconnected,
          freshness: SignalFreshness.none,
          error: () => reason,
          nextReconnectAt: () => null,
          connectedSince: () => null,
        ),
      );
      return;
    }
    if (!_bluetoothReady) {
      _update(
        (s) => s.copyWith(
          connection: SensorConnectionState.reconnecting,
          freshness: SignalFreshness.none,
          error: () => 'Waiting for Bluetooth',
          nextReconnectAt: () => null,
          connectedSince: () => null,
        ),
      );
      return;
    }

    final delay = _policy.delayFor(_retryAttempt);
    _retryAttempt++;
    final attempt = _retryAttempt;
    _log.info('[$_short] Reconnect in ${delay.inMilliseconds} ms (attempt $attempt)');
    _update(
      (s) => s.copyWith(
        connection: SensorConnectionState.reconnecting,
        freshness: SignalFreshness.none,
        error: () => reason,
        reconnectAttempt: attempt,
        nextReconnectAt: () => clock.now().add(delay),
        connectedSince: () => null,
      ),
    );
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_attempt());
    });
  }

  Future<void> _fail(BleException error) async {
    _log.warning('[$_short] Giving up: ${error.message}');
    _emit(ConnectionEventType.failed, error.kind.name);
    _wanted = false;
    _epoch++;
    _cancelRetryTimer();
    _stopLinkTimers();
    _cancelDataSub();
    _update(
      (s) => s.copyWith(
        connection: SensorConnectionState.failed,
        freshness: SignalFreshness.none,
        error: () => error.userMessage,
        nextReconnectAt: () => null,
        connectedSince: () => null,
      ),
    );
    await _adapter.disconnect(sensorId);
  }

  // ---------------------------------------------------------------------------
  // Periodic link maintenance
  // ---------------------------------------------------------------------------

  void _startLinkTimers(int epoch) {
    _stopLinkTimers();
    _watchdogTimer = Timer.periodic(_config.watchdogInterval, (_) {
      if (_isStale(epoch)) return;
      final last = _lastPacketAt ?? _subscribedAt;
      if (last == null) return;
      if (clock.now().difference(last) > _config.noDataTimeout) {
        _log.warning('[$_short] No data for ${_config.noDataTimeout.inSeconds}s - recycling link');
        _emit(ConnectionEventType.dataTimeout);
        unawaited(_teardownAndRetry('No data from sensor'));
      }
    });
    _rssiTimer = Timer.periodic(_config.rssiInterval, (_) async {
      if (_isStale(epoch)) return;
      final rssi = await _adapter.readRssi(sensorId);
      if (rssi != null && !_isStale(epoch)) {
        _update((s) => s.copyWith(rssi: () => rssi));
      }
    });
    if (_hasBatteryService) {
      _batteryTimer = Timer.periodic(_config.batteryInterval, (_) {
        if (!_isStale(epoch)) unawaited(_readBattery(epoch));
      });
    }
  }

  void _stopLinkTimers() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _rssiTimer?.cancel();
    _rssiTimer = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
  }

  Future<void> _readBattery(int epoch) async {
    try {
      final bytes = await _adapter.read(
        sensorId,
        BleUuids.batteryService,
        BleUuids.batteryLevel,
        timeout: _config.gattTimeout,
      );
      if (_isStale(epoch)) return;
      final level = parseBatteryLevel(bytes);
      if (level != null) {
        _update((s) => s.copyWith(batteryPercent: () => level));
      }
    } catch (e) {
      // Battery is optional and non-critical.
      _log.fine('[$_short] Battery read failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isStale(int epoch) => _disposed || epoch != _epoch;

  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Cancellation takes effect immediately (no further events are
  /// delivered), so there is no need to await the returned future.
  void _cancelDataSub() {
    final sub = _dataSub;
    _dataSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  void _update(SensorLiveState Function(SensorLiveState) change) {
    final next = change(_state);
    if (next == _state) return;
    _state = next;
    if (!_disposed) _onStateChanged(this);
  }

  void _emit(ConnectionEventType type, [String? detail]) {
    _onEvent(
      ConnectionEvent(sensorId: sensorId, type: type, timestamp: clock.now(), detail: detail),
    );
  }
}
