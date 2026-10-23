enum TelemetryCategory {
  startup,           // App cold start, feed startup
  media,             // First video frame, media processing
  hardware,          // Scroll FPS, memory, battery
  network,           // Network, API latency, CDN
  database,          // Database latency, query plans
  ai,                // AI latency
  realtime,          // Realtime latency (sockets)
}

enum OptimizationStrategy {
  cdn,
  caching,
  prefetch,
  virtualization,
  pagination,
  databaseIndexing,
  queryPlans,
  mediaVariants,
  backgroundQueues,
}

class PerformanceTrace {
  final String id;
  final TelemetryCategory category;
  final String metricName; // e.g., 'first_video_frame', 'scroll_fps'
  final double value;
  final String unit;       // 'ms', 'fps', 'mb', '%'
  final DateTime recordedAt;

  PerformanceTrace({
    required this.id,
    required this.category,
    required this.metricName,
    required this.value,
    required this.unit,
    required this.recordedAt,
  });
}
