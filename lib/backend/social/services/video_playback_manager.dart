import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/content.dart';
import 'recommendation_service.dart';
import '../../../feed/services/reel_prefetcher.dart';

final videoPlaybackManagerProvider = Provider<VideoPlaybackManager>((ref) {
  return VideoPlaybackManager(ref.read(recommendationServiceProvider), ref.read(reelPrefetcherProvider));
});

/// One reusable media_kit [Player] + [VideoController] pair.
class _PlayerSlot {
  _PlayerSlot(this.player, this.controller);

  final Player player;
  final VideoController controller;

  /// Content currently loaded into this slot, or null when the slot is free.
  String? contentId;
  Duration watchTime = Duration.zero;
}

/// Manages a fixed pool of media_kit Players so only a few videos are loaded
/// at a time (virtualization and prefetching).
///
/// Players are created lazily up to [maxCachedPlayers] and then REUSED by
/// opening new media into them. They are intentionally never disposed:
/// disposing a media_kit Player closes the FFI wakeup callback that libmpv's
/// core/opener threads call into, and on Android (seen on Android 16 arm64)
/// a late call into the freed trampoline crashes the app with SIGSEGV in
/// libmpv.so. Stopping a player is safe; destroying its mpv handle while
/// scrolling or navigating is not.
class VideoPlaybackManager {
  final RecommendationService _recommendationService;
  final ReelPrefetcher _prefetcher;

  final List<_PlayerSlot> _slots = [];

  /// Warm players: current, next, previous, next+1. Each holds at most
  /// [playerBufferBytes] of demuxed video, so the pool stays under ~64 MB
  /// of buffers on mid-range phones (media_kit's default is 32 MB each).
  static const int maxCachedPlayers = 4;
  static const int playerBufferBytes = 16 * 1024 * 1024;

  /// Bumped whenever a reel gains or loses its player, so feed pages that
  /// were built before their player was ready swap the cover for video.
  final ValueNotifier<int> slotsRevision = ValueNotifier(0);

  /// Slot that was playing when the app went to the background.
  _PlayerSlot? _pausedByLifecycle;

  VideoPlaybackManager(this._recommendationService, this._prefetcher) {
    // The Flutter engine outlives MainActivity on Android, so the feed can stay
    // mounted after the app is closed: keep it silent while hidden.
    AppLifecycleListener(
      onHide: _pauseForBackground,
      onShow: _resumeFromBackground,
    );
  }

  void _pauseForBackground() {
    for (final slot in _slots) {
      if (slot.contentId != null && slot.player.state.playing) {
        _pausedByLifecycle = slot;
        slot.player.pause();
      }
    }
  }

  void _resumeFromBackground() {
    final slot = _pausedByLifecycle;
    _pausedByLifecycle = null;
    if (slot != null && slot.contentId != null) {
      slot.player.play();
    }
  }

  _PlayerSlot? _slotFor(String contentId) {
    for (final slot in _slots) {
      if (slot.contentId == contentId) return slot;
    }
    return null;
  }

  VideoController? getController(String contentId) => _slotFor(contentId)?.controller;
  Player? getPlayer(String contentId) => _slotFor(contentId)?.player;

  void setLooping(String contentId, bool isLooping) {
    _slotFor(contentId)?.player.setPlaylistMode(isLooping ? PlaylistMode.loop : PlaylistMode.single);
  }

  /// Ensures that the active reel is actively playing without stalling
  void ensureCurrentPlaying(String contentId) {
    final player = _slotFor(contentId)?.player;
    if (player != null && !player.state.playing) {
      player.play();
    }
  }

