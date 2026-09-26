import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../speedcoach/peripheral_adapter.dart';
import '../speedcoach/speedcoach_protocol.dart';
import '../speedcoach/speedcoach_receiver.dart';
import 'core_providers.dart';
import 'settings_provider.dart';

/// The experimental SpeedCoach receiver (one per app).
final speedCoachReceiverProvider = Provider<SpeedCoachReceiver>((ref) {
  final adapter = ref.watch(bootstrapProvider).peripheralAdapter ?? UniversalBlePeripheralAdapter();
  final receiver = SpeedCoachReceiver(adapter: adapter);
  ref.onDispose(receiver.dispose);
  return receiver;
});

class SpeedCoachStateController extends Notifier<SpeedCoachLiveState> {
  @override
  SpeedCoachLiveState build() {
    final receiver = ref.watch(speedCoachReceiverProvider);
    final sub = receiver.states.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return receiver.state;
  }

  /// Starts the receiver. Advertises the remembered SpeedCoach's serial so it
  /// reconnects, or the pairing name if none is remembered (or [pairNew]).
  Future<void> start({bool pairNew = false}) {
    final settings = ref.read(settingsProvider);
    final serial = settings.speedCoachSerial;
    final name = (pairNew || serial == null) ? SpeedCoachNames.pairing : serial;
    return ref
        .read(speedCoachReceiverProvider)
        .start(advertisedName: name, boatName: settings.speedCoachBoatName);
  }

  Future<void> stop() => ref.read(speedCoachReceiverProvider).stop();

  Future<void> forgetSpeedCoach() async {
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(speedCoachSerial: () => null));
    final receiver = ref.read(speedCoachReceiverProvider);
    if (receiver.state.status != SpeedCoachReceiverStatus.stopped) {
      await start(pairNew: true);
    }
  }
}

final speedCoachStateProvider = NotifierProvider<SpeedCoachStateController, SpeedCoachLiveState>(
  SpeedCoachStateController.new,
);
