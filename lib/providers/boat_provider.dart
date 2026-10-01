import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../speedcoach/boat_metrics.dart';
import 'settings_provider.dart';
import 'speedcoach_provider.dart';

/// App-side calculations on the SpeedCoach stream (strokes, average rate,
/// trend, 500 m splits, target cue).
class BoatMetricsController extends Notifier<BoatMetrics> {
  final _tracker = BoatTracker();

  @override
  BoatMetrics build() {
    ref.listen(speedCoachStateProvider, (_, s) {
      state = _tracker.update(s, clock.now(), targetSplit: ref.read(settingsProvider).targetSplit);
    });
    return _tracker.update(
      ref.read(speedCoachStateProvider),
      clock.now(),
      targetSplit: ref.read(settingsProvider).targetSplit,
    );
  }
}

final boatMetricsProvider = NotifierProvider<BoatMetricsController, BoatMetrics>(
  BoatMetricsController.new,
);

/// Which live view is showing while recording. Starts at the user's default.
class LiveViewModeController extends Notifier<LiveViewMode> {
  @override
  LiveViewMode build() => ref.read(settingsProvider).liveViewMode;

  void show(LiveViewMode mode) => state = mode;
}

final liveViewModeProvider = NotifierProvider<LiveViewModeController, LiveViewMode>(
  LiveViewModeController.new,
);
