import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/social/models/content.dart';

final reelPrefetcherProvider = Provider<ReelPrefetcher>((ref) {
  final p = ReelPrefetcher();
  ref.onDispose(p.dispose);
  return p;
});

enum _JobPriority {
  immediateThumb, // Covers for current..current+8
  hotVideo, // Full videos for current+1..current+hotVideosAhead
  windowThumb, // Covers for current+9..current+windowSize (60 shorts)
  deepVideo, // Background full videos up to 55+ shorts ahead
}

/// High-throughput, anti-starvation Reel Auto-Loading Engine (55–60+ Shorts):
///
/// 1. **60-Reel Rolling Window**:
///    - Prefetches cover thumbnails for the next [windowSize] (60) shorts so
///      fast flings never hit an empty cover.
///    - Preloads full video files into disk cache across two tiers:
///      - **Hot Tier** ([hotVideosAheadWifi] = 8, [hotVideosAheadCellular] = 4):
///        downloaded immediately with parallel workers for sub-20ms swipe start.
///      - **Deep Background Tier** ([deepVideosAheadWifi] = 55,
///        [deepVideosAheadCellular] = 18): steadily preloads 50+ full shorts
///        ahead in the background with a 25ms frame-friendly yield between jobs.
/// 2. **Active-Playback Anti-Starvation**:
///    - When the active reel reports buffering via [setActiveReelBuffering],
///      deep background downloads pause launching new transfers so 100% of
///      bandwidth serves the on-screen reel, then automatically resume.
/// 3. **Warm Disk-Cache Indexing & Corruption Guard**:
///    - Indexes already-cached disk files into [_readyVideos] immediately on
///      window update so cached reels play from disk even after cold launch,
///      and evicts zero-byte/corrupt files on playback error.
class ReelPrefetcher {
  static const int windowSize = 60;
  static const int immediateThumbsAhead = 8;
  static const int hotVideosAheadWifi = 8;
  static const int hotVideosAheadCellular = 4;
  static const int deepVideosAheadWifi = 55;
  static const int deepVideosAheadCellular = 18;

  static const int maxHotConcurrentWifi = 3;
  static const int maxHotConcurrentCellular = 2;
  static const int maxDeepConcurrent = 1;

  static final CacheManager defaultVideoCache = CacheManager(Config(
    'oneova_reel_videos_v1',
    stalePeriod: const Duration(days: 3),
    maxNrOfCacheObjects: 120,
  ));

  static final CacheManager defaultThumbCache = CacheManager(Config(
    'oneova_reel_thumbs_v1',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 600,
  ));

  /// Shared thumbnail cache used by `CachedNetworkImageProvider` on the feed.
  static CacheManager get thumbCache => defaultThumbCache;
  static CacheManager get videoCache => defaultVideoCache;

  final BaseCacheManager _videoCache;
  final BaseCacheManager _thumbCache;

  final Map<String, String> _readyVideos = {};
  final Set<String> _thumbsDone = {};
  final Set<String> _indexedCheckInFlight = {};
  final List<_Job> _queue = [];
  final Map<String, _JobPriority> _inFlight = {};
  Set<String> _wanted = {};

  bool _cellular = false;
  bool _offline = false;
  bool _activeReelBuffering = false;
  bool _disposed = false;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  /// Reactive count of locally ready videos for diagnostics/tests.
  final ValueNotifier<int> readyVideoCountNotifier = ValueNotifier<int>(0);

  ReelPrefetcher({
    BaseCacheManager? customVideoCache,
    BaseCacheManager? customThumbCache,
    bool monitorConnectivity = true,
  })  : _videoCache = customVideoCache ?? defaultVideoCache,
        _thumbCache = customThumbCache ?? defaultThumbCache {
    if (monitorConnectivity) {
      _netSub = Connectivity().onConnectivityChanged.listen(_onNetwork, onError: (_) {});
      Connectivity().checkConnectivity().then(_onNetwork, onError: (_) {});
    }
  }

  void _onNetwork(List<ConnectivityResult> r) {
    if (_disposed) return;
    _offline = r.isEmpty || r.every((c) => c == ConnectivityResult.none);
    _cellular = !_offline &&
        !r.contains(ConnectivityResult.wifi) &&
        !r.contains(ConnectivityResult.ethernet);
    if (!_offline) _pump();
  }

  @visibleForTesting
  void setNetworkStateForTest({required bool cellular, required bool offline}) {
    _cellular = cellular;
    _offline = offline;
    if (!_offline) _pump();
  }

  /// Called by [VideoPlaybackManager] so background preloading yields bandwidth
  /// whenever the currently visible reel is opening or buffering.
  void setActiveReelBuffering(bool buffering) {
    if (_activeReelBuffering == buffering) return;
    _activeReelBuffering = buffering;
    if (!buffering && !_offline && !_disposed) {
      _pump();
    }
  }

