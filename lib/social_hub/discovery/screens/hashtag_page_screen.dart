import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/social/models/content.dart';
import '../../../backend/social/repositories/relationship_repository.dart';
import '../../../backend/user_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/animated_loading_indicator.dart';

/// Public reels tagged with the hashtag (hashtags are stored lower-case).
final _hashtagContentProvider = StreamProvider.autoDispose.family<List<Content>, String>((ref, tag) {
  return FirebaseFirestore.instance
      .collection('content')
      .where('hashtags', arrayContains: tag.toLowerCase())
      .limit(120)
      .snapshots()
      .map((snap) => snap.docs.map(Content.fromFirestore).where((c) => c.visibility == 'public').toList());
});

class HashtagPageScreen extends ConsumerStatefulWidget {
  final String hashtag;

  const HashtagPageScreen({super.key, required this.hashtag});

  @override
  ConsumerState<HashtagPageScreen> createState() => _HashtagPageScreenState();
}

class _HashtagPageScreenState extends ConsumerState<HashtagPageScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contentAsync = ref.watch(_hashtagContentProvider(widget.hashtag));

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('#${widget.hashtag}',
            style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: -0.3)),
        centerTitle: true,
      ),
      body: contentAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (e, _) => Center(child: Text('Could not load #${widget.hashtag}', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13))),
        data: (items) {
          final top = [...items]..sort((a, b) => b.viewCount.compareTo(a.viewCount));
          final latest = [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final creatorCounts = <String, int>{};
          for (final c in items) {
            creatorCounts[c.authorId] = (creatorCounts[c.authorId] ?? 0) + 1;
          }
          final creators = creatorCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final totalViews = items.fold<int>(0, (sum, c) => sum + c.viewCount);

          return NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _stat(_formatCompact(totalViews), 'Views'),
                          _divider(),
                          _stat(_formatCompact(items.length), 'Videos'),
                          _divider(),
                          _stat(_formatCompact(creators.length), 'Creators'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            context.push('/create/camera');
                          },
                          icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
                          label: Text('Create with #${widget.hashtag}',
                              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandBlue,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 250.ms),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.brandBlue,
                    unselectedLabelColor: context.textMuted,
                    indicatorColor: AppColors.brandBlue,
                    dividerColor: context.border,
                    labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                    tabs: const [Tab(text: 'Top', height: 40), Tab(text: 'Latest', height: 40), Tab(text: 'Creators', height: 40)],
                  ),
                  context.bg,
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildGrid(top),
                _buildGrid(latest),
                _buildCreatorsList(creators),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11.5)),
      ],
    );
  }

  Widget _divider() {
    return Container(height: 26, width: 1, color: context.border, margin: const EdgeInsets.symmetric(horizontal: 22));
  }

  Widget _empty(String text) {
    return Center(child: Text(text, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5)));
  }

  Widget _buildGrid(List<Content> items) {
    if (items.isEmpty) return _empty('No videos with #${widget.hashtag} yet');
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 9 / 16,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final thumb = item.mediaMetadata.thumbnailUrl;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            context.push('/hub/home?v=${item.id}');
          },
          child: Container(
            color: context.surfaceMid,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null && thumb.isNotEmpty)
                  Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
                else
                  Icon(Icons.play_circle_outline_rounded, color: context.textMuted, size: 26),
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Row(
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 13),
                      const SizedBox(width: 2),
                      Text(_formatCompact(item.viewCount),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreatorsList(List<MapEntry<String, int>> creators) {
    if (creators.isEmpty) return _empty('No creators yet');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: creators.length,
      itemBuilder: (context, index) => _CreatorRow(userId: creators[index].key, videoCount: creators[index].value),
    );
  }

  String _formatCompact(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }
}

class _CreatorRow extends ConsumerWidget {
  final String userId;
  final int videoCount;
  const _CreatorRow({required this.userId, required this.videoCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final repo = ref.read(relationshipRepositoryProvider);

    return FutureBuilder<AppUser?>(
      future: ref.read(userProvider.notifier).getUser(userId),
      builder: (context, snap) {
        final user = snap.data;
        final name = user?.fullName.isNotEmpty == true ? user!.fullName : (user?.username ?? 'Oneova creator');
        final photo = user?.profilePhotoUrl;
        return ListTile(
          dense: true,
          onTap: () => context.push(userId == currentUid ? '/profile/me' : '/profile/$userId'),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: context.surfaceMid,
            backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo == null || photo.isEmpty ? Icon(Icons.person, color: context.textMuted, size: 18) : null,
          ),
          title: Text(name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
          subtitle: Text('$videoCount video${videoCount == 1 ? '' : 's'} with this tag',
              style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11.5)),
          trailing: currentUid == null || currentUid == userId
              ? null
              : StreamBuilder<bool>(
                  stream: repo.watchIsFollowing(currentUid, userId),
                  builder: (context, followSnap) {
                    final following = followSnap.data ?? false;
                    return SizedBox(
                      height: 30,
                      child: OutlinedButton(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          following ? await repo.unfollowUser(currentUid, userId) : await repo.followUser(currentUid, userId);
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: following ? Colors.transparent : AppColors.brandBlue,
                          side: BorderSide(color: following ? context.border : AppColors.brandBlue, width: 1.0),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                        ),
                        child: Text(following ? 'Following' : 'Follow',
                            style: GoogleFonts.inter(
                                color: following ? context.textPrimary : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar, this._background);

  final TabBar _tabBar;
  final Color _background;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: _background, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => oldDelegate._background != _background;
}
