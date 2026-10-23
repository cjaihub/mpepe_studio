import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../../shared/theme/app_theme.dart';

/// Pre-import video trim and configuration result
class OneovaTrimmedMediaResult {
  final File file;
  final bool isVideo;
  final double startSeconds;
  final double endSeconds;
  final double totalDurationSeconds;
  final double speed;
  final bool muteAudio;
  final double aspectRatio;
  final bool isFullClip;

  const OneovaTrimmedMediaResult({
    required this.file,
    required this.isVideo,
    this.startSeconds = 0.0,
    this.endSeconds = 0.0,
    this.totalDurationSeconds = 0.0,
    this.speed = 1.0,
    this.muteAudio = false,
    this.aspectRatio = 9 / 16,
    this.isFullClip = true,
  });

  double get trimmedDuration =>
      (!isFullClip && endSeconds > startSeconds)
          ? (endSeconds - startSeconds) / speed
          : (totalDurationSeconds > 0 ? totalDurationSeconds / speed : 0.0);
}

/// Advanced pre-import video trimmer and clip inspection sheet
/// Allows creators to decide in/out points, trim length, speed, and audio
/// BEFORE importing a video clip into the timeline or sequence.
class OneovaClipTrimmerSheet extends StatefulWidget {
  final File videoFile;
  final String? clipTitle;
  final String actionLabel; // e.g. "Import to Timeline" or "Add to Sequence"

  const OneovaClipTrimmerSheet({
    super.key,
    required this.videoFile,
    this.clipTitle,
    this.actionLabel = 'Import to Timeline',
  });

  /// Shows the trimmer modal bottom sheet and returns the trimmed clip result
  static Future<OneovaTrimmedMediaResult?> show(
    BuildContext context, {
    required File videoFile,
    String? clipTitle,
    String actionLabel = 'Import to Timeline',
  }) {
    return showModalBottomSheet<OneovaTrimmedMediaResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OneovaClipTrimmerSheet(
        videoFile: videoFile,
        clipTitle: clipTitle,
        actionLabel: actionLabel,
      ),
    );
  }

  @override
  State<OneovaClipTrimmerSheet> createState() => _OneovaClipTrimmerSheetState();
}