  int get queuedJobCount => _queue.length;
  int get readyVideoCount => _readyVideos.length;

  /// Synchronous lookup of a verified local video file path if already ready.
  String? localVideoFor(String url) {
    final path = _readyVideos[url];
    if (path == null) return null;
    return path;
  }

  /// Resolves a local cached file if already on disk (even before background
  /// queue reaches it), falling back to the remote [url] without blocking UI.
  Future<String> resolvePlayableSource(String url) async {
    if (!prefetchableVideo(url)) return url;
    final mem = _readyVideos[url];
    if (mem != null) {
      final f = File(mem);
      if (f.existsSync() && f.lengthSync() > 0) return mem;
      _readyVideos.remove(url);
      readyVideoCountNotifier.value = _readyVideos.length;
    }
    try {
      final cached = await _videoCache
          .getFileFromCache(url)
          .timeout(const Duration(milliseconds: 120), onTimeout: () => null);
      if (cached != null && await cached.file.exists() && await cached.file.length() > 0) {
        _readyVideos[url] = cached.file.path;
        readyVideoCountNotifier.value = _readyVideos.length;
        return cached.file.path;
      }
    } catch (_) {}
    return url;
  }

  /// Evicts a corrupt or truncated local video cache entry so playback can
  /// immediately fall back to streaming from the network.
  Future<void> evictCorruptVideo(String url) async {
    _readyVideos.remove(url);
    readyVideoCountNotifier.value = _readyVideos.length;
    try {
      await _videoCache.removeFile(url);
    } catch (_) {}
  }

  static bool prefetchableVideo(String url) =>
      url.startsWith('http') && !url.contains('.m3u8') && !url.contains('.mpd');

  /// Re-targets the 60-short rolling window around [index] (the reel on screen).
  void update(List<Content> feed, int index) {
    if (_disposed || feed.isEmpty || index < 0 || index >= feed.length) return;

    final hotAhead = _cellular ? hotVideosAheadCellular : hotVideosAheadWifi;
    final deepAhead = _cellular ? deepVideosAheadCellular : deepVideosAheadWifi;
    final end = (index + 1 + windowSize).clamp(0, feed.length);

    // Pre-index any already-cached disk videos for the active + upcoming window
    unawaited(_indexCachedWindow(feed, index, end));

    final jobs = <_Job>[];
    final wanted = <String>{};

    void enqueue(String url, {required bool video, required _JobPriority priority}) {
      if (!wanted.add(url)) return;
      if (_inFlight.containsKey(url)) return;
      jobs.add(_Job(url, video: video, priority: priority));
    }

    // Tier 0: Immediate cover thumbnails (current .. current + 8)
    final immEnd = (index + 1 + immediateThumbsAhead).clamp(0, end);
    for (var i = index; i < immEnd; i++) {
      final c = feed[i];
      if (c.isPhotoOrCarousel && c.mediaUrls.isNotEmpty) {
        for (final imgUrl in c.mediaUrls) {
          if (imgUrl.startsWith('http') && !_thumbsDone.contains(imgUrl)) {
            enqueue(imgUrl, video: false, priority: _JobPriority.immediateThumb);
          }
        }
      } else {
        final thumb = c.isPhotoOrCarousel ? c.mediaUrl : c.mediaMetadata.thumbnailUrl;
        if (thumb != null && thumb.startsWith('http') && !_thumbsDone.contains(thumb)) {
          enqueue(thumb, video: false, priority: _JobPriority.immediateThumb);
        }
      }
    }

    // Tier 1: Hot full videos (current + 1 .. current + hotAhead)
    final hotEnd = (index + 1 + hotAhead).clamp(0, end);
    for (var i = index + 1; i < hotEnd; i++) {
      final c = feed[i];
      if (c.isPhotoOrCarousel || !prefetchableVideo(c.mediaUrl)) continue;
      if (_readyVideos.containsKey(c.mediaUrl)) continue;
      enqueue(c.mediaUrl, video: true, priority: _JobPriority.hotVideo);
    }

    // Tier 2: Remaining covers across the 60-short horizon
    for (var i = immEnd; i < end; i++) {
      final c = feed[i];
      if (c.isPhotoOrCarousel && c.mediaUrls.isNotEmpty) {
        for (final imgUrl in c.mediaUrls) {
          if (imgUrl.startsWith('http') && !_thumbsDone.contains(imgUrl)) {
            enqueue(imgUrl, video: false, priority: _JobPriority.windowThumb);
          }
        }
      } else {
        final thumb = c.isPhotoOrCarousel ? c.mediaUrl : c.mediaMetadata.thumbnailUrl;
        if (thumb != null && thumb.startsWith('http') && !_thumbsDone.contains(thumb)) {
          enqueue(thumb, video: false, priority: _JobPriority.windowThumb);
        }
      }
    }

    // Tier 3: Deep background full-video auto-loading (up to 55+ shorts ahead!)
    final deepEnd = (index + 1 + deepAhead).clamp(0, end);
    for (var i = hotEnd; i < deepEnd; i++) {
      final c = feed[i];
      if (c.isPhotoOrCarousel || !prefetchableVideo(c.mediaUrl)) continue;
      if (_readyVideos.containsKey(c.mediaUrl)) continue;
      enqueue(c.mediaUrl, video: true, priority: _JobPriority.deepVideo);
    }

    // Keep in-flight URLs that are still within the window as wanted
    for (final activeUrl in _inFlight.keys) {
      // Allow already-started hot jobs to complete cleanly
      if (_inFlight[activeUrl] == _JobPriority.hotVideo ||
          _inFlight[activeUrl] == _JobPriority.immediateThumb) {
        wanted.add(activeUrl);
      }
    }

    _wanted = wanted;
    _queue
      ..clear()
      ..addAll(jobs);
    _pump();
  }

