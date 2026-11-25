import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Which HLS rung to start on. The worker writes rungs lowest first.
enum ReelRung { low, mid, high }

/// Reels playback knobs. Every value can be changed from Remote Config
/// (keys prefixed `reels_`) without shipping an app update.
class ReelPlaybackConfig {
  /// Videos ahead of the current one whose first segments are prefetched.
  final int preloadAhead;

  /// Segments per upcoming video to prefetch (2 s each).
  final int preloadSegments;

  /// Same, on cellular. Kept lower to save the user's data and our egress.
  final int preloadSegmentsCellular;

  /// Disk cache size for HLS segments and playlists.
  final int cacheMb;

  final ReelRung startRungWifi;
  final ReelRung startRungCellular;

  /// Feed page size and when to fetch the next page (items left).
  final int pageSize;
  final int prefetchPageAt;

  const ReelPlaybackConfig({
    this.preloadAhead = 2,
    this.preloadSegments = 2,
    this.preloadSegmentsCellular = 1,
    this.cacheMb = 300,
    this.startRungWifi = ReelRung.mid,
    this.startRungCellular = ReelRung.low,
    this.pageSize = 10,
    this.prefetchPageAt = 5,
  });

  static const defaults = ReelPlaybackConfig();

  static Map<String, Object> get remoteDefaults => {
        'reels_preload_ahead': defaults.preloadAhead,
        'reels_preload_segments': defaults.preloadSegments,
        'reels_preload_segments_cell': defaults.preloadSegmentsCellular,
        'reels_cache_mb': defaults.cacheMb,
        'reels_start_rung_wifi': defaults.startRungWifi.name,
        'reels_start_rung_cell': defaults.startRungCellular.name,
        'reels_page_size': defaults.pageSize,
        'reels_prefetch_page_at': defaults.prefetchPageAt,
      };

  /// Reads Remote Config. Never throws: falls back to [defaults].
  static Future<ReelPlaybackConfig> load() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setDefaults(remoteDefaults);
      // Use what is already activated; fetch in the background for next time.
      rc.fetchAndActivate().ignore();
      ReelRung rung(String key, ReelRung fallback) => ReelRung.values.firstWhere(
            (r) => r.name == rc.getString(key),
            orElse: () => fallback,
          );
      int clamp(String key, int lo, int hi) => rc.getInt(key).clamp(lo, hi);
      return ReelPlaybackConfig(
        preloadAhead: clamp('reels_preload_ahead', 0, 4),
        preloadSegments: clamp('reels_preload_segments', 0, 5),
        preloadSegmentsCellular: clamp('reels_preload_segments_cell', 0, 5),
        cacheMb: clamp('reels_cache_mb', 50, 2000),
        startRungWifi: rung('reels_start_rung_wifi', defaults.startRungWifi),
        startRungCellular: rung('reels_start_rung_cell', defaults.startRungCellular),
        pageSize: clamp('reels_page_size', 3, 30),
        prefetchPageAt: clamp('reels_prefetch_page_at', 1, 15),
      );
    } catch (e) {
      debugPrint('ReelPlaybackConfig: using defaults ($e)');
      return defaults;
    }
  }
}

/// Network type, used to choose the start rung and preload depth.
class ReelNetwork {
  final Connectivity _connectivity = Connectivity();
  bool _cellular = false;

  bool get isCellular => _cellular;

  Future<void> start() async {
    _apply(await _connectivity.checkConnectivity());
    _connectivity.onConnectivityChanged.listen(_apply);
  }

  void _apply(List<ConnectivityResult> results) {
    // Treat "cellular only" as metered. Wi-Fi or ethernet wins if present.
    _cellular = results.contains(ConnectivityResult.mobile) &&
        !results.contains(ConnectivityResult.wifi) &&
        !results.contains(ConnectivityResult.ethernet);
  }
}
