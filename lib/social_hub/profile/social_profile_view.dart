import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../backend/social/models/post.dart';
import '../../backend/social/profile_stats_provider.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/animated_loading_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/profile_highlights_row.dart';
// Note: You can connect to a PostService or SocialFeedService to fetch posts
// For now we will mock the grid or pass posts in.

class SocialProfileView extends ConsumerStatefulWidget {
  final AppUser user;
  final bool isCurrentUser;
  final bool isBlocked;
  final VoidCallback? onMoreTap;
  final String primaryActionText;
  final VoidCallback? onPrimaryActionTap;
  final String secondaryActionText;
  final VoidCallback? onSecondaryActionTap;

  const SocialProfileView({
    super.key,
    required this.user,
    this.isCurrentUser = false,
    this.isBlocked = false,
    this.onMoreTap,
    this.primaryActionText = 'Edit profile',
    this.onPrimaryActionTap,
    this.secondaryActionText = 'Share profile',
    this.onSecondaryActionTap,
  });

  @override
  ConsumerState<SocialProfileView> createState() => _SocialProfileViewState();
}

class _SocialProfileViewState extends ConsumerState<SocialProfileView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Videos, Locked/Private, Reposts, Saved, Liked
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Ova Guard warning for visitors: a name copying a verified account, or
  /// an unsafe link in the bio. Written by the server (guard/monitor.ts).
  Widget _buildSafetyNotice(BuildContext context, AppUser user) {
    final safety = user.safety;
    if (safety == null) return const SizedBox.shrink();
    final bio = safety['bio'] is Map ? Map<String, dynamic>.from(safety['bio'] as Map) : null;
    final String? text = safety['impersonationOf'] != null
        ? 'Not a verified account: this name looks like another, verified profile. Never send money or codes.'
        : (bio != null && bio['verdict'] != 'safe')
            ? 'Ova Guard: a link in this bio may be unsafe. ${(bio['reasons'] as List?)?.firstOrNull ?? ''}'
            : null;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.brandPink.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          const Icon(Icons.gpp_maybe_rounded, size: 18, color: AppColors.brandPink),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, height: 1.3, color: context.textPrimary))),
        ]),
      ),
    );
  }

  Widget _buildStatColumn(BuildContext context, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final stats = ref.watch(profileStatsProvider(user.id)).value;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.isCurrentUser
            ? IconButton(
                icon: Icon(Icons.person_add_outlined, color: context.textPrimary),
                onPressed: () {
                  // Add friend action
                },
              )
            : IconButton(
                icon: Icon(Icons.arrow_back, color: context.textPrimary),
                onPressed: () => context.pop(),
              ),
        title: Text(
          user.fullName,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: context.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(widget.isCurrentUser ? Icons.menu : Icons.more_vert, color: context.textPrimary),
            onPressed: widget.onMoreTap ?? () {},
          ),
        ],
      ),
      body: DefaultTabController(
        length: 5,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // Cover Photo & Avatar
                    Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        // Cover Photo
                        Container(
                          height: 120,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 48),
                          color: context.surfaceMid,
                          child: user.coverPhotoUrl != null
                              ? Image.network(user.coverPhotoUrl!, fit: BoxFit.cover)
                              : null,
                        ),
                        // Avatar
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: context.bg,
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor: context.surfaceMid,
                                backgroundImage: user.profilePhotoUrl != null 
                                  ? NetworkImage(user.profilePhotoUrl!) as ImageProvider
                                  : const AssetImage('assets/images/oneova_logo.jpg'),
                              ),
                            ),
                            if (widget.isCurrentUser)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.brandBlue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: context.bg, width: 2),
                                ),
                                child: const Icon(Icons.add, color: Colors.white, size: 16),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Username
                    Text(
                      '@${user.username ?? user.id.substring(0, 8)}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: context.textSecondary,
                      ),
                    ),
                    if ((user.category != null && user.category!.isNotEmpty) ||
                        (user.pronouns != null && user.pronouns!.isNotEmpty)) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (user.category != null && user.category!.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 0.8),
                              ),
                              child: Text(
                                user.category!.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (user.pronouns != null && user.pronouns!.isNotEmpty)
                            Text(
                              '(${user.pronouns})',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: context.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStatColumn(context, 'Following', formatProfileCount(stats?.following ?? 0)),
                        Container(height: 24, width: 1, color: context.border, margin: const EdgeInsets.symmetric(horizontal: 24)),
                        _buildStatColumn(context, 'Followers', formatProfileCount(stats?.followers ?? 0)),
                        Container(height: 24, width: 1, color: context.border, margin: const EdgeInsets.symmetric(horizontal: 24)),
                        _buildStatColumn(context, 'Likes', formatProfileCount(stats?.likes ?? 0)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          context,
                          text: widget.primaryActionText,
                          color: widget.isCurrentUser ? null : AppColors.brandBlue,
                          textColor: widget.isCurrentUser ? null : Colors.white,
                          onTap: widget.onPrimaryActionTap ?? () {},
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          context,
                          text: widget.secondaryActionText,
                          onTap: widget.onSecondaryActionTap ?? () {},
                        ),
                        if (!widget.isCurrentUser) ...[
                          const SizedBox(width: 8),
                          _buildIconButton(
                            context,
                            icon: Icons.expand_more,
                            onTap: widget.onMoreTap ?? () {},
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Bio
                    if (user.bio != null && user.bio!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          user.bio!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                    if (!widget.isCurrentUser) _buildSafetyNotice(context, user),
                    const SizedBox(height: 8),
                    // Business Action Buttons
                    if (user.accountType == 'business' && user.businessDetails != null) ...[
                      const SizedBox(height: 12),
                      _buildBusinessActions(context, user.businessDetails!),
                    ],

                    // External Links
                    if (user.links.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildLinksRow(context, user.links),
                    ],

                    // Story Highlights
                    const SizedBox(height: 12),
                    ProfileHighlightsRow(
                      userId: user.id,
                      isCurrentUser: widget.isCurrentUser,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.brandBlue,
                    labelColor: context.textPrimary,
                    unselectedLabelColor: context.textSecondary,
                    dividerColor: context.border,
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_view)),
                      Tab(icon: Icon(Icons.lock_outline)),
                      Tab(icon: Icon(Icons.repeat)),
                      Tab(icon: Icon(Icons.bookmark_outline)),
                      Tab(icon: Icon(Icons.favorite_border)),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: widget.isBlocked 
            ? _buildEmptyGrid(context, 'This user is blocked')
            : TabBarView(
            controller: _tabController,
            children: [
              _buildVideoGrid(),
              _buildLockedGrid(context),
              _buildEmptyGrid(context, 'No reposts yet'),
              _buildEmptyGrid(context, 'No saved content'),
              _buildEmptyGrid(context, 'No liked content'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, {required String text, required VoidCallback onTap, Color? color, Color? textColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: color ?? context.surfaceMid,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: textColor ?? context.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessActions(BuildContext context, Map<String, dynamic> biz) {
    final email = biz['email'] as String? ?? '';
    final phone = biz['phone'] as String? ?? '';
    final shopUrl = biz['shopUrl'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (email.isNotEmpty)
            _buildBizButton(context, icon: Icons.email_outlined, label: 'Email', onTap: () {
              launchUrl(Uri.parse('mailto:$email'));
            }),
          if (email.isNotEmpty && (phone.isNotEmpty || shopUrl.isNotEmpty)) const SizedBox(width: 8),
          if (phone.isNotEmpty)
            _buildBizButton(context, icon: Icons.phone_outlined, label: 'Call', onTap: () {
              launchUrl(Uri.parse('tel:$phone'));
            }),
          if (phone.isNotEmpty && shopUrl.isNotEmpty) const SizedBox(width: 8),
          if (shopUrl.isNotEmpty)
            _buildBizButton(context, icon: Icons.storefront_outlined, label: 'Shop', isPrimary: true, onTap: () {
              launchUrl(Uri.parse(shopUrl));
            }),
        ],
      ),
    );
  }

  Widget _buildBizButton(BuildContext context, {required IconData icon, required String label, bool isPrimary = false, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.brandPink : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: isPrimary ? AppColors.brandPink : context.border, width: 1.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isPrimary ? Colors.white : context.textPrimary),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isPrimary ? Colors.white : context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinksRow(BuildContext context, List<Map<String, String>> links) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: links.map((link) {
          final title = link['title'] ?? 'Link';
          final url = link['url'] ?? '';
          return InkWell(
            onTap: () {
              if (url.isNotEmpty) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_rounded, size: 14, color: AppColors.brandBlue),
                const SizedBox(width: 3),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandBlue,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIconButton(BuildContext context, {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          color: context.textPrimary,
          size: 18,
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  Widget _buildVideoGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .where('authorId', isEqualTo: widget.user.id)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: AnimatedLoadingIndicator());
        }
        if (snapshot.hasError) {
          return _buildEmptyGrid(context, 'Failed to load posts');
        }
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyGrid(context, 'No posts yet');
        }

        final items = docs.map((d) => Post.fromFirestore(d)).toList();

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
            return GestureDetector(
              onTap: () {
                context.push('/social/feed', extra: {'contentId': item.id, 'authorId': widget.user.id});
              },
              child: Container(
                color: context.surfaceMid,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.attachments.isNotEmpty)
                      Image.network(
                        item.attachments.first,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(color: context.surfaceMid),
                      ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_outlined, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _formatCount(item.viewCount),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                const Shadow(color: Colors.black54, blurRadius: 4)
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLockedGrid(BuildContext context) {
    return _buildEmptyGrid(context, 'Subscribe to unlock exclusive content');
  }

  Widget _buildEmptyGrid(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library_outlined, size: 48, color: context.textMuted),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: context.bg,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
