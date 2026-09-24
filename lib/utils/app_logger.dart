import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// One captured log line.
@immutable
class LogEntry {
  const LogEntry(this.time, this.level, this.logger, this.message);

  final DateTime time;
  final Level level;
  final String logger;
  final String message;

  @override
  String toString() {
    final t = time.toIso8601String().substring(11, 23);
    return '$t ${level.name.padRight(7)} [$logger] $message';
  }
}

/// App-wide logging setup.
///
/// * Debug builds print to the console (visible in VS Code / `flutter run`).
/// * All builds keep the last [capacity] lines in memory so they can be
///   viewed and shared from Settings > Diagnostics - essential when you
///   develop without a Mac and cannot attach Xcode to see device logs.
/// * Per-packet HR logging only happens when "verbose logging" is enabled.
///
/// Log lines contain sensor ids and states, never athlete names or HR
/// history, so a shared log reveals nothing personal.
abstract final class AppLogger {
  static const int capacity = 1000;
  static final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>();
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _initialized = false;

  static List<LogEntry> get entries => List.unmodifiable(_buffer);

  static void init() {
    if (_initialized) return;
    _initialized = true;
    hierarchicalLoggingEnabled = false;
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      final message = record.error == null ? record.message : '${record.message} | ${record.error}';
      final entry = LogEntry(record.time, record.level, record.loggerName, message);
      _buffer.addLast(entry);
      while (_buffer.length > capacity) {
        _buffer.removeFirst();
      }
      revision.value++;
      if (kDebugMode) debugPrint(entry.toString());
    });
  }

  /// FINE records (per-packet HR logs) are only captured when verbose.
  static void setVerbose(bool verbose) {
    Logger.root.level = verbose ? Level.ALL : Level.INFO;
  }

  static String dump() => _buffer.map((e) => e.toString()).join('\n');

  static void clear() {
    _buffer.clear();
    revision.value++;
  }
}
