import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'peripheral_adapter.dart';
import 'speedcoach_protocol.dart';

final _log = Logger('SpeedCoach');

enum SpeedCoachReceiverStatus {
  /// Not running.
  stopped,

  /// Publishing the service / starting to advertise.
  starting,

  /// Advertising; no SpeedCoach data in the last few seconds.
  waiting,

  /// Receiving data from a SpeedCoach.
  streaming,

  /// This device cannot act as the receiver (no peripheral role / no custom
  /// advertised name, e.g. Windows).
  unsupported,

  error,
}

@immutable
class SpeedCoachLiveState {
  const SpeedCoachLiveState({
    this.status = SpeedCoachReceiverStatus.stopped,
    this.advertisedName,
    this.error,
    this.serial,
    this.elapsed,
    this.strokeCount,
    this.strokeRate,
    this.isIdle = false,
    this.lastPacketAt,
    this.packetsReceived = 0,
  });

  final SpeedCoachReceiverStatus status;
  final String? advertisedName;
  final String? error;

  /// Serial number the SpeedCoach reported when it connected.
  final String? serial;
  final Duration? elapsed;
  final int? strokeCount;

  /// Calculated from stroke timing (strokes per minute).
  final double? strokeRate;
  final bool isIdle;
  final DateTime? lastPacketAt;
  final int packetsReceived;

  bool get isStreaming => status == SpeedCoachReceiverStatus.streaming;

  SpeedCoachLiveState copyWith({
    SpeedCoachReceiverStatus? status,
    String? Function()? advertisedName,
    String? Function()? error,
    String? Function()? serial,
    Duration? Function()? elapsed,
    int? Function()? strokeCount,
    double? Function()? strokeRate,
    bool? isIdle,
    DateTime? Function()? lastPacketAt,
    int? packetsReceived,
  }) => SpeedCoachLiveState(
    status: status ?? this.status,
    advertisedName: advertisedName != null ? advertisedName() : this.advertisedName,
    error: error != null ? error() : this.error,
    serial: serial != null ? serial() : this.serial,
    elapsed: elapsed != null ? elapsed() : this.elapsed,
    strokeCount: strokeCount != null ? strokeCount() : this.strokeCount,
    strokeRate: strokeRate != null ? strokeRate() : this.strokeRate,
    isIdle: isIdle ?? this.isIdle,
    lastPacketAt: lastPacketAt != null ? lastPacketAt() : this.lastPacketAt,
    packetsReceived: packetsReceived ?? this.packetsReceived,
  );
}

/// One raw write received from the SpeedCoach, kept for decoding work.
@immutable
class SpeedCoachPacket {
  const SpeedCoachPacket(this.time, this.suffix, this.bytes);

  final DateTime time;

  /// NK characteristic suffix, e.g. "0103".
  final String suffix;
  final Uint8List bytes;

  String get hex => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

/// Receives live data from an NK SpeedCoach by acting as NK LiNK Logbook:
/// hosts NK's GATT service, advertises it, answers the SpeedCoach's reads and
/// decodes its writes.
///
/// EXPERIMENTAL: based on reverse-engineering one SpeedCoach GPS Pro
/// (firmware 2.25). NK LiNK must not be streaming at the same time.
class SpeedCoachReceiver {
  SpeedCoachReceiver({
    required PeripheralAdapter adapter,
    this.staleAfter = const Duration(seconds: 4),
    this.packetLogCapacity = 2000,
  }) : _adapter = adapter;

  final PeripheralAdapter _adapter;
  final Duration staleAfter;
  final int packetLogCapacity;

  final _states = StreamController<SpeedCoachLiveState>.broadcast();
  final _serials = StreamController<String>.broadcast();
  final _packetLog = ListQueue<SpeedCoachPacket>();
  final Map<String, Uint8List> _values = {};
  final StrokeRateEstimator _rate = StrokeRateEstimator();

  SpeedCoachLiveState _state = const SpeedCoachLiveState();
  String _boatName = 'PulseBoard';
  Timer? _staleTimer;
  bool _serviceAdded = false;
  bool _disposed = false;

  SpeedCoachLiveState get state => _state;
  Stream<SpeedCoachLiveState> get states => _states.stream;

  /// Emits the serial number whenever a SpeedCoach identifies itself.
  Stream<String> get serialReported => _serials.stream;

  /// Most recent raw packets, oldest first.
  List<SpeedCoachPacket> get packetLog => List.unmodifiable(_packetLog);

  bool get supported => _adapter.supportsLocalName;

