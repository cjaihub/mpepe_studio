import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/interaction_repository.dart';
import '../repositories/relationship_repository.dart';

class SocialInteractionState {
  final Set<String> likedPostIds;
  final Set<String> followedUserIds;

  SocialInteractionState({
    this.likedPostIds = const {},
    this.followedUserIds = const {},
  });

  SocialInteractionState copyWith({
    Set<String>? likedPostIds,
    Set<String>? followedUserIds,
  }) {
    return SocialInteractionState(
      likedPostIds: likedPostIds ?? this.likedPostIds,
      followedUserIds: followedUserIds ?? this.followedUserIds,
    );
  }
}

class SocialInteractionController extends Notifier<SocialInteractionState> {
  @override
  SocialInteractionState build() {
    return SocialInteractionState();
  }

  Future<void> toggleLike(String postId, String userId) async {
    final currentLikes = Set<String>.from(state.likedPostIds);
    final isLiking = !currentLikes.contains(postId);
    
    // Optimistic update
    if (isLiking) {
      currentLikes.add(postId);
    } else {
      currentLikes.remove(postId);
    }
    state = state.copyWith(likedPostIds: currentLikes);

    try {
      final repo = ref.read(interactionRepositoryProvider);
      if (isLiking) {
        await repo.likeContent(userId, postId);
      } else {
        await repo.unlikeContent(userId, postId);
      }
    } catch (e) {
      // Revert on failure
      final revertLikes = Set<String>.from(state.likedPostIds);
      if (isLiking) {
        revertLikes.remove(postId);
      } else {
        revertLikes.add(postId);
      }
      state = state.copyWith(likedPostIds: revertLikes);
    }
  }

  Future<void> toggleFollow(String targetUserId, String currentUserId) async {
    final currentFollows = Set<String>.from(state.followedUserIds);
    final isFollowing = !currentFollows.contains(targetUserId);

    // Optimistic update
    if (isFollowing) {
      currentFollows.add(targetUserId);
    } else {
      currentFollows.remove(targetUserId);
    }
    state = state.copyWith(followedUserIds: currentFollows);

    try {
      final repo = ref.read(relationshipRepositoryProvider);
      if (isFollowing) {
        await repo.followUser(currentUserId, targetUserId);
      } else {
        await repo.unfollowUser(currentUserId, targetUserId);
      }
    } catch (e) {
      // Revert on failure
      final revertFollows = Set<String>.from(state.followedUserIds);
      if (isFollowing) {
        revertFollows.remove(targetUserId);
      } else {
        revertFollows.add(targetUserId);
      }
      state = state.copyWith(followedUserIds: revertFollows);
    }
  }
}

final socialInteractionControllerProvider =
    NotifierProvider<SocialInteractionController, SocialInteractionState>(() {
  return SocialInteractionController();
});
