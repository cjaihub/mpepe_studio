import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../../feed/widgets/reel_palette.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. REEL TIME LIVE AUDIO WAVES (FOR SHORT VIDEO REELS / FEED)
// ─────────────────────────────────────────────────────────────────────────────

/// High-performance, lightweight audio visualizer waves for Reels / Stories.
/// Dances in real time when [isPlaying] is true, smoothly settles when paused.
class ReelLiveAudioWavesWidget extends StatefulWidget {
  final bool isPlaying;
  final String? trackTitle;
  final String? artistName;
  final VoidCallback? onTap;

  const ReelLiveAudioWavesWidget({
    super.key,
    required this.isPlaying,
    this.trackTitle,
    this.artistName,
    this.onTap,
  });

  @override
  State<ReelLiveAudioWavesWidget> createState() => _ReelLiveAudioWavesWidgetState();
}

class _ReelLiveAudioWavesWidgetState extends State<ReelLiveAudioWavesWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPlaying) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(ReelLiveAudioWavesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _animController.repeat();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _animController.stop();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.trackTitle ?? 'Original Audio - Oneova';
    final palette = ReelPalette.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.glassStrong,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.glassBorder, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sound equalizer icon / indicator
            const Icon(Icons.music_note_rounded, color: AppColors.brandPink, size: 14),
            const SizedBox(width: 6),
            // Live Equalizer Waveform Bars (7 bars)
            AnimatedBuilder(
              animation: _animController,
              builder: (context, _) {
                final t = _animController.value * 2 * math.pi;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(7, (i) {
                    final phase = i * 0.9;
                    final wave = widget.isPlaying
                        ? (math.sin(t + phase).abs() * 0.75 + 0.25)
                        : 0.3;
                    final height = 4.0 + (wave * 12.0);

                    // Alternate colors between Brand Blue & Brand Pink
                    final barColor = i % 2 == 0 ? AppColors.brandBlue : AppColors.brandPink;

                    return Container(
                      width: 2.5,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 1.0),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: widget.isPlaying
                            ? [
                                BoxShadow(
                                  color: barColor.withValues(alpha: 0.6),
                                  blurRadius: 3,
                                )
                              ]
                            : null,
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                title,
                style: GoogleFonts.inter(
                  color: palette.fg,
                  fontSize: 11.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. LIVE REAL-TIME AUDIO WAVEFORM VISUALIZER (DURING RECORDING)
// ─────────────────────────────────────────────────────────────────────────────

/// Paints dynamic audio wave bars reacting in real time to microphone amplitude.
class LiveWaveformVisualizer extends StatelessWidget {
  final bool isRecording;
  final double currentDecibels; // e.g. -60dB (silent) to 0dB (loud)
  final int barCount;
  final double height;
  final Color activeColor;
  final Color accentColor;

  const LiveWaveformVisualizer({
    super.key,
    required this.isRecording,
    this.currentDecibels = -30.0,
    this.barCount = 28,
    this.height = 36.0,
    this.activeColor = AppColors.brandBlue,
    this.accentColor = AppColors.brandPink,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _LiveWaveformPainter(
          isRecording: isRecording,
          decibels: currentDecibels,
          barCount: barCount,
          activeColor: activeColor,
          accentColor: accentColor,
        ),
      ),
    );
  }
}

class _LiveWaveformPainter extends CustomPainter {
  final bool isRecording;
  final double decibels;
  final int barCount;
  final Color activeColor;
  final Color accentColor;

  _LiveWaveformPainter({
    required this.isRecording,
    required this.decibels,
    required this.barCount,
    required this.activeColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barCount <= 0 || size.width <= 0) return;

    // Normalize decibels: -50 dB (quiet) to 0 dB (loud) -> range 0.0 to 1.0
    final normalizedEnergy = isRecording
        ? ((decibels + 50.0) / 50.0).clamp(0.12, 1.0)
        : 0.15;

    final totalSpacing = size.width * 0.35;
    final barSpacing = totalSpacing / (barCount - 1);
    final barWidth = (size.width - totalSpacing) / barCount;
    final midY = size.height / 2;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final random = math.Random(42);

    for (int i = 0; i < barCount; i++) {
      // Create organic speech envelope: center bars taller than edges
      final centerDist = ((i - (barCount / 2)).abs()) / (barCount / 2);
      final envelope = 1.0 - (centerDist * 0.6);

      // Pseudo random variation for voice texture
      final jitter = 0.7 + (random.nextDouble() * 0.6);

      final barHeight = (size.height * 0.9) * normalizedEnergy * envelope * jitter;
      final clampedHeight = math.max(4.0, math.min(size.height, barHeight));

      final x = i * (barWidth + barSpacing);
      final top = midY - (clampedHeight / 2);

      // Color gradation: brandBlue on ends, brandPink on dynamic peaks
      final isPeak = normalizedEnergy > 0.5 && (i % 3 == 0);
      paint.color = isPeak ? accentColor : activeColor;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, clampedHeight),
        Radius.circular(barWidth / 2),
      );

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWaveformPainter oldDelegate) {
    return oldDelegate.isRecording != isRecording ||
        oldDelegate.decibels != decibels ||
        oldDelegate.activeColor != activeColor;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. INTERACTIVE VOICE NOTE PLAYER BUBBLE (FOR CHAT MESSAGES)
// ─────────────────────────────────────────────────────────────────────────────

/// Full-featured interactive voice note player using MediaKit:
/// - Real audio playback using MediaKit `Player`
/// - Interactive scrubbable waveform
/// - Elapsed / total duration display
/// - Playback speed multiplier (1.0x -> 1.5x -> 2.0x)
/// - Oneova brand colors with dual-mode high-contrast tokens
class InteractiveVoiceNotePlayer extends StatefulWidget {
  final String audioUrl;
  final String? initialDuration;
  final List<double>? waveformSamples;
  final bool isMe;

  const InteractiveVoiceNotePlayer({
    super.key,
    required this.audioUrl,
    this.initialDuration,
    this.waveformSamples,
    this.isMe = false,
  });

  @override
  State<InteractiveVoiceNotePlayer> createState() => _InteractiveVoiceNotePlayerState();
}

class _InteractiveVoiceNotePlayerState extends State<InteractiveVoiceNotePlayer> {
  Player? _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  double _playbackSpeed = 1.0;
  bool _isLoading = false;
  bool _hasOpened = false;
  late final List<double> _waveformBars;

  StreamSubscription? _playingSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completedSub;

  @override
  void initState() {
    super.initState();
    _waveformBars = _generateWaveformBars();
    _initPlayer();
  }

  void _initPlayer() {
    try {
      _player = Player();
      _playingSub = _player!.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
            _isLoading = false;
          });
        }
      });

      _posSub = _player!.stream.position.listen((pos) {
        if (mounted) {
          setState(() => _position = pos);
        }
      });

      _durSub = _player!.stream.duration.listen((dur) {
        if (mounted && dur > Duration.zero) {
          setState(() => _duration = dur);
        }
      });

      _completedSub = _player!.stream.completed.listen((completed) {
        if (completed && mounted) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      });
    } catch (e) {
      debugPrint('[InteractiveVoiceNotePlayer] init error: $e');
    }
  }

  List<double> _generateWaveformBars() {
    if (widget.waveformSamples != null && widget.waveformSamples!.length >= 10) {
      final samples = widget.waveformSamples!;
      final result = <double>[];
      final step = samples.length / 26;
      for (int i = 0; i < 26; i++) {
        final idx = (i * step).floor().clamp(0, samples.length - 1);
        result.add(samples[idx].clamp(0.15, 1.0));
      }
      return result;
    }

    final rand = math.Random(widget.audioUrl.hashCode);
    return List.generate(26, (i) {
      final centerDist = ((i - 13).abs()) / 13.0;
      final envelope = 1.0 - (centerDist * 0.55);
      final val = (0.25 + (rand.nextDouble() * 0.75)) * envelope;
      return val.clamp(0.18, 1.0);
    });
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completedSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    HapticFeedback.lightImpact();
    if (_player == null) return;

    if (_isPlaying) {
      await _player!.pause();
    } else {
      setState(() => _isLoading = true);
      try {
        if (!_hasOpened) {
          await _player!.open(Media(widget.audioUrl), play: true);
          _hasOpened = true;
        } else {
          if (_position >= _duration && _duration > Duration.zero) {
            await _player!.seek(Duration.zero);
          }
          await _player!.play();
        }
        await _player!.setRate(_playbackSpeed);
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not play audio note: $e'),
              backgroundColor: AppColors.brandPink,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _cyclePlaybackSpeed() async {
    HapticFeedback.selectionClick();
    double nextSpeed = 1.0;
    if (_playbackSpeed == 1.0) {
      nextSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    setState(() => _playbackSpeed = nextSpeed);
    if (_player != null && _isPlaying) {
      await _player!.setRate(nextSpeed);
    }
  }

  void _seekToPercent(double percent) {
    if (_player != null && _duration.inMilliseconds > 0) {
      final seekMs = (_duration.inMilliseconds * percent).round();
      _player!.seek(Duration(milliseconds: seekMs));
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds;
    final currentMs = _position.inMilliseconds;
    final progress = totalMs > 0 ? (currentMs / totalMs).clamp(0.0, 1.0) : 0.0;

    final displayDuration = _isPlaying || currentMs > 0
        ? _formatDuration(_position)
        : (widget.initialDuration ?? (_duration > Duration.zero ? _formatDuration(_duration) : '0:00'));

    return Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? AppColors.brandBlue.withValues(alpha: 0.18)
            : context.surfaceMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isMe
              ? AppColors.brandBlue.withValues(alpha: 0.4)
              : context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play / Pause Circle Button
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _isPlaying ? AppColors.brandPink : AppColors.brandBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isPlaying ? AppColors.brandPink : AppColors.brandBlue)
                            .withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Interactive Scrubbable Waveform
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final localX = details.localPosition.dx.clamp(0.0, width);
                        _seekToPercent(localX / width);
                      },
                      onHorizontalDragUpdate: (details) {
                        final localX = details.localPosition.dx.clamp(0.0, width);
                        _seekToPercent(localX / width);
                      },
                      child: SizedBox(
                        height: 34,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(_waveformBars.length, (i) {
                            final barProgress = i / _waveformBars.length;
                            final isPlayed = barProgress <= progress;
                            final isHead = _isPlaying &&
                                (barProgress - progress).abs() < (1.0 / _waveformBars.length);

                            final barHeight = 8.0 + (_waveformBars[i] * 22.0);

                            Color barColor;
                            if (isHead) {
                              barColor = AppColors.brandPink;
                            } else if (isPlayed) {
                              barColor = widget.isMe ? AppColors.brandBlue : AppColors.brandPink;
                            } else {
                              barColor = context.textMuted.withValues(alpha: 0.35);
                            }

                            return Container(
                              width: 3.0,
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: BorderRadius.circular(2.0),
                                boxShadow: isHead
                                    ? [
                                        BoxShadow(
                                          color: AppColors.brandPink.withValues(alpha: 0.6),
                                          blurRadius: 4,
                                        )
                                      ]
                                    : null,
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Footer Row: Elapsed Duration, Live Indicator & Speed Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isPlaying)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.brandPink,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      displayDuration,
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                // Speed Multiplier Pill
                GestureDetector(
                  onTap: _cyclePlaybackSpeed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    child: Text(
                      '${_playbackSpeed.toStringAsFixed(1)}x',
                      style: GoogleFonts.inter(
                        color: _playbackSpeed > 1.0 ? AppColors.brandPink : context.textSecondary,
                        fontSize: 10.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
