import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/content.dart';
import 'recommendation_service.dart';
import 'reels/reel_playback_config.dart';
import 'reels/reel_segment_cache.dart';

final videoPlaybackManagerProvider = Provider<VideoPlaybackManager>((ref) {
  final manager = VideoPlaybackManager(ref.read(recommendationServiceProvider));
  ref.onDispose(manager.shutdown);
  return manager;
});

/// One reusable player. Players are expensive to create, so the pool keeps
/// three of them alive and points them at new videos as the user swipes.
class _Slot {
  _Slot(this.player) : controller = VideoController(player);

  final Player player;
  final VideoController controller;
  final List<StreamSubscription<dynamic>> subs = [];

  String? contentId;
  int generation = 0; // Bumped on every open; stale async work checks it.
  bool firstFrame = false;
  Duration maxPosition = Duration.zero;
  int rebuffers = 0;
  int rungIndex = 0;
  bool fromCache = false;
}

/// Plays the reels feed.
///
/// * Pool of 3 reused players: current, next, previous.
/// * HLS goes through [ReelSegmentCache], a shared disk cache, and the first
///   segments of upcoming videos are prefetched so a swipe starts from disk.
/// * Start quality is chosen per video from network type and measured speed.
/// * [isFirstFrameShown] lets the UI keep the preview until video is really
///   playing, so there is no black flash.
/// * Logs time to first frame, rebuffers and cache use to Analytics.
class VideoPlaybackManager extends ChangeNotifier {
  VideoPlaybackManager(this._recommendationService);

  static const int poolSize = 3;

  final RecommendationService _recommendationService;
  final ReelNetwork _network = ReelNetwork();
  ReelPlaybackConfig config = ReelPlaybackConfig.defaults;
  ReelSegmentCache? _cache;

  final List<_Slot> _slots = [];
  final Map<String, _Slot> _byId = {};
  String? _currentId;
  final Stopwatch _sinceSwipe = Stopwatch();
  bool _muted = false;
  bool _disposed = false;

  int _prefetchGeneration = 0;
  final Set<String> _prefetchedIds = {};
  final Set<String> _playedIds = {};

  Future<void>? _ready;

  /// Loads Remote Config, network state and the disk cache. Safe to call
  /// many times; the feed screen awaits it before the first video.
  Future<void> ensureReady() => _ready ??= _init();

  Future<void> _init() async {
    config = await ReelPlaybackConfig.load();
    try {
      await _network.start();
    } catch (e) {
      debugPrint('VideoPlaybackManager: connectivity unavailable ($e)');
    }
    final cache = ReelSegmentCache(maxBytes: config.cacheMb * 1024 * 1024);
    try {
      await cache.start();
      _cache = cache;
    } catch (e) {
      // Playback still works straight from the CDN.
      debugPrint('VideoPlaybackManager: cache unavailable ($e)');
    }
  }

  VideoController? getController(String contentId) => _byId[contentId]?.controller;

  bool isFirstFrameShown(String contentId) => _byId[contentId]?.firstFrame ?? false;

  bool get isMuted => _muted;

  // ---------------------------------------------------------------------------
  // Window management
  // ---------------------------------------------------------------------------

  /// Call on load and on every page change.
  void initializeAndPreload(List<Content> feed, int currentIndex) {
    if (_disposed || feed.isEmpty) return;
    currentIndex = currentIndex.clamp(0, feed.length - 1);
    final current = feed[currentIndex];

    // Priority order: current first, then next (more likely than previous).
    final window = <Content>[
      current,
      if (currentIndex + 1 < feed.length) feed[currentIndex + 1],
      if (currentIndex > 0) feed[currentIndex - 1],
    ];
    final keep = window.map((c) => c.id).toSet();

    // Release slots that left the window (logging their watch data).
    for (final id in _byId.keys.where((id) => !keep.contains(id)).toList()) {
      _release(_byId[id]!);
    }

    if (_currentId != current.id) {
      _currentId = current.id;
      _sinceSwipe
        ..reset()
        ..start();
      _playedIds.add(current.id);
      _recommendationService.trackEvent(
          currentSocialUid(), current.id, ContentInteractionType.impression, {});
    }

    for (final content in window) {
      final slot = _byId[content.id] ?? _open(content);
      if (slot == null) continue;
      if (content.id == _currentId) {
        slot.player.play();
      } else {
        slot.player.pause();
      }
    }

    _prefetchAhead(feed, currentIndex);
    notifyListeners();
  }

