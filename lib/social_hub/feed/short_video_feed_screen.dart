import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../backend/social/models/content.dart';
import '../../../backend/social/services/video_playback_manager.dart';
import '../../../backend/social/services/recommendation_service.dart';
import '../../../shared/design_system/app_colors.dart';

class ShortVideoFeedScreen extends ConsumerStatefulWidget {
  final FeedMode initialMode;

  const ShortVideoFeedScreen({super.key, this.initialMode = FeedMode.forYou});

  @override
  ConsumerState<ShortVideoFeedScreen> createState() => _ShortVideoFeedScreenState();
}

class _ShortVideoFeedScreenState extends ConsumerState<ShortVideoFeedScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  
  FeedMode _currentMode = FeedMode.forYou;
  List<Content> _feed = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _pageController = PageController(initialPage: 0);
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoading = true);
    final recommendations = await ref.read(recommendationServiceProvider).getFeed('currentUser', _currentMode);
    
    if (mounted) {
      setState(() {
        _feed = recommendations;
        _isLoading = false;
      });
      if (_feed.isNotEmpty) {
        ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, 0);
      }
    }
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
    ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, index);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: CircularProgressIndicator(color: AppColors.mpepeMaroon)),
      );
    }

    if (_feed.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: Text('No content available', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _feed.length,
        itemBuilder: (context, index) {
          final content = _feed[index];
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
        ref.read(recommendationServiceProvider).trackEvent('currentUser', widget.content.id, ContentInteractionType.like, {'source': 'double_tap'});
      },
      onLongPress: () => _showFeedControls(context),
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
          _buildActionButton(Icons.favorite, widget.content.likeCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent('currentUser', widget.content.id, ContentInteractionType.like, {});
          }),
          const SizedBox(height: 20),
          _buildActionButton(Icons.chat_bubble_outline, widget.content.commentCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent('currentUser', widget.content.id, ContentInteractionType.comment, {});
          }),
          const SizedBox(height: 20),
          _buildActionButton(Icons.bookmark_border, widget.content.saveCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent('currentUser', widget.content.id, ContentInteractionType.save, {});
          }),
          const SizedBox(height: 20),
          _buildActionButton(Icons.share, widget.content.shareCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent('currentUser', widget.content.id, ContentInteractionType.share, {});
          }),
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

  void _showFeedControls(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off, color: Colors.white),
                title: const Text('Not Interested', style: TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(recommendationServiceProvider).markNotInterested('currentUser', widget.content.id);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("We'll show fewer videos like this.")));
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_off, color: Colors.white),
                title: Text('Hide @${widget.content.authorId}', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(recommendationServiceProvider).hideCreator('currentUser', widget.content.authorId);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You won't see videos from @${widget.content.authorId}.")));
                },
              ),
              if (widget.content.hashtags.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.tag_faces, color: Colors.white), // Using tag_faces as proxy for topic hide
                  title: Text('Hide #${widget.content.hashtags.first}', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    ref.read(recommendationServiceProvider).hideTopic('currentUser', widget.content.hashtags.first);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You won't see videos about #${widget.content.hashtags.first}.")));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.white),
                title: const Text('Why am I seeing this?', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final explanation = await ref.read(recommendationServiceProvider).getWhyAmISeeingThis(widget.content.id);
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: AppColors.darkSurface,
                        title: const Text('About this video', style: TextStyle(color: Colors.white)),
                        content: Text(explanation['reason'], style: const TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close', style: TextStyle(color: AppColors.mpepeMaroon)))
                        ],
                      )
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon((ref.watch(videoPlaybackManagerProvider).getController(widget.content.id)?.player.state.volume ?? 100) == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                title: Text((ref.watch(videoPlaybackManagerProvider).getController(widget.content.id)?.player.state.volume ?? 100) == 0 ? 'Unmute' : 'Mute sound', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  final player = ref.read(videoPlaybackManagerProvider).getController(widget.content.id)?.player;
                  if (player != null) {
                    final newVolume = player.state.volume == 0 ? 100.0 : 0.0;
                    player.setVolume(newVolume);
                    ref.read(recommendationServiceProvider).trackEvent('currentUser', widget.content.id, ContentInteractionType.soundInteraction, {'volume': newVolume});
                  }
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag, color: Colors.white),
                title: const Text('Report', style: TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(recommendationServiceProvider).trackEvent('currentUser', widget.content.id, ContentInteractionType.report, {});
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report submitted.")));
                },
              ),
            ],
          ),
        );
      }
    );
  }
}
