// LIVE STUDIO v2 — audio-only fallback state machine (pure, ARCHITECTURE §7).
//
// Quality stays poor (or lost) for [StudioLimits.poorToAudioOnly] → audio-only.
// While audio-only, quality must stay good/excellent for
// [StudioLimits.goodToRecover] to recover. Any interruption restarts the
// relevant timer. Time comes from the caller, so it is testable with a fake
// clock: call [onQuality] on every change and [evaluate] periodically.

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';

class AudioOnlyFallback {
  AudioOnlyFallback({
    this.poorFor = StudioLimits.poorToAudioOnly,
    this.goodFor = StudioLimits.goodToRecover,
  });

  final Duration poorFor;
  final Duration goodFor;

  bool _audioOnly = false;
  StudioLinkQuality _quality = StudioLinkQuality.good;
  DateTime? _since; // when the current quality began
  DateTime? _audioOnlySince;
  Duration _audioOnlyTotal = Duration.zero;

  bool get audioOnly => _audioOnly;
  StudioLinkQuality get quality => _quality;

  static bool _bad(StudioLinkQuality q) => q == StudioLinkQuality.poor || q == StudioLinkQuality.lost;
  static bool _good(StudioLinkQuality q) => q == StudioLinkQuality.good || q == StudioLinkQuality.excellent;

  /// Records a quality change. Returns true when [audioOnly] flipped.
  bool onQuality(StudioLinkQuality q, DateTime now) {
    final changedClass = _since == null || _bad(q) != _bad(_quality) || _good(q) != _good(_quality);
    _quality = q;
    if (changedClass) _since = now;
    return evaluate(now);
  }

  /// Re-checks the timers. Returns true when [audioOnly] flipped.
  bool evaluate(DateTime now) {
    final since = _since;
    if (since == null) return false;
    final held = now.difference(since);
    if (!_audioOnly && _bad(_quality) && held >= poorFor) {
      _audioOnly = true;
      _audioOnlySince = now;
      return true;
    }
    if (_audioOnly && _good(_quality) && held >= goodFor) {
      _audioOnly = false;
      _audioOnlyTotal += now.difference(_audioOnlySince ?? now);
      _audioOnlySince = null;
      return true;
    }
    return false;
  }

  /// Total time spent audio-only up to [now] (including the current spell).
  Duration audioOnlyTime(DateTime now) =>
      _audioOnlyTotal + (_audioOnlySince == null ? Duration.zero : now.difference(_audioOnlySince!));
}