  _Slot? _takeFreeSlot() {
    for (final s in _slots) {
      if (s.contentId == null) return s;
    }
    if (_slots.length < poolSize) {
      final slot = _Slot(Player(
        configuration: const PlayerConfiguration(
          // Reels are short; a smaller demuxer buffer per player saves memory
          // with three players alive.
          bufferSize: 8 * 1024 * 1024,
        ),
      ));
      _wire(slot);
      _slots.add(slot);
      return slot;
    }
    return null;
  }

  void _wire(_Slot slot) {
    final p = slot.player;
    p.setPlaylistMode(PlaylistMode.single); // Loop like a reel.
    slot.subs.add(p.stream.position.listen((pos) {
      if (slot.contentId == null) return;
      if (pos > slot.maxPosition) slot.maxPosition = pos;
      // The first real progress after an open means a frame is on screen.
      // The upper bound ignores a stale position from the previous video.
      if (!slot.firstFrame && pos > Duration.zero && pos < const Duration(seconds: 3)) {
        slot.firstFrame = true;
        if (slot.contentId == _currentId) _logFirstFrame(slot);
        notifyListeners();
      }
    }));
    slot.subs.add(p.stream.buffering.listen((buffering) {
      if (buffering && slot.firstFrame && slot.contentId == _currentId && p.state.playing) {
        slot.rebuffers++;
      }
    }));
    slot.subs.add(p.stream.completed.listen((done) {
      final id = slot.contentId;
      if (done && id != null) {
        _recommendationService.trackEvent(
            currentSocialUid(), id, ContentInteractionType.viewCompletion, {});
      }
    }));
    slot.subs.add(p.stream.error.listen((e) => debugPrint('Reel player error: $e')));
  }

  _Slot? _open(Content content) {
    final slot = _takeFreeSlot();
    if (slot == null) return null;
    final gen = ++slot.generation;
    slot
      ..contentId = content.id
      ..firstFrame = false
      ..maxPosition = Duration.zero
      ..rebuffers = 0;
    _byId[content.id] = slot;
    slot.player.setVolume(_muted ? 0 : 100);
    unawaited(_openMedia(slot, content, gen));
    return slot;
  }

  Future<void> _openMedia(_Slot slot, Content content, int gen) async {
    var url = content.mediaUrl;
    final cache = _cache;
    if (cache != null && _isHls(url)) {
      slot.rungIndex = _chooseRung().index;
      final variant = await cache.resolveVariant(url, slot.rungIndex);
      if (slot.generation != gen) return; // Slot was reused meanwhile.
      url = cache.playbackUrl(variant ?? url);
      slot.fromCache = _prefetchedIds.contains(content.id);
    }
    await slot.player.open(Media(url), play: content.id == _currentId);
    if (slot.generation != gen) return;
    // State may have changed while opening (fast swipes).
    if (content.id == _currentId) {
      slot.player.play();
    } else {
      slot.player.pause();
    }
  }

  void _release(_Slot slot) {
    final id = slot.contentId;
    if (id == null) return;
    _recommendationService.trackEvent(currentSocialUid(), id, ContentInteractionType.watchDuration, {
      'durationMs': slot.maxPosition.inMilliseconds,
    });
    if (_playedIds.contains(id)) {
      _log('reel_view', {
        'content_id': id,
        'watch_ms': slot.maxPosition.inMilliseconds,
        'rebuffers': slot.rebuffers,
        'rung': slot.rungIndex,
      });
    }
    _byId.remove(id);
    slot.generation++;
    slot
      ..contentId = null
      ..firstFrame = false;
    slot.player.pause();
  }

  // ---------------------------------------------------------------------------
  // Quality and prefetch
  // ---------------------------------------------------------------------------

  bool _isHls(String url) => Uri.tryParse(url)?.path.endsWith('.m3u8') ?? false;

