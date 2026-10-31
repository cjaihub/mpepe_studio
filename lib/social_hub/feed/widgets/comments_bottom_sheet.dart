import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../backend/social/services/comment_service.dart';
import '../../../backend/social/models/comment.dart' as model;
import '../../../backend/user_service.dart';
import 'emoji_keyboard_panel.dart';
import 'gift_picker_modal.dart';
import 'gif_picker_sheet.dart';
import '../../../backend/giphy_service.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CommentsBottomSheet extends ConsumerStatefulWidget {
  final String postId;

  const CommentsBottomSheet({super.key, required this.postId});

  static void show(BuildContext context, String postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (context) => CommentsBottomSheet(postId: postId),
    );
  }

  @override
  ConsumerState<CommentsBottomSheet> createState() =>
      _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends ConsumerState<CommentsBottomSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _replyingToCommentId;
  String? _replyingToUsername;
  final Set<String> _expandedReplies = {};
  bool _showEmojiPicker = false;

  @override
  void dispose() {
    _commentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();

    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';

    final newComment = model.Comment(
      id: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc()
          .id,
      postId: widget.postId,
      authorId: userId,
      content: text,
      createdAt: DateTime.now(),
      replyToId: _replyingToCommentId,
    );

    try {
      await ref.read(commentServiceProvider).addComment(newComment);

      if (mounted) {
        if (_replyingToCommentId != null) {
          setState(() {
            _expandedReplies.add(_replyingToCommentId!);
          });
        }
        _commentController.clear();
        setState(() {
          _replyingToCommentId = null;
          _replyingToUsername = null;
        });
        _focusNode.unfocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _postDirectGifComment(String gifUrl) async {
    HapticFeedback.lightImpact();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';

    final newComment = model.Comment(
      id: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc()
          .id,
      postId: widget.postId,
      authorId: userId,
      content: gifUrl,
      type: model.CommentType.gif,
      createdAt: DateTime.now(),
      replyToId: _replyingToCommentId,
    );

    try {
      await ref.read(commentServiceProvider).addComment(newComment);
      if (mounted) {
        if (_replyingToCommentId != null) {
          setState(() => _expandedReplies.add(_replyingToCommentId!));
        }
        setState(() {
          _replyingToCommentId = null;
          _replyingToUsername = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to post comment')));
      }
    }
  }

  void _postGifComment(GiphyGif gif) async {
    HapticFeedback.lightImpact();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';

    final newComment = model.Comment(
      id: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .doc()
          .id,
      postId: widget.postId,
      authorId: userId,
      content: gif.fullUrl,
      type: model.CommentType.gif,
      createdAt: DateTime.now(),
      replyToId: _replyingToCommentId,
    );

    try {
      await ref.read(commentServiceProvider).addComment(newComment);
      if (mounted) {
        if (_replyingToCommentId != null) {
          setState(() => _expandedReplies.add(_replyingToCommentId!));
        }
        setState(() {
          _replyingToCommentId = null;
          _replyingToUsername = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: context.surface.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.85 : 0.95),
              border: Border(
                top: BorderSide(
                  color: context.border,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                _buildHeader(context),
                _buildPostLikesSection(),
                Divider(color: context.border, height: 1),
                Expanded(child: _buildCommentsList()),
                _buildInputArea(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 24),
              StreamBuilder<List<model.Comment>>(
                stream: ref
                    .read(commentServiceProvider)
                    .watchComments(widget.postId),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return Text(
                    '$count Comments',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      letterSpacing: 0.2,
                    ),
                  );
                },
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: context.textPrimary, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPostLikesSection() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final postData = snapshot.data!.data() as Map<String, dynamic>?;
        final likerAvatars =
            (postData?['liker_avatars'] as List<dynamic>?) ?? [];
        final likesCount = postData?['likes_count'] ?? 0;

        if (likesCount == 0) return const SizedBox.shrink();

        return InkWell(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Row(
              children: [
                if (likerAvatars.isNotEmpty)
                  SizedBox(
                    width:
                        (18.0 *
                            (likerAvatars.length > 3
                                ? 3
                                : likerAvatars.length)) +
                        14,
                    height: 32,
                    child: Stack(
                      children: List.generate(
                        likerAvatars.length > 3 ? 3 : likerAvatars.length,
                        (i) => Positioned(
                          left: i * 18.0,
                          child: _buildOverlapAvatar(
                            likerAvatars[i].toString(),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Liked by ${likerAvatars.isNotEmpty ? 'others' : likesCount}',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: context.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlapAvatar(String url) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.border, width: 2),
        color: AppColors.brandBlue,
        image: url.isNotEmpty
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: url.isEmpty
          ? const Icon(Icons.person, color: Colors.white, size: 16)
          : null,
    );
  }

  Widget _buildCommentsList() {
    return StreamBuilder<List<model.Comment>>(
      stream: ref.read(commentServiceProvider).watchComments(widget.postId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: AnimatedLoadingIndicator(color: AppColors.brandBlue),
          );
        }

        final allComments = snapshot.data!;
        final mainComments = allComments
            .where((c) => c.replyToId == null)
            .toList();

        if (mainComments.isEmpty) {
          return Center(
            child: Text(
              'No comments yet. Be the first!',
              style: GoogleFonts.inter(color: context.textMuted),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(
            top: 16,
            bottom: 16,
            left: 16,
            right: 16,
          ),
          itemCount: mainComments.length,
          itemBuilder: (context, index) {
            final comment = mainComments[index];
            final replies = allComments
                .where((c) => c.replyToId == comment.id)
                .toList();
            return _buildCommentTile(comment, replies: replies);
          },
        );
      },
    );
  }

  Widget _buildCommentTile(
    model.Comment comment, {
    bool isReply = false,
    List<model.Comment> replies = const [],
  }) {
    final hasReplies = replies.isNotEmpty;
    final isExpanded = _expandedReplies.contains(comment.id);

    return Padding(
      padding: EdgeInsets.only(bottom: isReply ? 12.0 : 20.0),
      child: FutureBuilder<AppUser?>(
        future: ref.read(userProvider.notifier).getUser(comment.authorId),
        builder: (context, userSnapshot) {
          final author = userSnapshot.data;
          final username = author?.fullName ?? author?.username ?? 'User';
          final avatar = author?.profilePhotoUrl;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author Avatar
                  GestureDetector(
                    onTap: () =>
                        context.push('/social/profile/${comment.authorId}'),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.border,
                          width: 1.5,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: isReply ? 12 : 16,
                        backgroundColor: AppColors.brandBlue,
                        backgroundImage: avatar != null
                            ? NetworkImage(avatar)
                            : null,
                        child: avatar == null
                            ? Text(
                                username.isNotEmpty
                                    ? username[0].toUpperCase()
                                    : 'U',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Comment Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => context.push(
                            '/social/profile/${comment.authorId}',
                          ),
                          child: Text(
                            username,
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (comment.type == model.CommentType.gif)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              comment.content,
                              height: 160,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                   (context, child, loadingProgress) {
                                     if (loadingProgress == null) return child;
                                     return Container(
                                       height: 160,
                                       decoration: BoxDecoration(
                                         color: context.surfaceMid,
                                         borderRadius: BorderRadius.circular(12),
                                       ),
                                       child: const Center(
                                         child: SizedBox(
                                           width: 24,
                                           height: 24,
                                           child: AnimatedLoadingIndicator(
                                             strokeWidth: 2,
                                             color: AppColors.brandBlue,
                                           ),
                                         ),
                                       ),
                                     );
                                   },
                               errorBuilder: (context, error, stackTrace) => Container(
                                 height: 100,
                                 decoration: BoxDecoration(
                                   color: context.surfaceMid,
                                   borderRadius: BorderRadius.circular(12),
                                 ),
                                 child: Center(
                                   child: Icon(
                                     Icons.broken_image_rounded,
                                     color: context.textMuted,
                                     size: 28,
                                   ),
                                 ),
                               ),
                             ),
                           )
                         else
                           Text(
                             comment.content,
                             style: GoogleFonts.inter(
                               color: context.textPrimary,
                               fontSize: 14,
                               height: 1.3,
                             ),
                           ),
                         if (comment.safetyVerdict == 'suspicious')
                           Padding(
                             padding: const EdgeInsets.only(top: 4),
                             child: Row(children: [
                               const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.brandPink),
                               const SizedBox(width: 4),
                               Expanded(
                                 child: Text(
                                   'Ova Guard: be careful. ${comment.safetyReason ?? 'This may be a scam.'}',
                                   style: GoogleFonts.inter(color: context.textMuted, fontSize: 11),
                                 ),
                               ),
                             ]),
                           ),
                         const SizedBox(height: 8),

                         // Comment Actions (Time, Reply)
                         Row(
                           children: [
                             Text(
                               _formatDate(comment.createdAt),
                               style: GoogleFonts.inter(
                                 color: context.textMuted,
                                 fontSize: 12,
                                 fontWeight: FontWeight.w500,
                               ),
                             ),
                             const SizedBox(width: 16),
                             GestureDetector(
                               onTap: () {
                                 setState(() {
                                   _replyingToCommentId = isReply
                                       ? comment.replyToId
                                       : comment.id;
                                   _replyingToUsername = username;
                                   _focusNode.requestFocus();
                                 });
                               },
                               child: Text(
                                 'Reply',
                                 style: GoogleFonts.inter(
                                   color: _replyingToCommentId == comment.id
                                       ? AppColors.brandBlue
                                       : context.textMuted,
                                   fontSize: 12,
                                   fontWeight: FontWeight.w600,
                                 ),
                               ),
                             ),
                           ],
                         ),

                         // View Replies Toggle
                         if (!isReply && hasReplies)
                           Padding(
                             padding: const EdgeInsets.only(top: 12.0),
                             child: GestureDetector(
                               onTap: () {
                                 setState(() {
                                   if (isExpanded) {
                                     _expandedReplies.remove(comment.id);
                                   } else {
                                     _expandedReplies.add(comment.id);
                                   }
                                 });
                               },
                               child: Row(
                                 children: [
                                   Container(
                                     width: 24,
                                     height: 1,
                                     color: context.border,
                                   ),
                                   const SizedBox(width: 8),
                                   Text(
                                     isExpanded
                                         ? 'Hide replies'
                                         : 'View ${replies.length} replies',
                                     style: GoogleFonts.inter(
                                       color: context.textSecondary,
                                       fontSize: 12,
                                       fontWeight: FontWeight.w600,
                                     ),
                                   ),
                                 ],
                               ),
                             ),
                           ),
                       ],
                     ),
                   ),
                  const SizedBox(width: 12),

                  // Comment Like Button
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final currentUserId =
                              FirebaseAuth.instance.currentUser?.uid;
                          if (currentUserId == null) return;

                          final isLiked = comment.likerIds.contains(
                            currentUserId,
                          );
                          ref
                              .read(commentServiceProvider)
                              .reactToComment(
                                widget.postId,
                                comment.id,
                                userId: currentUserId,
                                isLike: !isLiked,
                              );
                        },
                        child: Icon(
                          (FirebaseAuth.instance.currentUser != null &&
                                  comment.likerIds.contains(
                                    FirebaseAuth.instance.currentUser!.uid,
                                  ))
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color:
                              (FirebaseAuth.instance.currentUser != null &&
                                  comment.likerIds.contains(
                                    FirebaseAuth.instance.currentUser!.uid,
                                  ))
                              ? AppColors.brandBlue
                              : AppColors.textMuted,
                          size: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${comment.reactionCount}',
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Render Nested Replies
              if (!isReply && isExpanded && hasReplies)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0, left: 16.0),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: context.border,
                            borderRadius: BorderRadius.circular(1),
                          ),
                          margin: const EdgeInsets.only(
                            right: 14,
                            top: 4,
                            bottom: 4,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: replies
                                .map(
                                  (reply) =>
                                      _buildCommentTile(reply, isReply: true),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!isReply && !isExpanded && hasReplies)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, left: 44.0),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _expandedReplies.add(comment.id)),
                    child: Row(
                      children: [
                        Container(width: 24, height: 1, color: context.border),
                        const SizedBox(width: 8),
                        Text(
                          'View ${replies.length} replies',
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h';
    } else {
      return '${diff.inDays}d';
    }
  }

  Widget _buildInputArea(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Container(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            top: BorderSide(
              color: context.border,
              width: 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyingToCommentId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, left: 4),
                child: Row(
                  children: [
                    Text(
                      'Replying to ${_replyingToUsername ?? ''}',
                      style: TextStyle(
                        color: context.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() {
                        _replyingToCommentId = null;
                        _replyingToUsername = null;
                      }),
                      child: Icon(
                        Icons.close,
                        color: context.textMuted,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                FutureBuilder<AppUser?>(
                  future: ref
                      .read(userProvider.notifier)
                      .getUser(FirebaseAuth.instance.currentUser?.uid ?? ''),
                  builder: (context, userSnapshot) {
                    final user = userSnapshot.data;
                    final avatar = user?.profilePhotoUrl;
                    final username = user?.username ?? '';
                    final initial = username.isNotEmpty
                        ? username[0].toUpperCase()
                        : 'U';
                    return GestureDetector(
                      onTap: () {
                        if (user?.id != null) {
                          context.push('/profile/${user!.id}');
                        }
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.brandBlue,
                        backgroundImage: avatar != null
                            ? NetworkImage(avatar)
                            : null,
                        child: avatar == null
                            ? Text(
                                initial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _replyingToCommentId != null
                            ? AppColors.brandBlue.withValues(alpha: 0.5)
                            : context.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(
                              () => _showEmojiPicker = !_showEmojiPicker,
                            );
                            if (_showEmojiPicker) {
                              _focusNode.unfocus();
                            } else {
                              _focusNode.requestFocus();
                            }
                          },
                          child: Icon(
                            _showEmojiPicker
                                ? Icons.keyboard
                                : Icons.emoji_emotions_outlined,
                            color: context.textMuted,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            focusNode: _focusNode,
                            onTap: () {
                              if (_showEmojiPicker) {
                                setState(() => _showEmojiPicker = false);
                              }
                            },
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Add a comment...',
                              hintStyle: GoogleFonts.inter(
                                color: context.textMuted,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => _postComment(),
                          ),
                        ),
                        // GIF Button
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.gif_box_outlined,
                            color: context.textSecondary,
                            size: 24,
                          ),
                          onPressed: () async {
                            final gif = await GifPickerSheet.show(context);
                            if (gif != null) {
                              _postGifComment(gif);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        // Create GIF Button
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.camera_alt_outlined,
                            color: context.textSecondary,
                            size: 22,
                          ),
                          onPressed: () {
                            context.push(
                              '/create/gif',
                              extra: {
                                'onGifCreated': (String gifUrl) {
                                  // We just create a manual GiphyGif-like object with the url or directly call a private post method
                                  _postDirectGifComment(gifUrl);
                                },
                              },
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        // Gift Button
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.card_giftcard,
                            color: Colors.amber,
                            size: 22,
                          ),
                          onPressed: () {
                            GiftPickerModal.show(
                              context,
                              targetUserId:
                                  'creator123', // In a real app, pass the actual content creator ID
                              onSendGift: (gift) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Sent ${gift.name} ${gift.emoji} worth ${gift.coinCost} coins!',
                                    ),
                                  ),
                                );
                                // TODO: Append gift as a comment or trigger backend gift API
                              },
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _postComment,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.brandBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_upward,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            EmojiKeyboardPanel(
              controller: _commentController,
              isVisible: _showEmojiPicker,
            ),
          ],
        ),
      ),
    );
  }
}
