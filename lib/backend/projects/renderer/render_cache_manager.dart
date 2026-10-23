import 'dart:collection';
import 'render_models.dart';

/// A bounded LRU Cache to manage RenderFrame objects in memory.
/// Ensures we do not encounter Out-of-Memory (OOM) errors during rapid scrubbing or 4K playback.
class RenderCacheManager {
  final int maxFrames;
  // Store cached items securely with a deterministic hash string
  final LinkedHashMap<String, RenderResult> _cache = LinkedHashMap<String, RenderResult>();

  RenderCacheManager({this.maxFrames = 50});

  /// Retrieve a frame from cache using its exact state hash
  RenderResult? get(String cacheKey) {
    if (_cache.containsKey(cacheKey)) {
      final result = _cache.remove(cacheKey)!;
      // Re-insert to mark as most recently used
      _cache[cacheKey] = result;
      return result;
    }
    return null;
  }

  /// Add a frame to cache, evicting the oldest if capacity is exceeded
  void put(String cacheKey, RenderResult result) {
    if (_cache.containsKey(cacheKey)) {
      _cache.remove(cacheKey);
    }
    _cache[cacheKey] = result;

    if (_cache.length > maxFrames) {
      final oldestKey = _cache.keys.first;
      final evicted = _cache.remove(oldestKey);
      
      // Explicitly release C++/GPU resources bounded to the RenderFrame
      if (evicted != null && evicted.frame != null) {
        evicted.frame!.dispose();
      }
    }
  }

  /// Manually flush the cache (e.g., when closing a project or on memory warnings)
  void flush() {
    for (var result in _cache.values) {
      if (result.frame != null) {
        result.frame!.dispose();
      }
    }
    _cache.clear();
  }
}
