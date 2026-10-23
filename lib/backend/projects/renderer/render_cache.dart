import 'dart:collection';
import 'render_models.dart';

class RenderCache {
  final int maxFrames;
  final LinkedHashMap<String, RenderFrame> _frameCache = LinkedHashMap();

  RenderCache({this.maxFrames = 100});

  void put(String key, RenderFrame frame) {
    if (_frameCache.containsKey(key)) {
      _frameCache.remove(key);
    }
    _frameCache[key] = frame;

    // LRU eviction
    if (_frameCache.length > maxFrames) {
      final firstKey = _frameCache.keys.first;
      final removed = _frameCache.remove(firstKey);
      removed?.dispose();
    }
  }

  RenderFrame? get(String key) {
    if (_frameCache.containsKey(key)) {
      final frame = _frameCache.remove(key)!;
      _frameCache[key] = frame; // move to end
      return frame;
    }
    return null;
  }

  void invalidatePrefix(String prefix) {
    final keysToRemove = _frameCache.keys.where((k) => k.startsWith(prefix)).toList();
    for (var key in keysToRemove) {
      final frame = _frameCache.remove(key);
      frame?.dispose();
    }
  }

  void clear() {
    for (var frame in _frameCache.values) {
      frame.dispose();
    }
    _frameCache.clear();
  }
}
