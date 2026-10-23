// LIVE STUDIO v2 — seq-ordered StudioState merge (pure, ARCHITECTURE §3/§5).
//
// - patches apply strictly in `seq` order; old / duplicate seq are ignored;
// - a patch that skips ahead is buffered. If the hole fills (packets from
//   concurrent function calls can arrive out of order) it drains; otherwise
//   [hasGap] stays true and the controller asks for `lsStateFull`;
// - a full state replaces the base unless it is older than what we have,
//   then buffered patches above it drain.

import 'dart:collection';

import '../contracts/studio_contracts.dart';

enum StudioPatchOutcome {
  /// Applied (and possibly drained buffered patches after it).
  applied,

  /// seq ≤ current: duplicate or old, dropped.
  stale,

  /// No base state yet: kept until the first full state.
  buffered,

  /// seq skipped ahead: buffered, [StudioStateSync.hasGap] is true.
  gap,
}

class StudioStateSync {
  StudioState? _state;
  final SplayTreeMap<int, StatePatchEvent> _pending = SplayTreeMap();

  /// Max buffered patches; beyond this the oldest are dropped (a full state
  /// will be needed anyway).
  static const int maxPending = 256;

  StudioState? get state => _state;

  /// Patches waiting for a base or for a missing seq.
  int get pendingCount => _pending.length;

  /// True when patches are buffered behind a missing seq.
  bool get hasGap => _state != null && _pending.isNotEmpty;

  StudioPatchOutcome applyPatch(StatePatchEvent e) {
    final s = _state;
    if (s == null) {
      _buffer(e);
      return StudioPatchOutcome.buffered;
    }
    if (e.seq <= s.seq) return StudioPatchOutcome.stale;
    if (e.seq == s.seq + 1) {
      _state = s.applyPatch(e.seq, e.path, e.value);
      _drain();
      return StudioPatchOutcome.applied;
    }
    _buffer(e);
    return StudioPatchOutcome.gap;
  }

  /// Applies an authoritative full state. Returns false (ignored) when it is
  /// older than the current one.
  bool applyFull(StudioState full) {
    final s = _state;
    if (s != null && full.seq < s.seq) return false;
    _state = full;
    _pending.removeWhere((seq, _) => seq <= full.seq);
    _drain();
    return true;
  }

  void _buffer(StatePatchEvent e) {
    _pending[e.seq] = e;
    while (_pending.length > maxPending) {
      _pending.remove(_pending.firstKey());
    }
  }

  void _drain() {
    var s = _state!;
    while (_pending.isNotEmpty) {
      final first = _pending.firstKey()!;
      if (first <= s.seq) {
        _pending.remove(first);
        continue;
      }
      if (first != s.seq + 1) break;
      final e = _pending.remove(first)!;
      s = s.applyPatch(e.seq, e.path, e.value);
    }
    _state = s;
  }
}
