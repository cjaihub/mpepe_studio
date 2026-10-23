import '../contracts/studio_contracts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SpeakerHysteresis — ARCHITECTURE §8. Pure Dart, injected clock.
//
// autoActiveSpeaker:
//  • a speaker takes the center after [takeCenter] (1.5 s) of continuous
//    speech;
//  • whoever is in the center stays at least [minHold] (4 s);
//  • the previous center moves into the slot the new speaker left (the server
//    does the swap; this class only names who to promote);
//  • `pinnedUid` blocks auto moves until unpinned.
// hostPinned / manual: never promotes anyone.
// ─────────────────────────────────────────────────────────────────────────────

typedef NowMs = int Function();

class SpeakerHysteresis {
  SpeakerHysteresis({
    required NowMs nowMs,
    Duration takeCenter = StudioLimits.speakToTakeCenter,
    Duration minHold = StudioLimits.minCenterHold,
  })  : _now = nowMs,
        _takeMs = takeCenter.inMilliseconds,
        _holdMs = minHold.inMilliseconds;

  final NowMs _now;
  final int _takeMs;
  final int _holdMs;

  /// uid → local time their current continuous speech run began.
  final Map<String, int> _since = {};
  List<String> _speakers = const [];
  String? _center;
  int _centerSince = 0;

  /// Local time the current center took the center (for tests/debug).
  int get centerSinceMs => _centerSince;

  /// Feed the latest SFU active-speaker list (loudest first).
  void onSpeakers(List<String> speakers) {
    final now = _now();
    final set = speakers.toSet();
    _since.removeWhere((uid, _) => !set.contains(uid));
    for (final uid in speakers) {
      _since.putIfAbsent(uid, () => now);
    }
    _speakers = List.unmodifiable(speakers);
  }

  /// Observe the authoritative stage. A center change restarts the hold.
  void observeStage(StageLayout stage) {
    if (stage.centerUid != _center) {
      _center = stage.centerUid;
      _centerSince = _now();
    }
  }

  /// Who should be promoted now, or null. Call on every speaker event and on
  /// a periodic tick (speech duration grows without new events). When a uid
  /// is returned the class assumes the move happens (optimistic) and starts
  /// the hold, so it never fires twice in a row for the same change.
  String? evaluate({required StageLayout stage, required SpeakerMode mode}) {
    observeStage(stage);
    if (mode != SpeakerMode.autoActiveSpeaker) return null;
    if (stage.pinnedUid != null) return null;
    final now = _now();
    if (now - _centerSince < _holdMs) return null;

    final eligible = <String>{...stage.wall.whereType<String>(), ...stage.overflow};
    for (final uid in _speakers) {
      if (uid == stage.centerUid || !eligible.contains(uid)) continue;
      final since = _since[uid];
      if (since != null && now - since >= _takeMs) {
        _center = uid;
        _centerSince = now;
        return uid;
      }
    }
    return null;
  }

  /// Earliest local time at which [evaluate] could return a uid given the
  /// current inputs (null = nothing pending). Lets callers schedule one timer
  /// instead of polling.
  int? nextDecisionAtMs({required StageLayout stage, required SpeakerMode mode}) {
    if (mode != SpeakerMode.autoActiveSpeaker || stage.pinnedUid != null) return null;
    final eligible = <String>{...stage.wall.whereType<String>(), ...stage.overflow};
    int? best;
    for (final uid in _speakers) {
      if (uid == stage.centerUid || !eligible.contains(uid)) continue;
      final t = _since[uid]! + _takeMs;
      if (best == null || t < best) best = t;
    }
    if (best == null) return null;
    final holdEnd = _centerSince + _holdMs;
    return best > holdEnd ? best : holdEnd;
  }

  void reset() {
    _since.clear();
    _speakers = const [];
    _center = null;
    _centerSince = 0;
  }
}
