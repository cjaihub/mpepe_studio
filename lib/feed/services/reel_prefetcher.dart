import 'dart:async';
import 'dart:collection';

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

/// Background prefetch for the Reels feed, in a rolling window ahead of the
/// reel on screen:
///
/// - the next [windowSize] reels: cover thumbnails go to a disk cache, so
///   every page has an image the moment it is built;
/// - the next [videosAheadWifi] reels (fewer on mobile data): the whole video
///   file is downloaded to a disk cache, and [VideoPlaybackManager] opens the
///   local file instead of streaming once it is there.
///
/// Work that falls out of the window (the user scrolled away) is dropped
/// before it starts. Downloads run [maxConcurrent] at a time so they never
/// starve the reel that is playing. Disk use is bounded by the cache object
/// limits below; nothing is held in RAM except the url→path map.
class ReelPrefetcher {
  static const int windowSize = 50;
  static const int videosAheadWifi = 6;
  static const int videosAheadCellular = 3;
  static const int maxConcurrent = 2;

  static final CacheManager videoCache = CacheManager(Config(
    'oneova_reel_videos_v1',
    stalePeriod: const Duration(days: 2),
    maxNrOfCacheObjects: 30,
  ));

  static final CacheManager thumbCache = CacheManager(Config(
    'oneova_reel_thumbs_v1',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 400,
  ));

  final Map<String, String> _readyVideos = {};
  final Set<String> _thumbsDone = {};
  final Queue<_Job> _queue = Queue();
  final Set<String> _inFlight = {};
  Set<String> _wanted = {};
  bool _cellular = false;
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _netSub;

  ReelPrefetcher() {
    _netSub = Connectivity().onConnectivityChanged.listen(_onNetwork, onError: (_) {});
    Connectivity().checkConnectivity().then(_onNetwork, onError: (_) {});
  }

  void _onNetwork(List<ConnectivityResult> r) {
    _offline = r.isEmpty || r.every((c) => c == ConnectivityResult.none);
    _cellular = !_offline && !r.contains(ConnectivityResult.wifi) && !r.contains(ConnectivityResult.ethernet);
    if (!_offline) _pump();
  }

  /// Local file for [url] once it is fully downloaded, else null.
  String? localVideoFor(String url) => _readyVideos[url];

  static bool _prefetchable(String url) =>
      url.startsWith('http') && !url.contains('.m3u8') && !url.contains('.mpd');

  /// Re-targets the window around [index] (the reel on screen).
  void update(List<Content> feed, int index) {
    if (feed.isEmpty || index < 0 || index >= feed.length) return;
    final videosAhead = _cellular ? videosAheadCellular : videosAheadWifi;
    final end = (index + 1 + windowSize).clamp(0, feed.length);
    final jobs = <_Job>[];
    final wanted = <String>{};

    // Videos first (closest first), then thumbnails for the rest of the window.
    for (var i = index + 1; i < end && i <= index + videosAhead; i++) {
      final c = feed[i];
      if (c.type == ContentType.photo || !_prefetchable(c.mediaUrl)) continue;
      if (_readyVideos.containsKey(c.mediaUrl)) continue;
      jobs.add(_Job(c.mediaUrl, video: true));
      wanted.add(c.mediaUrl);
    }
    for (var i = index; i < end; i++) {
      final c = feed[i];
      final thumb = c.type == ContentType.photo ? c.mediaUrl : c.mediaMetadata.thumbnailUrl;
      if (thumb == null || !thumb.startsWith('http') || _thumbsDone.contains(thumb)) continue;
      jobs.add(_Job(thumb, video: false));
      wanted.add(thumb);
    }
    _wanted = wanted;
    _queue
      ..clear()
      ..addAll(jobs.where((j) => !_inFlight.contains(j.url)));
    _pump();
  }

  void _pump() {
    if (_offline) return;
    while (_inFlight.length < maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      if (!_wanted.contains(job.url) || _inFlight.contains(job.url)) continue;
      _inFlight.add(job.url);
      unawaited(_run(job).whenComplete(() {
        _inFlight.remove(job.url);
        _pump();
      }));
    }
  }

  Future<void> _run(_Job job) async {
    final cache = job.video ? videoCache : thumbCache;
    try {
      final file = await cache.getFileFromCache(job.url) ?? await cache.downloadFile(job.url);
      if (job.video) {
        _readyVideos[job.url] = file.file.path;
      } else {
        _thumbsDone.add(job.url);
      }
    } catch (e) {
      debugPrint('[ReelPrefetcher] ${job.video ? 'video' : 'thumb'} failed: $e');
    }
  }

  void dispose() {
    _netSub?.cancel();
    _queue.clear();
  }
}

class _Job {
  final String url;
  final bool video;
  const _Job(this.url, {required this.video});
}
