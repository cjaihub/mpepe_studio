// LIVE STUDIO v2 — watch-party sync (workstream #5, ARCHITECTURE §9).
//
// Pure: no Flutter widgets, no plugins. The player and the server clock are
// injected, so the drift rules are unit-tested with fakes.
//
//   target = WatchParty.targetPositionMs(clock.serverNowMs())
//   |player − target| > StudioLimits.maxDriftMs  →  seek to target
//
// Runs every [interval] (1 s) and on every WatchParty change; follows
// play / pause / ended and the playback rate.

import 'dart:async';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';

/// The minimum a local video player must offer to be synced.
abstract class WatchPlayer {
  int get positionMs;
  bool get isPlaying;
  double get rate;

  /// Media duration, or null while unknown (live HLS).
  int? get durationMs;

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(int positionMs);
  Future<void> setRate(double rate);
}

typedef PeriodicTimerFactory = Timer Function(Duration interval, void Function(Timer) onTick);

/// What one sync pass did (for tests and telemetry).
class WatchSyncResult {
  const WatchSyncResult({
    required this.targetMs,
    required this.driftMs,
    this.seeked = false,
    this.played = false,
    this.paused = false,
    this.rateChanged = false,
  });

  static const WatchSyncResult idle = WatchSyncResult(targetMs: 0, driftMs: 0);

  final int targetMs;

  /// player − target, before any seek.
  final int driftMs;
  final bool seeked;
  final bool played;
  final bool paused;
  final bool rateChanged;

  bool get didSomething => seeked || played || paused || rateChanged;

  @override
  String toString() => 'WatchSyncResult(target $targetMs, drift $driftMs, seek $seeked, '
      'play $played, pause $paused, rate $rateChanged)';
}

class WatchPartySync {
  WatchPartySync({
    required this.player,
    required this.clock,
    this.interval = const Duration(seconds: 1),
    this.maxDriftMs = StudioLimits.maxDriftMs,
    PeriodicTimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.periodic;

  final WatchPlayer player;
  final StudioClockPort clock;
  final Duration interval;
  final int maxDriftMs;
  final PeriodicTimerFactory _timerFactory;

  WatchParty? _party;
  Timer? _timer;
  bool _running = false;
  Future<WatchSyncResult>? _inFlight;
  bool _again = false;

  WatchParty? get party => _party;
  bool get isRunning => _timer != null;

  /// Starts the periodic check. Call [update] with the current party first.
  void start() {
    _timer ??= _timerFactory(interval, (_) => unawaited(sync()));
    unawaited(sync());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// New server state: syncs at once when it changed.
  Future<WatchSyncResult> update(WatchParty? party) {
    final changed = !_same(_party, party);
    _party = party;
    return changed ? sync() : Future.value(WatchSyncResult.idle);
  }

  /// Position the room should be at right now (server clock), clamped.
  int targetNowMs() {
    final p = _party;
    if (p == null) return 0;
    final t = p.targetPositionMs(clock.serverNowMs());
    final d = player.durationMs;
    final clampedHigh = d != null && d > 0 && t > d ? d : t;
    return clampedHigh < 0 ? 0 : clampedHigh;
  }

  /// One pass. Passes never overlap: a call during a pass schedules one more.
  Future<WatchSyncResult> sync() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    final f = _pass().whenComplete(() {
      _inFlight = null;
      if (_again) {
        _again = false;
        unawaited(sync());
      }
    });
    _inFlight = f;
    return f;
  }

  Future<WatchSyncResult> _pass() async {
    if (_running) return WatchSyncResult.idle;
    _running = true;
    try {
      final p = _party;
      if (p == null) {
        if (player.isPlaying) {
          await player.pause();
          return const WatchSyncResult(targetMs: 0, driftMs: 0, paused: true);
        }
        return WatchSyncResult.idle;
      }
      final target = targetNowMs();
      final drift = player.positionMs - target;
      var seeked = false, played = false, paused = false, rateChanged = false;

      if (p.state == PlaybackState.playing) {
        if ((player.rate - p.rate).abs() > 0.001) {
          await player.setRate(p.rate);
          rateChanged = true;
        }
      } else if (player.isPlaying) {
        await player.pause();
        paused = true;
      }

      if (drift.abs() > maxDriftMs) {
        await player.seekTo(target);
        seeked = true;
      }

      if (p.state == PlaybackState.playing && !player.isPlaying) {
        await player.play();
        played = true;
      }
      return WatchSyncResult(
        targetMs: target,
        driftMs: drift,
        seeked: seeked,
        played: played,
        paused: paused,
        rateChanged: rateChanged,
      );
    } finally {
      _running = false;
    }
  }

  void dispose() {
    stop();
    _party = null;
  }

  static bool _same(WatchParty? a, WatchParty? b) {
    if (a == null || b == null) return a == b;
    return a.catalogId == b.catalogId &&
        a.state == b.state &&
        a.positionMs == b.positionMs &&
        a.rate == b.rate &&
        a.anchorServerMs == b.anchorServerMs;
  }
}
