import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'telemetry_service.dart';

final performanceMonitorProvider = Provider<PerformanceMonitor>((ref) {
  return PerformanceMonitor(ref.read(telemetryServiceProvider));
});

/// Monitors critical performance metrics across the app lifecycle.
/// Enforces the rule: "Measure before optimizing."
class PerformanceMonitor {
  final TelemetryService _telemetry;
  DateTime? _appStartTime;
  
  PerformanceMonitor(this._telemetry) {
    _appStartTime = DateTime.now();
  }

  /// 1. Cold Startup Measurement
  /// Should be called the moment the first meaningful frame (e.g. Feed) is rendered.
  void recordColdStartupComplete() {
    if (_appStartTime != null) {
      final duration = DateTime.now().difference(_appStartTime!);
      _telemetry.recordMetric('time_to_interactive_ms', duration.inMilliseconds.toDouble());
      _telemetry.logEvent('perf_cold_start', {'duration_ms': duration.inMilliseconds});
      _appStartTime = null; // Only record once per lifecycle
    }
  }

  /// 2. First Video Frame Measurement
  /// Called by the video player when the first frame is actually drawn.
  void recordFirstVideoFrame(String videoId, Duration loadTime) {
    _telemetry.recordMetric('video_time_to_first_frame_ms', loadTime.inMilliseconds.toDouble(), attributes: {'videoId': videoId});
  }

  /// 3. Scroll Performance (Jank Tracking)
  /// In Flutter, this is typically captured via SchedulerBinding/FrameTiming.
  /// We record dropped frames or high build times.
  void recordScrollJank(int droppedFrames, double averageFrameTimeMs) {
    if (averageFrameTimeMs > 16.6) { // 60fps threshold
      _telemetry.recordMetric('scroll_jank_frames', droppedFrames.toDouble());
      _telemetry.recordMetric('scroll_avg_frame_time_ms', averageFrameTimeMs);
    }
  }

  /// 4. Feed & API Latency
  /// Wraps any Future to measure execution time.
  Future<T> measureApiLatency<T>(String endpointName, Future<T> Function() apiCall) async {
    final span = _telemetry.startSpan('api_latency', attributes: {'endpoint': endpointName});
    final stopwatch = Stopwatch()..start();
    try {
      final result = await apiCall();
      stopwatch.stop();
      _telemetry.recordMetric('api_latency_ms', stopwatch.elapsedMilliseconds.toDouble(), attributes: {'endpoint': endpointName});
      span.end();
      return result;
    } catch (e) {
      span.recordException(e);
      span.end();
      rethrow;
    }
  }

  /// 5. Memory & Battery (Simulated OS hooks)
  /// In production, use MethodChannels to query native iOS/Android memory pressure.
  void recordMemoryPressure() {
    _telemetry.logEvent('perf_memory_pressure_warning', {'timestamp': DateTime.now().toIso8601String()});
  }
}
