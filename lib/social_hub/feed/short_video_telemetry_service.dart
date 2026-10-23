import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'short_video_feed_models.dart';

final shortVideoTelemetryServiceProvider = Provider<ShortVideoTelemetryService>((ref) {
  return ShortVideoTelemetryService();
});

class ShortVideoTelemetryService {
  // Protects against duplicate event counting per session
  // Set contains strings like: "${videoId}_${eventType}"
  final Set<String> _recordedSessionEvents = {};
  
  // Track continuous watch duration mathematically
  final Map<String, Stopwatch> _watchTimers = {};

  /// Records an event exactly once per watch session.
  /// Never fabricates counts.
  void trackEvent(String videoId, VideoMetricEvent event) {
    final eventKey = '${videoId}_${event.name}';
    
    // Prevent duplicate counting for one-off events
    if (event != VideoMetricEvent.rewatch && _recordedSessionEvents.contains(eventKey)) {
      return;
    }
    
    _recordedSessionEvents.add(eventKey);
    
    // TODO: Send to backend database/analytics
    // ignore: avoid_print
    print('REAL METRIC RECORDED: $event for video $videoId');
  }

  void startWatchTimer(String videoId) {
    if (!_watchTimers.containsKey(videoId)) {
      _watchTimers[videoId] = Stopwatch()..start();
      trackEvent(videoId, VideoMetricEvent.start);
    } else {
      _watchTimers[videoId]!.start();
    }
  }

  void pauseWatchTimer(String videoId) {
    _watchTimers[videoId]?.stop();
  }

  Duration getWatchDuration(String videoId) {
    return _watchTimers[videoId]?.elapsed ?? Duration.zero;
  }

  void completeWatch(String videoId) {
    trackEvent(videoId, VideoMetricEvent.completion);
  }

  void clearSession(String videoId) {
    // Optionally called when heavily scrolling to free up memory, 
    // but typically we want to remember we watched it to prevent duplicate impressions.
    _watchTimers[videoId]?.stop();
    _watchTimers.remove(videoId);
  }
}
