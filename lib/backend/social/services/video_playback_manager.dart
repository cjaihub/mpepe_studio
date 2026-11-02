import 'dart:async';
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

/// Global route observer used by feed screens to detect when another full screen
/// or route is pushed on top, enabling auto-mute and auto-pause.
final RouteObserver<ModalRoute<void>> mainFeedRouteObserver = RouteObserver<ModalRoute<void>>();

/// One reusable media_kit [Player] + [VideoController] pair.
class _PlayerSlot {
  _PlayerSlot(this.player, this.controller);

  final Player player;
  final VideoController controller;

  /// Content currently loaded into this slot, or null when the slot is free.
  String? contentId;
  String? mediaUrl;
  Duration watchTime = Duration.zero;
  int generation = 0;
  bool isRecovering = false;
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

  /// Notifies whether the active reel is currently buffering so the UI
  /// can show a subtle indicator and the prefetcher can throttle deep jobs.
  final ValueNotifier<bool> activeReelBuffering = ValueNotifier<bool>(false);

  /// Global mute state applied across reel transitions.
  bool _isMuted = false;
  bool get isMuted => _isMuted;

  /// Whether the reels screen is currently the active on-screen view.
  /// When false, all video audio is forced to 0.0 (auto-muted) and playback paused.
  bool _isScreenActive = true;
  bool get isScreenActive => _isScreenActive;
  final ValueNotifier<bool> screenActiveNotifier = ValueNotifier<bool>(true);

  /// Active content currently on screen.
  String? _activeContentId;

  /// Slot that was playing when the app went to the background.
  _PlayerSlot? _pausedByLifecycle;

  late final AppLifecycleListener _lifecycle;
  AppLifecycleListener get lifecycle => _lifecycle;
  Timer? _stallWatchdog;
  Duration _lastStallPosition = Duration.zero;
  int _stallTicks = 0;

  VideoPlaybackManager(this._recommendationService, this._prefetcher) {
    // The Flutter engine outlives MainActivity on Android, so the feed can stay
    // mounted after the app is closed: keep it silent while hidden or paused.
    _lifecycle = AppLifecycleListener(
      onPause: _pauseForBackground,
      onInactive: _pauseForBackground,
      onHide: _pauseForBackground,
      onResume: _resumeFromBackground,
      onShow: _resumeFromBackground,
    );
    _startStallWatchdog();
  }

  void _startStallWatchdog() {
    _stallWatchdog?.cancel();
    _stallWatchdog = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_isScreenActive) return;
      final activeId = _activeContentId;
      if (activeId == null) return;
      final slot = _slotFor(activeId);
      if (slot == null || slot.contentId != activeId || slot.isRecovering) return;

      final p = slot.player;
      final state = p.state;

