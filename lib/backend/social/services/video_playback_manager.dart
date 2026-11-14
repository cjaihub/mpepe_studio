import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/content.dart';
import 'recommendation_service.dart';
import '../../../feed/services/reel_prefetcher.dart';
import '../../../shared/audio/mic_coordinator.dart';

final videoPlaybackManagerProvider = Provider<VideoPlaybackManager>((ref) {
  final manager = VideoPlaybackManager(
    ref.read(recommendationServiceProvider),
    ref.read(reelPrefetcherProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Global route observer used by root routes to detect when another full screen
/// or route is pushed on top, enabling auto-mute and auto-pause.
final RouteObserver<ModalRoute<void>> mainFeedRouteObserver = RouteObserver<ModalRoute<void>>();

/// Separate route observer for the nested `/hub/home` branch Navigator so a
/// single [NavigatorObserver] is never attached to two Navigators simultaneously.
final RouteObserver<ModalRoute<void>> homeBranchRouteObserver = RouteObserver<ModalRoute<void>>();

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

  /// Warm players: current, next, previous, next+1, next+2. Each holds at most
  /// [playerBufferBytes] of demuxed video, so the pool stays under ~80 MB
  /// of buffers on mid-range phones (media_kit's default is 32 MB each).
  static const int maxCachedPlayers = 5;
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

  /// When true, a phone or video call is active (ringing, connecting, or connected).
  /// All video playback and audio across feeds is forced silent (0.0 volume) and paused.
  bool _isCallActive = false;
  bool get isCallActive => _isCallActive;

  /// True whenever reels must stay completely silent and paused:
  /// screen not active, active phone/video call, or any microphone session active.
  bool get isSilenced =>
      !_isScreenActive ||
      _isCallActive ||
      MicCoordinator.instance.owner.value != null;

  void _silenceAllSlots() {
    for (final slot in _slots) {
      slot.player.setVolume(0.0);
      if (slot.contentId != null || slot.player.state.playing) {
        slot.player.pause();
      }
    }
    activeReelBuffering.value = false;
    _prefetcher.setActiveReelBuffering(false);
  }

  void _restoreActiveSlot() {
    if (isSilenced || _activeContentId == null) return;
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

  /// Pauses and mutes all cached slots immediately (e.g. when scrolling onto a
  /// non-video card like a Live slot or photo).
  void pauseAllSlots({bool clearActive = false}) {
    if (clearActive) {
      _activeContentId = null;
    }
    _silenceAllSlots();
    slotsRevision.value++;
  }

  void _onMicOwnerChanged() {
    final micOwner = MicCoordinator.instance.owner.value;
    debugPrint('[VideoPlaybackManager] mic owner changed: $micOwner');
    if (micOwner != null) {
      _silenceAllSlots();
      slotsRevision.value++;
    } else if (!isSilenced) {
      _restoreActiveSlot();
      slotsRevision.value++;
    }
  }

  /// Sets whether a live phone/video call is active. When true, all background video
  /// audio is auto-muted and playback is paused. When false (call finished), playback
  /// and volume are cleanly restored if the feed is on screen.
  void setCallActive(bool inCall) {
    if (_isCallActive == inCall) return;
    _isCallActive = inCall;
    debugPrint('[VideoPlaybackManager] setCallActive: $inCall');

    if (inCall || isSilenced) {
      _silenceAllSlots();
      slotsRevision.value++;
    } else {
      _restoreActiveSlot();
      slotsRevision.value++;
    }
  }

  /// Active content currently on screen.
  String? _activeContentId;
  String? get activeContentId => _activeContentId;

  /// True when the active reel was playing right before the app entered background.
  bool _pausedActiveForBackground = false;

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
    MicCoordinator.instance.owner.addListener(_onMicOwnerChanged);
    _startStallWatchdog();
  }

  void dispose() {
    MicCoordinator.instance.owner.removeListener(_onMicOwnerChanged);
    _stallWatchdog?.cancel();
    _lifecycle.dispose();
  }

  void _startStallWatchdog() {
    _stallWatchdog?.cancel();
    _stallWatchdog = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (isSilenced) return;
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
    if (id == null || url == null || slot.isRecovering || isSilenced || _activeContentId != id) return;

    slot.isRecovering = true;
    _stallTicks = 0;
    try {
      debugPrint('[VideoPlaybackManager] recovering stalled reel: $id');
      final pos = slot.player.state.position;
      await slot.player.stop();
      // If we loaded from a local cached file, evict in case of corruption
      await _prefetcher.evictCorruptVideo(url);
      if (slot.contentId == id) {
        final canPlay = _activeContentId == id && !isSilenced;
        slot.player.setVolume(canPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
        await slot.player.open(Media(url), play: canPlay);
        if (pos > Duration.zero && slot.contentId == id) {
          await slot.player.seek(pos);
        }
        if (slot.contentId != id || _activeContentId != id || isSilenced) {
          slot.player.setVolume(0.0);
          await slot.player.pause();
        }
      }
    } catch (e) {
      debugPrint('[VideoPlaybackManager] stall recovery failed: $e');
    } finally {
      slot.isRecovering = false;
    }
  }

  void _pauseForBackground() {
    final activeId = _activeContentId;
    if (activeId != null) {
      final activeSlot = _slotFor(activeId);
      if (activeSlot != null && activeSlot.player.state.playing) {
        _pausedActiveForBackground = true;
      }
    }
    _silenceAllSlots();
  }

  void _resumeFromBackground() {
    final shouldResume = _pausedActiveForBackground;
    _pausedActiveForBackground = false;
    if (isSilenced) return;
    if (shouldResume) {
      _restoreActiveSlot();
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
    debugPrint('[VideoPlaybackManager] setScreenActive: $active (callActive: $_isCallActive, mic: ${MicCoordinator.instance.owner.value}, muted: $_isMuted, activeContent: $_activeContentId)');

    if (isSilenced) {
      _silenceAllSlots();
      slotsRevision.value++;
    } else {
      _restoreActiveSlot();
      slotsRevision.value++;
    }
  }

  /// Ensures that the active reel is actively playing without stalling
  void ensureCurrentPlaying(String contentId) {
    _activeContentId = contentId;
    for (final s in _slots) {
      if (s.contentId != contentId) {
        s.player.setVolume(0.0);
        if (s.contentId != null || s.player.state.playing) {
          s.player.pause();
        }
      }
    }
    final slot = _slotFor(contentId);
    if (slot != null) {
      final p = slot.player;
      if (isSilenced) {
        p.setVolume(0.0);
        p.pause();
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
    final currentContent = feed[currentIndex];
    final currentId = currentContent.id;
    _activeContentId = currentId;

    if (currentContent.isPhotoOrCarousel) {
      activeReelBuffering.value = false;
      _prefetcher.setActiveReelBuffering(false);
    }

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
        if (content.isPhotoOrCarousel) {
          final audioUrl = content.mediaMetadata.audioTrackUrl?.trim() ?? '';
          if (audioUrl.isEmpty) continue;
          final slot = _acquireSlot();
          if (slot == null) continue;
          _loadAudioIntoSlot(slot, content.id, audioUrl, isCurrent);
          continue;
        }
        final slot = _acquireSlot();
        if (slot == null) continue;
        _loadIntoSlot(slot, content, isCurrent);
      } else {
        final canPlay = isCurrent && !isSilenced;
        // Strict audio isolation: only current reel plays audio when screen is active & unsilenced
        existing.player.setVolume(canPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
        // Play if current and unsilenced, pause if preloaded background buffer or silenced
        if (canPlay) {
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

    // Ironclad playback & audio guard: if libmpv finishes async open/demux after
    // the user scrolled away, switched tabs, or activated a mic/call, silence & pause immediately.
    player.stream.playing.listen((isPlaying) {
      if (!isPlaying) return;
      final allowed = slot.contentId != null &&
          slot.contentId == _activeContentId &&
          !isSilenced;
      if (!allowed) {
        player.setVolume(0.0);
        player.pause();
      } else {
        player.setVolume(_isMuted ? 0.0 : 100.0);
      }
    });

    // Track real playback events for whichever content the slot currently holds
    player.stream.position.listen((pos) {
      final allowed = slot.contentId != null &&
          slot.contentId == _activeContentId &&
          !isSilenced;
      if (!allowed && (player.state.playing || player.state.volume > 0.0)) {
        player.setVolume(0.0);
        player.pause();
        return;
      }
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
      if (slot.contentId == _activeContentId && !isSilenced) {
        activeReelBuffering.value = isBuffering;
        _prefetcher.setActiveReelBuffering(isBuffering);
      }
    });

    player.stream.error.listen((err) {
      debugPrint('[VideoPlaybackManager] player error on ${slot.contentId}: $err');
      final url = slot.mediaUrl;
      if (url != null) {
        unawaited(_prefetcher.evictCorruptVideo(url));
        if (slot.contentId != null &&
            slot.contentId == _activeContentId &&
            !isSilenced &&
            !slot.isRecovering) {
          _recoverStalledSlot(slot);
        }
      }
    });

    _slots.add(slot);
    return slot;
  }

  void _loadAudioIntoSlot(_PlayerSlot slot, String contentId, String audioUrl, bool autoPlay) {
    slot.generation++;
    slot.contentId = contentId;
    slot.mediaUrl = audioUrl;
    slot.watchTime = Duration.zero;
    final player = slot.player;
    final shouldPlay = autoPlay && !isSilenced && _activeContentId == contentId;
    player.setVolume(shouldPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
    player.setPlaylistMode(PlaylistMode.loop);
    player.open(Media(audioUrl), play: shouldPlay);
    slotsRevision.value++;
  }

  /// Attaches and plays resolved music track audio for a photo or multi-photo
  /// carousel reel once its `musicId` is resolved.
  void attachAudioForPhotoReel(String contentId, String audioUrl) {
    final clean = audioUrl.trim();
    if (clean.isEmpty) return;
    final existing = _slotFor(contentId);
    if (existing != null) {
      if (existing.mediaUrl == clean) return;
      _loadAudioIntoSlot(existing, contentId, clean, _activeContentId == contentId);
      return;
    }
    if (_activeContentId != contentId) return;
    final slot = _acquireSlot();
    if (slot == null) return;
    _loadAudioIntoSlot(slot, contentId, clean, true);
  }

  void _loadIntoSlot(_PlayerSlot slot, Content content, bool autoPlay) {
    final gen = ++slot.generation;
    slot.contentId = content.id;
    slot.mediaUrl = content.mediaUrl;
    slot.watchTime = Duration.zero;
    final player = slot.player;
    final shouldPlay = autoPlay && !isSilenced && _activeContentId == content.id;
    // Strict audio isolation: only active reel gets volume if screen is active & unsilenced
    player.setVolume(shouldPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
    player.setPlaylistMode(PlaylistMode.single);

    // If prefetcher has a local copy right now, open immediately
    final local = _prefetcher.localVideoFor(content.mediaUrl);
    if (local != null) {
      player.open(Media(local), play: shouldPlay);
      slotsRevision.value++;
    } else {
      // Check disk cache with a tiny non-blocking timeout first so we never
      // double-open the same slot when a file is already on disk.
      _prefetcher.resolvePlayableSource(content.mediaUrl).then((resolved) {
        if (slot.contentId != content.id || slot.generation != gen) return;
        final canStillPlay = autoPlay && !isSilenced && _activeContentId == content.id;
        player.setVolume(canStillPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
        player.open(Media(resolved), play: canStillPlay);
        slotsRevision.value++;
      }).catchError((_) {
        if (slot.contentId != content.id || slot.generation != gen) return;
        final canStillPlay = autoPlay && !isSilenced && _activeContentId == content.id;
        player.setVolume(canStillPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
        player.open(Media(content.mediaUrl), play: canStillPlay);
        slotsRevision.value++;
      });
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
    slot.player.setVolume(0.0);
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
      } else if (!isSilenced && _activeContentId == contentId) {
        player.setVolume(_isMuted ? 0.0 : 100.0);
        player.play();
      }
    }
  }

  void setMute(String contentId, bool mute) {
    _isMuted = mute;
    for (final slot in _slots) {
      if (slot.contentId == contentId && _activeContentId == contentId && !isSilenced) {
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
