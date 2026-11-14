import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/social/models/content.dart';
import '../../../backend/social/profile_stats_provider.dart';
import '../../../backend/social/models/relationship.dart';
import '../../../backend/social/repositories/relationship_repository.dart';
import '../../../backend/user_service.dart';
import '../../../backend/messaging_repository.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import '../../../shared/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────

/// Live-streams the author profile doc from Firestore.
final _authorProfileProvider =
    StreamProvider.family<AppUser?, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) {
        if (!snap.exists || snap.data() == null) return null;
        return AppUser.fromMap(snap.data()!, snap.id);
      });
});

/// Streams the relationship status between current user and author.
final _feedRelationshipProvider =
    StreamProvider.family<Relationship?, String>((ref, targetUid) {
  final currentUid = FirebaseAuth.instance.currentUser?.uid;
  if (currentUid == null) return Stream.value(null);
  final relId = '${currentUid}_$targetUid';
  return FirebaseFirestore.instance
      .collection('relationships')
      .doc(relId)
      .snapshots()
      .map((s) => s.exists ? Relationship.fromFirestore(s) : null);
});

/// Live-streams the public content count for the author.
final _authorContentCountProvider =
    StreamProvider.family<int, String>((ref, authorId) {
  return FirebaseFirestore.instance
      .collection('content')
      .where('authorId', isEqualTo: authorId)
      .where('visibility', isEqualTo: 'public')
      .snapshots()
      .map((snap) => snap.size);
});

// ─────────────────────────────────────────────────────────────
// Panel Brand Color
// ─────────────────────────────────────────────────────────────
const _kPanelBlue = AppColors.brandBlue;     // Deep brand sapphire blue #0C4FA8
const _kPanelBlueDim = Color(0xFF093E85);  // Darker shade
const _kPanelBlueSoft = Color(0xFF062C5F); // Deep for gradients

// ─────────────────────────────────────────────────────────────
// AuthorSidePanel
// ─────────────────────────────────────────────────────────────

class AuthorSidePanel extends ConsumerStatefulWidget {
  final Content content;
  final VoidCallback onClose;

  const AuthorSidePanel({
    super.key,
    required this.content,
    required this.onClose,
  });

  @override
  ConsumerState<AuthorSidePanel> createState() => _AuthorSidePanelState();
}