      if (state.playing) {
        if (state.buffering) {
          _stallTicks++;
          if (_stallTicks >= 3) { // ~4.5 seconds stalled
            _recoverStalledSlot(slot);
          }
        } else if (state.position == _lastStallPosition && state.duration > Duration.zero) {
          _stallTicks++;
          if (_stallTicks >= 4) { // Frozen frame
            _recoverStalledSlot(slot);
          }
        } else {
          _stallTicks = 0;
          _lastStallPosition = state.position;
        }
      } else {
        _stallTicks = 0;
      }
    });
  }

  Future<void> _recoverStalledSlot(_PlayerSlot slot) async {
    final id = slot.contentId;
    final url = slot.mediaUrl;
    if (id == null || url == null || slot.isRecovering || !_isScreenActive) return;

    slot.isRecovering = true;
    _stallTicks = 0;
    try {
      debugPrint('[VideoPlaybackManager] recovering stalled reel: $id');
      final pos = slot.player.state.position;
      await slot.player.stop();
      // If we loaded from a local cached file, evict in case of corruption
      await _prefetcher.evictCorruptVideo(url);
      if (slot.contentId == id && _isScreenActive) {
        await slot.player.open(Media(url), play: true);
        if (pos > Duration.zero) {
          await slot.player.seek(pos);
        }
      }
    } catch (e) {
      debugPrint('[VideoPlaybackManager] stall recovery failed: $e');
    } finally {
      slot.isRecovering = false;
    }
  }

  void _pauseForBackground() {
    for (final slot in _slots) {
      slot.player.setVolume(0.0);
      if (slot.contentId != null && slot.player.state.playing) {
        _pausedByLifecycle = slot;
        slot.player.pause();
      }
    }
  }

  void _resumeFromBackground() {
    final slot = _pausedByLifecycle;
    _pausedByLifecycle = null;
    if (!_isScreenActive) return;
    if (slot != null && slot.contentId != null) {
      slot.player.setVolume(_isMuted ? 0.0 : 100.0);
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

  /// Controls active screen visibility. When the user navigates away from the
  /// reels feed (tabs away, pushes a new route, opens a sheet/modal, minimizes app),
  /// [setScreenActive(false)] forces volume to 0.0 (auto-mute) and pauses playback.
  /// When returning, [setScreenActive(true)] restores audio and playback.
  void setScreenActive(bool active) {
    if (_isScreenActive == active) return;
    _isScreenActive = active;
    screenActiveNotifier.value = active;
    debugPrint('[VideoPlaybackManager] setScreenActive: $active (muted: $_isMuted, activeContent: $_activeContentId)');

    if (!active) {
      // Force-mute all slots and pause any playing video
      for (final slot in _slots) {
        slot.player.setVolume(0.0);
        if (slot.player.state.playing) {
          slot.player.pause();
        }
      }
      activeReelBuffering.value = false;
      _prefetcher.setActiveReelBuffering(false);
      slotsRevision.value++;
    } else {
      // Restore current video volume and resume playback (honoring user's manual mute choice)
      if (_activeContentId != null) {
        final slot = _slotFor(_activeContentId!);
        if (slot != null) {
          slot.player.setVolume(_isMuted ? 0.0 : 100.0);
          if (slot.player.state.completed) {
            slot.player.seek(Duration.zero);
          }
          if (!slot.player.state.playing) {
            slot.player.play();
          }
          activeReelBuffering.value = slot.player.state.buffering;
          _prefetcher.setActiveReelBuffering(slot.player.state.buffering);
        }
      }
      slotsRevision.value++;
    }
  }

  /// Ensures that the active reel is actively playing without stalling
  void ensureCurrentPlaying(String contentId) {
    _activeContentId = contentId;
    final slot = _slotFor(contentId);
    if (slot != null) {
      final p = slot.player;
      if (!_isScreenActive) {
        p.setVolume(0.0);
        if (p.state.playing) {
          p.pause();
        }
        return;
      }
      p.setVolume(_isMuted ? 0.0 : 100.0);
      if (p.state.completed) {
        p.seek(Duration.zero);
      }
      if (!p.state.playing) {
        p.play();
      }
      activeReelBuffering.value = p.state.buffering;
      _prefetcher.setActiveReelBuffering(p.state.buffering);
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
    _activeContentId = currentId;

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
        // Strict audio isolation: only current reel plays audio when screen is active
        existing.player.setVolume((isCurrent && _isScreenActive) ? (_isMuted ? 0.0 : 100.0) : 0.0);
        // Play if current and screen is active, pause if preloaded background buffer or screen inactive
        if (isCurrent && _isScreenActive) {
          activeReelBuffering.value = existing.player.state.buffering;
          _prefetcher.setActiveReelBuffering(existing.player.state.buffering);
          if (existing.player.state.completed) {
            existing.player.seek(Duration.zero);
          }
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

    player.stream.buffering.listen((isBuffering) {
      if (slot.contentId == _activeContentId) {
        activeReelBuffering.value = isBuffering;
        _prefetcher.setActiveReelBuffering(isBuffering);
      }
    });

    player.stream.error.listen((err) {
      debugPrint('[VideoPlaybackManager] player error on ${slot.contentId}: $err');
      final url = slot.mediaUrl;
      if (url != null) {
        unawaited(_prefetcher.evictCorruptVideo(url));
        if (slot.contentId != null && !slot.isRecovering) {
          _recoverStalledSlot(slot);
        }
      }
    });

    _slots.add(slot);
    return slot;
  }

  void _loadIntoSlot(_PlayerSlot slot, Content content, bool autoPlay) {
    final gen = ++slot.generation;
    slot.contentId = content.id;
    slot.mediaUrl = content.mediaUrl;
    slot.watchTime = Duration.zero;
    final player = slot.player;
    final shouldPlay = autoPlay && _isScreenActive;
    // Strict audio isolation: only active reel gets volume if screen is active
    player.setVolume(shouldPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
    player.setPlaylistMode(PlaylistMode.single);

    // If prefetcher has a local copy right now, open immediately
    final local = _prefetcher.localVideoFor(content.mediaUrl);
    if (local != null) {
      player.open(Media(local), play: shouldPlay);
      slotsRevision.value++;
    } else {
      // Open network source immediately for zero startup latency, then resolve local cache
      player.open(Media(content.mediaUrl), play: shouldPlay);
      slotsRevision.value++;

      _prefetcher.resolvePlayableSource(content.mediaUrl).then((resolved) {
        if (resolved != content.mediaUrl &&
            slot.contentId == content.id &&
            slot.generation == gen &&
            !player.state.playing) {
          player.open(Media(resolved), play: shouldPlay);
        }
      }).catchError((_) {});
    }
  }

  void _releaseSlot(_PlayerSlot slot) {
    final id = slot.contentId;
    if (id == null) return;

    // Log the watch time before unloading
    _trackPlaybackEvent(id, ContentInteractionType.watchDuration, {'durationMs': slot.watchTime.inMilliseconds});

    slot.contentId = null;
    slot.mediaUrl = null;
    slot.watchTime = Duration.zero;
    slot.generation++;
    // stop() unloads the media and frees its buffers; the mpv handle is kept for reuse.
    slot.player.stop();
    slotsRevision.value++;
  }

  void togglePlayPause(String contentId) {
    final slot = _slotFor(contentId);
    if (slot != null) {
      final player = slot.player;
      if (player.state.playing) {
        player.pause();
      } else {
        player.setVolume((_isMuted || !_isScreenActive) ? 0.0 : 100.0);
        player.play();
      }
    }
  }

  void setMute(String contentId, bool mute) {
    _isMuted = mute;
    for (final slot in _slots) {
      if (slot.contentId == contentId && _isScreenActive) {
        slot.player.setVolume(mute ? 0.0 : 100.0);
      } else {
        slot.player.setVolume(0.0);
      }
    }
  }

  /// Unloads every video (e.g. when the feed screen goes away).
  /// Players stay in the pool for reuse; see the class doc for why they are not disposed.
  void disposeAll() {
    _activeContentId = null;
    activeReelBuffering.value = false;
    _prefetcher.setActiveReelBuffering(false);
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
