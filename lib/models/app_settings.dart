import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'hr_zones.dart';

enum KeepAwakeMode {
  never('Never'),
  duringSession('During sessions'),
  always('Always while open');

  const KeepAwakeMode(this.label);
  final String label;
}

enum DashboardDensity {
  /// Fit every athlete on screen when possible (coach tablet mode).
  auto('Auto-fit'),

  /// Big cards, scroll when needed.
  large('Large'),

  /// Smaller cards, more per screen.
  compact('Compact');

  const DashboardDensity(this.label);
  final String label;
}

/// All user preferences. Persisted as JSON in the `settings` table.
@immutable
class AppSettings {
  const AppSettings({
    this.zoneModel = ZoneModel.standard,
    this.maxHrFormula = MaxHrFormula.fox,
    this.autoReconnect = true,
    this.staleAfter = const Duration(seconds: 5),
    this.signalLostAfter = const Duration(seconds: 15),
    this.keepAwake = KeepAwakeMode.duringSession,
    this.density = DashboardDensity.auto,
    this.themeMode = ThemeMode.system,
    this.showTimeInZone = true,
    this.verboseLogging = false,
    this.bluetoothIntroSeen = false,
  });

  final ZoneModel zoneModel;
  final MaxHrFormula maxHrFormula;
  final bool autoReconnect;

  /// After this long without a reading, the BPM is shown greyed as stale.
  final Duration staleAfter;

  /// After this long without a reading, "--" is shown instead of a BPM.
  final Duration signalLostAfter;
  final KeepAwakeMode keepAwake;
  final DashboardDensity density;
  final ThemeMode themeMode;
  final bool showTimeInZone;

  /// Log every HR packet (noisy). Only meaningful in debug builds or the
  /// in-app diagnostics log.
  final bool verboseLogging;

  /// Whether the first-launch Bluetooth explanation has been shown.
  final bool bluetoothIntroSeen;

  static const List<int> staleChoicesSeconds = [3, 5, 8, 10, 15];
  static const List<int> lostChoicesSeconds = [10, 15, 20, 30, 60];

  AppSettings copyWith({
    ZoneModel? zoneModel,
    MaxHrFormula? maxHrFormula,
    bool? autoReconnect,
    Duration? staleAfter,
    Duration? signalLostAfter,
    KeepAwakeMode? keepAwake,
    DashboardDensity? density,
    ThemeMode? themeMode,
    bool? showTimeInZone,
    bool? verboseLogging,
    bool? bluetoothIntroSeen,
  }) {
    return AppSettings(
      zoneModel: zoneModel ?? this.zoneModel,
      maxHrFormula: maxHrFormula ?? this.maxHrFormula,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      staleAfter: staleAfter ?? this.staleAfter,
      signalLostAfter: signalLostAfter ?? this.signalLostAfter,
      keepAwake: keepAwake ?? this.keepAwake,
      density: density ?? this.density,
      themeMode: themeMode ?? this.themeMode,
      showTimeInZone: showTimeInZone ?? this.showTimeInZone,
      verboseLogging: verboseLogging ?? this.verboseLogging,
      bluetoothIntroSeen: bluetoothIntroSeen ?? this.bluetoothIntroSeen,
    );
  }

  /// The signal-lost timeout is always strictly longer than the stale one.
  Duration get effectiveSignalLostAfter =>
      signalLostAfter > staleAfter ? signalLostAfter : staleAfter + const Duration(seconds: 5);

  Map<String, Object?> toJson() => {
    'zoneLowerBounds': zoneModel.lowerBoundsPercent,
    'maxHrFormula': maxHrFormula.name,
    'autoReconnect': autoReconnect,
    'staleAfterMs': staleAfter.inMilliseconds,
    'signalLostAfterMs': signalLostAfter.inMilliseconds,
    'keepAwake': keepAwake.name,
    'density': density.name,
    'themeMode': themeMode.name,
    'showTimeInZone': showTimeInZone,
    'verboseLogging': verboseLogging,
    'bluetoothIntroSeen': bluetoothIntroSeen,
  };

  /// Tolerant decoding: unknown or invalid values fall back to defaults so a
  /// corrupted/old settings blob can never crash the app.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const d = AppSettings();

    T enumOr<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    Duration durationOr(Object? ms, Duration fallback) =>
        ms is int && ms > 0 ? Duration(milliseconds: ms) : fallback;

    var zones = d.zoneModel;
    final rawBounds = json['zoneLowerBounds'];
    if (rawBounds is List) {
      final bounds = rawBounds.whereType<num>().map((n) => n.toDouble()).toList();
      if (bounds.length == rawBounds.length && ZoneModel.validate(bounds) == null) {
        zones = ZoneModel(List.unmodifiable(bounds));
      }
    }

    return AppSettings(
      zoneModel: zones,
      maxHrFormula: enumOr(MaxHrFormula.values, json['maxHrFormula'], d.maxHrFormula),
      autoReconnect: json['autoReconnect'] is bool
          ? json['autoReconnect']! as bool
          : d.autoReconnect,
      staleAfter: durationOr(json['staleAfterMs'], d.staleAfter),
      signalLostAfter: durationOr(json['signalLostAfterMs'], d.signalLostAfter),
      keepAwake: enumOr(KeepAwakeMode.values, json['keepAwake'], d.keepAwake),
      density: enumOr(DashboardDensity.values, json['density'], d.density),
      themeMode: enumOr(ThemeMode.values, json['themeMode'], d.themeMode),
      showTimeInZone: json['showTimeInZone'] is bool
          ? json['showTimeInZone']! as bool
          : d.showTimeInZone,
      verboseLogging: json['verboseLogging'] is bool
          ? json['verboseLogging']! as bool
          : d.verboseLogging,
      bluetoothIntroSeen: json['bluetoothIntroSeen'] is bool
          ? json['bluetoothIntroSeen']! as bool
          : d.bluetoothIntroSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.zoneModel == zoneModel &&
      other.maxHrFormula == maxHrFormula &&
      other.autoReconnect == autoReconnect &&
      other.staleAfter == staleAfter &&
      other.signalLostAfter == signalLostAfter &&
      other.keepAwake == keepAwake &&
      other.density == density &&
      other.themeMode == themeMode &&
      other.showTimeInZone == showTimeInZone &&
      other.verboseLogging == verboseLogging &&
      other.bluetoothIntroSeen == bluetoothIntroSeen;

  @override
  int get hashCode => Object.hash(
    zoneModel,
    maxHrFormula,
    autoReconnect,
    staleAfter,
    signalLostAfter,
    keepAwake,
    density,
    themeMode,
    showTimeInZone,
    verboseLogging,
    bluetoothIntroSeen,
  );
}
