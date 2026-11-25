import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../backend/social/models/content.dart';
import '../../backend/social/services/recommendation_service.dart';
import '../../backend/social/services/video_playback_manager.dart';
import '../../shared/theme/app_theme.dart';

class ShortVideoFeedScreen extends ConsumerStatefulWidget {
  final FeedMode initialMode;

  const ShortVideoFeedScreen({super.key, this.initialMode = FeedMode.forYou});

  @override
  ConsumerState<ShortVideoFeedScreen> createState() => _ShortVideoFeedScreenState();
}

class _ShortVideoFeedScreenState extends ConsumerState<ShortVideoFeedScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  late final VideoPlaybackManager _manager;
  late final RecommendationService _recommendations;

  int _currentIndex = 0;
  late FeedMode _currentMode;
  final List<Content> _feed = [];
  final Set<String> _seenIds = {};
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    // Read providers once here: `ref` must not be used in dispose().
    _manager = ref.read(videoPlaybackManagerProvider);
    _recommendations = ref.read(recommendationServiceProvider);
    _currentMode = widget.initialMode;
    WidgetsBinding.instance.addObserver(this);
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoading = true);
    // Player setup (config, cache, network) runs alongside the feed query.
    final ready = _manager.ensureReady();
    final page = await _recommendations.getFeed(
      currentSocialUid(),
      _currentMode,
      limit: _manager.config.pageSize,
    );
    await ready;
    if (!mounted) return;
    setState(() {
      _feed
        ..clear()
        ..addAll(page);
      _seenIds
        ..clear()
        ..addAll(page.map((c) => c.id));
      _isLoading = false;
      _reachedEnd = page.isEmpty;
    });
    if (_feed.isNotEmpty) {
      _manager.initializeAndPreload(_feed, 0);
      _precachePosters(0);
    }
  }

  /// Next page, fetched while the user still has a few videos left.
  /// The recommendation service has no cursor yet, so this asks for a longer
  /// ranked list and keeps only videos not already shown.
  Future<void> _loadMore() async {
    if (_loadingMore || _reachedEnd) return;
    _loadingMore = true;
    try {
      final page = await _recommendations.getFeed(
        currentSocialUid(),
        _currentMode,
        limit: _feed.length + _manager.config.pageSize,
      );
      final fresh = page.where((c) => _seenIds.add(c.id)).toList();
      if (!mounted) return;
      setState(() {
        _feed.addAll(fresh);
        if (fresh.isEmpty) _reachedEnd = true;
      });
      // The window may now have a "next" video it did not have before.
      if (fresh.isNotEmpty) _manager.initializeAndPreload(_feed, _currentIndex);
    } finally {
      _loadingMore = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _manager.resumeCurrent();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _manager.pauseAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _manager.disposeAll();
    super.dispose();
  }

  /// Opens another screen over the feed: playback pauses while covered.
  Future<void> _openOver(String route) async {
    _manager.pauseAll();
    await context.push(route);
    if (!mounted) return;
    if (_feed.isEmpty) {
      await _loadFeed();
    } else {
      _manager.resumeCurrent();
    }
  }

  Widget _topBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.canPop() ? context.pop() : context.go('/social_hub'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Feed settings',
              icon: const Icon(Icons.tune, color: Colors.white),
              onPressed: () => _openOver('/social_hub/reels/controls'),
            ),
            IconButton(
              tooltip: 'Post a reel',
              icon: const Icon(Icons.add_box_outlined, color: Colors.white),
              onPressed: () => _openOver('/social_hub/reels/post'),
            ),
          ],
        ),
      ),
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _manager.initializeAndPreload(_feed, index);
    _precachePosters(index);
    if (_feed.length - index <= _manager.config.prefetchPageAt) _loadMore();
  }

  /// Posters for the next two videos, so even a cold swipe shows a sharp
  /// image at once.
  void _precachePosters(int index) {
    for (final c in _feed.skip(index + 1).take(2)) {
      final url = c.mediaMetadata.posterFrameUrl ?? c.mediaMetadata.thumbnailUrl;
      if (url != null) precacheImage(NetworkImage(url), context).ignore();
    }
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
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No reels yet', style: TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.mpepeMaroon),
                    onPressed: () => _openOver('/social_hub/reels/post'),
                    icon: const Icon(Icons.add),
                    label: const Text('Post the first one'),
                  ),
                ],
              ),
            ),
            _topBar(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: _feed.length,
            itemBuilder: (context, index) {
              final content = _feed[index];
              return _ShortVideoItem(
                key: ValueKey(content.id),
                content: content,
                manager: _manager,
                isActive: index == _currentIndex,
              );
            },
          ),
          _topBar(),
        ],
      ),
    );
  }
}

