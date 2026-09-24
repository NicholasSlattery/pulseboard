/// Branding lives here and nowhere else in Dart code, so renaming the app is a
/// one-line change (plus `CFBundleDisplayName` in ios/Runner/Info.plist).
abstract final class AppInfo {
  static const String name = 'PulseBoard';
  static const String tagline = 'Team heart-rate dashboard';

  /// File name of the local SQLite database.
  static const String databaseFileName = 'pulseboard.db';

  /// Prefix used for exported CSV files.
  static const String exportFilePrefix = 'pulseboard';

  /// When true (via `--dart-define=PULSEBOARD_SIMULATOR=true`) the app uses
  /// simulated heart-rate straps instead of real Bluetooth. Intended for UI
  /// development on Windows. It is a compile-time constant, so release builds
  /// made without the flag can never show simulated data.
  static const bool useSimulator = bool.fromEnvironment('PULSEBOARD_SIMULATOR');
}
