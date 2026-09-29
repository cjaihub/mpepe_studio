import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/content.dart';
import 'recommendation_service.dart';

final videoPlaybackManagerProvider = Provider<VideoPlaybackManager>((ref) {
  return VideoPlaybackManager(ref.read(recommendationServiceProvider));
});

/// Manages a pool of media_kit Players to ensure we only keep a few videos
/// loaded in memory at a time (Virtualization and Prefetching).
class VideoPlaybackManager {
  final RecommendationService _recommendationService;

  // Map of Content ID -> Player instance
  final Map<String, Player> _players = {};
  final Map<String, VideoController> _controllers = {};
  
  // Track playback time for analytics
  final Map<String, Duration> _watchTime = {};
  final Map<String, StreamSubscription> _positionSubs = {};

  static const int maxCachedPlayers = 3;

  VideoPlaybackManager(this._recommendationService);

  VideoController? getController(String contentId) => _controllers[contentId];

  void initializeAndPreload(List<Content> feed, int currentIndex) {
    // Only keep players for current, next, and previous.
    final Set<String> keepIds = {};
    if (currentIndex >= 0 && currentIndex < feed.length) {
      keepIds.add(feed[currentIndex].id);
    }
    if (currentIndex > 0) {
      keepIds.add(feed[currentIndex - 1].id);
    }
    if (currentIndex < feed.length - 1) {
      keepIds.add(feed[currentIndex + 1].id);
    }

    // Dispose players not in the keep set
    final toRemove = _players.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in toRemove) {
      _disposePlayer(id);
    }

    // Initialize players in the keep set
    for (final id in keepIds) {
      if (!_players.containsKey(id)) {
        final content = feed.firstWhere((c) => c.id == id);
        _initPlayer(content, id == feed[currentIndex].id);
      } else {
        // Play if current, pause if not
        if (id == feed[currentIndex].id) {
          _players[id]?.play();
        } else {
          _players[id]?.pause();
        }
      }
    }
    if (currentIndex >= 0 && currentIndex < feed.length) {
      _trackPlaybackEvent(feed[currentIndex].id, ContentInteractionType.impression);
    }
  }

  void _initPlayer(Content content, bool autoPlay) {
    final player = Player();
    final controller = VideoController(player);

    player.open(Media(content.mediaUrl), play: autoPlay);
    player.setPlaylistMode(PlaylistMode.single);

    _players[content.id] = player;
    _controllers[content.id] = controller;

    // Track real playback events
    _watchTime[content.id] = Duration.zero;
    _positionSubs[content.id] = player.stream.position.listen((pos) {
      // In a real app, track segments watched or use state.playing
      // Here we just keep track of the max position reached as watch time
      if (pos > (_watchTime[content.id] ?? Duration.zero)) {
        _watchTime[content.id] = pos;
      }
    });

    player.stream.completed.listen((_) {
      _trackPlaybackEvent(content.id, ContentInteractionType.viewCompletion);
    });
  }

  void _disposePlayer(String id) {
    _positionSubs[id]?.cancel();
    _positionSubs.remove(id);
    
    // Log the watch time before disposing
    if (_watchTime.containsKey(id)) {
      _trackPlaybackEvent(id, ContentInteractionType.watchDuration, {'durationMs': _watchTime[id]?.inMilliseconds});
      _watchTime.remove(id);
    }

    _players[id]?.dispose();
    _players.remove(id);
    _controllers.remove(id);
  }

  void togglePlayPause(String contentId) {
    final player = _players[contentId];
    if (player != null) {
      player.state.playing ? player.pause() : player.play();
    }
  }

  void setMute(String contentId, bool mute) {
    _players[contentId]?.setVolume(mute ? 0.0 : 100.0);
  }

  void disposeAll() {
    for (final id in _players.keys.toList()) {
      _disposePlayer(id);
    }
  }

  void _trackPlaybackEvent(String contentId, ContentInteractionType type, [Map<String, dynamic>? extraData]) {
    // In a real app we need currentUserId from Auth state, using a placeholder for now
    _recommendationService.trackEvent('currentUser', contentId, type, extraData ?? {});
  }
}
