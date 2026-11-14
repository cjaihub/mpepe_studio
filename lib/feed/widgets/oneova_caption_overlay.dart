import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import '../../backend/social/models/content.dart';
import '../../backend/social/services/video_playback_manager.dart';
import '../models/video_transcript_model.dart';
import '../services/oneova_transcription_service.dart';
import 'oneova_transcript_sheet.dart';
import '../services/reel_translation_service.dart';

/// Realtime floating Closed Caption (CC) overlay widget.
///
/// Synchronizes timed subtitle lines with the active media_kit [Player],
/// honors user CC visibility preferences, and opens the interactive
/// transcript sheet upon tap.
class OneovaCaptionOverlay extends ConsumerStatefulWidget {
  final Content content;

  const OneovaCaptionOverlay({
    super.key,
    required this.content,
  });

  @override
  ConsumerState<OneovaCaptionOverlay> createState() => _OneovaCaptionOverlayState();
}

class _OneovaCaptionOverlayState extends ConsumerState<OneovaCaptionOverlay> {
  VideoTranscript? _transcript;
  CaptionSegment? _currentSegment;
  StreamSubscription<Duration>? _posSub;
  Duration _currentPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadTranscript();
    _attachPlayer();
  }

  @override
  void didUpdateWidget(covariant OneovaCaptionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content.id != oldWidget.content.id) {
      _posSub?.cancel();
      _loadTranscript();
      _attachPlayer();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  void _loadTranscript() {
    ref.read(oneovaTranscriptionServiceProvider).getTranscript(
          widget.content.id,
          mediaUrl: widget.content.mediaUrl,
          fallbackText: widget.content.description,
          duration: widget.content.mediaMetadata.duration,
        ).then((t) {
      if (mounted && t != null) {
        setState(() {
          _transcript = t;
          _updateSegment(_currentPosition.inMilliseconds);
        });
      }
    });
  }

  void _attachPlayer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final player = ref.read(videoPlaybackManagerProvider).getPlayer(widget.content.id);
      if (player != null) {
        _posSub?.cancel();
        _posSub = player.stream.position.listen((pos) {
          if (!mounted) return;
          _currentPosition = pos;
          _updateSegment(pos.inMilliseconds);
        });
      }
    });
  }

  String? _translatedShown;

  void _updateSegment(int posMs) {
    if (_transcript == null) return;
    final next = _transcript!.segmentAt(posMs);
    final translated = _translatedLine(posMs);
    if (next?.text != _currentSegment?.text || translated != _translatedShown) {
      setState(() {
        _currentSegment = next;
        _translatedShown = translated;
      });
    }
  }

  /// Line of the translated caption track at [posMs], or null when not translated.
  String? _translatedLine(int posMs) {
    final tr = ref.read(reelTranslationProvider((id: widget.content.id, caption: widget.content.description))).value;
    if (tr == null || tr.segments.isEmpty || ref.read(reelShowOriginalProvider(widget.content.id))) return null;
    for (final s in tr.segments) {
      if (posMs >= s.startMs && posMs < s.endMs) return s.text;
    }
    return null;
  }

  void _openFullTranscript() {
    if (_transcript == null) return;
    HapticFeedback.lightImpact();
    final player = ref.read(videoPlaybackManagerProvider).getPlayer(widget.content.id);

    showOneovaTranscriptSheet(
      context,
      transcript: _transcript!,
      currentPositionMs: _currentPosition.inMilliseconds,
      onSeek: (ms) {
        player?.seek(Duration(milliseconds: ms));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final captionsEnabled = ref.watch(oneovaCaptionsEnabledProvider);
    if (!captionsEnabled || _currentSegment == null || _currentSegment!.text.isEmpty) {
      return const SizedBox.shrink();
    }
    // Translated caption track (reel_translation_service.dart) unless "See original".
    ref.watch(reelTranslationProvider((id: widget.content.id, caption: widget.content.description)));
    ref.watch(reelShowOriginalProvider(widget.content.id));
    final line = _translatedLine(_currentPosition.inMilliseconds) ?? _currentSegment!.text;

    return Center(
      child: GestureDetector(
        onTap: _openFullTranscript,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: Container(
            key: ValueKey(line),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'CC',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    line,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.3,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

