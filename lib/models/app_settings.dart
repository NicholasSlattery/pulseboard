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

/// Colour scheme of the live (on-the-water) screens.
enum LiveTheme {
  /// Near-black background, white and amber numerals. Default.
  water('On the water'),

  /// White background, for direct sun.
  daylight('Daylight');

  const LiveTheme(this.label);
  final String label;
}

/// Which view the live screen opens in while recording.
enum LiveViewMode {
  /// SpeedCoach heroes plus one row per seat with heart rate.
  crew('Crew'),

  /// Every SpeedCoach value, trends and 500 m splits.
  boat('Boat data'),

  /// Split, rate, distance and elapsed only.
  simple('Simple');

  const LiveViewMode(this.label);
  final String label;
}

/// Optional goal for a piece.
enum TargetKind {
  none('None'),
  distance('Distance'),
  time('Time');

  const TargetKind(this.label);
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
    this.themeMode = ThemeMode.system,
    this.showTimeInZone = true,
    this.verboseLogging = false,
    this.bluetoothIntroSeen = false,
    this.speedCoachSerial,
    this.speedCoachBoatName = 'PulseBoard',
    this.liveTheme = LiveTheme.water,
    this.liveViewMode = LiveViewMode.crew,
    this.targetSplit,
    this.targetKind = TargetKind.none,
    this.targetDistanceMeters = 2000,
    this.targetTime = const Duration(minutes: 20),
  });

  final ZoneModel zoneModel;
  final MaxHrFormula maxHrFormula;
  final bool autoReconnect;

  /// After this long without a reading, the BPM is shown greyed as stale.
  final Duration staleAfter;

  /// After this long without a reading, "--" is shown instead of a BPM.
  final Duration signalLostAfter;
  final KeepAwakeMode keepAwake;
  final ThemeMode themeMode;
  final bool showTimeInZone;

  /// Log every HR packet (noisy). Only meaningful in debug builds or the
  /// in-app diagnostics log.
  final bool verboseLogging;

  /// Whether the first-launch Bluetooth explanation has been shown.
  final bool bluetoothIntroSeen;

  /// Serial of the SpeedCoach paired with the experimental receiver. When
  /// set, the receiver advertises this so that SpeedCoach reconnects.
  final String? speedCoachSerial;

  /// Boat name the SpeedCoach reads from the receiver.
  final String speedCoachBoatName;

  final LiveTheme liveTheme;
  final LiveViewMode liveViewMode;

  /// Target time per 500 m. When set, the live views show ahead / on /
  /// behind.
  final Duration? targetSplit;
  final TargetKind targetKind;
  final int targetDistanceMeters;
  final Duration targetTime;

  static const List<int> staleChoicesSeconds = [3, 5, 8, 10, 15];
  static const List<int> lostChoicesSeconds = [10, 15, 20, 30, 60];

  AppSettings copyWith({
    ZoneModel? zoneModel,
    MaxHrFormula? maxHrFormula,
    bool? autoReconnect,
    Duration? staleAfter,
    Duration? signalLostAfter,
    KeepAwakeMode? keepAwake,
    ThemeMode? themeMode,
    bool? showTimeInZone,
    bool? verboseLogging,
    bool? bluetoothIntroSeen,
    String? Function()? speedCoachSerial,
    String? speedCoachBoatName,
    LiveTheme? liveTheme,
    LiveViewMode? liveViewMode,
    Duration? Function()? targetSplit,
    TargetKind? targetKind,
    int? targetDistanceMeters,
    Duration? targetTime,
  }) {
    return AppSettings(
      zoneModel: zoneModel ?? this.zoneModel,
      maxHrFormula: maxHrFormula ?? this.maxHrFormula,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      staleAfter: staleAfter ?? this.staleAfter,
      signalLostAfter: signalLostAfter ?? this.signalLostAfter,
      keepAwake: keepAwake ?? this.keepAwake,
      themeMode: themeMode ?? this.themeMode,
      showTimeInZone: showTimeInZone ?? this.showTimeInZone,
      verboseLogging: verboseLogging ?? this.verboseLogging,
      bluetoothIntroSeen: bluetoothIntroSeen ?? this.bluetoothIntroSeen,
      speedCoachSerial: speedCoachSerial != null ? speedCoachSerial() : this.speedCoachSerial,
      speedCoachBoatName: speedCoachBoatName ?? this.speedCoachBoatName,
      liveTheme: liveTheme ?? this.liveTheme,
      liveViewMode: liveViewMode ?? this.liveViewMode,
      targetSplit: targetSplit != null ? targetSplit() : this.targetSplit,
      targetKind: targetKind ?? this.targetKind,
      targetDistanceMeters: targetDistanceMeters ?? this.targetDistanceMeters,
      targetTime: targetTime ?? this.targetTime,
    );
  }

  /// The signal-lost timeout is always strictly longer than the stale one.
  Duration get effectiveSignalLostAfter =>
      signalLostAfter > staleAfter ? signalLostAfter : staleAfter + const Duration(seconds: 5);

  bool get hasTargets => targetSplit != null || targetKind != TargetKind.none;

  Map<String, Object?> toJson() => {
    'zoneLowerBounds': zoneModel.lowerBoundsPercent,
    'maxHrFormula': maxHrFormula.name,
    'autoReconnect': autoReconnect,
    'staleAfterMs': staleAfter.inMilliseconds,
    'signalLostAfterMs': signalLostAfter.inMilliseconds,
    'keepAwake': keepAwake.name,
    'themeMode': themeMode.name,
    'showTimeInZone': showTimeInZone,
    'verboseLogging': verboseLogging,
    'bluetoothIntroSeen': bluetoothIntroSeen,
    'speedCoachSerial': speedCoachSerial,
    'speedCoachBoatName': speedCoachBoatName,
    'liveTheme': liveTheme.name,
    'liveViewMode': liveViewMode.name,
    'targetSplitMs': targetSplit?.inMilliseconds,
    'targetKind': targetKind.name,
    'targetDistanceM': targetDistanceMeters,
    'targetTimeMs': targetTime.inMilliseconds,
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

    bool boolOr(Object? v, bool fallback) => v is bool ? v : fallback;

    var zones = d.zoneModel;
    final rawBounds = json['zoneLowerBounds'];
    if (rawBounds is List) {
      final bounds = rawBounds.whereType<num>().map((n) => n.toDouble()).toList();
      if (bounds.length == rawBounds.length && ZoneModel.validate(bounds) == null) {
        zones = ZoneModel(List.unmodifiable(bounds));
      }
    }

    final split = json['targetSplitMs'];
    final distance = json['targetDistanceM'];
    return AppSettings(
      zoneModel: zones,
      maxHrFormula: enumOr(MaxHrFormula.values, json['maxHrFormula'], d.maxHrFormula),
      autoReconnect: boolOr(json['autoReconnect'], d.autoReconnect),
      staleAfter: durationOr(json['staleAfterMs'], d.staleAfter),
      signalLostAfter: durationOr(json['signalLostAfterMs'], d.signalLostAfter),
      keepAwake: enumOr(KeepAwakeMode.values, json['keepAwake'], d.keepAwake),
      themeMode: enumOr(ThemeMode.values, json['themeMode'], d.themeMode),
      showTimeInZone: boolOr(json['showTimeInZone'], d.showTimeInZone),
      verboseLogging: boolOr(json['verboseLogging'], d.verboseLogging),
      bluetoothIntroSeen: boolOr(json['bluetoothIntroSeen'], d.bluetoothIntroSeen),
      speedCoachSerial:
          json['speedCoachSerial'] is String && (json['speedCoachSerial']! as String).isNotEmpty
          ? json['speedCoachSerial']! as String
          : null,
      speedCoachBoatName:
          json['speedCoachBoatName'] is String &&
              (json['speedCoachBoatName']! as String).trim().isNotEmpty
          ? json['speedCoachBoatName']! as String
          : d.speedCoachBoatName,
      liveTheme: enumOr(LiveTheme.values, json['liveTheme'], d.liveTheme),
      liveViewMode: enumOr(LiveViewMode.values, json['liveViewMode'], d.liveViewMode),
      targetSplit: split is int && split > 0 ? Duration(milliseconds: split) : null,
      targetKind: enumOr(TargetKind.values, json['targetKind'], d.targetKind),
      targetDistanceMeters: distance is int && distance > 0 ? distance : d.targetDistanceMeters,
      targetTime: durationOr(json['targetTimeMs'], d.targetTime),
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
      other.themeMode == themeMode &&
      other.showTimeInZone == showTimeInZone &&
      other.verboseLogging == verboseLogging &&
      other.bluetoothIntroSeen == bluetoothIntroSeen &&
      other.speedCoachSerial == speedCoachSerial &&
      other.speedCoachBoatName == speedCoachBoatName &&
      other.liveTheme == liveTheme &&
      other.liveViewMode == liveViewMode &&
      other.targetSplit == targetSplit &&
      other.targetKind == targetKind &&
      other.targetDistanceMeters == targetDistanceMeters &&
      other.targetTime == targetTime;

  @override
  int get hashCode => Object.hash(
    zoneModel,
    maxHrFormula,
    autoReconnect,
    staleAfter,
    signalLostAfter,
    keepAwake,
    themeMode,
    showTimeInZone,
    verboseLogging,
    bluetoothIntroSeen,
    speedCoachSerial,
    speedCoachBoatName,
    liveTheme,
    liveViewMode,
    targetSplit,
    targetKind,
    targetDistanceMeters,
    targetTime,
  );
}
