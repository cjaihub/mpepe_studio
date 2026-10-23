// LIVE STUDIO v2 — app-level reconnect policy (pure, ARCHITECTURE §7).

import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../contracts/studio_contracts.dart';

/// Exponential backoff from [StudioLimits.reconnectBackoff] with ±[jitter]
/// proportional jitter, so 100k viewers do not reconnect in lockstep.
class StudioReconnectBackoff {
  StudioReconnectBackoff({
    Random? random,
    this.schedule = StudioLimits.reconnectBackoff,
    this.jitter = 0.2,
  }) : _random = random ?? Random();

  final Random _random;
  final List<Duration> schedule;

  /// Fraction of the base delay (0.2 → ±20 %).
  final double jitter;

  /// Delay before retry number [attempt] (0-based). Past the end of the
  /// schedule the last step (30 s) repeats.
  Duration delayFor(int attempt) {
    final base = schedule[attempt.clamp(0, schedule.length - 1)];
    final f = 1 + jitter * (_random.nextDouble() * 2 - 1);
    return Duration(milliseconds: (base.inMilliseconds * f).round());
  }
}

/// Join errors that retrying cannot fix: the live ended, the user is blocked
/// or signed out, or the stream does not exist.
bool isFatalJoinError(Object error) {
  if (error is FirebaseFunctionsException) {
    const fatal = {'failed-precondition', 'permission-denied', 'unauthenticated', 'not-found', 'invalid-argument'};
    return fatal.contains(error.code);
  }
  return false;
}
