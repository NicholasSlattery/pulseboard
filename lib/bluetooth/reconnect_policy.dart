import 'dart:math';

/// Exponential backoff with jitter for reconnection attempts.
///
/// attempt 0 -> ~1 s, 1 -> ~2 s, 2 -> ~4 s ... capped at [maxDelay] (30 s).
/// Each attempt on iOS is a pending CoreBluetooth connection request (a
/// low-power, controller-level operation), not an active scan, so even the
/// steady-state retry costs very little battery.
class ReconnectPolicy {
  ReconnectPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitterFraction = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;

  /// +/- fraction of randomisation so many straps dropping at once (e.g. a
  /// crew rowing out of range together) don't retry in lock-step.
  final double jitterFraction;
  final Random _random;

  /// Delay before retry number [attempt] (0-based).
  Duration delayFor(int attempt) {
    final safeAttempt = attempt.clamp(0, 30);
    final baseMs = min(
      initialDelay.inMilliseconds * pow(multiplier, safeAttempt),
      maxDelay.inMilliseconds.toDouble(),
    );
    final jitter = 1 + jitterFraction * (_random.nextDouble() * 2 - 1);
    final ms = (baseMs * jitter).round();
    return Duration(milliseconds: ms.clamp(0, maxDelay.inMilliseconds));
  }
}
