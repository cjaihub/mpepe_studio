import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/device/models/device_benchmark_result.dart';
import 'package:oneova/looks/device/models/device_hardware_tier.dart';
import 'package:oneova/looks/device/services/device_benchmark_service.dart';
import 'package:oneova/looks/device/services/device_profile_telemetry_service.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DeviceBenchmarkResult Model', () {
    test('serializes and deserializes to JSON correctly', () {
      final now = DateTime(2026, 3, 15, 10, 30);
      final result = DeviceBenchmarkResult(
        deviceModel: 'Pixel 8 Pro',
        chip: 'Tensor G3',
        ramMb: 12288,
        medianFrameMsTier1: 1.45,
        medianFrameMsTier2: 3.20,
        medianFrameMsTier3: 6.80,
        p95FrameMs: 7.90,
        thermalSlope: 0.012,
        totalFramesRendered: 150,
        benchmarkDuration: const Duration(seconds: 5),
        timestamp: now,
        benchmarkTier: DeviceHardwareTier.high,
      );

      final jsonStr = result.toJson();
      final parsed = DeviceBenchmarkResult.fromJson(jsonStr);

      expect(parsed.deviceModel, 'Pixel 8 Pro');
      expect(parsed.chip, 'Tensor G3');
      expect(parsed.ramMb, 12288);
      expect(parsed.medianFrameMsTier1, 1.45);
      expect(parsed.medianFrameMsTier2, 3.20);
      expect(parsed.medianFrameMsTier3, 6.80);
      expect(parsed.p95FrameMs, 7.90);
      expect(parsed.thermalSlope, 0.012);
      expect(parsed.benchmarkTier, DeviceHardwareTier.high);
      expect(parsed.performanceScore, greaterThan(80.0));
    });

    test('calculates proportional performance score', () {
      final fastResult = DeviceBenchmarkResult(
        deviceModel: 'Fast Device',
        chip: 'Flagship',
        ramMb: 12000,
        medianFrameMsTier1: 0.8,
        medianFrameMsTier2: 1.8,
        medianFrameMsTier3: 3.5,
        p95FrameMs: 4.0,
        thermalSlope: 0.005,
        totalFramesRendered: 200,
        benchmarkDuration: const Duration(seconds: 5),
        timestamp: DateTime.now(),
        benchmarkTier: DeviceHardwareTier.high,
      );

      final slowResult = DeviceBenchmarkResult(
        deviceModel: 'Slow Device',
        chip: 'Entry',
        ramMb: 3000,
        medianFrameMsTier1: 8.0,
        medianFrameMsTier2: 18.0,
        medianFrameMsTier3: 35.0,
        p95FrameMs: 42.0,
        thermalSlope: 0.08,
        totalFramesRendered: 50,
        benchmarkDuration: const Duration(seconds: 5),
        timestamp: DateTime.now(),
        benchmarkTier: DeviceHardwareTier.low,
      );

      expect(fastResult.performanceScore, greaterThan(slowResult.performanceScore));
      expect(fastResult.performanceScore, greaterThanOrEqualTo(90.0));
      expect(slowResult.performanceScore, lessThan(40.0));
    });
  });

  group('DeviceProfileTelemetryService', () {
    test('sanitizes model ID for safe Firestore document paths', () {
      expect(DeviceProfileTelemetryService.sanitizeModelId('Pixel 8 Pro'), 'Pixel_8_Pro');
      expect(DeviceProfileTelemetryService.sanitizeModelId('iPhone 15,3'), 'iPhone_15_3');
      expect(DeviceProfileTelemetryService.sanitizeModelId('SM-S928B / Galaxy'), 'SM-S928B_Galaxy');
    });
  });

  group('DeviceBenchmarkService', () {
    test('executes benchmark, returns result, and caches in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = DeviceBenchmarkService(prefs: prefs);

      const caps = HardwareCapabilities(
        model: 'TestBenchmarkPhone',
        manufacturer: 'TestVendor',
        device: 'test_dev',
        hardware: 'test_hw',
        board: 'test_bd',
        socModel: 'TestChip 8',
        osVersion: '14',
        sdkInt: 34,
        hardwareTier: 'high',
        totalRamBytes: 8 * 1024 * 1024 * 1024,
        availRamBytes: 4 * 1024 * 1024 * 1024,
        lowMemory: false,
        cameras: [
          CameraFormatCapability(
            id: '0',
            facing: 'back',
            resolutions: [CameraResolution(width: 3840, height: 2160)],
            maxFps: 60,
            is10BitSupported: true,
            isHdrSupported: true,
          ),
        ],
        encoders: [
          EncoderProfileCapability(
            name: 'hevc',
            codec: 'video/hevc',
            isHardwareAccelerated: true,
            maxWidth: 3840,
            maxHeight: 2160,
            maxBitrateBps: 80000000,
            maxFps: 60,
            supports10Bit: true,
            profileLevels: [],
          ),
        ],
        gpu: GpuCapability(
          glEsVersion: '3.2',
          reqGlEsVersion: 0x00030002,
          hasVulkan: true,
          hasUnifiedMemory: true,
        ),
        rawMap: {},
      );

      // Run benchmark with shorter duration for unit testing
      final result = await service.runBenchmark(
        capabilities: caps,
        targetDuration: const Duration(milliseconds: 150),
        force: true,
      );

      expect(result.deviceModel, 'TestBenchmarkPhone');
      expect(result.totalFramesRendered, greaterThan(0));
      expect(result.medianFrameMsTier1, greaterThan(0.0));
      expect(result.medianFrameMsTier2, greaterThan(0.0));
      expect(result.medianFrameMsTier3, greaterThan(0.0));

      // Verify cached in prefs
      final cached = await service.getCachedBenchmark();
      expect(cached, isNotNull);
      expect(cached!.deviceModel, 'TestBenchmarkPhone');
    });
  });
}