  /// Start rung for the next open: network type sets the base, measured
  /// speed moves it one step. Cellular never goes above mid.
  ReelRung _chooseRung() {
    final cellular = _network.isCellular;
    var rung = cellular ? config.startRungCellular : config.startRungWifi;
    final kbps = _cache?.estimatedKbps ?? 0;
    if (kbps > 0) {
      if (kbps < 1500) {
        rung = ReelRung.low;
      } else if (kbps > 6000 && rung.index < ReelRung.high.index) {
        rung = ReelRung.values[rung.index + 1];
      }
    }
    if (cellular && rung == ReelRung.high) rung = ReelRung.mid;
    return rung;
  }

  void _prefetchAhead(List<Content> feed, int index) {
    final cache = _cache;
    if (cache == null) return;
    final gen = ++_prefetchGeneration;
    final segments =
        _network.isCellular ? config.preloadSegmentsCellular : config.preloadSegments;
    final upcoming = feed
        .skip(index + 1)
        .take(config.preloadAhead)
        .where((c) => _isHls(c.mediaUrl))
        .toList();
    if (upcoming.isEmpty || segments == 0) return;
    final rung = _chooseRung().index;
    unawaited(() async {
      // One at a time, nearest first: the next video matters most, and a
      // new swipe cancels the rest instead of wasting data.
      for (final c in upcoming) {
        if (gen != _prefetchGeneration || _disposed) return;
        await cache.prefetch(c.mediaUrl, rung, segments,
            cancelled: () => gen != _prefetchGeneration || _disposed);
        _prefetchedIds.add(c.id);
      }
    }());
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  void togglePlayPause(String contentId) {
    final player = _byId[contentId]?.player;
    if (player == null) return;
    player.state.playing ? player.pause() : player.play();
  }

  void setMute(bool mute) {
    _muted = mute;
    for (final s in _slots) {
      s.player.setVolume(mute ? 0 : 100);
    }
    notifyListeners();
  }

  /// App went to background or the feed is covered by another screen.
  void pauseAll() {
    for (final s in _slots) {
      s.player.pause();
    }
  }

  void resumeCurrent() {
    final id = _currentId;
    if (id != null) _byId[id]?.player.play();
  }

  /// Feed screen closed: log, release players and stop prefetching. The
  /// disk cache stays for next time.
  void disposeAll() {
    _prefetchGeneration++;
    for (final slot in _slots) {
      _release(slot);
    }
    for (final slot in _slots) {
      for (final s in slot.subs) {
        s.cancel();
      }
      slot.player.dispose();
    }
    _slots.clear();
    _byId.clear();
    _currentId = null;
    _logSession();
  }

  /// Provider disposal.
  void shutdown() {
    disposeAll();
    _disposed = true;
    _cache?.stop();
    dispose();
  }

  // ---------------------------------------------------------------------------
  // Metrics
  // ---------------------------------------------------------------------------

  void _logFirstFrame(_Slot slot) {
    _log('reel_first_frame', {
      'ms': _sinceSwipe.elapsedMilliseconds,
      'rung': slot.rungIndex,
      'prefetched': slot.fromCache ? 1 : 0,
      'cellular': _network.isCellular ? 1 : 0,
    });
  }

  void _logSession() {
    final cache = _cache;
    if (_playedIds.isEmpty && _prefetchedIds.isEmpty) return;
    _log('reel_session', {
      'played': _playedIds.length,
      'prefetched_unwatched': _prefetchedIds.difference(_playedIds).length,
      'cache_hit_kb': (cache?.hitBytes ?? 0) ~/ 1024,
      'network_kb': (cache?.missBytes ?? 0) ~/ 1024,
      'est_kbps': (cache?.estimatedKbps ?? 0).round(),
    });
    _playedIds.clear();
    _prefetchedIds.clear();
    cache?.hitBytes = 0;
    cache?.missBytes = 0;
  }

  void _log(String name, Map<String, Object> params) {
    try {
      FirebaseAnalytics.instance.logEvent(name: name, parameters: params).ignore();
    } catch (_) {
      // Analytics is best effort.
    }
  }
}