  /// Starts advertising as NK LiNK under [advertisedName]
  /// ([SpeedCoachNames.pairing] for "Find New", or a SpeedCoach serial to
  /// reconnect a remembered unit).
  Future<void> start({required String advertisedName, required String boatName}) async {
    if (_disposed) return;
    _boatName = boatName;
    if (!_adapter.supportsLocalName) {
      _set(
        _state.copyWith(
          status: SpeedCoachReceiverStatus.unsupported,
          error: () => 'This device cannot advertise as a SpeedCoach receiver. Use the iPhone app.',
        ),
      );
      return;
    }
    if (_state.status == SpeedCoachReceiverStatus.starting) return;
    _set(
      _state.copyWith(
        status: SpeedCoachReceiverStatus.starting,
        advertisedName: () => advertisedName,
        error: () => null,
      ),
    );
    try {
      if (!await _adapter.waitUntilReady()) {
        throw StateError('Bluetooth is off or not allowed');
      }
      _adapter.setHandlers(onWrite: _onWrite, onRead: _onRead);
      if (!_serviceAdded) {
        await _adapter.addService(SpeedCoachUuids.service, [
          for (final s in SpeedCoachUuids.suffixes) SpeedCoachUuids.char(s),
        ]);
        _serviceAdded = true;
      }
      await _adapter.stopAdvertising();
      await _adapter.startAdvertising(
        serviceUuid: SpeedCoachUuids.service,
        localName: advertisedName,
      );
      _log.info('Advertising as "$advertisedName"');
      _set(_state.copyWith(status: SpeedCoachReceiverStatus.waiting));
      _staleTimer?.cancel();
      _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkStale());
    } catch (e) {
      _log.warning('Could not start SpeedCoach receiver: $e');
      _set(_state.copyWith(status: SpeedCoachReceiverStatus.error, error: () => '$e'));
    }
  }

  Future<void> stop() async {
    _staleTimer?.cancel();
    _staleTimer = null;
    if (_state.status == SpeedCoachReceiverStatus.stopped) return;
    await _adapter.stopAdvertising();
    if (_serviceAdded) {
      await _adapter.removeService(SpeedCoachUuids.service);
      _serviceAdded = false;
    }
    _adapter.clearHandlers();
    _rate.reset();
    _log.info('Receiver stopped');
    _set(const SpeedCoachLiveState());
  }

  void updateBoatName(String name) => _boatName = name;

  void clearPacketLog() => _packetLog.clear();

  /// CSV of the raw packet log (for sharing while decoding the protocol).
  String packetLogCsv() {
    final b = StringBuffer('time_utc,characteristic,hex\r\n');
    for (final p in _packetLog) {
      b.write('${p.time.toUtc().toIso8601String()},${p.suffix},${p.hex}\r\n');
    }
    return b.toString();
  }

  // --- GATT callbacks -------------------------------------------------------

  void _onWrite(String deviceId, String characteristicUuid, Uint8List value) {
    if (_disposed) return;
    final suffix = SpeedCoachUuids.suffixOf(characteristicUuid);
    if (suffix == null) return;
    final now = clock.now();
    _values[suffix] = value;
    _packetLog.addLast(SpeedCoachPacket(now, suffix, value));
    while (_packetLog.length > packetLogCapacity) {
      _packetLog.removeFirst();
    }

    var next = _state.copyWith(
      status: SpeedCoachReceiverStatus.streaming,
      lastPacketAt: () => now,
      packetsReceived: _state.packetsReceived + 1,
    );
    if (_state.status != SpeedCoachReceiverStatus.streaming) {
      _log.info('SpeedCoach streaming');
    }

    switch (suffix) {
      case SpeedCoachUuids.serialSuffix:
        final serial = ascii.decode(value.where((b) => b >= 0x20 && b < 0x7F).toList()).trim();
        if (serial.isNotEmpty) {
          _log.info('SpeedCoach serial $serial');
          next = next.copyWith(serial: () => serial);
          _serials.add(serial);
        }
      case SpeedCoachUuids.liveStatusSuffix:
        final status = SpeedCoachStatusPacket.parse(value);
        if (status != null) next = next.copyWith(elapsed: () => status.elapsed);
      case SpeedCoachUuids.strokeSuffix:
        final stroke = SpeedCoachStrokePacket.parse(value);
        if (stroke != null) {
          if (stroke.isIdle) {
            _rate.reset();
            next = next.copyWith(
              isIdle: true,
              strokeRate: () => null,
              strokeCount: () => stroke.strokeCount,
            );
          } else {
            _rate.addStroke(stroke.strokeCount, now);
            next = next.copyWith(
              isIdle: false,
              strokeCount: () => stroke.strokeCount,
              strokeRate: () => _rate.rate,
            );
          }
        }
    }
    _set(next);
  }

  Uint8List _onRead(String deviceId, String characteristicUuid) {
    final suffix = SpeedCoachUuids.suffixOf(characteristicUuid);
    switch (suffix) {
      case SpeedCoachUuids.boatNameSuffix:
        return Uint8List.fromList(utf8.encode(_boatName).take(20).toList());
      case SpeedCoachUuids.streamControlSuffix:
        // What NK LiNK answers while streaming is switched on.
        return Uint8List.fromList([1, ...List.filled(19, 0)]);
      case null:
        return Uint8List(0);
      default:
        return _values[suffix] ?? Uint8List(0);
    }
  }

  void _checkStale() {
    final last = _state.lastPacketAt;
    if (_state.status != SpeedCoachReceiverStatus.streaming || last == null) return;
    if (clock.now().difference(last) > staleAfter) {
      _log.info('SpeedCoach data stopped');
      _rate.reset();
      _set(_state.copyWith(status: SpeedCoachReceiverStatus.waiting, strokeRate: () => null));
    }
  }

  void _set(SpeedCoachLiveState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _staleTimer?.cancel();
    await _states.close();
    await _serials.close();
  }
}
