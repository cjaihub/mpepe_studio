// LIVE STUDIO v2 — Follow ↔ Following for the host card (workstream #2).
//
// Reuses RelationshipRepository (transactional, block-aware). The button
// flips optimistically; the repository's follow-state stream then confirms
// (or corrects, e.g. `requested` for private accounts). Errors roll back.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../social/repositories/relationship_repository.dart';
import 'studio_social_ports.dart';

@immutable
class StudioFollowState {
  const StudioFollowState({this.follow = FollowState.none, this.busy = false, this.error, this.errorSeq = 0});

  final FollowState follow;
  final bool busy;
  final String? error;
  final int errorSeq;

  /// "Following" in the UI (requested counts too: the tap was registered).
  bool get isFollowing =>
      follow == FollowState.following || follow == FollowState.mutual || follow == FollowState.requested;

  /// Hidden for yourself and when either side blocked the other.
  bool get canFollow => follow != FollowState.self && follow != FollowState.blocked;

  StudioFollowState copyWith({FollowState? follow, bool? busy, String? error, int? errorSeq}) =>
      StudioFollowState(
        follow: follow ?? this.follow,
        busy: busy ?? this.busy,
        error: error ?? this.error,
        errorSeq: errorSeq ?? this.errorSeq,
      );
}

/// Family key: the host's uid.
final studioFollowProvider = NotifierProvider.autoDispose
    .family<StudioFollowController, StudioFollowState, String>(StudioFollowController.new);

class StudioFollowController extends Notifier<StudioFollowState> {
  StudioFollowController(this.hostId);

  final String hostId;

  @override
  StudioFollowState build() {
    final me = ref.watch(studioViewerIdentityProvider)?.uid ?? '';
    if (me.isEmpty) return const StudioFollowState();
    if (me == hostId) return const StudioFollowState(follow: FollowState.self);
    final sub = ref.read(relationshipRepositoryProvider).watchFollowState(me, hostId).listen((s) {
      // While a toggle is in flight, keep the optimistic value.
      if (!state.busy) state = state.copyWith(follow: s);
    }, onError: (_) {});
    ref.onDispose(sub.cancel);
    return const StudioFollowState();
  }

  Future<void> toggle() async {
    final me = ref.read(studioViewerIdentityProvider)?.uid ?? '';
    if (state.busy || !state.canFollow) return;
    if (me.isEmpty) {
      state = state.copyWith(error: 'Sign in to follow.', errorSeq: state.errorSeq + 1);
      return;
    }
    final before = state.follow;
    final unfollow = state.isFollowing;
    final optimistic = unfollow
        ? (before == FollowState.mutual ? FollowState.followsYou : FollowState.none)
        : (before == FollowState.followsYou ? FollowState.mutual : FollowState.following);
    state = state.copyWith(follow: optimistic, busy: true);
    final repo = ref.read(relationshipRepositoryProvider);
    try {
      if (unfollow) {
        await repo.unfollowUser(me, hostId);
      } else {
        await repo.followUser(me, hostId);
      }
      if (!ref.mounted) return;
      state = state.copyWith(busy: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        follow: before,
        busy: false,
        error: unfollow ? 'Could not unfollow. Try again.' : 'Could not follow. Try again.',
        errorSeq: state.errorSeq + 1,
      );
    }
  }
}
