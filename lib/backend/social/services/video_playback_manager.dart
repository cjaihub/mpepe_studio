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
final RouteObserver<ModalRoute<void>> mainFeedRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Separate route observer for the nested `/hub/home` branch Navigator so a
/// single [NavigatorObserver] is never attached to two Navigators simultaneously.
final RouteObserver<ModalRoute<void>> homeBranchRouteObserver =
    RouteObserver<ModalRoute<void>>();

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

  /// True only after the newly loaded media for [generation] has decoded a
  /// real video frame. Prevents a reused slot from flashing black while the
  /// previous video's `state.width` is still non-zero.
  final ValueNotifier<bool> frameReady = ValueNotifier<bool>(false);
}

/// Manages a fixed pool of media_kit Players so only a few videos are loaded
/// at a time (virtualization and prefetching).
class VideoPlaybackManager {
  final RecommendationService _recommendationService;
  final ReelPrefetcher _prefetcher;

  final List<_PlayerSlot> _slots = [];

  static const int maxCachedPlayers = 5;
  static const int playerBufferBytes = 16 * 1024 * 1024;

  final ValueNotifier<int> slotsRevision = ValueNotifier(0);
  final ValueNotifier<bool> activeReelBuffering = ValueNotifier<bool>(false);

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isScreenActive = true;
  bool get isScreenActive => _isScreenActive;
  final ValueNotifier<bool> screenActiveNotifier = ValueNotifier<bool>(true);

  bool _isCallActive = false;
  bool get isCallActive => _isCallActive;

  bool get isSilenced =>
      !_isScreenActive ||
      _isCallActive ||
      MicCoordinator.instance.owner.value != null;

  void _silenceAllSlots() {
    for (final slot in _slots) {
      slot.player.setVolume(0.0);
      slot.player.setRate(1.0);
      if (slot.contentId != null || slot.player.state.playing) {
        slot.player.pause();
      }
    }
    activeReelBuffering.value = false;
    _prefetcher.setActiveReelBuffering(false);
  }

  /// Guarantees that only [_activeContentId] can ever play or output audio,
  /// silencing and pausing every other slot immediately.
  void _enforceSingleAudioOwner() {
    final activeId = _activeContentId;
    for (final slot in _slots) {
      final isCurrent =
          activeId != null && slot.contentId == activeId && !isSilenced;
      if (!isCurrent) {
        if (slot.player.state.volume > 0.0) {
          slot.player.setVolume(0.0);
        }
        if (slot.player.state.playing) {
          slot.player.pause();
        }
        if (slot.player.state.rate != 1.0) {
          slot.player.setRate(1.0);
        }
      }
    }
  }

