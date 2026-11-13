import 'package:oneova/shared/widgets/smooth_load.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../shared/widgets/follow_button.dart';
import 'package:share_plus/share_plus.dart';
import '../../backend/routing/oneova_share_engine.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/social/models/content.dart';
import '../../backend/social/models/relationship.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import '../../backend/user_service.dart';
import '../../backend/messaging_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/social/profile_stats_provider.dart';
import '../../auth/widgets/profile_completion_reminder_card.dart';
import '../../inbox/calling/call_launcher.dart';
import 'owner_profile_menu.dart';
import '../../settings/widgets/oneova_profile_qr_sheet.dart';
import '../../settings/widgets/oneova_about_account_sheet.dart';
import '../coins/coin_screens.dart';
import '../../identity/widgets/oneova_verified_badge.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

/// Streams the target user profile from Firestore by UID, so name, avatar,
/// bio and badges update live.
final _profileUserProvider =
    StreamProvider.autoDispose.family<AppUser?, String>((ref, uid) {
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots().map(
      (doc) => doc.exists && doc.data() != null ? AppUser.fromMap(doc.data()!, doc.id) : null);
});

/// Streams the relationship doc between currentUser and target.
final _relationshipProvider =
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

/// Streams public content for a given author UID ordered by newest first.
/// Streams the creator's published reels from `content` (where uploads land).
/// Others only see public items; the owner sees everything they posted.
final _userContentProvider =
    StreamProvider.family<List<Content>, String>((ref, authorId) {
  final isOwner = FirebaseAuth.instance.currentUser?.uid == authorId;
  return FirebaseFirestore.instance
      .collection('content')
      .where('authorId', isEqualTo: authorId)
      .limit(90)
      .snapshots()
      .map((snap) {
    final items = snap.docs
        .map(Content.fromFirestore)
        .where((c) => isOwner || c.visibility == 'public')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  });
});

Future<List<Content>> _resolveContent(Iterable<String> ids) async {
  final docs = await Future.wait(ids.map((id) => FirebaseFirestore.instance.collection('content').doc(id).get()));
  return docs.where((d) => d.exists).map(Content.fromFirestore).where((c) => c.visibility == 'public').toList();
}

/// Streams content the user has reposted.
final _userRepostsProvider =
    StreamProvider.family<List<Content>, String>((ref, userId) {
  return FirebaseFirestore.instance
      .collection('content_reposts')
      .where('userId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .asyncMap((snap) => _resolveContent(snap.docs.map((d) => d.data()['contentId'] as String)));
});

/// Streams the user's liked reels (one `users/{uid}/likes/{contentId}` doc per like).
final _userLikesProvider =
    StreamProvider.family<List<Content>, String>((ref, userId) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('likes')
      .limit(60)
      .snapshots()
      .asyncMap((snap) => _resolveContent(snap.docs.map((d) => d.id)));
});

// ─────────────────────────────────────────────────────────────────────────────
// Public Profile Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Full public-facing profile screen for any user.
///
/// Route: /social/profile/:uid
///
/// Data sources:
///   - User data: Firestore `users/{uid}` via [UserService.getUser]
///   - Relationship: streamed from `relationships/{currentUid_targetUid}`
///   - Content grid: streamed from `content` collection filtered by authorId
///   - Repost grid: streamed from `content_reposts` → resolved to `content`
///
/// No mock data — all counts and content from real Firestore state.
class PublicProfileScreen extends ConsumerStatefulWidget {
  final String targetUserId;

  const PublicProfileScreen({super.key, required this.targetUserId});

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _resolvedTargetUserId {
    return widget.targetUserId == 'current'
        ? _currentUid
        : widget.targetUserId;
  }

  bool get _isOwnProfile => _currentUid == _resolvedTargetUserId;

  // ── Follow / Unfollow ───────────────────────────────────────────────────