class _AuthorSidePanelState extends ConsumerState<AuthorSidePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(-1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _closePanel() async {
    await _animCtrl.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final panelW = screenW * 0.72; // 72% on mobile feels like ~25% of viewport

    final authorAsync = ref.watch(_authorProfileProvider(widget.content.authorId));
    final relAsync = ref.watch(_feedRelationshipProvider(widget.content.authorId));
    final contentCountAsync = ref.watch(_authorContentCountProvider(widget.content.authorId));

    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Stack(
      children: [
        // Dim backdrop
        FadeTransition(
          opacity: _fadeAnim,
          child: GestureDetector(
            onTap: _closePanel,
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),

        // Side panel
        Align(
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: _slideAnim,
            child: SizedBox(
              width: panelW,
              height: double.infinity,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.surface,
                    border: Border(
                      right: BorderSide(color: context.border, width: 1.5),
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        // ── Author card at top ──────────────────────────
                        _AuthorTopCard(
                          content: widget.content,
                          authorAsync: authorAsync,
                          relAsync: relAsync,
                          contentCountAsync: contentCountAsync,
                          currentUid: currentUid,
                          onClose: _closePanel,
                          onNavigate: (path) {
                            _closePanel();
                            context.push(path);
                          },
                        ),

                        const SizedBox(height: 8),
                        Divider(
                          color: context.border,
                          height: 1,
                          thickness: 1,
                        ),
                        const SizedBox(height: 8),

                        // ── Navigation actions ──────────────────────────
                        Expanded(
                          child: _NavActionsList(
                            content: widget.content,
                            onNavigate: (path) {
                              _closePanel();
                              context.push(path);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Author Top Card
// ─────────────────────────────────────────────────────────────

class _AuthorTopCard extends ConsumerWidget {
  final Content content;
  final AsyncValue<AppUser?> authorAsync;
  final AsyncValue<Relationship?> relAsync;
  final AsyncValue<int> contentCountAsync;
  final String? currentUid;
  final VoidCallback onClose;
  final void Function(String path) onNavigate;

  const _AuthorTopCard({
    required this.content,
    required this.authorAsync,
    required this.relAsync,
    required this.contentCountAsync,
    required this.currentUid,
    required this.onClose,
    required this.onNavigate,
  });

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = authorAsync.asData?.value;
    final rel = relAsync.asData?.value;
    final stats = ref.watch(profileStatsProvider(content.authorId)).value;
    final contentCount = stats?.posts ?? contentCountAsync.asData?.value ?? 0;

    final isFollowing = rel?.status == RelationshipStatus.accepted;
    final isPending = rel?.status == RelationshipStatus.pending;

    return GestureDetector(
      onTap: () => onNavigate('/social/profile/${content.authorId}'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kPanelBlueDim, _kPanelBlueSoft, Color(0xFF0F172A)],
            stops: [0.0, 0.5, 1.0],
          ),
          border: Border.all(color: _kPanelBlue.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _kPanelBlue.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar + name row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                _buildAvatar(author),
                const SizedBox(width: 10),
                // Name / username / bio
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              author?.fullName ?? '@${content.authorId}',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (author?.isVerified == true) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              color: Colors.lightBlue,
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@${author?.username ?? content.authorId}',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                      if (author?.bio != null && author!.bio!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          author.bio!,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Live stat counters — all tappable
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatChip(
                  label: 'Followers',
                  value: _formatCount(stats?.followers ?? 0),
                  icon: Icons.people_alt_rounded,
                  onTap: () => onNavigate('/social/profile/${content.authorId}'),
                ),
                _StatDivider(),
                _StatChip(
                  label: 'Likes',
                  value: _formatCount(stats?.likes ?? 0),
                  icon: Icons.favorite_rounded,
                  onTap: () => onNavigate('/social/profile/${content.authorId}'),
                ),
                _StatDivider(),
                _StatChip(
                  label: 'Videos',
                  value: _formatCount(contentCount),
                  icon: Icons.play_circle_rounded,
                  onTap: () => onNavigate('/social/profile/${content.authorId}'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Follow / Following button + Message button
            if (currentUid != null && currentUid != content.authorId)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: _FollowButton(
                        targetUserId: content.authorId,
                        currentUserId: currentUid!,
                        isFollowing: isFollowing,
                        isPending: isPending,
                        ref: ref,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () async {
                          try {
                            final chatId = await ref.read(messagingRepositoryProvider).getOrCreateDirectChat(currentUid!, content.authorId);
                            if (context.mounted) {
                              context.push('/hub/messages/$chatId');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error starting chat: $e')));
                            }
                          }
                        },
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text('Message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(AppUser? author) {
    return Stack(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            gradient: const LinearGradient(
              colors: [_kPanelBlue, _kPanelBlueSoft],
            ),
          ),
          child: ClipOval(
            child: author?.profilePhotoUrl != null
                ? Image.network(
                    author!.profilePhotoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => _avatarFallback(author),
                  )
                : _avatarFallback(author),
          ),
        ),
        // Online indicator
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF0A0A0A), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatarFallback(AppUser? author) {
    final initials = (author?.fullName.isNotEmpty == true)
        ? author!.fullName.substring(0, 1).toUpperCase()
        : (content.authorId.isNotEmpty ? content.authorId[0].toUpperCase() : '?');
    return Center(
      child: Text(
        initials,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stat Chip
// ─────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withValues(alpha: 0.15),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Follow Button (live backend wired)
// ─────────────────────────────────────────────────────────────

class _FollowButton extends StatefulWidget {
  final String targetUserId;
  final String currentUserId;
  final bool isFollowing;
  final bool isPending;
  final WidgetRef ref;

  const _FollowButton({
    required this.targetUserId,
    required this.currentUserId,
    required this.isFollowing,
    required this.isPending,
    required this.ref,
  });

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.93,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _scaleCtrl;
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_loading) return;
    HapticFeedback.mediumImpact();
    await _scaleCtrl.reverse();
    await _scaleCtrl.forward();

    setState(() => _loading = true);
    try {
      final repo = widget.ref.read(relationshipRepositoryProvider);
      if (widget.isFollowing) {
        await repo.unfollowUser(widget.currentUserId, widget.targetUserId);
      } else {
        await repo.followUser(widget.currentUserId, widget.targetUserId);
      }
    } catch (_) {
      // Silently fail — snackbar could be added here
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

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isFollowing
                ? Colors.white.withValues(alpha: 0.08)
                : _kPanelBlue,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isFollowing ? Colors.white24 : _kPanelBlue,
              width: 1.5,
            ),
          ),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: AnimatedLoadingIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Navigation Actions List
// ─────────────────────────────────────────────────────────────

class _NavActionsList extends StatelessWidget {
  final Content content;
  final void Function(String path) onNavigate;

  const _NavActionsList({required this.content, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final actions = _buildActionItems(context, content);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final item = actions[index];
        if (item is _NavDivider) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Text(
              item.label,
              style: GoogleFonts.inter(
                color: _kPanelBlue.withValues(alpha: 0.8),
                fontWeight: FontWeight.w900,
                fontSize: 9,
                letterSpacing: 1.2,
              ),
            ),
          );
        }
        if (item is _NavItem) {
          return _NavTile(item: item, onTap: () => onNavigate(item.route));
        }
        return const SizedBox.shrink();
      },
    );
  }

  List<Object> _buildActionItems(BuildContext context, Content content) => [
        const _NavDivider('CREATOR'),
        _NavItem(Icons.analytics_rounded, 'Analytics', '/creator/insights', _kPanelBlue),
        _NavItem(Icons.video_library, 'My Videos', '/profile/me', _kPanelBlue),
        _NavItem(Icons.star_rate_rounded, 'Monetization', '/profile/monetization', const Color(0xFFD4AF37)),
        _NavItem(Icons.trending_up_rounded, 'Video Insights', '/creator/insights/clip/${content.id}', _kPanelBlue),
        const _NavDivider('SOCIAL'),
        _NavItem(Icons.notifications_active_rounded, 'Interactions', '/notifications', const Color(0xFF22C55E)),
        _NavItem(Icons.hub_rounded, 'Social Accounts', '/social_hub', _kPanelBlue),
        const _NavDivider('CONTENT'),
        _NavItem(Icons.movie_edit, 'Studio', '/create/studio', _kPanelBlue),
        _NavItem(Icons.add_circle_rounded, 'Create', '/upload/global', _kPanelBlue),
        _NavItem(Icons.bookmark_rounded, 'Saved', '/social/profile/${content.authorId}', _kPanelBlue),
        const _NavDivider('SETTINGS'),
        _NavItem(Icons.settings_rounded, 'Settings', '/settings/main', context.textSecondary),
        _NavItem(Icons.privacy_tip_rounded, 'Privacy', '/settings/privacy', context.textSecondary),
      ];
}

class _NavDivider {
  final String label;
  const _NavDivider(this.label);
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  final Color color;
  const _NavItem(this.icon, this.label, this.route, this.color);
}

class _NavTile extends StatefulWidget {
  final _NavItem item;
  final VoidCallback onTap;
  const _NavTile({required this.item, required this.onTap});

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _pressed
              ? _kPanelBlue.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: widget.item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: widget.item.color.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Icon(
                widget.item.icon,
                color: widget.item.color,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.item.label,
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