class _OneovaClipTrimmerSheetState extends State<OneovaClipTrimmerSheet> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;

  double _totalDurationSeconds = 0.0;
  double _trimStartSeconds = 0.0;
  double _trimEndSeconds = 0.0;
  double _currentPositionSeconds = 0.0;

  double _selectedSpeed = 1.0;
  bool _isMuted = false;
  double _aspectRatio = 9 / 16; // 9:16 Reel, 1:1 Square, 16:9 Cinema
  String _aspectRatioLabel = '9:16';

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.file(widget.videoFile);
      await _controller!.initialize();
      final totalSec = _controller!.value.duration.inMilliseconds / 1000.0;

      _controller!.addListener(_onPlayerUpdate);
      _controller!.setLooping(false);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _totalDurationSeconds = totalSec > 0 ? totalSec : 1.0;
          _trimStartSeconds = 0.0;
          _trimEndSeconds = _totalDurationSeconds;
        });
      }
    } catch (e) {
      debugPrint('[OneovaClipTrimmer] Player init error: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  void _onPlayerUpdate() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

    final pos = _controller!.value.position.inMilliseconds / 1000.0;
    final isPlaying = _controller!.value.isPlaying;

    // Loop within trimmed boundaries
    if (isPlaying && pos >= _trimEndSeconds) {
      _controller!.seekTo(Duration(milliseconds: (_trimStartSeconds * 1000).toInt()));
      return;
    }

    setState(() {
      _currentPositionSeconds = pos;
      _isPlaying = isPlaying;
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    HapticFeedback.lightImpact();
    if (_controller == null || !_isInitialized) return;

    if (_isPlaying) {
      _controller!.pause();
    } else {
      if (_currentPositionSeconds >= _trimEndSeconds || _currentPositionSeconds < _trimStartSeconds) {
        _controller!.seekTo(Duration(milliseconds: (_trimStartSeconds * 1000).toInt()));
      }
      _controller!.play();
    }
  }

  void _seekTo(double seconds) {
    if (_controller == null || !_isInitialized) return;
    final clamped = seconds.clamp(0.0, _totalDurationSeconds);
    _controller!.seekTo(Duration(milliseconds: (clamped * 1000).toInt()));
    setState(() => _currentPositionSeconds = clamped);
  }

  void _stepFrame(double deltaSeconds) {
    HapticFeedback.selectionClick();
    _seekTo(_currentPositionSeconds + deltaSeconds);
  }

  void _setInPointAtCurrent() {
    HapticFeedback.mediumImpact();
    setState(() {
      _trimStartSeconds = _currentPositionSeconds.clamp(0.0, _trimEndSeconds - 0.5);
    });
  }

  void _setOutPointAtCurrent() {
    HapticFeedback.mediumImpact();
    setState(() {
      _trimEndSeconds = _currentPositionSeconds.clamp(_trimStartSeconds + 0.5, _totalDurationSeconds);
    });
  }

  void _applyDurationPreset(double? maxDuration) {
    HapticFeedback.lightImpact();
    setState(() {
      _trimStartSeconds = 0.0;
      if (maxDuration == null || maxDuration >= _totalDurationSeconds) {
        _trimEndSeconds = _totalDurationSeconds;
      } else {
        _trimEndSeconds = maxDuration;
      }
    });
    _seekTo(0.0);
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() {
      _isMuted = !_isMuted;
      _controller?.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _changeSpeed(double speed) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedSpeed = speed;
      _controller?.setPlaybackSpeed(speed);
    });
  }

  void _cycleAspectRatio() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_aspectRatioLabel == '9:16') {
        _aspectRatioLabel = '1:1';
        _aspectRatio = 1.0;
      } else if (_aspectRatioLabel == '1:1') {
        _aspectRatioLabel = '16:9';
        _aspectRatio = 16 / 9;
      } else {
        _aspectRatioLabel = '9:16';
        _aspectRatio = 9 / 16;
      }
    });
  }

  void _confirmImport({required bool fullClip}) {
    HapticFeedback.mediumImpact();
    _controller?.pause();

    final result = OneovaTrimmedMediaResult(
      file: widget.videoFile,
      isVideo: true,
      startSeconds: fullClip ? 0.0 : _trimStartSeconds,
      endSeconds: fullClip ? _totalDurationSeconds : _trimEndSeconds,
      totalDurationSeconds: _totalDurationSeconds,
      speed: _selectedSpeed,
      muteAudio: _isMuted,
      aspectRatio: _aspectRatio,
      isFullClip: fullClip,
    );

    Navigator.of(context).pop(result);
  }

  String _formatTimecode(double totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toInt().toString().padLeft(2, '0');
    final ms = ((totalSeconds % 1) * 10).toInt();
    return '$mins:$secs.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF141414) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF475569);

    final selectedDuration = (_trimEndSeconds - _trimStartSeconds).clamp(0.0, _totalDurationSeconds);
    final fileName = widget.clipTitle ?? widget.videoFile.path.split('/').last;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Top Header
            _buildHeader(context, fileName, textPrimary, textSecondary, borderColor),

            // Main Body: Video Preview & Scrubber
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Video Player Canvas
                      _buildVideoCanvas(borderColor, textSecondary),

                      const SizedBox(height: 12),

                      // Transport Controls (Play/Pause, Step, Timecode)
                      _buildTransportBar(textPrimary, textSecondary, borderColor),

                      const SizedBox(height: 14),

                      // Dual-Handle Visual Trimmer
                      _buildVisualTrimmer(borderColor, textPrimary, textSecondary),

                      const SizedBox(height: 14),

                      // In / Out Quick Steppers & Trim Presets
                      _buildTrimmerTools(borderColor, textPrimary, textSecondary),

                      const SizedBox(height: 14),

                      // Secondary Settings (Speed, Audio, Aspect Ratio)
                      _buildClipConfigRow(borderColor, textPrimary, textSecondary),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Action Deck
            _buildBottomActionDeck(borderColor, textPrimary, selectedDuration),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String fileName,
    Color textPrimary,
    Color textSecondary,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                color: textPrimary,
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Trim Video Clip',
                        style: GoogleFonts.inter(
                          color: textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.brandPink, width: 0.8),
                        ),
                        child: Text(
                          'PRE-INGEST',
                          style: GoogleFonts.inter(
                            color: AppColors.brandPink,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // File Size & Codec Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.movie_filter_rounded, size: 12, color: AppColors.brandBlue),
                const SizedBox(width: 4),
                Text(
                  'H.264 HD',
                  style: GoogleFonts.inter(
                    color: AppColors.brandBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCanvas(Color borderColor, Color textSecondary) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md - 1),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isInitialized && _controller != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.brandPink, size: 32),
                    const SizedBox(height: 6),
                    Text(
                      'Preview unavailable for this format',
                      style: GoogleFonts.inter(color: textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              )
            else
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),

            // Tap Canvas to Play/Pause Overlay
            GestureDetector(
              onTap: _togglePlayPause,
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: !_isPlaying ? 1.0 : 0.0,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 1.5),
                      ),
                      child: const Center(
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Aspect Ratio Watermark Pill
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Text(
                  _aspectRatioLabel,
                  style: GoogleFonts.firaCode(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),

            // In/Out Active Range Marker
            Positioned(
              bottom: 8,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.8), width: 1.0),
                ),
                child: Row(
                  children: [
                    Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      'TRIMMED ${_formatTimecode(_trimEndSeconds - _trimStartSeconds)}',
                      style: GoogleFonts.firaCode(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportBar(Color textPrimary, Color textSecondary, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Current Timecode
          Row(
            children: [
              Text(
                _formatTimecode(_currentPositionSeconds),
                style: GoogleFonts.firaCode(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                ' / ${_formatTimecode(_totalDurationSeconds)}',
                style: GoogleFonts.firaCode(
                  color: textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          // Transport Buttons: -0.1s, Play/Pause, +0.1s
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, size: 20),
                color: textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _stepFrame(-0.5),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppColors.brandBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, size: 20),
                color: textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _stepFrame(0.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisualTrimmer(Color borderColor, Color textPrimary, Color textSecondary) {
    final double safeTotal = _totalDurationSeconds > 0 ? _totalDurationSeconds : 1.0;
    final double startRatio = (_trimStartSeconds / safeTotal).clamp(0.0, 1.0);
    final double endRatio = (_trimEndSeconds / safeTotal).clamp(0.0, 1.0);
    final double currentRatio = (_currentPositionSeconds / safeTotal).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TIMELINE TRIMMER (IN & OUT)',
              style: GoogleFonts.inter(
                color: textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Selected: ${_formatTimecode(_trimEndSeconds - _trimStartSeconds)}',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Visual Filmstrip Track Container
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;

            return GestureDetector(
              onHorizontalDragUpdate: (details) {
                final localX = details.localPosition.dx.clamp(0.0, trackWidth);
                final tappedRatio = localX / trackWidth;
                final tappedSec = tappedRatio * safeTotal;
                _seekTo(tappedSec);
              },
              child: Container(
                height: 52,
                width: trackWidth,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Stack(
                  children: [
                    // Simulated Filmstrip Cells
                    Row(
                      children: List.generate(8, (index) {
                        return Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.movie_outlined,
                                color: Colors.white.withValues(alpha: 0.12),
                                size: 16,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    // Excluded Head Dimmer (Before In-Point)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: trackWidth * startRatio,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),

                    // Excluded Tail Dimmer (After Out-Point)
                    Positioned(
                      left: trackWidth * endRatio,
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),

                    // Active Trimmed Zone (Highlighted with Brand Blue/Pink glow)
                    Positioned(
                      left: trackWidth * startRatio,
                      top: 0,
                      bottom: 0,
                      width: (trackWidth * (endRatio - startRatio)).clamp(4.0, trackWidth),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(color: AppColors.brandBlue, width: 2.5),
                          ),
                          color: AppColors.brandBlue.withValues(alpha: 0.15),
                        ),
                      ),
                    ),

                    // Left In-Point Handle
                    Positioned(
                      left: (trackWidth * startRatio - 12).clamp(0.0, trackWidth - 24),
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          final newX = (trackWidth * startRatio + details.delta.dx).clamp(0.0, trackWidth * endRatio - 16);
                          final newStart = (newX / trackWidth) * safeTotal;
                          setState(() => _trimStartSeconds = newStart);
                          _seekTo(newStart);
                        },
                        child: Container(
                          width: 24,
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue,
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppRadius.sm)),
                            boxShadow: [
                              BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.4), blurRadius: 4),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.arrow_right_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),

                    // Right Out-Point Handle
                    Positioned(
                      left: (trackWidth * endRatio - 12).clamp(12.0, trackWidth - 24),
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          final newX = (trackWidth * endRatio + details.delta.dx).clamp(trackWidth * startRatio + 16, trackWidth);
                          final newEnd = (newX / trackWidth) * safeTotal;
                          setState(() => _trimEndSeconds = newEnd);
                          _seekTo(newEnd);
                        },
                        child: Container(
                          width: 24,
                          decoration: BoxDecoration(
                            color: AppColors.brandPink,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppRadius.sm)),
                            boxShadow: [
                              BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.4), blurRadius: 4),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.arrow_left_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),

                    // Current Playhead Scrubber Line
                    Positioned(
                      left: (trackWidth * currentRatio - 1.5).clamp(0.0, trackWidth - 3),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(1.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 6),
        // Start and End Time Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'IN: ${_formatTimecode(_trimStartSeconds)}',
              style: GoogleFonts.firaCode(color: AppColors.brandBlue, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
            Text(
              'OUT: ${_formatTimecode(_trimEndSeconds)}',
              style: GoogleFonts.firaCode(color: AppColors.brandPink, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrimmerTools(Color borderColor, Color textPrimary, Color textSecondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stepper Buttons Row: Set IN, Set OUT, Presets
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.first_page_rounded, size: 16),
                label: const Text('Set IN Point'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandBlue,
                  side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.6), width: 1.0),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: _setInPointAtCurrent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.last_page_rounded, size: 16),
                label: const Text('Set OUT Point'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandPink,
                  side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.6), width: 1.0),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: _setOutPointAtCurrent,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Quick Preset Chips (Full, 15s, 30s, 60s)
        Row(
          children: [
            Text('PRESETS:', style: GoogleFonts.inter(color: textSecondary, fontSize: 10, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            _presetChip('Full Clip', null, textPrimary, borderColor),
            const SizedBox(width: 6),
            _presetChip('15s Reel', 15.0, textPrimary, borderColor),
            const SizedBox(width: 6),
            _presetChip('30s', 30.0, textPrimary, borderColor),
            const SizedBox(width: 6),
            _presetChip('60s', 60.0, textPrimary, borderColor),
          ],
        ),
      ],
    );
  }

  Widget _presetChip(String label, double? seconds, Color textPrimary, Color borderColor) {
    final isFull = seconds == null;
    final isSelected = isFull
        ? (_trimStartSeconds == 0.0 && (_trimEndSeconds - _totalDurationSeconds).abs() < 0.2)
        : (_trimStartSeconds == 0.0 && (_trimEndSeconds - seconds).abs() < 0.2);

    return GestureDetector(
      onTap: () => _applyDurationPreset(seconds),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandBlue : borderColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: isSelected ? AppColors.brandBlue : borderColor, width: 1.0),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : textPrimary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildClipConfigRow(Color borderColor, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SEQUENCE INGEST SETTINGS',
            style: GoogleFonts.inter(
              color: textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Audio Toggle
              GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isMuted ? AppColors.brandPink.withValues(alpha: 0.15) : borderColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: _isMuted ? AppColors.brandPink : borderColor,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        size: 15,
                        color: _isMuted ? AppColors.brandPink : textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isMuted ? 'Muted' : 'Audio On',
                        style: GoogleFonts.inter(
                          color: _isMuted ? AppColors.brandPink : textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Framing Aspect Ratio
              GestureDetector(
                onTap: _cycleAspectRatio,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: borderColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: borderColor, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.crop_rounded, size: 15, color: AppColors.brandBlue),
                      const SizedBox(width: 6),
                      Text(
                        'Aspect: $_aspectRatioLabel',
                        style: GoogleFonts.inter(
                          color: textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Speed Selector Chips
              Row(
                children: [0.5, 1.0, 2.0].map((spd) {
                  final isCur = _selectedSpeed == spd;
                  return GestureDetector(
                    onTap: () => _changeSpeed(spd),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: isCur ? AppColors.brandBlue : borderColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isCur ? AppColors.brandBlue : borderColor, width: 0.8),
                      ),
                      child: Text(
                        '${spd}x',
                        style: GoogleFonts.inter(
                          color: isCur ? Colors.white : textPrimary,
                          fontSize: 10.5,
                          fontWeight: isCur ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionDeck(Color borderColor, Color textPrimary, double selectedDuration) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: 0.15),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Row(
        children: [
          // "Use Full Video" Secondary Option
          Expanded(
            flex: 2,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: textPrimary,
                side: BorderSide(color: borderColor, width: 1.0),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () => _confirmImport(fullClip: true),
              child: Text(
                'Full Clip',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Primary "Import to Timeline" / "Add to Sequence" Action
          Expanded(
            flex: 3,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () => _confirmImport(fullClip: false),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_downward_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    widget.actionLabel,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${selectedDuration.toStringAsFixed(1)}s',
                      style: GoogleFonts.firaCode(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
