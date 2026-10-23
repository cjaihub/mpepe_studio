import 'package:oneova/backend/performance/models/performance_metrics.dart';

class PerformanceEngine {
  final List<PerformanceTrace> _traces = [];
  final Map<String, int> _activeTimers = {};

  // --- Measurement API ---

  void recordMetric(TelemetryCategory category, String name, double value, String unit) {
    _traces.add(PerformanceTrace(
      id: 'trace_${DateTime.now().microsecondsSinceEpoch}',
      category: category,
      metricName: name,
      value: value,
      unit: unit,
      recordedAt: DateTime.now(),
    ));
  }

  void startTimer(String timerId) {
    _activeTimers[timerId] = DateTime.now().microsecondsSinceEpoch;
  }

  void stopTimerAndRecord(String timerId, TelemetryCategory category, String name) {
    final start = _activeTimers.remove(timerId);
    if (start != null) {
      final end = DateTime.now().microsecondsSinceEpoch;
      final durationMs = (end - start) / 1000.0;
      recordMetric(category, name, durationMs, 'ms');
    }
  }

  // Analyzes traces to recommend targeted optimizations, satisfying "Measure before optimizing"
  List<OptimizationStrategy> getRecommendedOptimizations() {
    final recommendations = <OptimizationStrategy>{};

    for (var trace in _traces) {
      if (trace.category == TelemetryCategory.media && trace.metricName == 'first_video_frame' && trace.value > 500) {
        recommendations.add(OptimizationStrategy.cdn);
        recommendations.add(OptimizationStrategy.prefetch);
      }
      if (trace.category == TelemetryCategory.hardware && trace.metricName == 'scroll_fps' && trace.value < 55) {
        recommendations.add(OptimizationStrategy.virtualization);
        recommendations.add(OptimizationStrategy.mediaVariants);
      }
      if (trace.category == TelemetryCategory.database && trace.value > 200) {
        recommendations.add(OptimizationStrategy.databaseIndexing);
        recommendations.add(OptimizationStrategy.queryPlans);
      }
      if (trace.category == TelemetryCategory.network && trace.metricName == 'feed_startup' && trace.value > 1000) {
        recommendations.add(OptimizationStrategy.caching);
        recommendations.add(OptimizationStrategy.pagination);
      }
      if (trace.category == TelemetryCategory.media && trace.metricName == 'media_processing' && trace.value > 5000) {
        recommendations.add(OptimizationStrategy.backgroundQueues);
      }
    }

    return recommendations.toList();
  }

  List<PerformanceTrace> get traces => List.unmodifiable(_traces);
}
