import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/social/models/post.dart';
import '../../../backend/social/models/relationship.dart';
import '../../../backend/social/repositories/relationship_repository.dart';
import '../../../backend/user_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

// ─────────────────────────────────────────────────────────────
// Providers (file-scoped)
// ─────────────────────────────────────────────────────────────

final _overlayAuthorProvider =
    StreamProvider.family<AppUser?, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) =>
          (snap.exists && snap.data() != null)
              ? AppUser.fromMap(snap.data()!, snap.id)
              : null);
});

final _overlayRelationshipProvider =
    StreamProvider.family<Relationship?, String>((ref, targetUid) {
  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  if (currentUid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('relationships')
      .doc('${currentUid}_$targetUid')
      .snapshots()
      .map((s) => s.exists ? Relationship.fromFirestore(s) : null);
});

// ─────────────────────────────────────────────────────────────
// ContentInfoOverlay
// ─────────────────────────────────────────────────────────────

class ContentInfoOverlay extends ConsumerStatefulWidget {
  final Post post;
  const ContentInfoOverlay({super.key, required this.post});

  @override
  ConsumerState<ContentInfoOverlay> createState() => _ContentInfoOverlayState();
}

class _ContentInfoOverlayState extends ConsumerState<ContentInfoOverlay> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final authorAsync = ref.watch(_overlayAuthorProvider(widget.post.authorId));
    final relAsync = ref.watch(_overlayRelationshipProvider(widget.post.authorId));

    final author = authorAsync.asData?.value;
    final rel = relAsync.asData?.value;
    final isFollowing = rel?.status == RelationshipStatus.accepted;
    final isPending = rel?.status == RelationshipStatus.pending;
    final isSelf = currentUid == widget.post.authorId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Author row: avatar + name + follow ────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tappable avatar
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.push('/social/profile/${widget.post.authorId}');
              },
              child: _AuthorAvatar(author: author)
                  .animate()
                  .fadeIn(duration: 350.ms)
                  .scaleXY(begin: 0.85, duration: 300.ms, curve: Curves.easeOutBack),
            ),

            const SizedBox(width: 10),

            // Name + username (both tappable)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.push('/social/profile/${widget.post.authorId}');
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            author?.fullName.isNotEmpty == true
                                ? author!.fullName
                                : '@${widget.post.authorId}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (author?.isVerified == true) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, color: Colors.lightBlue, size: 15)
                              .animate().fadeIn(delay: 200.ms),
                        ],
                      ],
                    ),
                    if (author?.username != null && author!.username!.isNotEmpty)
                      Text(
                        '@${author.username}',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 10),

            // ── Inline Follow Button ──────────────────────────────
            if (!isSelf && currentUid != null)
              _InlineFollowButton(
                targetUserId: widget.post.authorId,
                currentUserId: currentUid,
                isFollowing: isFollowing,
                isPending: isPending,
              ).animate().fadeIn(delay: 150.ms, duration: 300.ms),
          ],
        ),

        const SizedBox(height: 10),

        // ── Caption (expandable) ──────────────────────────────────
        if (widget.post.content.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Text(
                widget.post.content,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 5, offset: Offset(0, 1)),
                  ],
                ),
                maxLines: _isExpanded ? null : 2,
                overflow: _isExpanded ? null : TextOverflow.ellipsis,
              ),
            ),
          ),

        const SizedBox(height: 8),

        // ── Hashtag chips ─────────────────────────────────────────
        if (widget.post.hashtags.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.post.hashtags.take(5).map((tag) {
                return _HashtagChip(tag: tag);
              }).toList(),
            ),
          ),

        const SizedBox(height: 10),

        // ── Audio Ticker ──────────────────────────────────────────
        _AudioTicker(
          musicId: widget.post.musicId,
          authorId: widget.post.authorId,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Author Avatar
// ─────────────────────────────────────────────────────────────

class _AuthorAvatar extends StatelessWidget {
  final AppUser? author;
  const _AuthorAvatar({required this.author});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        gradient: const LinearGradient(
          colors: [AppColors.brandBlue, AppColors.brandPink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: author?.profilePhotoUrl != null
            ? Image.network(
                author!.profilePhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    final initial = (author?.fullName.isNotEmpty == true)
        ? author!.fullName[0].toUpperCase()
        : (author?.username?.isNotEmpty == true
            ? author!.username![0].toUpperCase()
            : '?');
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 17,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Inline Follow Button — wired to RelationshipRepository
// ─────────────────────────────────────────────────────────────

class _InlineFollowButton extends ConsumerStatefulWidget {
  final String targetUserId;
  final String currentUserId;
  final bool isFollowing;
  final bool isPending;

  const _InlineFollowButton({
    required this.targetUserId,
    required this.currentUserId,
    required this.isFollowing,
    required this.isPending,
  });

  @override
  ConsumerState<_InlineFollowButton> createState() => _InlineFollowButtonState();
}

class _InlineFollowButtonState extends ConsumerState<_InlineFollowButton>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_loading) return;
    HapticFeedback.mediumImpact();
    await _pulseCtrl.reverse();
    await _pulseCtrl.forward();

    setState(() => _loading = true);
    try {
      final repo = ref.read(relationshipRepositoryProvider);
      if (widget.isFollowing) {
        await repo.unfollowUser(widget.currentUserId, widget.targetUserId);
      } else {
        await repo.followUser(widget.currentUserId, widget.targetUserId);
      }
    } catch (_) {
      // Silent fail
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isFollowing
        ? 'Following'
        : widget.isPending
            ? 'Requested'
            : 'Follow';
    final isActive = !widget.isFollowing && !widget.isPending;

    return ScaleTransition(
      scale: _pulseCtrl,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.brandBlue
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? AppColors.brandBlue : Colors.white38,
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: AnimatedLoadingIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isFollowing) ...[
                        const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.2,
                          shadows: const [Shadow(color: Colors.black38, blurRadius: 3)],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Hashtag Chip
// ─────────────────────────────────────────────────────────────

class _HashtagChip extends StatelessWidget {
  final String tag;
  const _HashtagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/social/explore/hashtag/$tag');
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
        ),
        child: Text(
          '#$tag',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Audio Ticker (spinning vinyl + scrolling text)
// ─────────────────────────────────────────────────────────────

class _AudioTicker extends StatefulWidget {
  final String? musicId;
  final String authorId;
  const _AudioTicker({this.musicId, required this.authorId});

  @override
  State<_AudioTicker> createState() => _AudioTickerState();
}

class _AudioTickerState extends State<_AudioTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotCtrl;

  @override
  void initState() {
    super.initState();
    _rotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackLabel = widget.musicId != null
        ? 'Track · ${widget.musicId}'
        : 'Original Audio · @${widget.authorId}';

    return GestureDetector(
      onTap: () {
        if (widget.musicId != null) {
          context.push('/social/sound/${widget.musicId}');
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _rotCtrl,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38, width: 1.5),
                color: const Color(0xFF1A1A1A),
              ),
              child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 13),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              trackLabel,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

