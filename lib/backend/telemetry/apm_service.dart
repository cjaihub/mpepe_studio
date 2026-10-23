import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final apmProvider = Provider((ref) => ApmService());

/// Application Performance Monitoring (APM) Service
/// Collects and aggregates latency metrics across the application
/// to ensure we optimize only after measuring, avoiding speculative rewrites.
class ApmService {
  final Map<String, List<int>> _metricBuckets = {};
  final Map<String, Stopwatch> _activeTraces = {};

  void startTrace(String metricName, {String? traceId}) {
    final key = traceId != null ? "\${metricName}_\$traceId" : metricName;
    _activeTraces[key] = Stopwatch()..start();
  }

  void stopTrace(String metricName, {String? traceId}) {
    final key = traceId != null ? "\${metricName}_\$traceId" : metricName;
    final stopwatch = _activeTraces.remove(key);
    
    if (stopwatch != null) {
      stopwatch.stop();
      _recordMetric(metricName, stopwatch.elapsedMilliseconds);
    }
  }

  /// Records a raw metric (e.g., from UI render callbacks)
  void recordLatency(String metricName, int milliseconds) {
    _recordMetric(metricName, milliseconds);
  }

  void _recordMetric(String name, int value) {
    if (!_metricBuckets.containsKey(name)) {
      _metricBuckets[name] = [];
    }
    _metricBuckets[name]!.add(value);
    
    // Prevent memory leaks in long-running sessions
    if (_metricBuckets[name]!.length > 1000) {
      _metricBuckets[name]!.removeAt(0); 
    }
    
    // In production, batch these up and send to Datadog/Firebase Performance
  }

  /// Prints a statistical report of current metrics to the console for optimization analysis.
  void printOptimizationReport() {
    debugPrint("\n====== APM PERFORMANCE REPORT ======");
    for (final entry in _metricBuckets.entries) {
      // ignore: unused_local_variable
      final name = entry.key;
      final values = entry.value;
      if (values.isEmpty) continue;

      values.sort();
      final min = values.first;
      final max = values.last;
      final avg = values.reduce((a, b) => a + b) / values.length;
      final p95 = values[(values.length * 0.95).floor()];

      debugPrint("Metric: $name");
      debugPrint("  Count: ${values.length}");
      debugPrint("  Avg:   ${avg.toStringAsFixed(2)} ms");
      debugPrint("  P95:   $p95 ms");
      debugPrint("  Min:   $min ms | Max: $max ms\n");
    }
    debugPrint("===================================\n");
  }

  Map<String, dynamic> generateReportJson() {
    final report = <String, dynamic>{};
    for (final entry in _metricBuckets.entries) {
      final values = entry.value;
      if (values.isEmpty) continue;
      
      values.sort();
      report[entry.key] = {
        'count': values.length,
        'avg': values.reduce((a, b) => a + b) / values.length,
        'p95': values[(values.length * 0.95).floor()],
      };
    }
    return report;
  }
}
