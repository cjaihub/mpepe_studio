// LIVE STUDIO v2 — love / sparkles (workstream #2).
//
// Taps update the shown totals optimistically and emit a local burst for the
// floating-hearts animation. Taps are queued and flushed every 300 ms as one
// `lsReact` call of up to StudioLimits.reactionMaxPerCall (one call per tick,
// so at most ~3.3 calls/s, inside the 5/s server limit). Server totals come
// from `reaction.agg` events (and StudioState.counts when wired). Failed
// batches are rolled back.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import 'studio_social_ports.dart';

/// One floating-hearts burst for the UI.
@immutable
class StudioReactionBurst {
  const StudioReactionBurst(this.kind, this.count, {required this.local});
  final ReactionKind kind;
  final int count;

  /// True for the local user's taps; false for other viewers (from aggregates).
  final bool local;
}

@immutable
class StudioReactionsState {
  const StudioReactionsState({
    this.loves = 0,
    this.sparkles = 0,
    this.myLoves = 0,
    this.mySparkles = 0,
  });

  /// Totals shown in the UI (server totals + local unconfirmed taps).
  final int loves;
  final int sparkles;

  /// This session's own taps (e.g. the "+N" badge).
  final int myLoves;
  final int mySparkles;

  int totalOf(ReactionKind k) => k == ReactionKind.love ? loves : sparkles;
}

const Duration kStudioReactionFlushInterval = Duration(milliseconds: 300);

final studioReactionsProvider = NotifierProvider.autoDispose
    .family<StudioReactionsController, StudioReactionsState, String>(
        StudioReactionsController.new);

class StudioReactionsController extends Notifier<StudioReactionsState> {
  StudioReactionsController(this.streamId);

  final String streamId;

  final Map<ReactionKind, int> _server = {ReactionKind.love: 0, ReactionKind.sparkles: 0};
  final Map<ReactionKind, int> _queued = {ReactionKind.love: 0, ReactionKind.sparkles: 0};
  final Map<ReactionKind, int> _inFlight = {ReactionKind.love: 0, ReactionKind.sparkles: 0};

  /// Acked by the server but not yet reflected in an aggregate total.
  final Map<ReactionKind, int> _ackedUnseen = {ReactionKind.love: 0, ReactionKind.sparkles: 0};

  /// Own acked taps not yet subtracted from remote aggregate deltas.
  final Map<ReactionKind, int> _ownInDeltas = {ReactionKind.love: 0, ReactionKind.sparkles: 0};
  int _myLoves = 0;
  int _mySparkles = 0;

  Timer? _timer;
  bool _sending = false;
  ReactionKind _nextFirst = ReactionKind.love;
  StreamController<StudioReactionBurst>? _bursts;

  /// Floating-hearts events (local taps immediately, others' from aggregates).
  Stream<StudioReactionBurst> get bursts =>
      (_bursts ??= StreamController<StudioReactionBurst>.broadcast()).stream;

  @override
  StudioReactionsState build() {
    final sub = studioSocialEvents(ref, streamId).listen(_onEvent);
    final stateStream = ref.watch(studioSocialStateSourceProvider(streamId));
    final stateSub = stateStream?.listen((s) => _applyTotals(s.counts.loves, s.counts.sparkles));
    ref.onDispose(() {
      sub.cancel();
      stateSub?.cancel();
      _timer?.cancel();
      _timer = null;
      _bursts?.close();
      _bursts = null;
    });
    return const StudioReactionsState();
  }

  void tap(ReactionKind kind, [int n = 1]) {
    if (n <= 0) return;
    _queued[kind] = _queued[kind]! + n;
    if (kind == ReactionKind.love) {
      _myLoves += n;
    } else {
      _mySparkles += n;
    }
    _bursts?.add(StudioReactionBurst(kind, n, local: true));
    _publish();
    _timer ??= Timer.periodic(kStudioReactionFlushInterval, (_) => flush());
  }

  /// Sends one batch now (normally driven by the 300 ms timer).
  Future<void> flush() async {
    if (_sending) return;
    final order = _nextFirst == ReactionKind.love
        ? const [ReactionKind.love, ReactionKind.sparkles]
        : const [ReactionKind.sparkles, ReactionKind.love];
    ReactionKind? kind;
    for (final k in order) {
      if (_queued[k]! > 0) {
        kind = k;
        break;
      }
    }
    if (kind == null) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _nextFirst = kind == ReactionKind.love ? ReactionKind.sparkles : ReactionKind.love;
    final n = _queued[kind]! < StudioLimits.reactionMaxPerCall
        ? _queued[kind]!
        : StudioLimits.reactionMaxPerCall;
    _queued[kind] = _queued[kind]! - n;
    _inFlight[kind] = _inFlight[kind]! + n;
    _sending = true;
    try {
      await ref
          .read(studioCallPortProvider)
          .call(StudioCallables.react, {'streamId': streamId, 'kind': kind.wire, 'n': n});
      if (!ref.mounted) return;
      _inFlight[kind] = _inFlight[kind]! - n;
      _ackedUnseen[kind] = _ackedUnseen[kind]! + n;
      _ownInDeltas[kind] = _ownInDeltas[kind]! + n;
    } catch (_) {
      if (!ref.mounted) return;
      // Roll back the optimistic taps of this batch.
      _inFlight[kind] = _inFlight[kind]! - n;
      if (kind == ReactionKind.love) {
        _myLoves -= n;
      } else {
        _mySparkles -= n;
      }
    } finally {
      _sending = false;
    }
    if (ref.mounted) _publish();
  }

  void _onEvent(StudioEvent e) {
    if (e is! ReactionAggEvent) return;
    _emitRemote(ReactionKind.love, e.loves);
    _emitRemote(ReactionKind.sparkles, e.sparkles);
    _applyTotals(e.totals.loves, e.totals.sparkles, fromAggregate: true);
  }

  void _emitRemote(ReactionKind k, int delta) {
    final own = _ownInDeltas[k]! < delta ? _ownInDeltas[k]! : delta;
    _ownInDeltas[k] = _ownInDeltas[k]! - own;
    final others = delta - own;
    if (others > 0) _bursts?.add(StudioReactionBurst(k, others, local: false));
  }

  void _applyTotals(int loves, int sparkles, {bool fromAggregate = false}) {
    if (loves > _server[ReactionKind.love]!) _server[ReactionKind.love] = loves;
    if (sparkles > _server[ReactionKind.sparkles]!) _server[ReactionKind.sparkles] = sparkles;
    if (fromAggregate) {
      // An aggregate is flushed after our acked increments landed.
      _ackedUnseen[ReactionKind.love] = 0;
      _ackedUnseen[ReactionKind.sparkles] = 0;
    }
    _publish();
  }

  int _shown(ReactionKind k) => _server[k]! + _queued[k]! + _inFlight[k]! + _ackedUnseen[k]!;

  void _publish() {
    state = StudioReactionsState(
      loves: _shown(ReactionKind.love),
      sparkles: _shown(ReactionKind.sparkles),
      myLoves: _myLoves,
      mySparkles: _mySparkles,
    );
  }
}