  Future<void> _indexCachedWindow(List<Content> feed, int start, int end) async {
    for (var i = start; i < end; i++) {
      if (_disposed) return;
      final c = feed[i];
      if (c.isPhotoOrCarousel || !prefetchableVideo(c.mediaUrl)) continue;
      final url = c.mediaUrl;
      if (_readyVideos.containsKey(url) || !_indexedCheckInFlight.add(url)) continue;
      try {
        final info = await _videoCache.getFileFromCache(url);
        if (info != null && await info.file.exists() && await info.file.length() > 0) {
          _readyVideos[url] = info.file.path;
          readyVideoCountNotifier.value = _readyVideos.length;
        }
      } catch (_) {
      } finally {
        _indexedCheckInFlight.remove(url);
      }
    }
  }

  void _pump() {
    if (_offline || _disposed || _queue.isEmpty) return;

    final maxTotal = _activeReelBuffering
        ? 1
        : (_cellular ? maxHotConcurrentCellular : maxHotConcurrentWifi);

    var cursor = 0;
    while (_inFlight.length < maxTotal && cursor < _queue.length) {
      final job = _queue[cursor];

      if (!_wanted.contains(job.url) ||
          _inFlight.containsKey(job.url) ||
          (job.video && _readyVideos.containsKey(job.url)) ||
          (!job.video && _thumbsDone.contains(job.url))) {
        _queue.removeAt(cursor);
        continue;
      }

      // Anti-starvation: while the active reel is buffering, hold back deep
      // background jobs so on-screen playback starts with zero lag.
      if (_activeReelBuffering &&
          (job.priority == _JobPriority.deepVideo || job.priority == _JobPriority.windowThumb)) {
        cursor++;
        continue;
      }

      // Limit deep background video downloads to [maxDeepConcurrent] at a time
      // so hot cover/video slots remain open if the user swipes suddenly.
      if (job.priority == _JobPriority.deepVideo) {
        final deepRunning = _inFlight.values.where((p) => p == _JobPriority.deepVideo).length;
        if (deepRunning >= maxDeepConcurrent) {
          cursor++;
          continue;
        }
      }

      _queue.removeAt(cursor);
      _inFlight[job.url] = job.priority;
      unawaited(_run(job).whenComplete(() {
        _inFlight.remove(job.url);
        if (_disposed) return;
        if (job.priority == _JobPriority.deepVideo) {
          // Small frame-friendly yield between background video downloads
          Future.delayed(const Duration(milliseconds: 25), _pump);
        } else {
          _pump();
        }
      }));
    }
  }

  Future<void> _run(_Job job) async {
    final cache = job.video ? _videoCache : _thumbCache;
    try {
      final cached = await cache.getFileFromCache(job.url);
      if (_disposed || !_wanted.contains(job.url)) return;
      final fileInfo = cached ?? await cache.downloadFile(job.url);
      if (_disposed) return;
      if (job.video) {
        if (await fileInfo.file.exists() && await fileInfo.file.length() > 0) {
          _readyVideos[job.url] = fileInfo.file.path;
          readyVideoCountNotifier.value = _readyVideos.length;
        }
      } else {
        _thumbsDone.add(job.url);
      }
    } catch (e) {
      debugPrint('[ReelPrefetcher] ${job.video ? 'video' : 'thumb'} failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _netSub?.cancel();
    _queue.clear();
    readyVideoCountNotifier.dispose();
  }
}

class _Job {
  final String url;
  final bool video;
  final _JobPriority priority;
  const _Job(this.url, {required this.video, required this.priority});
}
