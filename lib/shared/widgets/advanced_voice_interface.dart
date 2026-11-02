import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/voice_audio_cache.dart';
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
    this.barCount = 22,
    this.height = 22.0,
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

/// Compact, ultra-fast interactive voice note player:
/// - Instant <15ms playback via [VoiceAudioDiskCache]
/// - Single-pass GPU scrubbable waveform ([_CompactScrubWaveformPainter])
/// - Playback speed cycling (`1x` -> `1.5x` -> `2x`)
/// - Auto-translation & 1-tap voice-matched speech synthesis in the speaker's
///   vocal profile (with on-device [FlutterTts] fallback)
class InteractiveVoiceNotePlayer extends StatefulWidget {
  final String audioUrl;
  final String? initialDuration;
  final List<double>? waveformSamples;
  final bool isMe;

  /// When true, renders flush inside an enclosing chat bubble without adding
  /// a nested box border or extra padding.
  final bool embedded;
  final String? messageId;
  final String? senderUid;
  final bool autoTranslateVoice;
  final Future<VoiceTranslationResult> Function()? onTranslateVoice;

  const InteractiveVoiceNotePlayer({
    super.key,
    required this.audioUrl,
    this.initialDuration,
    this.waveformSamples,
    this.isMe = false,
    this.embedded = false,
    this.messageId,
    this.senderUid,
    this.autoTranslateVoice = false,
    this.onTranslateVoice,
  });

  /// Duration-proportional compact bubble width (148..224px) so short voice
  /// notes stay tight and never bloat to full-screen width.
  @visibleForTesting
  static double computeCompactWidth(
    Duration duration, {
    String? initialDuration,
    bool hasTranslationAction = false,
  }) {
    var secs = duration.inSeconds;
    if (secs <= 0 && initialDuration != null && initialDuration.contains(':')) {
      final parts = initialDuration.split(':');
      if (parts.length == 2) {
        secs = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      }
    }
    final clamped = secs.clamp(2, 48);
    final base = 148.0 + ((clamped - 2) / 46.0) * 54.0;
    return base + (hasTranslationAction ? 20.0 : 0.0);
  }

  @override
  State<InteractiveVoiceNotePlayer> createState() => _InteractiveVoiceNotePlayerState();
}

class _InteractiveVoiceNotePlayerState extends State<InteractiveVoiceNotePlayer> {
  static const int _barCount = 20;

  Player? _player;
  FlutterTts? _fallbackTts;
  bool _isPlaying = false;
  bool _isTtsSpeaking = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  double _playbackSpeed = 1.0;
  bool _isLoading = false;
  bool _hasOpened = false;
  String? _openedSourcePath;
  bool _playButtonPressed = false;

  bool _isTranslating = false;
  bool _useTranslatedVoice = false;
  bool _captionExpanded = false;
  VoiceTranslationResult? _translation;
  late List<double> _waveformBars;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _translateBusSub;

