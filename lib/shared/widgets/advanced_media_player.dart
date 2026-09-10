import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:audio_waveforms/audio_waveforms.dart' as aw;

class AdvancedMediaPlayer extends StatefulWidget {
  final String source;
  final bool isAudio;
  final bool autoPlay;

  const AdvancedMediaPlayer({
    super.key,
    required this.source,
    this.isAudio = false,
    this.autoPlay = false,
  });

  @override
  State<AdvancedMediaPlayer> createState() => _AdvancedMediaPlayerState();
}

class _AdvancedMediaPlayerState extends State<AdvancedMediaPlayer> {
  // Video Player (media_kit)
  Player? _videoPlayer;
  VideoController? _videoController;

  // Audio Player (audio_waveforms)
  aw.PlayerController? _audioController;

  bool _isPlaying = false;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      if (widget.isAudio) {
        _audioController = aw.PlayerController();
        await _audioController!.preparePlayer(
          path: widget.source,
          shouldExtractWaveform: true,
          noOfSamples: 100,
          volume: 1.0,
        );
        _audioController!.onPlayerStateChanged.listen((state) {
          if (mounted) {
            setState(() {
              _isPlaying = state == aw.PlayerState.playing;
            });
          }
        });
        if (widget.autoPlay) {
          await _audioController!.startPlayer();
        }
      } else {
        _videoPlayer = Player();
        _videoController = VideoController(_videoPlayer!);
        _videoPlayer!.open(Media(widget.source), play: widget.autoPlay);
        
        _videoPlayer!.stream.playing.listen((playing) {
          if (mounted) {
            setState(() {
              _isPlaying = playing;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoPlayer?.dispose();
    _audioController?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (widget.isAudio) {
      if (_isPlaying) {
        _audioController?.pausePlayer();
      } else {
        _audioController?.startPlayer();
      }
    } else {
      _videoPlayer?.playOrPause();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return Container(
        height: 200,
        color: Theme.of(context).colorScheme.surface,
        child: const Center(child: Text('Failed to load media')),
      );
    }

    if (widget.isAudio) {
      if (_audioController == null) {
        return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: _togglePlay,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: aw.AudioFileWaveforms(
                size: Size(MediaQuery.of(context).size.width, 60),
                playerController: _audioController!,
                enableSeekGesture: true,
                waveformType: aw.WaveformType.fitWidth,
                playerWaveStyle: aw.PlayerWaveStyle(
                  fixedWaveColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  liveWaveColor: Theme.of(context).colorScheme.primary,
                  spacing: 4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Video Player
    if (_videoController == null) {
      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Video(controller: _videoController!),
            if (!_isPlaying)
              Container(
                color: Colors.black45,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.play_circle_fill, size: 64, color: Colors.white),
                    onPressed: _togglePlay,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
