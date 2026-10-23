import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart' as aw;
import '../../shared/theme/app_theme.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final bool isOutgoing;

  const AudioPlayerWidget({
    super.key,
    required this.audioUrl,
    this.isOutgoing = false,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final aw.PlayerController _controller = aw.PlayerController();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _controller.preparePlayer(
        path: widget.audioUrl,
        shouldExtractWaveform: false,
        volume: 1.0,
      );
      _controller.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == aw.PlayerState.playing;
          });
        }
      });
      _controller.onCurrentDurationChanged.listen((duration) {
        if (mounted) {
          setState(() {
            _position = Duration(milliseconds: duration);
          });
        }
      });
      final maxDuration = await _controller.getDuration(aw.DurationType.max);
      if (mounted) {
        setState(() {
          _duration = Duration(milliseconds: maxDuration);
        });
      }
    } catch (e) {
      debugPrint('AudioPlayerWidget init error: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    try {
      if (_isPlaying) {
        await _controller.pausePlayer();
      } else {
        await _controller.startPlayer();
      }
    } catch (e) {
      debugPrint('Error toggling play: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final textColor = context.textPrimary;
    final iconColor = AppColors.brandBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isOutgoing ? AppColors.brandBlue.withValues(alpha: 0.12) : context.surfaceMid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isOutgoing ? AppColors.brandBlue.withValues(alpha: 0.25) : context.border,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                key: ValueKey<bool>(_isPlaying),
                color: iconColor,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: iconColor,
                inactiveTrackColor: iconColor.withValues(alpha: 0.3),
                thumbColor: iconColor,
              ),
              child: Slider(
                min: 0,
                max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                value: _position.inMilliseconds.toDouble().clamp(0.0, _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0),
                onChanged: (value) async {
                  await _controller.seekTo(value.toInt());
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_position.inMilliseconds > 0 || _isPlaying ? _position : _duration),
            style: AppTypography.small(textColor).copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
