import 'dart:convert';
import 'device_hardware_tier.dart';

/// Result of the silent 5-second first-run engine frame time & thermal slope benchmark.
class DeviceBenchmarkResult {
  final String deviceModel;
  final String chip;
  final int ramMb;
  final double medianFrameMsTier1; // Neutral / simple pass
  final double medianFrameMsTier2; // LUT + curves + HSL
  final double medianFrameMsTier3; // Heavy stack: grain + sharpen + LUT + curves
  final double p95FrameMs;
  final double thermalSlope; // Headroom rise per second under benchmark load
  final int totalFramesRendered;
  final Duration benchmarkDuration;
  final DateTime timestamp;
  final DeviceHardwareTier benchmarkTier;

  const DeviceBenchmarkResult({
    required this.deviceModel,
    required this.chip,
    required this.ramMb,
    required this.medianFrameMsTier1,
    required this.medianFrameMsTier2,
    required this.medianFrameMsTier3,
    required this.p95FrameMs,
    required this.thermalSlope,
    required this.totalFramesRendered,
    required this.benchmarkDuration,
    required this.timestamp,
    required this.benchmarkTier,
  });

  factory DeviceBenchmarkResult.fromMap(Map<String, dynamic> map) {
    return DeviceBenchmarkResult(
      deviceModel: map['deviceModel'] as String? ?? 'Unknown',
      chip: map['chip'] as String? ?? 'Unknown',
      ramMb: (map['ramMb'] as num?)?.toInt() ?? 4096,
      medianFrameMsTier1: (map['medianFrameMsTier1'] as num?)?.toDouble() ?? 2.0,
      medianFrameMsTier2: (map['medianFrameMsTier2'] as num?)?.toDouble() ?? 4.5,
      medianFrameMsTier3: (map['medianFrameMsTier3'] as num?)?.toDouble() ?? 8.0,
      p95FrameMs: (map['p95FrameMs'] as num?)?.toDouble() ?? 9.5,
      thermalSlope: (map['thermalSlope'] as num?)?.toDouble() ?? 0.01,
      totalFramesRendered: (map['totalFramesRendered'] as num?)?.toInt() ?? 100,
      benchmarkDuration: Duration(milliseconds: (map['benchmarkDurationMs'] as num?)?.toInt() ?? 5000),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      benchmarkTier: DeviceHardwareTier.fromString(map['benchmarkTier'] as String?),
    );
  }

  Map<String, dynamic> toMap() => {
        'deviceModel': deviceModel,
        'chip': chip,
        'ramMb': ramMb,
        'medianFrameMsTier1': medianFrameMsTier1,
        'medianFrameMsTier2': medianFrameMsTier2,
        'medianFrameMsTier3': medianFrameMsTier3,
        'p95FrameMs': p95FrameMs,
        'thermalSlope': thermalSlope,
        'totalFramesRendered': totalFramesRendered,
        'benchmarkDurationMs': benchmarkDuration.inMilliseconds,
        'timestampMs': timestamp.millisecondsSinceEpoch,
        'benchmarkTier': benchmarkTier.name,
      };

  String toJson() => jsonEncode(toMap());

  factory DeviceBenchmarkResult.fromJson(String source) =>
      DeviceBenchmarkResult.fromMap(jsonDecode(source) as Map<String, dynamic>);

  /// An aggregated score from 0 to 100 representing frame rendering performance.
  double get performanceScore {
    // 60fps frame budget = 16.6ms. Target median tier 2 <= 6.0ms = 100 points
    final frameCost = (medianFrameMsTier1 * 0.2) + (medianFrameMsTier2 * 0.5) + (medianFrameMsTier3 * 0.3);
    final score = (16.6 / (frameCost + 1.0)) * 40.0;
    return score.clamp(10.0, 100.0);
  }
}