  void _restoreActiveSlot() {
    _enforceSingleAudioOwner();
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

  void pauseAllSlots({bool clearActive = false}) {
    if (clearActive) {
      _activeContentId = null;
    }
    _silenceAllSlots();
    slotsRevision.value++;
  }

  void _onMicOwnerChanged() {
    final micOwner = MicCoordinator.instance.owner.value;
    if (micOwner != null) {
      _silenceAllSlots();
      slotsRevision.value++;
    } else if (!isSilenced) {
      _restoreActiveSlot();
      slotsRevision.value++;
    }
  }

  void setCallActive(bool inCall) {
    if (_isCallActive == inCall) return;
    _isCallActive = inCall;
    if (inCall || isSilenced) {
      _silenceAllSlots();
      slotsRevision.value++;
    } else {
      _restoreActiveSlot();
      slotsRevision.value++;
    }
  }

  String? _activeContentId;
  String? get activeContentId => _activeContentId;

  bool _pausedActiveForBackground = false;

  late final AppLifecycleListener _lifecycle;
  AppLifecycleListener get lifecycle => _lifecycle;
  Timer? _stallWatchdog;
  Duration _lastStallPosition = Duration.zero;
  int _stallTicks = 0;

  VideoPlaybackManager(this._recommendationService, this._prefetcher) {
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
      _enforceSingleAudioOwner();
      final activeId = _activeContentId;
      if (activeId == null) return;
      final slot = _slotFor(activeId);
      if (slot == null || slot.contentId != activeId || slot.isRecovering) return;

      final p = slot.player;
      final state = p.state;

      if (state.playing) {
        if (state.buffering) {
          _stallTicks++;
          if (_stallTicks >= 3) {
            _recoverStalledSlot(slot);
          }
        } else if (state.position == _lastStallPosition &&
            state.duration > Duration.zero) {
          _stallTicks++;
          if (_stallTicks >= 4) {
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
    if (id == null ||
        url == null ||
        slot.isRecovering ||
        isSilenced ||
        _activeContentId != id) {
      return;
    }

    slot.isRecovering = true;
    _stallTicks = 0;
    try {
      final pos = slot.player.state.position;
      await slot.player.stop();
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

  VideoController? getController(String contentId) =>
      _slotFor(contentId)?.controller;
  Player? getPlayer(String contentId) => _slotFor(contentId)?.player;

  /// Notifies whether the slot for [contentId] has decoded a genuine frame for
  /// this specific video (preventing black flashes when slots are reused).
  ValueNotifier<bool>? getFrameReadyNotifier(String contentId) =>
      _slotFor(contentId)?.frameReady;

  void setLooping(String contentId, bool isLooping) {
    _slotFor(contentId)
        ?.player
        .setPlaylistMode(isLooping ? PlaylistMode.loop : PlaylistMode.single);
  }

  /// Sets playback speed (`0.25x` .. `3.0x`) on the active reel.
  Future<void> setPlaybackSpeed(String contentId, double rate) async {
    final slot = _slotFor(contentId);
    if (slot == null) return;
    final clamped = rate.clamp(0.25, 3.0);
    await slot.player.setRate(clamped);
  }

  /// Steps playback position forward or backward smoothly (e.g. hold-to-rewind).
  Future<void> seekRelative(String contentId, Duration delta) async {
    final slot = _slotFor(contentId);
    if (slot == null) return;
    final p = slot.player;
    final dur = p.state.duration;
    final cur = p.state.position;
    var next = cur + delta;
    if (next < Duration.zero) {
      next = dur > Duration.zero ? dur + next : Duration.zero;
      if (next < Duration.zero) next = Duration.zero;
    } else if (dur > Duration.zero && next > dur) {
      next = Duration.zero;
    }
    await p.seek(next);
  }

  void setScreenActive(bool active) {
    if (_isScreenActive == active) return;
    _isScreenActive = active;
    screenActiveNotifier.value = active;

    if (isSilenced) {
      _silenceAllSlots();
      slotsRevision.value++;
    } else {
      _restoreActiveSlot();
      slotsRevision.value++;
    }
  }

  /// Ensures that [contentId] is the sole playing reel and all other slots
  /// are immediately muted and paused.
  void ensureCurrentPlaying(String contentId) {
    _activeContentId = contentId;
    _enforceSingleAudioOwner();
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
      if ((p.state.width ?? 0) > 0 && !slot.frameReady.value) {
        slot.frameReady.value = true;
      }
      activeReelBuffering.value = p.state.buffering;
      _prefetcher.setActiveReelBuffering(p.state.buffering);
    }
  }

  void initializeAndPreload(List<Content> feed, int currentIndex) {
    if (currentIndex < 0 || currentIndex >= feed.length) return;

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

    // Silence all non-current slots first so two reels never overlap
    _enforceSingleAudioOwner();

    // Load the keep set (current plays, others buffer silently in background)
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
        existing.player.setVolume(canPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
        existing.player.setRate(1.0);
        if (canPlay) {
          activeReelBuffering.value = existing.player.state.buffering;
          _prefetcher.setActiveReelBuffering(existing.player.state.buffering);
          if (existing.player.state.completed) {
            existing.player.seek(Duration.zero);
          }
          if (!existing.player.state.playing) {
            existing.player.play();
          }
          if ((existing.player.state.width ?? 0) > 0 && !existing.frameReady.value) {
            existing.frameReady.value = true;
          }
        } else {
          existing.player.pause();
        }
      }
    }
  }

  _PlayerSlot? _acquireSlot() {
    for (final slot in _slots) {
      if (slot.contentId == null) return slot;
    }
    if (_slots.length >= maxCachedPlayers) return null;

    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: playerBufferBytes),
    );
    final slot = _PlayerSlot(player, VideoController(player));

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
        if ((player.state.width ?? 0) > 0 && !slot.frameReady.value) {
          slot.frameReady.value = true;
        }
      }
    });

    player.stream.width.listen((w) {
      if ((w ?? 0) > 0 && slot.contentId != null && !slot.frameReady.value) {
        slot.frameReady.value = true;
      }
    });

