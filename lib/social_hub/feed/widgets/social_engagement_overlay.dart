import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../backend/social/models/post.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../backend/social/providers/social_interaction_controller.dart';
import '../../../backend/social/repositories/interaction_repository.dart';
import 'comments_bottom_sheet.dart';
import 'share_sheet.dart';

final _authorStreamProvider = StreamProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, uid) {
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots().map((doc) => doc.exists ? doc.data() : null);
});

final _postStreamProvider = StreamProvider.autoDispose.family<Post, String>((
  ref,
  postId,
) {
  return FirebaseFirestore.instance
      .collection('posts')
      .doc(postId)
      .snapshots()
      .map((doc) {
        if (!doc.exists) throw Exception('Post not found');
        return Post.fromFirestore(doc);
      });
});

final _isLikedStreamProvider = StreamProvider.autoDispose.family<bool, String>((
  ref,
  postId,
) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(false);
  final repo = ref.watch(interactionRepositoryProvider);
  return repo.watchIsLiked(uid, postId);
});

class SocialEngagementOverlay extends ConsumerWidget {
  final Post initialPost;

  const SocialEngagementOverlay({super.key, required Post post})
    : initialPost = post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Listen to real-time post updates (fallback to initial post if loading)
    final postAsync = ref.watch(_postStreamProvider(initialPost.id));
    final post = postAsync.value ?? initialPost;

    // 2. Listen to real-time like status
    final isLikedAsync = ref.watch(_isLikedStreamProvider(post.id));
    final isLiked = isLikedAsync.value ?? false;

    // 3. Follow status (still from controller since it's user-to-user, but could also be stream if needed)
    final interactionState = ref.watch(socialInteractionControllerProvider);
    final isFollowed = interactionState.followedUserIds.contains(post.authorId);

    // We don't manually add +1 anymore unless we want optimistic UI before stream updates,
    // but the task specifically said: "Transition ... to use real-time Firestore Streams ... so that likes and comments update live in real-time"
    // To ensure strict sync, we use the actual likeCount from the stream.
    // However, during the optimistic phase, we might still want it to feel fast.
    // The stream should reflect the change within ms.
    final likeCount = post.reactionCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar with Follow Plus Icon
        _buildAvatar(context, ref, post, isFollowed),
        const SizedBox(height: 24),

        // Like Button
        _buildActionButton(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? AppColors.brandBlue : Colors.white,
          label: _formatCount(likeCount),
          onTap: () {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) return;
            // Use toggleLike directly from repository to ensure strict logic
            ref.read(interactionRepositoryProvider).toggleLike(uid, post.id);
          },
        ),
        const SizedBox(height: 16),

        // Comment Button
        _buildActionButton(
          icon: Icons.chat_bubble_outline,
          color: Colors.white,
          label: _formatCount(post.commentCount),
          onTap: () {
            CommentsBottomSheet.show(context, post.id);
          },
        ),
        const SizedBox(height: 16),

        // Save Button
        _buildActionButton(
          icon: Icons.bookmark_border,
          color: Colors.white,
          label: 'Save',
          onTap: () {
            // Enterprise save collection bottom sheet
          },
        ),
        const SizedBox(height: 16),

        // Share Button
        _buildActionButton(
          icon: Icons.share_outlined,
          color: Colors.white,
          label: 'Share',
          onTap: () {
            ShareSheet.show(context, postId: post.id, authorId: post.authorId);
          },
        ),
      ],
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    WidgetRef ref,
    Post post,
    bool isFollowed,
  ) {
    // Listen to real-time author updates
    final authorAsync = ref.watch(_authorStreamProvider(post.authorId));
    final avatarUrl = authorAsync.value?['profilePhotoUrl'] ?? authorAsync.value?['photoUrl'];

    return SizedBox(
      width: 50,
      height: 60,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () {
              context.push('/social/profile/${post.authorId}');
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                color: context.surfaceMid,
              ),
              child: ClipOval(
                child: avatarUrl != null
                  ? Image.network(avatarUrl as String, fit: BoxFit.cover)
                  : Center(child: Text(post.authorId.isNotEmpty ? post.authorId[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 15,
            child: GestureDetector(
              onTap: () {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                ref
                    .read(socialInteractionControllerProvider.notifier)
                    .toggleFollow(post.authorId, uid);
              },
              child: AnimatedScale(
                scale: isFollowed ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutBack,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 36,
            shadows: const [
              Shadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}