  @override
  void initState() {
    super.initState();
    _waveformBars = _generateWaveformBars();
    _initPlayer();
    _translateBusSub = VoiceAudioDiskCache.translateRequests.listen((msgId) {
      if (mounted && widget.messageId != null && msgId == widget.messageId) {
        unawaited(_runTranslateVoice(autoPlay: true));
      }
    });
    // Warm local disk cache in the background for remote URLs so first tap is instant.
    if (widget.audioUrl.startsWith('http')) {
      unawaited(VoiceAudioDiskCache.resolvePlayablePath(widget.audioUrl));
    }
    if (widget.autoTranslateVoice && !widget.isMe && widget.onTranslateVoice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runTranslateVoice(autoPlay: false));
      });
    }
  }

  @override
  void didUpdateWidget(InteractiveVoiceNotePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waveformSamples != widget.waveformSamples) {
      _waveformBars = _generateWaveformBars();
    }
    if (oldWidget.audioUrl != widget.audioUrl && !_useTranslatedVoice) {
      // Keep playing seamlessly if the remote URL maps to the same seeded local file.
      unawaited(_reconcileUpdatedSource());
    }
    if (!oldWidget.autoTranslateVoice &&
        widget.autoTranslateVoice &&
        !widget.isMe &&
        _translation == null &&
        !_isTranslating &&
        widget.onTranslateVoice != null) {
      unawaited(_runTranslateVoice(autoPlay: false));
    }
  }

  Future<void> _reconcileUpdatedSource() async {
    final resolved = await VoiceAudioDiskCache.resolvePlayablePath(widget.audioUrl);
    if (!mounted) return;
    if (_openedSourcePath != null && _openedSourcePath == resolved) return;
    if (!_isPlaying) {
      setState(() => _hasOpened = false);
    }
  }

  void _initPlayer() {
    try {
      _player = Player();
      _playingSub = _player!.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
            if (playing) _isLoading = false;
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
    final samples = widget.waveformSamples;
    if (samples != null && samples.isNotEmpty) {
      final result = <double>[];
      final step = samples.length / _barCount;
      for (var i = 0; i < _barCount; i++) {
        final idx = (i * step).floor().clamp(0, samples.length - 1);
        result.add(samples[idx].clamp(0.16, 1.0));
      }
      return result;
    }

    final rand = math.Random(widget.audioUrl.hashCode);
    return List<double>.generate(_barCount, (i) {
      final centerDist = ((i - (_barCount / 2)).abs()) / (_barCount / 2);
      final envelope = 1.0 - (centerDist * 0.5);
      final val = (0.24 + (rand.nextDouble() * 0.72)) * envelope;
      return val.clamp(0.18, 1.0);
    });
  }

  @override
  void dispose() {
    _translateBusSub?.cancel();
    _playingSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completedSub?.cancel();
    _fallbackTts?.stop();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _stopAllPlayback() async {
    if (_isTtsSpeaking) {
      await _fallbackTts?.stop();
      if (mounted) setState(() => _isTtsSpeaking = false);
    }
    if (_player != null && _isPlaying) {
      await _player!.pause();
    }
  }

  Future<void> _speakFallbackTts(VoiceTranslationResult tr) async {
    _fallbackTts ??= FlutterTts()
      ..setCompletionHandler(() {
        if (mounted) setState(() => _isTtsSpeaking = false);
      })
      ..setCancelHandler(() {
        if (mounted) setState(() => _isTtsSpeaking = false);
      })
      ..setErrorHandler((_) {
        if (mounted) setState(() => _isTtsSpeaking = false);
      });
    await _fallbackTts!.setLanguage(tr.target);
    await _fallbackTts!.setPitch(tr.pitch.clamp(0.8, 1.25));
    // FlutterTts speechRate uses ~0.5 as natural conversational speed on iOS/Android.
    await _fallbackTts!.setSpeechRate((0.48 * tr.rate * _playbackSpeed).clamp(0.35, 0.95));
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isTtsSpeaking = true;
      });
    }
    await _fallbackTts!.speak(tr.translated);
  }

  Future<void> _togglePlayPause() async {
    HapticFeedback.lightImpact();
    if (_isPlaying || _isTtsSpeaking) {
      await _stopAllPlayback();
      return;
    }
    if (_player == null) return;

    final tr = _translation;
    if (_useTranslatedVoice && tr != null && !tr.same && tr.localAudioPath == null) {
      await _speakFallbackTts(tr);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final targetSource = (_useTranslatedVoice && tr != null && !tr.same && tr.localAudioPath != null)
          ? tr.localAudioPath!
          : await VoiceAudioDiskCache.resolvePlayablePath(widget.audioUrl);

      if (!_hasOpened || _openedSourcePath != targetSource) {
        _openedSourcePath = targetSource;
        await _player!.open(Media(targetSource), play: true);
        _hasOpened = true;
      } else {
        if (_duration > Duration.zero && _position >= _duration - const Duration(milliseconds: 120)) {
          await _player!.seek(Duration.zero);
        }
        await _player!.play();
      }
      await _player!.setRate(_playbackSpeed);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not play voice note: $e'),
            backgroundColor: AppColors.brandPink,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _runTranslateVoice({required bool autoPlay}) async {
    final cb = widget.onTranslateVoice;
    if (cb == null || _isTranslating) return;

    if (_translation != null) {
      HapticFeedback.selectionClick();
      await _stopAllPlayback();
      setState(() {
        _useTranslatedVoice = !_useTranslatedVoice;
        _hasOpened = false;
        _position = Duration.zero;
      });
      if (autoPlay && _useTranslatedVoice && !_translation!.same) {
        await _togglePlayPause();
      }
      return;
    }

    setState(() => _isTranslating = true);
    try {
      final res = await cb();
      if (!mounted) return;
      await _stopAllPlayback();
      setState(() {
        _translation = res;
        _isTranslating = false;
        _useTranslatedVoice = !res.same && res.translated.isNotEmpty;
        _hasOpened = false;
        _position = Duration.zero;
      });
      if (autoPlay) {
        if (!res.same && res.translated.isNotEmpty) {
          await _togglePlayPause();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Voice note is already in your language.'),
              backgroundColor: AppColors.brandBlue,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTranslating = false);
      if (autoPlay) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: AppColors.brandPink,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _cyclePlaybackSpeed() async {
    HapticFeedback.selectionClick();
    final nextSpeed = _playbackSpeed == 1.0
        ? 1.5
        : (_playbackSpeed == 1.5 ? 2.0 : 1.0);
    setState(() => _playbackSpeed = nextSpeed);
    if (_player != null && _isPlaying) {
      await _player!.setRate(nextSpeed);
    }
  }

  void _seekToPercent(double percent) {
    if (_player != null && _duration.inMilliseconds > 0) {
      final seekMs = (_duration.inMilliseconds * percent.clamp(0.0, 1.0)).round();
      _player!.seek(Duration(milliseconds: seekMs));
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _speedLabel() {
    if (_playbackSpeed == 1.0) return '1x';
    if (_playbackSpeed == 1.5) return '1.5x';
    return '2x';
  }

  @override
  Widget build(BuildContext context) {
    final activePlaying = _isPlaying || _isTtsSpeaking;
    final totalMs = _duration.inMilliseconds;
    final currentMs = _position.inMilliseconds;
    final progress = _isTtsSpeaking
        ? 0.65
        : (totalMs > 0 ? (currentMs / totalMs).clamp(0.0, 1.0) : 0.0);

    final displayDuration = activePlaying || currentMs > 0
        ? _formatDuration(_position)
        : (widget.initialDuration ?? (_duration > Duration.zero ? _formatDuration(_duration) : '0:00'));

    final onBrandBlue = widget.embedded && widget.isMe;
    final hasTranslate = widget.onTranslateVoice != null;
    final targetWidth = InteractiveVoiceNotePlayer.computeCompactWidth(
      _duration,
      initialDuration: widget.initialDuration,
      hasTranslationAction: hasTranslate,
    );

    final playBtnBg = onBrandBlue
        ? (activePlaying ? AppColors.brandPink : AppColors.brandWhite.withValues(alpha: 0.22))
        : (activePlaying ? AppColors.brandPink : AppColors.brandBlue);

    final playedBarColor = onBrandBlue
        ? AppColors.brandWhite
        : (_useTranslatedVoice ? AppColors.brandPink : AppColors.brandBlue);
    final unplayedBarColor = onBrandBlue
        ? AppColors.brandWhite.withValues(alpha: 0.34)
        : context.textMuted.withValues(alpha: 0.32);

    final metaTextColor = onBrandBlue
        ? AppColors.brandWhite.withValues(alpha: 0.92)
        : context.textSecondary;
    final pillBg = onBrandBlue
        ? AppColors.brandWhite.withValues(alpha: 0.16)
        : context.surfaceMid;
    final pillBorderColor = onBrandBlue
        ? AppColors.brandWhite.withValues(alpha: 0.24)
        : context.border;

    final tr = _translation;
    final showCaption = tr != null &&
        ((_useTranslatedVoice && tr.translated.isNotEmpty) ||
            (tr.same && tr.transcript.isNotEmpty && !widget.autoTranslateVoice));

    final coreContent = SizedBox(
      width: targetWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Crisp 26x26 Play / Pause Button
              GestureDetector(
                onTapDown: (_) => setState(() => _playButtonPressed = true),
                onTapUp: (_) => setState(() => _playButtonPressed = false),
                onTapCancel: () => setState(() => _playButtonPressed = false),
                onTap: _togglePlayPause,
                child: AnimatedScale(
                  scale: _playButtonPressed ? 0.92 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: playBtnBg,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandWhite),
                              ),
                            )
                          : Icon(
                              activePlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: AppColors.brandWhite,
                              size: 16,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),

              // Slim 18px GPU-Painted Scrubbable Waveform
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = math.max(1.0, constraints.maxWidth);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _seekToPercent(d.localPosition.dx / width),
                      onHorizontalDragUpdate: (d) => _seekToPercent(d.localPosition.dx / width),
                      child: SizedBox(
                        height: 18,
                        child: CustomPaint(
                          size: Size(width, 18),
                          painter: _CompactScrubWaveformPainter(
                            bars: _waveformBars,
                            progress: progress,
                            isPlaying: activePlaying,
                            playedColor: playedBarColor,
                            unplayedColor: unplayedBarColor,
                            headColor: AppColors.brandPink,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),

              // Inline Tabular Duration
              Text(
                displayDuration,
                style: GoogleFonts.inter(
                  color: metaTextColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 5),

              // Micro Speed Pill (1x / 1.5x / 2x)
              GestureDetector(
                onTap: _cyclePlaybackSpeed,
                child: Container(
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: pillBorderColor, width: 1.0),
                  ),
                  child: Text(
                    _speedLabel(),
                    style: GoogleFonts.inter(
                      color: _playbackSpeed > 1.0 && !onBrandBlue
                          ? AppColors.brandPink
                          : metaTextColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              // Auto-Translate / Speaker-Matched Voice Synthesis Toggle
              if (hasTranslate) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _runTranslateVoice(autoPlay: _translation == null),
                  child: Tooltip(
                    message: _useTranslatedVoice
                        ? 'Playing in speaker voice (tap for original)'
                        : 'Translate in speaker voice',
                    child: Container(
                      width: 20,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _useTranslatedVoice ? AppColors.brandPink : pillBg,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: _useTranslatedVoice ? AppColors.brandPink : pillBorderColor,
                          width: 1.0,
                        ),
                      ),
                      child: _isTranslating
                          ? SizedBox(
                              width: 9,
                              height: 9,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  onBrandBlue ? AppColors.brandWhite : AppColors.brandPink,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.record_voice_over_rounded,
                              size: 11,
                              color: _useTranslatedVoice
                                  ? AppColors.brandWhite
                                  : metaTextColor,
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Compact Voice-Matched Translation Caption & Mode Strip
          if (showCaption) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _captionExpanded = !_captionExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(AppRadius.xs + 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 10,
                          color: onBrandBlue ? AppColors.brandWhite : AppColors.brandPink,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            _useTranslatedVoice
                                ? '${tr.source.isNotEmpty ? "${tr.source.toUpperCase()} → " : ""}${tr.target.toUpperCase()} · Speaker Voice'
                                : 'Transcript',
                            style: GoogleFonts.inter(
                              fontSize: 9.0,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: onBrandBlue ? AppColors.brandWhite : AppColors.brandPink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      _useTranslatedVoice ? tr.translated : tr.transcript,
                      maxLines: _captionExpanded ? 8 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.0,
                        height: 1.28,
                        fontWeight: FontWeight.w500,
                        color: onBrandBlue ? AppColors.brandWhite : context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) {
      return coreContent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: widget.isMe
            ? AppColors.brandBlue.withValues(alpha: 0.14)
            : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: widget.isMe
              ? AppColors.brandBlue.withValues(alpha: 0.35)
              : context.border,
          width: 1.0,
        ),
      ),
      child: coreContent,
    );
  }
}

class _CompactScrubWaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final bool isPlaying;
  final Color playedColor;
  final Color unplayedColor;
  final Color headColor;

  const _CompactScrubWaveformPainter({
    required this.bars,
    required this.progress,
    required this.isPlaying,
    required this.playedColor,
    required this.unplayedColor,
    required this.headColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;

    const barWidth = 2.0;
    final count = bars.length;
    final gap = count > 1 ? math.max(1.2, (size.width - count * barWidth) / (count - 1)) : 0.0;
    final midY = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final x = i * (barWidth + gap);
      if (x + barWidth > size.width + 0.5) break;
      final barProgress = count > 1 ? i / (count - 1) : 0.0;
      final isHead = isPlaying && (barProgress - progress).abs() <= (0.85 / count);
      final isPlayed = barProgress <= progress && progress > 0.0;

      final h = (3.0 + bars[i].clamp(0.0, 1.0) * (size.height - 3.5)).clamp(3.0, size.height);
      paint.color = isHead ? headColor : (isPlayed ? playedColor : unplayedColor);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - h / 2, barWidth, h),
          const Radius.circular(1.0),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CompactScrubWaveformPainter old) {
    return old.progress != progress ||
        old.isPlaying != isPlaying ||
        old.playedColor != playedColor ||
        old.unplayedColor != unplayedColor ||
        old.bars != bars;
  }
}
