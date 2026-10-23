import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

import '../../../backend/social/models/content.dart';
import '../../../backend/social/repositories/relationship_repository.dart';
import '../../../backend/user_service.dart';
import '../../../shared/theme/app_theme.dart';

final _likerProfileProvider = StreamProvider.autoDispose.family<AppUser?, String>((ref, uid) {
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots().map((s) {
    if (s.exists && s.data() != null) {
      return AppUser.fromMap(s.data()!, s.id);
    }
    return null;
  });
});

final _relationshipStatusFamilyProvider =
    StreamProvider.autoDispose.family<MutualRelationshipStatus, String>((ref, targetUid) {
  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final repo = ref.watch(relationshipRepositoryProvider);
  return repo.watchRelationshipStatus(currentUid, targetUid);
});

/// High-density executive modal bottom sheet displaying the list of users who liked this reel.
/// Matches Oneova's premium Linear/Apple executive design language.
class ReelLikesBottomSheet extends ConsumerStatefulWidget {
  final Content content;

  const ReelLikesBottomSheet({super.key, required this.content});

  static void show(BuildContext context, Content content) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: ReelLikesBottomSheet(content: content),
      ),
    );
  }

  @override
  ConsumerState<ReelLikesBottomSheet> createState() => _ReelLikesBottomSheetState();
}

class _ReelLikesBottomSheetState extends ConsumerState<ReelLikesBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final surfaceColor = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.94)
        : AppColors.lightSurface.withValues(alpha: 0.96);

    final likesStream = FirebaseFirestore.instance
        .collection('content_likes')
        .where('contentId', isEqualTo: widget.content.id)
        .snapshots();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: context.border, width: 1.0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandPink.withValues(alpha: 0.40),
                          width: 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: AppColors.brandPink,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Likes',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: context.textSecondary, size: 20),
                      onPressed: () => Navigator.pop(context),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),

              // Liker list stream
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: likesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(child: AnimatedLoadingIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Unable to load likes',
                          style: GoogleFonts.inter(
                            color: context.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.brandPink.withValues(alpha: 0.12),
                                border: Border.all(
                                  color: AppColors.brandPink.withValues(alpha: 0.35),
                                  width: 1.0,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.favorite_border_rounded,
                                color: AppColors.brandPink,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No likes yet',
                              style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Be the first to like this reel!',
                              style: GoogleFonts.inter(
                                color: context.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => Divider(
                        color: context.border.withValues(alpha: 0.5),
                        height: 1,
                        thickness: 0.6,
                      ),
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final userId = data['userId'] as String? ?? '';
                        if (userId.isEmpty) return const SizedBox.shrink();

                        return _LikerUserTile(
                          userId: userId,
                          onTap: () {
                            context.push('/profile/$userId');
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikerUserTile extends ConsumerWidget {
  final String userId;
  final VoidCallback onTap;

  const _LikerUserTile({
    required this.userId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(_likerProfileProvider(userId));
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isMe = currentUid == userId;

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return const SizedBox.shrink();
        }

        final username = user.username?.isNotEmpty == true ? user.username! : 'user';
        final displayName = user.fullName.isNotEmpty ? user.fullName : username;
        final photoUrl = user.profilePhotoUrl;
        final isVerified = user.isVerified;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                // Avatar with attached mini pink heart badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.brandPink.withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                      ),
                      child: ClipOval(
                        child: (photoUrl != null && photoUrl.isNotEmpty)
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _buildAvatarFallback(displayName),
                              )
                            : _buildAvatarFallback(displayName),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brandPink,
                          border: Border.all(
                            color: context.surface,
                            width: 1.2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 9,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),

                // Name and username
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.verified,
                              color: AppColors.brandBlue,
                              size: 13,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Follow / Following Action Button
                if (!isMe && currentUid.isNotEmpty)
                  _FollowButton(targetUid: userId),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 52),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildAvatarFallback(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: AppColors.brandBlue.withValues(alpha: 0.20),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.inter(
          color: AppColors.brandBlue,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _FollowButton extends ConsumerStatefulWidget {
  final String targetUid;

  const _FollowButton({required this.targetUid});

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final relAsync = ref.watch(_relationshipStatusFamilyProvider(widget.targetUid));
    final status = relAsync.value ?? MutualRelationshipStatus.none;

    final isFollowing = status == MutualRelationshipStatus.following ||
        status == MutualRelationshipStatus.mutual;

    if (_isLoading) {
      return Container(
        width: 76,
        height: 28,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandBlue),
        ),
      );
    }

    if (isFollowing) {
      return OutlinedButton(
        onPressed: _toggleFollow,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          minimumSize: const Size(76, 28),
          side: BorderSide(color: context.border, width: 1.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        child: Text(
          status == MutualRelationshipStatus.mutual ? 'Mutual' : 'Following',
          style: GoogleFonts.inter(
            color: context.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: _toggleFollow,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        minimumSize: const Size(76, 28),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: Text(
        'Follow',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return;

    final repo = ref.read(relationshipRepositoryProvider);
    final status = ref.read(_relationshipStatusFamilyProvider(widget.targetUid)).value ??
        MutualRelationshipStatus.none;
    final isFollowing = status == MutualRelationshipStatus.following ||
        status == MutualRelationshipStatus.mutual;

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      if (isFollowing) {
        await repo.unfollowUser(currentUid, widget.targetUid);
      } else {
        await repo.followUser(currentUid, widget.targetUid);
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