  void initializeAndPreload(List<Content> feed, int currentIndex) {
    if (currentIndex < 0 || currentIndex >= feed.length) return;

    // Keep players for current, previous, and the next 2 upcoming videos for seamless zero-lag playback.
    // Ordered by priority so the current reel always gets a slot first.
    final List<String> keepIds = [feed[currentIndex].id];
    if (currentIndex < feed.length - 1) {
      keepIds.add(feed[currentIndex + 1].id);
    }
    if (currentIndex > 0) {
      keepIds.add(feed[currentIndex - 1].id);
    }
    if (currentIndex < feed.length - 2) {
      keepIds.add(feed[currentIndex + 2].id);
    }
    final currentId = feed[currentIndex].id;

    // Release slots holding content outside the keep set
    for (final slot in _slots) {
      final id = slot.contentId;
      if (id != null && !keepIds.contains(id)) {
        _releaseSlot(slot);
      }
    }

    // Load the keep set (current plays, others buffer in background)
    for (final id in keepIds.toSet()) {
      final isCurrent = id == currentId;
      final existing = _slotFor(id);
      if (existing == null) {
        final content = feed.firstWhere((c) => c.id == id);
        // Photos render as an image; they never take a player slot.
        if (content.type == ContentType.photo) continue;
        final slot = _acquireSlot();
        if (slot == null) continue;
        _loadIntoSlot(slot, content, isCurrent);
      } else {
        // Play if current, pause if preloaded background buffer
        if (isCurrent) {
          if (!existing.player.state.playing) {
            existing.player.play();
          }
        } else {
          existing.player.pause();
        }
      }
    }
    // The impression itself is tracked by the feed (_onPageChanged).
  }

  /// Returns a free slot, creating a new player while under the pool limit.
  _PlayerSlot? _acquireSlot() {
    for (final slot in _slots) {
      if (slot.contentId == null) return slot;
    }
    if (_slots.length >= maxCachedPlayers) return null;

    final player = Player(configuration: const PlayerConfiguration(bufferSize: playerBufferBytes));
    final slot = _PlayerSlot(player, VideoController(player));

    // Track real playback events for whichever content the slot currently holds
    player.stream.position.listen((pos) {
      // Keep track of the max position reached as watch time
      if (slot.contentId != null && pos > slot.watchTime) {
        slot.watchTime = pos;
      }
    });
    player.stream.completed.listen((isCompleted) {
      final id = slot.contentId;
      if (isCompleted && id != null) {
        _trackPlaybackEvent(id, ContentInteractionType.viewCompletion);
      }
    });

    _slots.add(slot);
    return slot;
  }

  void _loadIntoSlot(_PlayerSlot slot, Content content, bool autoPlay) {
    slot.contentId = content.id;
    slot.watchTime = Duration.zero;
    final player = slot.player;
    player.setVolume(100.0);
    player.setPlaylistMode(PlaylistMode.single);
    // A prefetched file plays instantly and without network.
    final source = _prefetcher.localVideoFor(content.mediaUrl) ?? content.mediaUrl;
    player.open(Media(source), play: autoPlay);
    slotsRevision.value++;
  }

  void _releaseSlot(_PlayerSlot slot) {
    final id = slot.contentId;
    if (id == null) return;

    // Log the watch time before unloading
    _trackPlaybackEvent(id, ContentInteractionType.watchDuration, {'durationMs': slot.watchTime.inMilliseconds});

    slot.contentId = null;
    slot.watchTime = Duration.zero;
    // stop() unloads the media and frees its buffers; the mpv handle is kept for reuse.
    slot.player.stop();
    slotsRevision.value++;
  }

  void togglePlayPause(String contentId) {
    final player = _slotFor(contentId)?.player;
    if (player != null) {
      player.state.playing ? player.pause() : player.play();
    }
  }

  void setMute(String contentId, bool mute) {
    _slotFor(contentId)?.player.setVolume(mute ? 0.0 : 100.0);
  }

  /// Unloads every video (e.g. when the feed screen goes away).
  /// Players stay in the pool for reuse; see the class doc for why they are not disposed.
  void disposeAll() {
    for (final slot in _slots) {
      _releaseSlot(slot);
    }
  }

  void _trackPlaybackEvent(String contentId, ContentInteractionType type, [Map<String, dynamic>? extraData]) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _recommendationService.trackEvent(uid, contentId, type, extraData ?? {});
  }
}
