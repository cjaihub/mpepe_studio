import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import '../shared/audio/mic_coordinator.dart';
import 'services/reel_prefetcher.dart';

class FeedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double aspectRatio;
  final String? thumbnailUrl;
  final String? processingStatus;

  const FeedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.aspectRatio,
    this.thumbnailUrl,
    this.processingStatus,
  });

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  double _visibleFraction = 0.0;
  bool _appResumed = true;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: () => _onLifecycle(false),
      onInactive: () => _onLifecycle(false),
      onHide: () => _onLifecycle(false),
      onResume: () => _onLifecycle(true),
      onShow: () => _onLifecycle(true),
    );
    MicCoordinator.instance.owner.addListener(_syncPlayback);
    _initializePlayer();
  }

  void _onLifecycle(bool resumed) {
    _appResumed = resumed;
    _syncPlayback();
  }

  bool get _canPlay =>
      mounted &&
      _isInitialized &&
      _appResumed &&
      _visibleFraction > 0.7 &&
      MicCoordinator.instance.owner.value == null;

  void _syncPlayback() {
    final ctrl = _controller;
    if (ctrl == null || !_isInitialized) return;
    if (_canPlay) {
      ctrl.setVolume(1.0);
      if (!ctrl.value.isPlaying) {
        ctrl.play();
      }
    } else {
      ctrl.setVolume(0.0);
      if (ctrl.value.isPlaying) {
        ctrl.pause();
      }
    }
  }

  Future<void> _initializePlayer() async {
    try {
      if (widget.videoUrl.isEmpty) return;
      final cached = await ReelPrefetcher.videoCache.getFileFromCache(widget.videoUrl);
      VideoPlayerController ctrl;
      if (cached != null && await cached.file.exists() && await cached.file.length() > 0) {
        ctrl = VideoPlayerController.file(cached.file)..setLooping(true);
      } else {
        ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))..setLooping(true);
      }
      await ctrl.setVolume(0.0);
      await ctrl.initialize();
      if (mounted) {
        setState(() {
          _controller = ctrl;
          _isInitialized = true;
        });
        _syncPlayback();
      } else {
        await ctrl.dispose();
      }
    } catch (e) {
      // Network/format error: gracefully degrade to thumbnail placeholder.
      debugPrint('[FeedVideoPlayer] initialize error: $e');
    }
  }

  @override
  void deactivate() {
    _controller?.setVolume(0.0);
    _controller?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    MicCoordinator.instance.owner.removeListener(_syncPlayback);
    _lifecycle.dispose();
    _controller?.setVolume(0.0);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  void _handleVisibilityChanged(VisibilityInfo info) {
    _visibleFraction = info.visibleFraction;
    _syncPlayback();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: _handleVisibilityChanged,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Container(
          color: Colors.black, // Dark grey / black placeholder
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bottom layer: Thumbnail
              if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: widget.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: AnimatedLoadingIndicator(color: Colors.white54),
                  ),
                  errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                ),
              
              // Top layer: VideoPlayer
              if (_controller != null && _isInitialized)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _controller!,
                  builder: (context, VideoPlayerValue value, child) {
                    return AnimatedOpacity(
                      opacity: value.isInitialized && value.isPlaying ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: value.isInitialized ? VideoPlayer(_controller!) : const SizedBox.shrink(),
                    );
                  },
                ),

              // Overlay: Processing Status
              if (widget.processingStatus != null && widget.processingStatus != 'complete')
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedLoadingIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          'Optimizing media for high-performance playback...',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
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
