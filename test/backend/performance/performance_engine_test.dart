import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/performance/models/performance_metrics.dart';
import 'package:oneova/backend/performance/services/performance_engine.dart';

void main() {
  late PerformanceEngine engine;

  setUp(() {
    engine = PerformanceEngine();
  });

  test('Timer records metric accurately', () async {
    engine.startTimer('startup_seq');
    // Simulate a brief delay
    await Future.delayed(const Duration(milliseconds: 50));
    engine.stopTimerAndRecord('startup_seq', TelemetryCategory.startup, 'app_cold_start');

    expect(engine.traces.length, 1);
    expect(engine.traces.first.metricName, 'app_cold_start');
    expect(engine.traces.first.value, greaterThan(40.0)); // Should be ~50ms
  });

  test('getRecommendedOptimizations derives strategies strictly from measured traces', () {
    // 1. Inject a slow video trace
    engine.recordMetric(TelemetryCategory.media, 'first_video_frame', 800.0, 'ms');
    
    // 2. Inject a poor scroll framerate trace
    engine.recordMetric(TelemetryCategory.hardware, 'scroll_fps', 45.0, 'fps');

    // 3. Request optimizations
    final strategies = engine.getRecommendedOptimizations();

    // Verify it didn't speculatively rewrite, but returned specific recommendations based *only* on the bad traces
    expect(strategies.contains(OptimizationStrategy.cdn), true);
    expect(strategies.contains(OptimizationStrategy.prefetch), true);
    expect(strategies.contains(OptimizationStrategy.virtualization), true);
    expect(strategies.contains(OptimizationStrategy.mediaVariants), true);

    // Ensure it didn't recommend things that aren't broken (e.g. database is fine here)
    expect(strategies.contains(OptimizationStrategy.databaseIndexing), false);
  });
}