    player.stream.position.listen((pos) {
      final allowed = slot.contentId != null &&
          slot.contentId == _activeContentId &&
          !isSilenced;
      if (!allowed && (player.state.playing || player.state.volume > 0.0)) {
        player.setVolume(0.0);
        player.pause();
        return;
      }
      if (pos > Duration.zero && (player.state.width ?? 0) > 0 && !slot.frameReady.value) {
        slot.frameReady.value = true;
      }
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

  void _loadAudioIntoSlot(
    _PlayerSlot slot,
    String contentId,
    String audioUrl,
    bool autoPlay,
  ) {
    slot.generation++;
    slot.contentId = contentId;
    slot.mediaUrl = audioUrl;
    slot.watchTime = Duration.zero;
    slot.frameReady.value = false;
    final player = slot.player;
    final shouldPlay = autoPlay && !isSilenced && _activeContentId == contentId;
    player.setVolume(shouldPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
    player.setRate(1.0);
    player.setPlaylistMode(PlaylistMode.loop);
    player.open(Media(audioUrl), play: shouldPlay);
    slotsRevision.value++;
  }

  void attachAudioForPhotoReel(String contentId, String audioUrl) {
    final clean = audioUrl.trim();
    if (clean.isEmpty) return;
    final existing = _slotFor(contentId);
    if (existing != null) {
      if (existing.mediaUrl == clean) return;
      _loadAudioIntoSlot(
        existing,
        contentId,
        clean,
        _activeContentId == contentId,
      );
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
    slot.frameReady.value = false;
    final player = slot.player;
    final shouldPlay = autoPlay && !isSilenced && _activeContentId == content.id;
    player.setVolume(shouldPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
    player.setRate(1.0);
    player.setPlaylistMode(PlaylistMode.single);

    Future<void> openMedia(String source) async {
      if (slot.contentId != content.id || slot.generation != gen) return;
      final canStillPlay =
          autoPlay && !isSilenced && _activeContentId == content.id;
      player.setVolume(canStillPlay ? (_isMuted ? 0.0 : 100.0) : 0.0);
      await player.open(Media(source), play: canStillPlay);
      if (slot.contentId != content.id || slot.generation != gen) return;
      if (!canStillPlay) {
        player.setVolume(0.0);
        await player.pause();
      } else if ((player.state.width ?? 0) > 0) {
        slot.frameReady.value = true;
      }
      slotsRevision.value++;
    }

    final local = _prefetcher.localVideoFor(content.mediaUrl);
    if (local != null) {
      unawaited(openMedia(local));
    } else {
      _prefetcher.resolvePlayableSource(content.mediaUrl).then((resolved) {
        unawaited(openMedia(resolved));
      }).catchError((_) {
        unawaited(openMedia(content.mediaUrl));
      });
    }
  }

  void _releaseSlot(_PlayerSlot slot) {
    final id = slot.contentId;
    if (id == null) return;

    _trackPlaybackEvent(
      id,
      ContentInteractionType.watchDuration,
      {'durationMs': slot.watchTime.inMilliseconds},
    );

    slot.contentId = null;
    slot.mediaUrl = null;
    slot.watchTime = Duration.zero;
    slot.frameReady.value = false;
    slot.generation++;
    slot.player.setVolume(0.0);
    slot.player.setRate(1.0);
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
        _enforceSingleAudioOwner();
        player.setVolume(_isMuted ? 0.0 : 100.0);
        player.play();
      }
    }
  }

  void setMute(String contentId, bool mute) {
    _isMuted = mute;
    for (final slot in _slots) {
      if (slot.contentId == contentId &&
          _activeContentId == contentId &&
          !isSilenced) {
        slot.player.setVolume(mute ? 0.0 : 100.0);
      } else {
        slot.player.setVolume(0.0);
      }
    }
  }

  void disposeAll() {
    _activeContentId = null;
    activeReelBuffering.value = false;
    _prefetcher.setActiveReelBuffering(false);
    for (final slot in _slots) {
      _releaseSlot(slot);
    }
  }

  void _trackPlaybackEvent(
    String contentId,
    ContentInteractionType type, [
    Map<String, dynamic>? extraData,
  ]) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _recommendationService.trackEvent(uid, contentId, type, extraData ?? {});
  }
}
