// LIVE STUDIO v2 — package:video_player adapter for the watch party.
// Loaded with a deferred import (see watch_player_handle.dart).

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../../../backend/live_studio/table/watch_party_sync.dart';
import 'watch_player_handle.dart';

Future<WatchPlayerHandle> createVideoWatchPlayer(String hlsUrl) async {
  final c = VideoPlayerController.networkUrl(
    Uri.parse(hlsUrl),
    formatHint: VideoFormat.hls,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
  await c.initialize();
  return _VideoWatchPlayer(c);
}

class _VideoWatchPlayer implements WatchPlayerHandle, WatchPlayer {
  _VideoWatchPlayer(this._c);
  final VideoPlayerController _c;

  @override
  WatchPlayer get player => this;

  @override
  Widget buildView(BuildContext context) => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _c.value.size.width <= 0 ? 16 : _c.value.size.width,
          height: _c.value.size.height <= 0 ? 9 : _c.value.size.height,
          child: VideoPlayer(_c),
        ),
      );

  @override
  int get positionMs => _c.value.position.inMilliseconds;
  @override
  bool get isPlaying => _c.value.isPlaying;
  @override
  double get rate => _c.value.playbackSpeed;
  @override
  int? get durationMs {
    final d = _c.value.duration.inMilliseconds;
    return d > 0 ? d : null;
  }

  @override
  Future<void> play() => _c.play();
  @override
  Future<void> pause() => _c.pause();
  @override
  Future<void> seekTo(int positionMs) => _c.seekTo(Duration(milliseconds: positionMs));
  @override
  Future<void> setRate(double rate) => _c.setPlaybackSpeed(rate);

  @override
  Future<void> dispose() => _c.dispose();
}
