// LIVE STUDIO v2 — viewer / participant counts (workstream #2).
//
// Viewers and participants come from the lossy `counts` events (≤ every 2 s);
// until the first event arrives they fall back to StudioState.counts. Love,
// sparkle and share totals follow `reaction.agg` totals and the state.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import 'studio_social_ports.dart';

final studioCountsProvider = NotifierProvider.autoDispose
    .family<StudioCountsController, StudioCounts, String>(StudioCountsController.new);

class StudioCountsController extends Notifier<StudioCounts> {
  StudioCountsController(this.streamId);

  final String streamId;
  bool _haveLiveCounts = false;

  @override
  StudioCounts build() {
    _haveLiveCounts = false;
    final sub = studioSocialEvents(ref, streamId).listen(_onEvent);
    final stateSub = ref.watch(studioSocialStateSourceProvider(streamId))?.listen(_onState);
    ref.onDispose(() {
      sub.cancel();
      stateSub?.cancel();
    });
    return const StudioCounts();
  }

  void _onState(StudioState s) {
    final c = s.counts;
    state = state.copyWith(
      viewers: _haveLiveCounts ? null : c.viewers,
      participants: _haveLiveCounts ? null : c.participants,
      loves: _max(state.loves, c.loves),
      sparkles: _max(state.sparkles, c.sparkles),
      shares: _max(state.shares, c.shares),
    );
  }

  void _onEvent(StudioEvent e) {
    switch (e) {
      case CountsEvent(:final viewers, :final participants):
        _haveLiveCounts = true;
        state = state.copyWith(viewers: viewers, participants: participants);
      case ReactionAggEvent(:final totals):
        state = state.copyWith(
          loves: _max(state.loves, totals.loves),
          sparkles: _max(state.sparkles, totals.sparkles),
          shares: _max(state.shares, totals.shares),
        );
      default:
        break;
    }
  }

  static int _max(int a, int b) => a > b ? a : b;
}

/// Compact count: 999 → "999", 1250 → "1.2K", 200000 → "200K",
/// 1250000 → "1.2M", 3400000000 → "3.4B". Truncates (never rounds up), so a
/// count is never shown higher than it is.
String formatStudioCount(int n) {
  if (n < 0) return '-${formatStudioCount(-n)}';
  if (n < 1000) return '$n';
  const units = [(1000000000, 'B'), (1000000, 'M'), (1000, 'K')];
  for (final (size, suffix) in units) {
    if (n >= size) {
      final whole = n ~/ size;
      // One decimal below 100 of a unit, none above (e.g. "200K", "12.5K").
      if (whole >= 100) return '$whole$suffix';
      final tenth = (n * 10 ~/ size) % 10;
      return tenth == 0 ? '$whole$suffix' : '$whole.$tenth$suffix';
    }
  }
  return '$n';
}
