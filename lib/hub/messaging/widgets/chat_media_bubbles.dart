import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../shared/theme/app_theme.dart';

/// Muted, looping MP4 shown like a GIF. Plays only while visible so a long
/// chat doesn't decode dozens of videos at once.
class LoopingVideoGif extends StatefulWidget {
  final String url;
  final BoxFit fit;
  const LoopingVideoGif({super.key, required this.url, this.fit = BoxFit.cover});

  @override
  State<LoopingVideoGif> createState() => _LoopingVideoGifState();
}

class _LoopingVideoGifState extends State<LoopingVideoGif> {
  VideoPlayerController? _c;
  bool _visible = false;

  Future<void> _ensure() async {
    if (_c != null) return;
    final c = chatVideoController(widget.url);
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) return;
      if (_visible) await c.play();
      setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return VisibilityDetector(
      key: ValueKey('gif_${widget.url}_$hashCode'),
      onVisibilityChanged: (info) {
        _visible = info.visibleFraction > 0.3;
        if (_visible) {
          _ensure().then((_) => _c?.play());
        } else {
          _c?.pause();
        }
      },
      child: c != null && c.value.isInitialized
          ? FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            )
          : ColoredBox(
              color: context.surfaceMid,
              child: const Center(child: Icon(Icons.gif_box_rounded, color: AppColors.brandBlue)),
            ),
    );
  }
}

/// GIF message bubble: real .gif images or camera-made looping clips.
class GifBubble extends StatelessWidget {
  final String url;
  final bool isVideo;
  const GifBubble({super.key, required this.url, required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220, minWidth: 140, minHeight: 140),
        child: Stack(
          children: [
            Positioned.fill(
              child: isVideo
                  ? LoopingVideoGif(url: url)
                  : Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: context.surfaceMid)),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.brandBlack.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text('GIF',
                    style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: AppColors.brandWhite)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round "video message" bubble (WhatsApp / Telegram style). Loops muted
/// while visible; tap plays from the start with sound and a progress ring.
class VideoNoteBubble extends StatefulWidget {
  final String url;
  final String? duration;
  final double size;
  const VideoNoteBubble({super.key, required this.url, this.duration, this.size = 210});

  @override
  State<VideoNoteBubble> createState() => _VideoNoteBubbleState();
}

class _VideoNoteBubbleState extends State<VideoNoteBubble> {
  VideoPlayerController? _c;
  bool _withSound = false;
  bool _failed = false;

  Future<void> _ensure() async {
    if (_c != null) return;
    final c = chatVideoController(widget.url);
    _c = c;
    c.addListener(_tick);
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() {});
  }

  void _tick() {
    final c = _c;
    if (c == null || !mounted) return;
    // After one full play with sound, fall back to silent looping.
    if (_withSound && c.value.isInitialized && c.value.position >= c.value.duration - const Duration(milliseconds: 150)) {
      _withSound = false;
      c.setVolume(0);
    }
    setState(() {});
  }

  Future<void> _toggleSound() async {
    HapticFeedback.selectionClick();
    await _ensure();
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (_withSound && c.value.isPlaying) {
      await c.pause();
      return;
    }
    if (!_withSound) {
      _withSound = true;
      await c.seekTo(Duration.zero);
      await c.setVolume(1);
    }
    await c.play();
  }

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final progress = ready && _withSound && c.value.duration.inMilliseconds > 0
        ? c.value.position.inMilliseconds / c.value.duration.inMilliseconds
        : 0.0;
    return VisibilityDetector(
      key: ValueKey('vnote_${widget.url}_$hashCode'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.4) {
          _ensure().then((_) {
            if (mounted && !(_c?.value.isPlaying ?? true)) _c?.play();
          });
        } else if (!_withSound) {
          _c?.pause();
        }
      },
      child: GestureDetector(
        onTap: _toggleSound,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(
                child: SizedBox(
                  width: widget.size - 8,
                  height: widget.size - 8,
                  child: ready
                      ? FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: c.value.size.width,
                            height: c.value.size.height,
                            child: VideoPlayer(c),
                          ),
                        )
                      : ColoredBox(
                          color: context.surfaceMid,
                          child: Center(
                            child: _failed
                                ? Icon(Icons.videocam_off_rounded, color: context.textMuted)
                                : const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                                  ),
                          ),
                        ),
                ),
              ),
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  color: AppColors.brandPink,
                  backgroundColor: AppColors.brandBlue.withValues(alpha: 0.35),
                ),
              ),
              if (!_withSound)
                Positioned(
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlack.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.volume_off_rounded, size: 12, color: AppColors.brandWhite),
                        if (widget.duration != null) ...[
                          const SizedBox(width: 4),
                          Text(widget.duration!,
                              style: GoogleFonts.inter(
                                  fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brandWhite)),
                        ],
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

/// Inline player for regular video messages (tap to play/pause).
class ChatVideoBubble extends StatefulWidget {
  final String url;
  final String? title;
  const ChatVideoBubble({super.key, required this.url, this.title});

  @override
  State<ChatVideoBubble> createState() => _ChatVideoBubbleState();
}

class _ChatVideoBubbleState extends State<ChatVideoBubble> {
  VideoPlayerController? _c;
  bool _loading = false;

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (_c == null) {
      setState(() => _loading = true);
      final c = chatVideoController(widget.url);
      _c = c;
      c.addListener(() {
        if (mounted) setState(() {});
      });
      try {
        await c.initialize();
        await c.play();
      } catch (_) {}
      if (mounted) setState(() => _loading = false);
      return;
    }
    final c = _c!;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
      await c.play();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      onTap: _toggle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 250, minWidth: 180, minHeight: 140),
          color: AppColors.brandBlack,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (ready)
                AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
              if (!ready || !c.value.isPlaying)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
                  child: _loading
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite),
                        )
                      : const Icon(Icons.play_arrow_rounded, color: AppColors.brandWhite, size: 26),
                ),
              if (ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(playedColor: AppColors.brandPink),
                  ),
                ),
              if (!ready && widget.title != null)
                Positioned(
                  bottom: 10,
                  left: 12,
                  right: 12,
                  child: Text(widget.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.brandWhite)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Network URL or decrypted local file path -> video controller.
VideoPlayerController chatVideoController(String urlOrPath) => urlOrPath.startsWith('/')
    ? VideoPlayerController.file(File(urlOrPath))
    : VideoPlayerController.networkUrl(Uri.parse(urlOrPath));
