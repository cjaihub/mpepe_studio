import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_benchmark_result.dart';
import '../models/device_hardware_tier.dart';
import 'device_profile_telemetry_service.dart';

/// Silent first-run benchmark (~5 seconds).
/// Measures engine frame rendering latency at different look complexities and sustained thermal slope.
class DeviceBenchmarkService {
  static const String _storageKey = 'device_benchmark_result_v1';
  final SharedPreferences? prefs;
  final DeviceProfileTelemetryService _telemetryService;

  DeviceBenchmarkService({
    this.prefs,
    DeviceProfileTelemetryService? telemetryService,
  })  : _telemetryService = telemetryService ?? DeviceProfileTelemetryService();

  /// Loads cached benchmark from storage if it has already been executed.
  Future<DeviceBenchmarkResult?> getCachedBenchmark() async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final jsonStr = p.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return DeviceBenchmarkResult.fromJson(jsonStr);
    } catch (e) {
      debugPrint('[DeviceBenchmarkService] Failed to parse cached benchmark: $e');
      return null;
    }
  }

  /// Runs the 5-second silent benchmark, persists to SharedPreferences, and streams telemetry.
  Future<DeviceBenchmarkResult> runBenchmark({
    required HardwareCapabilities capabilities,
    Duration targetDuration = const Duration(seconds: 5),
    bool force = false,
  }) async {
    if (!force) {
      final cached = await getCachedBenchmark();
      if (cached != null) {
        debugPrint('[DeviceBenchmarkService] Using cached benchmark score: ${cached.performanceScore.toStringAsFixed(1)}');
        return cached;
      }
    }

    debugPrint('[DeviceBenchmarkService] Starting silent benchmark (${targetDuration.inSeconds}s)...');

    // 1. Initial thermal baseline
    final initialHeadroom = await ThermalProbe.getThermalHeadroom();
    final stopwatch = Stopwatch()..start();

    final tier1Samples = <double>[];
    final tier2Samples = <double>[];
    final tier3Samples = <double>[];
    final allSamples = <double>[];

    final random = Random();
    int currentPhase = 1;

    // Run benchmark loop until target duration has elapsed
    while (stopwatch.elapsed < targetDuration) {
      final frameSw = Stopwatch()..start();

      // Execute simulated shader & memory workload representative of Look tiers
      _executeLookComplexityPass(currentPhase, random);

      frameSw.stop();
      final frameMs = frameSw.elapsedMicroseconds / 1000.0;
      allSamples.add(frameMs);

      switch (currentPhase) {
        case 1:
          tier1Samples.add(frameMs);
          if (tier1Samples.length >= 30) currentPhase = 2;
          break;
        case 2:
          tier2Samples.add(frameMs);
          if (tier2Samples.length >= 30) currentPhase = 3;
          break;
        case 3:
          tier3Samples.add(frameMs);
          if (tier3Samples.length >= 30) currentPhase = 2; // loop between 2 and 3
          break;
      }

      // Small 1ms yield to ensure UI responsiveness / prevent frame stutter
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    stopwatch.stop();

    // 2. Final thermal baseline to measure sustained slope
    final finalHeadroom = await ThermalProbe.getThermalHeadroom();
    final elapsedSeconds = max(1.0, stopwatch.elapsedMilliseconds / 1000.0);
    final thermalSlope = max(0.0, (finalHeadroom - initialHeadroom) / elapsedSeconds);

    // Compute metrics
    tier1Samples.sort();
    tier2Samples.sort();
    tier3Samples.sort();
    allSamples.sort();

    final medianTier1 = tier1Samples.isNotEmpty ? tier1Samples[tier1Samples.length ~/ 2] : 1.5;
    final medianTier2 = tier2Samples.isNotEmpty ? tier2Samples[tier2Samples.length ~/ 2] : 3.8;
    final medianTier3 = tier3Samples.isNotEmpty ? tier3Samples[tier3Samples.length ~/ 2] : 7.2;

    final p95Index = ((allSamples.length - 1) * 0.95).toInt();
    final p95 = allSamples.isNotEmpty ? allSamples[p95Index] : 8.5;

    // Determine hardware tier from benchmark and hardware capabilities
    final totalRamMb = (capabilities.totalRamBytes / (1024 * 1024)).toInt();
    final DeviceHardwareTier benchmarkTier;
    if (medianTier2 < 6.0 && thermalSlope < 0.06 && totalRamMb >= 6000 && capabilities.supports4KRecording) {
      benchmarkTier = DeviceHardwareTier.high;
    } else if (medianTier2 < 14.0 && totalRamMb >= 3500) {
      benchmarkTier = DeviceHardwareTier.medium;
    } else {
      benchmarkTier = DeviceHardwareTier.low;
    }

    final result = DeviceBenchmarkResult(
      deviceModel: capabilities.model,
      chip: capabilities.socModel.isNotEmpty ? capabilities.socModel : capabilities.hardware,
      ramMb: totalRamMb,
      medianFrameMsTier1: double.parse(medianTier1.toStringAsFixed(2)),
      medianFrameMsTier2: double.parse(medianTier2.toStringAsFixed(2)),
      medianFrameMsTier3: double.parse(medianTier3.toStringAsFixed(2)),
      p95FrameMs: double.parse(p95.toStringAsFixed(2)),
      thermalSlope: double.parse(thermalSlope.toStringAsFixed(4)),
      totalFramesRendered: allSamples.length,
      benchmarkDuration: stopwatch.elapsed,
      timestamp: DateTime.now(),
      benchmarkTier: benchmarkTier,
    );

    // 3. Persist locally in SharedPreferences
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(_storageKey, result.toJson());
    debugPrint('[DeviceBenchmarkService] Benchmark completed: ${result.performanceScore.toStringAsFixed(1)} pts (${result.benchmarkTier.name})');

    // 4. Stream anonymous telemetry to Firestore deviceProfiles/{model}
    unawaited(_telemetryService.sendBenchmarkTelemetry(result));

    return result;
  }

  /// Executes mathematical computations simulating shader uniform evaluations,
  /// 3D LUT trilinear interpolation sampling, and 8-band HSL calculations.
  void _executeLookComplexityPass(int phase, Random random) {
    // Workload size proportional to look complexity
    final iterations = switch (phase) {
      1 => 800,   // Tier 1: Primary adjustments
      2 => 2500,  // Tier 2: LUT interpolation + curves + HSL
      3 => 5500,  // Tier 3: LUT + curves + HSL + sharpen convolution + grain hash
      _ => 1000,
    };

    double acc = 0.5;
    for (int i = 0; i < iterations; i++) {
      final u = (i % 33) / 32.0;
      final v = ((i * 3) % 33) / 32.0;
      final w = ((i * 7) % 33) / 32.0;
      // Trilinear blend simulation
      acc = (acc * 0.7) + (u * v * w * 0.3) + sin(u * 3.14159) * 0.05;
    }

    if (acc > 10000.0) {
      debugPrint('$acc'); // Prevent dead code elimination
    }
  }
}
