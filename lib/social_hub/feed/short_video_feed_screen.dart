import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../backend/social/models/content.dart';
import '../../../backend/social/services/video_playback_manager.dart';
import '../../../shared/design_system/app_colors.dart';

class ShortVideoFeedScreen extends ConsumerStatefulWidget {
  final List<Content> feed;

  const ShortVideoFeedScreen({super.key, required this.feed});

  @override
  ConsumerState<ShortVideoFeedScreen> createState() => _ShortVideoFeedScreenState();
}

class _ShortVideoFeedScreenState extends ConsumerState<ShortVideoFeedScreen> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    // Initialize playback manager for the first time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoPlaybackManagerProvider).initializeAndPreload(widget.feed, 0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    // In a real app we might not dispose all if navigating away but keeping in stack.
    // We'll dispose for safety here.
    ref.read(videoPlaybackManagerProvider).disposeAll();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    ref.read(videoPlaybackManagerProvider).initializeAndPreload(widget.feed, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: widget.feed.length,
        itemBuilder: (context, index) {
          final content = widget.feed[index];
          return _ShortVideoItem(
            content: content,
            isActive: index == _currentIndex,
          );
        },
      ),
    );
  }
}

class _ShortVideoItem extends ConsumerStatefulWidget {
  final Content content;
  final bool isActive;

  const _ShortVideoItem({required this.content, required this.isActive});

  @override
  ConsumerState<_ShortVideoItem> createState() => _ShortVideoItemState();
}

class _ShortVideoItemState extends ConsumerState<_ShortVideoItem> {
  bool _isMuted = false;

  void _togglePlay() {
    ref.read(videoPlaybackManagerProvider).togglePlayPause(widget.content.id);
  }

  @override
  Widget build(BuildContext context) {
    final playbackManager = ref.watch(videoPlaybackManagerProvider);
    final controller = playbackManager.getController(widget.content.id);

    return GestureDetector(
      onTap: _togglePlay,
      onDoubleTap: () {
        // Implement double tap to like
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video Player
          if (controller != null)
            Video(
              controller: controller,
              fit: BoxFit.cover,
              controls: NoVideoControls, // custom controls via overlay
            )
          else
            // Placeholder/Thumbnail while preloading
            _buildThumbnail(),

          // Overlays
          if (widget.isActive) _buildEngagementOverlay(),
          if (widget.isActive) _buildContentInfoOverlay(),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (widget.content.mediaMetadata.thumbnailUrl != null) {
      return Image.network(
        widget.content.mediaMetadata.thumbnailUrl!,
        fit: BoxFit.cover,
      );
    }
    return Container(color: AppColors.darkSurface);
  }

  Widget _buildEngagementOverlay() {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionButton(Icons.favorite, widget.content.likeCount.toString(), () {}),
          const SizedBox(height: 20),
          _buildActionButton(Icons.chat_bubble_outline, widget.content.commentCount.toString(), () {}),
          const SizedBox(height: 20),
          _buildActionButton(Icons.bookmark_border, widget.content.saveCount.toString(), () {}),
          const SizedBox(height: 20),
          _buildActionButton(Icons.share, widget.content.shareCount.toString(), () {}),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white, size: 32),
          onPressed: onTap,
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        )
      ],
    );
  }

  Widget _buildContentInfoOverlay() {
    return Positioned(
      left: 16,
      bottom: 40,
      right: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '@${widget.content.authorId}', // In a real app, resolve to username
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            widget.content.description,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.content.mediaMetadata.musicId != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.music_note, color: Colors.white, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Original Audio - Track ${widget.content.mediaMetadata.musicId}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }
}