class _ShortVideoItem extends ConsumerStatefulWidget {
  final Content content;
  final VideoPlaybackManager manager;
  final bool isActive;

  const _ShortVideoItem({
    super.key,
    required this.content,
    required this.manager,
    required this.isActive,
  });

  @override
  ConsumerState<_ShortVideoItem> createState() => _ShortVideoItemState();
}

class _ShortVideoItemState extends ConsumerState<_ShortVideoItem> {
  Uint8List? _tinyPreview;

  @override
  void initState() {
    super.initState();
    final b64 = widget.content.mediaMetadata.tinyPreview;
    if (b64 != null) {
      try {
        _tinyPreview = base64Decode(b64);
      } catch (_) {}
    }
  }

  void _togglePlay() => widget.manager.togglePlayPause(widget.content.id);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlay,
      onDoubleTap: () {
        ref.read(recommendationServiceProvider).trackEvent(currentSocialUid(), widget.content.id,
            ContentInteractionType.like, {'source': 'double_tap'});
      },
      onLongPress: () => _showFeedControls(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Only the video layer listens to the manager, so overlays do not
          // rebuild on every playback change.
          ListenableBuilder(
            listenable: widget.manager,
            builder: (context, _) {
              final controller = widget.manager.getController(widget.content.id);
              final shown = widget.manager.isFirstFrameShown(widget.content.id);
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null)
                    Video(
                      key: ObjectKey(controller),
                      controller: controller,
                      fit: BoxFit.cover,
                      fill: Colors.black,
                      controls: NoVideoControls,
                    ),
                  // Preview stays on top until a real frame is playing, then
                  // fades out. No black flash, no spinner.
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: shown ? 0 : 1,
                      duration: const Duration(milliseconds: 160),
                      child: _buildPreview(),
                    ),
                  ),
                ],
              );
            },
          ),
          if (widget.isActive) _buildEngagementOverlay(),
          if (widget.isActive) _buildContentInfoOverlay(),
        ],
      ),
    );
  }

  /// Blurred tiny preview (inline in the Firestore doc, no download) with
  /// the sharp poster fading in over it once loaded.
  Widget _buildPreview() {
    final meta = widget.content.mediaMetadata;
    final poster = meta.posterFrameUrl ?? meta.thumbnailUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.darkSurface),
        if (_tinyPreview != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Image.memory(_tinyPreview!, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        if (poster != null)
          Image.network(
            poster,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSyncLoaded) {
              if (wasSyncLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: child,
              );
            },
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _buildEngagementOverlay() {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionButton(Icons.favorite, widget.content.likeCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent(currentSocialUid(), widget.content.id, ContentInteractionType.like, {});
          }),
          const SizedBox(height: 20),
          _buildActionButton(Icons.chat_bubble_outline, widget.content.commentCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent(currentSocialUid(), widget.content.id, ContentInteractionType.comment, {});
          }),
          const SizedBox(height: 20),
          _buildActionButton(Icons.bookmark_border, widget.content.saveCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent(currentSocialUid(), widget.content.id, ContentInteractionType.save, {});
          }),
          const SizedBox(height: 20),
          _buildActionButton(Icons.share, widget.content.shareCount.toString(), () {
            ref.read(recommendationServiceProvider).trackEvent(currentSocialUid(), widget.content.id, ContentInteractionType.share, {});
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
    final manager = widget.manager;
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
                  ref.read(recommendationServiceProvider).markNotInterested(currentSocialUid(), widget.content.id);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("We'll show fewer videos like this.")));
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_off, color: Colors.white),
                title: Text('Hide @${widget.content.authorId}', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(recommendationServiceProvider).hideCreator(currentSocialUid(), widget.content.authorId);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You won't see videos from @${widget.content.authorId}.")));
                },
              ),
              if (widget.content.hashtags.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.tag_faces, color: Colors.white), // Using tag_faces as proxy for topic hide
                  title: Text('Hide #${widget.content.hashtags.first}', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    ref.read(recommendationServiceProvider).hideTopic(currentSocialUid(), widget.content.hashtags.first);
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
                leading: Icon(manager.isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                title: Text(manager.isMuted ? 'Unmute' : 'Mute sound', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  final mute = !manager.isMuted;
                  manager.setMute(mute);
                  ref.read(recommendationServiceProvider).trackEvent(currentSocialUid(), widget.content.id,
                      ContentInteractionType.soundInteraction, {'volume': mute ? 0.0 : 100.0});
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag, color: Colors.white),
                title: const Text('Report', style: TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(recommendationServiceProvider).trackEvent(currentSocialUid(), widget.content.id, ContentInteractionType.report, {});
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
