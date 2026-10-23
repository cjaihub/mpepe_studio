import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../backend/social/models/post.dart';
import '../../shared/theme/app_theme.dart';
import 'widgets/feed_reel_player.dart';
import 'widgets/social_engagement_overlay.dart';
import 'widgets/content_info_overlay.dart';
import 'widgets/story_tray.dart';

class SocialFeedScreen extends ConsumerStatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  ConsumerState<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends ConsumerState<SocialFeedScreen> {
  final PageController _pageController = PageController();
  bool _isForYou = true; // true = For You, false = Following
  // ignore: unused_field
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        children: [
          // 1. The immersive vertical PageView
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .orderBy('createdAt', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error loading feed: ${snapshot.error}', style: TextStyle(color: context.textPrimary)));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(child: Text('No posts found', style: TextStyle(color: context.textPrimary)));
              }

              final posts = docs.map((doc) => Post.fromFirestore(doc)).toList();

              return PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: posts.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  return _buildFeedItem(posts[index]);
                },
              );
            },
          ),
          
          // 2. Top Navigation (For You / Following) + Stories
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTopNavigation(),
                const SizedBox(height: 8),
                const StoryTray(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedItem(Post post) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Media (Video/Image)
        FeedReelPlayer(post: post),

        // Dark gradient at bottom for text readability
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Right-side Engagement Bar (Like, Comment, Share)
        Positioned(
          bottom: 20,
          right: 16,
          child: SocialEngagementOverlay(post: post),
        ),

        // Bottom-left Info (Username, Caption, Music)
        Positioned(
          bottom: 20,
          left: 16,
          right: 80, // Leave room for engagement bar
          child: ContentInfoOverlay(post: post),
        ),
      ],
    );
  }

  Widget _buildTopNavigation() {
    return Container(
      padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Icon (Search)
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            onPressed: () {
              context.push('/social_hub/search');
            },
          ),
          // Center Tabs
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTab(title: 'Following', isActive: !_isForYou, onTap: () => setState(() => _isForYou = false)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('|', style: GoogleFonts.inter(color: Colors.white24, fontSize: 16)),
              ),
              _buildTab(title: 'For You', isActive: _isForYou, onTap: () => setState(() => _isForYou = true)),
            ],
          ),
          // Right Icon (Create)
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Colors.white, size: 28),
            onPressed: () {
              // Navigate to the Creator Studio camera
              context.push('/upload/global');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTab({required String title, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          title,
          style: GoogleFonts.inter(
            color: isActive ? Colors.white : Colors.white54,
            fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
            fontSize: isActive ? 18 : 16,
            shadows: [
              if (isActive) 
                const Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))
            ],
          ),
        ),
      ),
    );
  }
}