  // ── More Menu ───────────────────────────────────────────────────────────
  /// One report per reporter per account (deterministic ticket id).
  Future<void> _showReportDialog() async {
    const reasons = ['Spam', 'Harassment or bullying', 'Impersonation', 'Inappropriate content'];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Text('Report account', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        children: [
          for (final r in reasons)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Text(r, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13.5)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.textMuted, fontSize: 13.5)),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    HapticFeedback.mediumImpact();
    try {
      await FirebaseFirestore.instance
          .collection('moderation_tickets')
          .doc('${_currentUid}_user_$_resolvedTargetUserId')
          .set({
        'targetId': _resolvedTargetUserId,
        'targetType': 'user',
        'reportedByUserId': _currentUid,
        'flaggedCategories': [reason],
        'state': 'pendingAutomatedReview',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks. Our team will review this account.'), backgroundColor: AppColors.brandBlue),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send report: $e'), backgroundColor: AppColors.brandPink),
        );
      }
    }
  }

  void _showMoreMenu(BuildContext context, Relationship? rel) {

    final repo = ref.read(relationshipRepositoryProvider);
    final isBlocked = rel?.status == RelationshipStatus.blocked;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.share, color: context.textPrimary),
              title: Text('Share profile',
                  style: TextStyle(color: context.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                HapticFeedback.lightImpact();
                SharePlus.instance.share(ShareParams(
                  text: 'Check out this creator on Oneova\nhttps://${OneovaShareEngine.webDomain}/profile/$_resolvedTargetUserId',
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded, color: AppColors.brandBlue),
              title: Text('Profile QR Code',
                  style: TextStyle(color: context.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                final targetUser = ref.read(_profileUserProvider(_resolvedTargetUserId)).value;
                if (targetUser != null) {
                  OneovaProfileQrSheet.show(context, targetUser);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline_rounded, color: context.textPrimary),
              title: Text('About this account',
                  style: TextStyle(color: context.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                final targetUser = ref.read(_profileUserProvider(_resolvedTargetUserId)).value;
                if (targetUser != null) {
                  OneovaAboutAccountSheet.show(context, targetUser);
                }
              },
            ),
            if (!_isOwnProfile) ...[
              ListTile(
                leading: Icon(
                    rel?.isMuted == true
                        ? Icons.volume_up
                        : Icons.volume_off,
                    color: context.textPrimary),
                title: Text(
                    rel?.isMuted == true ? 'Unmute' : 'Mute',
                    style: TextStyle(color: context.textPrimary)),
                onTap: () async {
                  Navigator.pop(context);
                  if (rel?.isMuted == true) {
                    await repo.unmuteUser(_currentUid, _resolvedTargetUserId);
                  } else {
                    await repo.muteUser(_currentUid, _resolvedTargetUserId);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_off, color: AppColors.brandPink),
                title: Text(
                    isBlocked ? 'Unblock' : 'Block',
                    style: const TextStyle(color: AppColors.brandPink)),
                onTap: () async {
                  Navigator.pop(context);
                  // Confirmation dialog — mandatory per UI/UX guidelines
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: context.surface,
                      title: Text(
                          isBlocked ? 'Unblock user?' : 'Block user?',
                          style: TextStyle(
                              color: context.textPrimary,
                              fontWeight: FontWeight.w700)),
                      content: Text(
                          isBlocked
                              ? 'They will be able to see your content and contact you again.'
                              : 'They won\'t be able to find your profile or content.',
                          style:
                              TextStyle(color: context.textSecondary)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel',
                                style:
                                    TextStyle(color: context.textSecondary))),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(isBlocked ? 'Unblock' : 'Block',
                                style: const TextStyle(
                                    color: AppColors.brandBlue,
                                    fontWeight: FontWeight.w700))),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    if (isBlocked) {
                      await repo.unblockUser(_currentUid, _resolvedTargetUserId);
                    } else {
                      await repo.blockUser(_currentUid, _resolvedTargetUserId);
                    }
                  }
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.flag_outlined, color: AppColors.brandPink),
                title: const Text('Report',
                    style: TextStyle(color: AppColors.brandPink)),
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(_profileUserProvider(_resolvedTargetUserId));
    final relAsync = ref.watch(_relationshipProvider(_resolvedTargetUserId));
    final statsAsync = ref.watch(profileStatsProvider(_resolvedTargetUserId));
    final topBarBg = context.topBarBg;
    final topBarFg = context.topBarFg;

    return userAsync.smoothWhen(
      loading: () => Scaffold(
        backgroundColor: context.bg,
        body: const Center(
            child: AnimatedLoadingIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          backgroundColor: topBarBg,
          leading: IconButton(
              icon: Icon(Icons.arrow_back, color: topBarFg),
              onPressed: () {
                HapticFeedback.lightImpact();
                if (Navigator.of(context).canPop()) {
                  context.pop();
                } else {
                  context.go('/hub/home');
                }
              }),
        ),
        body: Center(
          child: Text('Failed to load profile: $e',
              style: TextStyle(color: context.textSecondary)),
        ),
      ),
      data: (user) {
        if (user == null) {
          return Scaffold(
            backgroundColor: context.bg,
            appBar: AppBar(
              backgroundColor: topBarBg,
              leading: IconButton(
                  icon: Icon(Icons.arrow_back, color: topBarFg),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (Navigator.of(context).canPop()) {
                      context.pop();
                    } else {
                      context.go('/hub/home');
                    }
                  }),
            ),
            body: Center(
                child: Text('User not found',
                    style: TextStyle(color: context.textSecondary))),
          );
        }

        final rel = relAsync.when(
          data: (r) => r,
          loading: () => null,
          error: (_, _) => null,
        );
        final isBlocked = rel?.status == RelationshipStatus.blocked;
        final isFollowing = rel?.status == RelationshipStatus.accepted;
        final isPending = rel?.status == RelationshipStatus.pending;
        final isPrivateLocked = !_isOwnProfile && (user.isPrivate == true) && !isFollowing;

        return Scaffold(
          backgroundColor: context.bg,
          body: DefaultTabController(
            length: 3,
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                // ── App Bar ──────────────────────────────────────────────
                SliverAppBar(
                  backgroundColor: topBarBg,
                  pinned: true,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back, color: topBarFg),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (Navigator.of(context).canPop()) {
                        context.pop();
                      } else {
                        context.go('/hub/home');
                      }
                    },
                  ),
                  title: Text(
                    '@${user.username ?? user.id.substring(0, 8)}',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: topBarFg),
                  ),
                  centerTitle: true,
                  actions: [
                    if (_isOwnProfile)
                      IconButton(
                        tooltip: 'Menu',
                        icon: Icon(Icons.menu_rounded, color: topBarFg),
                        onPressed: () => showOwnerProfileMenu(context, ref, uid: _resolvedTargetUserId),
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.more_vert, color: topBarFg),
                        onPressed: () => _showMoreMenu(context, rel),
                      ),
                  ],
                ),
                // ── Profile Header ───────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildProfileHeader(context, user, rel, statsAsync.value,
                      isBlocked: isBlocked,
                      isFollowing: isFollowing,
                      isPending: isPending),
                ),
                // ── Tab Bar ──────────────────────────────────────────────
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.brandBlue,
                      labelColor: context.textPrimary,
                      unselectedLabelColor: context.textSecondary,
                      dividerColor: context.border,
                      tabs: const [
                        Tab(icon: Icon(Icons.grid_view_rounded)),
                        Tab(icon: Icon(Icons.repeat_rounded)),
                        Tab(icon: Icon(Icons.favorite_border_rounded)),
                      ],
                    ),
                  ),
                ),
              ],
              // ── Content Tabs ─────────────────────────────────────────
              body: isBlocked
                  ? _buildBlocked(context)
                  : (isPrivateLocked
                      ? _buildPrivateLocked(context)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _ContentGrid(authorId: _resolvedTargetUserId),
                            _RepostGrid(userId: _resolvedTargetUserId),
                            _LikedGrid(userId: _resolvedTargetUserId, isOwnProfile: _isOwnProfile),
                          ],
                        )),
            ),
          ),
        );
      },
    );
  }

  // ── Profile Header ─────────────────────────────────────────────────────

  Widget _buildProfileHeader(
    BuildContext context,
    AppUser user,
    Relationship? rel,
    ProfileStats? stats, {
    required bool isBlocked,
    required bool isFollowing,
    required bool isPending,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Avatar + Cover
          Stack(
            alignment: Alignment.center,
            children: [
              // Cover strip
              if (user.coverPhotoUrl != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(user.coverPhotoUrl!,
                          fit: BoxFit.cover),
                    ),
                  ),
                ),
              // Avatar
              CircleAvatar(
                radius: 46,
                backgroundColor: context.bg,
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: context.surfaceMid,
                  backgroundImage: user.profilePhotoUrl != null
                      ? NetworkImage(user.profilePhotoUrl!) as ImageProvider
                      : const AssetImage('assets/images/oneova_logo.jpg'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Name + verified
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                user.fullName,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: context.textPrimary),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 6),
                user.businessLevel > 0
                    ? OneovaVerifiedBadge(kind: VerifiedKind.business, level: user.businessLevel, size: 18)
                    : const OneovaVerifiedBadge(size: 18),
              ],
              const SizedBox(width: 6),
              GifterLevelBadge(uid: _resolvedTargetUserId),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '@${user.username ?? user.id.substring(0, 8)}',
            style: GoogleFonts.inter(
                fontSize: 13, color: context.textSecondary),
          ),
          const SizedBox(height: 16),
          // Stats row — live Firestore streams (profileStatsProvider)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statColumn(context, formatProfileCount(stats?.posts ?? 0), 'Posts'),
              _divider(context),
              _statColumn(context, formatProfileCount(stats?.following ?? 0), 'Following'),
              _divider(context),
              _statColumn(context, formatProfileCount(stats?.followers ?? 0), 'Followers'),
              _divider(context),
              _statColumn(context, formatProfileCount(stats?.likes ?? 0), 'Likes'),
            ],
          ),
          const SizedBox(height: 16),
          // Action buttons
          if (!isBlocked)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isOwnProfile) ...[
                  FollowButton(
                    targetUserId: _resolvedTargetUserId,
                    targetName: user.fullName,
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    context,
                    label: 'Message',
                    filled: false,
                    compact: true,
                    onTap: () async {
                      final currentUid = FirebaseAuth.instance.currentUser?.uid;
                      if (currentUid != null && currentUid.isNotEmpty) {
                        try {
                          final chatId = await ref.read(messagingRepositoryProvider).getOrCreateDirectChat(currentUid, _resolvedTargetUserId);
                          if (context.mounted) {
                            context.push('/hub/messages/$chatId');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening chat: $e')));
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _iconAction(context,
                      icon: Icons.call_rounded,
                      tooltip: 'Voice call',
                      onTap: () => _call(isVideo: false)),
                  const SizedBox(width: 8),
                  _iconAction(context,
                      icon: Icons.videocam_rounded,
                      tooltip: 'Video call',
                      onTap: () => _call(isVideo: true)),
                  const SizedBox(width: 8),
                  _iconAction(context,
                      icon: Icons.card_giftcard_rounded,
                      tooltip: 'Send a gift',
                      onTap: () => UserGiftSheet.show(context, toUid: _resolvedTargetUserId, toName: user.fullName)),
                ] else ...[
                  _actionButton(
                    context,
                    label: 'Edit profile',
                    filled: false,
                    compact: true,
                    onTap: () => context.push('/settings/profile'),
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    context,
                    label: 'Earnings',
                    filled: true,
                    compact: true,
                    onTap: () => context.push('/profile/earnings'),
                  ),
                  const SizedBox(width: 8),
                  _iconAction(context,
                      icon: Icons.tune_rounded,
                      tooltip: 'Settings and tools',
                      onTap: () => showOwnerProfileMenu(context, ref, uid: _resolvedTargetUserId)),
                ],
              ],
            ),
          const SizedBox(height: 12),
          // Bio
          if (user.bio != null && user.bio!.isNotEmpty)
            Text(
              user.bio!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: context.textPrimary, height: 1.4),
            ),
          const SizedBox(height: 16),
          if (_isOwnProfile) const ProfileCompletionReminderCard(),
        ],
      ),
    );
  }

  Widget _statColumn(BuildContext context, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: context.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12, color: context.textSecondary)),
      ],
    );
  }

  Widget _divider(BuildContext context) => Container(
        height: 24,
        width: 1,
        color: context.border,
        margin: const EdgeInsets.symmetric(horizontal: 20),
      );

  /// Places a 1:1 call from the profile. Uses the direct chat (if any) so
  /// files shared during the call land with that conversation.
  Future<void> _call({required bool isVideo}) async {
    String? chatId;
    try {
      chatId = await ref
          .read(messagingRepositoryProvider)
          .getOrCreateDirectChat(_currentUid, _resolvedTargetUserId);
    } catch (_) {}
    if (!mounted) return;
    await startOneovaCall(
      context,
      ref,
      targetUserIds: [_resolvedTargetUserId],
      isVideo: isVideo,
      chatId: chatId,
    );
  }

  Widget _iconAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: SizedBox(
            width: 40,
            height: 38,
            child: Icon(icon, size: 19, color: context.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required bool filled,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            EdgeInsets.symmetric(horizontal: compact ? 18 : 28, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.brandBlue : context.surfaceMid,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: filled ? Colors.white : context.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildBlocked(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block_rounded, size: 48, color: context.textMuted),
          const SizedBox(height: 16),
          Text('This user is blocked',
              style: GoogleFonts.inter(color: context.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildPrivateLocked(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                shape: BoxShape.circle,
                border: Border.all(color: context.border, width: 1.2),
              ),
              child: Icon(Icons.lock_outline_rounded, size: 30, color: context.textPrimary),
            ),
            const SizedBox(height: 16),
            Text(
              'This Account is Private',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Follow this account to see their photos, reels, and stories.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: context.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }


}

// ─────────────────────────────────────────────────────────────────────────────
// Content grids — real Firestore data
// ─────────────────────────────────────────────────────────────────────────────

class _ContentGrid extends ConsumerWidget {
  final String authorId;
  const _ContentGrid({required this.authorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ContentTileGrid(
      async: ref.watch(_userContentProvider(authorId)),
      emptyIcon: Icons.video_library_outlined,
      emptyText: 'No videos yet',
    );
  }
}

class _RepostGrid extends ConsumerWidget {
  final String userId;
  const _RepostGrid({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ContentTileGrid(
      async: ref.watch(_userRepostsProvider(userId)),
      emptyIcon: Icons.repeat_rounded,
      emptyText: 'No reposts yet',
    );
  }
}

class _LikedGrid extends ConsumerWidget {
  final String userId;
  final bool isOwnProfile;
  const _LikedGrid({required this.userId, required this.isOwnProfile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOwnProfile) {
      return const _EmptyGrid(icon: Icons.lock_outline_rounded, text: 'Liked videos are private');
    }
    return _ContentTileGrid(
      async: ref.watch(_userLikesProvider(userId)),
      emptyIcon: Icons.favorite_border_rounded,
      emptyText: 'Videos you like appear here',
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyGrid({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: context.textMuted),
          const SizedBox(height: 10),
          Text(text, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13)),
        ],
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}

class _ContentTileGrid extends StatelessWidget {
  final AsyncValue<List<Content>> async;
  final IconData emptyIcon;
  final String emptyText;

  const _ContentTileGrid({required this.async, required this.emptyIcon, required this.emptyText});

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return async.smoothWhen(
      loading: () => const Center(child: AnimatedLoadingIndicator()),
      error: (e, _) => Center(
        child: Text('Failed to load', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13)),
      ),
      data: (items) {
        if (items.isEmpty) return _EmptyGrid(icon: emptyIcon, text: emptyText);
        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 9 / 16,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final thumb = item.mediaMetadata.thumbnailUrl;
            final isPhoto = item.type.name == 'photo';
            final imageUrl = (thumb != null && thumb.isNotEmpty) ? thumb : (isPhoto ? item.mediaUrl : null);
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                context.push('/post/${item.id}');
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(color: context.surfaceMid),
                    )
                  else
                    Container(
                      color: context.surfaceMid,
                      child: Icon(Icons.play_circle_outline_rounded, color: context.textMuted, size: 26),
                    ),
                  if (item.visibility != 'public')
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.lock_rounded, color: Colors.white, size: 13, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                    ),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 2),
                        Text(
                          _formatCount(item.viewCount),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 200.ms, delay: (index.clamp(0, 12) * 20).ms);
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Bar Delegate
// ─────────────────────────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  const _TabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: context.bg, child: _tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate old) => false;
}
