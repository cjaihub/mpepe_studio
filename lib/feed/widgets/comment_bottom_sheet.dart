import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../backend/social/models/content.dart';
import '../../../backend/social/models/comment.dart';
import '../../../backend/social/services/comment_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../backend/user_service.dart';
import '../../../auth/widgets/auth_interaction_gate.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import '../../../shared/services/draft_store.dart';
import 'oneova_gif_picker_sheet.dart';
import 'voice_comment_card.dart';
import '../../../shared/widgets/oneova_voice_typing_button.dart';

final _commentAuthorProvider = StreamProvider.autoDispose
    .family<AppUser?, String>((ref, uid) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .map((s) {
            if (s.exists && s.data() != null) {
              return AppUser.fromMap(s.data()!, s.id);
            }
            return null;
          });
    });

class CommentBottomSheet extends ConsumerStatefulWidget {
  final Content content;
  final bool autoFocus;

  const CommentBottomSheet({
    super.key,
    required this.content,
    this.autoFocus = false,
  });

  static void show(
    BuildContext context,
    Content content, {
    bool autoFocus = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: CommentBottomSheet(content: content, autoFocus: autoFocus),
        ),
      ),
    );
  }

  @override
  ConsumerState<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends ConsumerState<CommentBottomSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isPosting = false;
  String? _inlineError;
  bool _sortByNewest = false;
  CommentGif? _stagedGif;

  static const List<String> _quickEmojis = ['❤️', '🔥', '😂', '👏', '😍', '💯', '🙌', '😮'];
  static const List<String> _quickSuggestions = [
    '🔥 Fire!',
    '😂 So true',
    '❤️ Love this',
    '👏 Incredible',
    '🙌 10/10',
    '✨ Vibe',
    '👀 Need part 2',
  ];

  /// Top-level comment the next post replies to (replies stay one level deep).
  String? _replyToId;
  String? _replyToName;

  void _startReply(Comment comment, String username) {
    HapticFeedback.selectionClick();
    setState(() {
      _replyToId = comment.replyToId ?? comment.id;
      _replyToName = username;
    });
    _commentController.text = '@$username ';
    _commentController.selection = TextSelection.fromPosition(
      TextPosition(offset: _commentController.text.length),
    );
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToId = null;
      _replyToName = null;
    });
    if (_commentController.text.startsWith('@')) _commentController.clear();
  }

  /// Orders top-level comments with their replies (oldest first) directly underneath.
  /// Supports Top (by reactionCount) or Newest (by createdAt), pinned always on top.
  static List<Comment> _threaded(List<Comment> comments, {bool newest = false}) {
    final ids = comments.map((c) => c.id).toSet();
    final replies = <String, List<Comment>>{};
    final roots = <Comment>[];
    for (final c in comments) {
      final parent = c.replyToId;
      if (parent != null && parent.isNotEmpty && ids.contains(parent)) {
        replies.putIfAbsent(parent, () => []).add(c);
      } else {
        roots.add(c);
      }
    }
    roots.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (newest) {
        return b.createdAt.compareTo(a.createdAt);
      } else {
        return b.reactionCount.compareTo(a.reactionCount);
      }
    });
    return [
      for (final root in roots) ...[
        root,
        ...(replies[root.id] ?? const <Comment>[]).reversed,
      ],
    ];
  }

  @override
  void initState() {
    super.initState();
    final savedDraft = DraftStore.instance.getDraft(DraftStore.commentKey(widget.content.id));
    if (savedDraft != null && savedDraft.isNotEmpty) {
      _commentController.text = savedDraft;
    }
    _commentController.addListener(_onTextChanged);
    if (widget.autoFocus) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _onTextChanged() {
    DraftStore.instance.setDraft(DraftStore.commentKey(widget.content.id), _commentController.text);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _commentController.removeListener(_onTextChanged);
    _commentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// GIF search powered by Oneova GIF Engine (`lsGifSearch`).
  Future<void> _pickGif() async {
    if (_isPosting) return;
    final g = await OneovaGifPickerSheet.show(context);
    if (g == null || !mounted) return;
    setState(() => _stagedGif = g);
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    final gif = _stagedGif;
    if ((text.isEmpty && gif == null) || _isPosting) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      AuthInteractionGate.requireAuth(
        context,
        actionTitle: 'Comment on this video',
      );
      return;
    }

    final currentUid = user.uid;
    HapticFeedback.lightImpact();

    setState(() {
      _isPosting = true;
      _inlineError = null;
    });

    try {
      final newComment = Comment(
        id: '',
        postId: widget.content.id,
        authorId: currentUid,
        content: text,
        type: gif != null ? CommentType.gif : CommentType.text,
        gif: gif,
        replyToId: _replyToId,
        createdAt: DateTime.now(),
      );

      await ref
          .read(commentServiceProvider)
          .addComment(
            newComment,
            isCreator: widget.content.authorId == currentUid,
          );

      if (mounted) {
        _commentController.clear();
        DraftStore.instance.clearDraft(DraftStore.commentKey(widget.content.id));
        setState(() {
          _stagedGif = null;
          _replyToId = null;
          _replyToName = null;
        });
        _focusNode.unfocus();
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _inlineError = 'Could not post comment: ${e.toString()}',
        );
        HapticFeedback.mediumImpact();
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsStreamProvider(widget.content.id));
    final currentUser = FirebaseAuth.instance.currentUser;
    final isDark = context.isDark;
    final surfaceColor = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.94)
        : AppColors.lightSurface.withValues(alpha: 0.96);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.border, width: 1.0),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      commentsAsync.maybeWhen(
                        data: (comments) => '${comments.length} Comments',
                        orElse: () => '${widget.content.commentCount} Comments',
                      ),
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    // Top / Newest sort toggle
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: context.border, width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (_sortByNewest) {
                                HapticFeedback.selectionClick();
                                setState(() => _sortByNewest = false);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: !_sortByNewest ? AppColors.brandBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Text(
                                'Top',
                                style: GoogleFonts.inter(
                                  color: !_sortByNewest ? Colors.white : context.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (!_sortByNewest) {
                                HapticFeedback.selectionClick();
                                setState(() => _sortByNewest = true);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _sortByNewest ? AppColors.brandBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Text(
                                'Newest',
                                style: GoogleFonts.inter(
                                  color: _sortByNewest ? Colors.white : context.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: context.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),

              // Optional Inline Error
              if (_inlineError != null)
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppColors.brandPink.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.brandPink,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _inlineError!,
                          style: GoogleFonts.inter(
                            color: AppColors.brandPink,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _inlineError = null),
                        child: Icon(
                          Icons.close,
                          color: context.textMuted,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),

              // Comment List
              Expanded(
                child: commentsAsync.when(
                  data: (comments) {
                    if (comments.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 36,
                              color: context.textMuted.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Be the first to comment!',
                              style: GoogleFonts.inter(
                                color: context.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final threaded = _threaded(comments, newest: _sortByNewest);
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 20),
                      itemCount: threaded.length,
                      itemBuilder: (context, index) {
                        final comment = threaded[index];
                        return _CommentTile(
                          key: ValueKey(comment.id),
                          comment: comment,
                          postAuthorId: widget.content.authorId,
                          isReply:
                              comment.replyToId != null &&
                              comment.replyToId!.isNotEmpty,
                          onReply: (username) => _startReply(comment, username),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: AnimatedLoadingIndicator(color: AppColors.brandBlue),
                  ),
                  error: (err, stack) => Center(
                    child: Text(
                      'Could not load comments',
                      style: GoogleFonts.inter(
                        color: AppColors.brandPink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),

              // Input Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  border: Border(
                    top: BorderSide(color: context.border, width: 1.0),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_replyToName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.reply_rounded,
                                size: 14,
                                color: context.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Replying to @$_replyToName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: context.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _cancelReply,
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: context.textMuted,
                                ),
                              ),
                            ],
                          ).animate().fadeIn(duration: 150.ms),
                        ),
                      if (_stagedGif != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    color: context.surfaceMid,
                                    child: Image.network(_stagedGif!.url, fit: BoxFit.cover, gaplessPlayback: true),
                                  ),
                                ),
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _stagedGif = null),
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black87),
                                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(duration: 150.ms),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SizedBox(
                          height: 28,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final e in _quickEmojis)
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _commentController.text += e;
                                    _commentController.selection = TextSelection.fromPosition(
                                      TextPosition(offset: _commentController.text.length),
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: context.surfaceMid,
                                      borderRadius: BorderRadius.circular(AppRadius.full),
                                      border: Border.all(color: context.border, width: 1.0),
                                    ),
                                    child: Text(e, style: const TextStyle(fontSize: 14)),
                                  ),
                                ),
                              Container(
                                width: 1,
                                height: 16,
                                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                color: context.border,
                              ),
                              for (final chip in _quickSuggestions)
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    if (_commentController.text.isEmpty) {
                                      _commentController.text = chip;
                                    } else {
                                      _commentController.text += ' $chip';
                                    }
                                    _commentController.selection = TextSelection.fromPosition(
                                      TextPosition(offset: _commentController.text.length),
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: context.surfaceMid,
                                      borderRadius: BorderRadius.circular(AppRadius.full),
                                      border: Border.all(color: context.border, width: 1.0),
                                    ),
                                    child: Center(
                                      child: Text(
                                        chip,
                                        style: GoogleFonts.inter(
                                          color: context.textPrimary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          // User Avatar
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: context.surfaceMid,
                            backgroundImage:
                                (currentUser?.photoURL != null &&
                                    currentUser!.photoURL!.isNotEmpty)
                                ? NetworkImage(currentUser.photoURL!)
                                : null,
                            child:
                                (currentUser?.photoURL == null ||
                                    currentUser!.photoURL!.isEmpty)
                                ? Icon(
                                    Icons.person,
                                    color: context.textSecondary,
                                    size: 18,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          // Input TextField Container
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: context.surfaceMid,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                border: Border.all(
                                  color: context.border,
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _commentController,
                                      focusNode: _focusNode,
                                      style: GoogleFonts.inter(
                                        color: context.textPrimary,
                                        fontSize: 13,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Add a comment...',
                                        hintStyle: GoogleFonts.inter(
                                          color: context.textMuted,
                                          fontSize: 13,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                      ),
                                      maxLines: null,
                                      textInputAction: TextInputAction.send,
                                      onSubmitted: (_) => _postComment(),
                                    ),
                                  ),
                                  OneovaVoiceTypingButton(
                                    controller: _commentController,
                                    onChanged: (_) => setState(() {}),
                                    iconSize: 20,
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    tooltip: 'Voice typing comment',
                                    showTranslateAction: true,
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _pickGif,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.gif_box_outlined,
                                        color: context.textSecondary,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Send Button
                          _isPosting
                              ? const SizedBox(
                                  width: 38,
                                  height: 38,
                                  child: Padding(
                                    padding: EdgeInsets.all(9),
                                    child: AnimatedLoadingIndicator(
                                      color: AppColors.brandBlue,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    Icons.send_rounded,
                                    color:
                                        (_commentController.text.trim().isNotEmpty || _stagedGif != null)
                                            ? AppColors.brandBlue
                                            : context.textMuted.withValues(
                                                alpha: 0.5,
                                              ),
                                    size: 22,
                                  ),
                                  onPressed:
                                      (_commentController.text.trim().isNotEmpty || _stagedGif != null)
                                          ? _postComment
                                          : null,
                                  splashRadius: 20,
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  final Comment comment;
  final String postAuthorId;
  final bool isReply;
  final void Function(String username)? onReply;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.postAuthorId,
    this.isReply = false,
    this.onReply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorAsync = ref.watch(_commentAuthorProvider(comment.authorId));
    final isCreator = comment.authorId == postAuthorId;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isLiked = currentUid != null && comment.likerIds.contains(currentUid);

    void navigateToProfile() {
      final uid = comment.authorId;
      if (uid.isNotEmpty) {
        context.push(uid == currentUid ? '/profile/me' : '/profile/$uid');
      }
    }

    final canDelete =
        currentUid != null &&
        (comment.authorId == currentUid || postAuthorId == currentUid);

    Future<void> confirmDelete() async {
      HapticFeedback.mediumImpact();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          title: Text(
            'Delete comment?',
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          content: Text(
            'This can\'t be undone.',
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: context.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Delete',
                style: GoogleFonts.inter(
                  color: AppColors.brandPink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref
            .read(commentServiceProvider)
            .deleteComment(
              postId: comment.postId,
              commentId: comment.id,
              userId: currentUid!,
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not delete: $e'),
              backgroundColor: AppColors.brandPink,
            ),
          );
        }
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: canDelete ? confirmDelete : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(isReply ? 58 : 16, 7, 16, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            GestureDetector(
              onTap: navigateToProfile,
              child: CircleAvatar(
                radius: isReply ? 13 : 17,
                backgroundColor: context.surfaceMid,
                backgroundImage: authorAsync.value?.profilePhotoUrl != null
                    ? NetworkImage(authorAsync.value!.profilePhotoUrl!)
                    : null,
                child: authorAsync.value?.profilePhotoUrl == null
                    ? Text(
                        authorAsync.value?.fullName.isNotEmpty == true
                            ? authorAsync.value!.fullName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 11),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: navigateToProfile,
                        child: Text(
                          authorAsync.value?.username ?? 'User',
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isCreator) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            'Creator',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      if (comment.isPinned) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.push_pin_rounded, color: Colors.amber, size: 9),
                              const SizedBox(width: 3),
                              Text(
                                'Pinned',
                                style: GoogleFonts.inter(
                                  color: Colors.amber,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        timeago.format(comment.createdAt, locale: 'en_short'),
                        style: GoogleFonts.inter(
                          color: context.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (comment.type == CommentType.voice && comment.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: VoiceCommentMiniCard(
                        url: comment.content,
                        seed: comment.id,
                        durationMs: comment.voiceDurationMs,
                      ),
                    )
                  else if (comment.content.isNotEmpty)
                    Text(
                      comment.content,
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  if (comment.gif != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          showDialog(
                            context: context,
                            builder: (ctx) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(16),
                              child: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(AppRadius.lg),
                                    child: InteractiveViewer(
                                      child: Image.network(comment.gif!.url, fit: BoxFit.contain),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                                    onPressed: () => Navigator.pop(ctx),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170, maxHeight: 200),
                          child: AspectRatio(
                            aspectRatio: comment.gif!.aspectRatio,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: ColoredBox(
                                color: context.surfaceMid,
                                child: Image.network(
                                  comment.gif!.url,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onReply?.call(authorAsync.value?.username ?? 'user');
                        },
                        child: Text(
                          'Reply',
                          style: GoogleFonts.inter(
                            color: context.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Like Button
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? AppColors.brandPink : context.textMuted,
                    size: 16,
                  ),
                  onPressed: () {
                    if (currentUid == null) {
                      AuthInteractionGate.requireAuth(
                        context,
                        actionTitle: 'Like this comment',
                      );
                      return;
                    }
                    HapticFeedback.lightImpact();
                    ref
                        .read(commentServiceProvider)
                        .reactToComment(
                          comment.postId,
                          comment.id,
                          userId: currentUid,
                          isLike: !isLiked,
                        );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                if (comment.reactionCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    comment.reactionCount.toString(),
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Global provider for comments stream
final commentsStreamProvider = StreamProvider.autoDispose
    .family<List<Comment>, String>((ref, postId) {
      return ref.watch(commentServiceProvider).watchComments(postId);
    });
