import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/device/models/compute_task.dart';
import 'package:oneova/looks/device/models/device_hardware_tier.dart';
import 'package:oneova/looks/device/models/thermal_state.dart';
import 'package:oneova/looks/device/router/compute_router.dart';

void main() {
  const router = ComputeRouter();

  final testTimestamp = DateTime(2026, 1, 1, 12, 0);

  final nominalThermal = ThermalSnapshot(
    headroom: 0.35,
    forecastHeadroom10s: 0.38,
    thermalLevel: ThermalLevel.nominal,
    isBatterySaver: false,
    batteryLevel: 90,
    isCharging: false,
    activeMitigationTier: 0,
    activeMitigations: const [],
    timestamp: testTimestamp,
  );

  final throttledThermal = ThermalSnapshot(
    headroom: 0.92,
    forecastHeadroom10s: 0.98,
    thermalLevel: ThermalLevel.fair,
    isBatterySaver: false,
    batteryLevel: 70,
    isCharging: false,
    activeMitigationTier: 2,
    activeMitigations: const [MitigationAction.reduceMlRate, MitigationAction.disableHeavyEffects],
    timestamp: testTimestamp,
  );

  final criticalThermal = ThermalSnapshot(
    headroom: 1.25,
    forecastHeadroom10s: 1.30,
    thermalLevel: ThermalLevel.critical,
    isBatterySaver: false,
    batteryLevel: 60,
    isCharging: false,
    activeMitigationTier: 6,
    activeMitigations: const [MitigationAction.dropResolution],
    timestamp: testTimestamp,
  );

  const goodBattery = DeviceBatteryState(level: 85, isCharging: false, isPowerSaveMode: false);
  const lowBattery = DeviceBatteryState(level: 10, isCharging: false, isPowerSaveMode: false);
  const powerSaveBattery = DeviceBatteryState(level: 18, isCharging: false, isPowerSaveMode: true);

  const fastWifi = NetworkQuality(type: NetworkType.wifi, bandwidthMbps: 80.0, roundTripTimeMs: 20.0);
  const slowCellular = NetworkQuality(type: NetworkType.cellular, bandwidthMbps: 1.0, roundTripTimeMs: 550.0);
  const offlineNet = NetworkQuality(type: NetworkType.none, bandwidthMbps: 0.0, roundTripTimeMs: 9999.0);

  group('ComputeRouter: Live & Camera Looks', () {
    test('routes to device on nominal thermal envelope', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.liveCameraLooks),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.device);
    });

    test('falls back to deviceLow when device is throttled or low tier, never cloud', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.liveCameraLooks),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: throttledThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.deviceLow);
      expect(decision.target, isNot(ComputeTarget.cloud));
    });

    test('routes to deviceLow when battery saver is active', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.liveCameraLooks),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: powerSaveBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.deviceLow);
    });
  });

  group('ComputeRouter: Scopes & Scope Sentinel', () {
    test('runs full GPU scopes on device nominally', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.scopesSentinel),
        hardwareTier: DeviceHardwareTier.medium,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.device);
    });

    test('drops to deviceLow on critical heat or low tier', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.scopesSentinel),
        hardwareTier: DeviceHardwareTier.low,
        thermalSnapshot: criticalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.deviceLow);
    });
  });

  group('ComputeRouter: Voice & NL Grading', () {
    test('routes to cloud when online with good connection', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.voiceNlGrading),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.cloud);
    });

    test('falls back to on-device LLM when offline', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.voiceNlGrading),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: offlineNet,
      );

      expect(decision.target, ComputeTarget.device);
      expect(decision.reason, contains('on-device LLM'));
    });

    test('falls back to on-device LLM when network is slow', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.voiceNlGrading),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: slowCellular,
      );

      expect(decision.target, ComputeTarget.device);
    });

    test('falls back to on-device when cloud spend is RED for free user', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.voiceNlGrading, isUserProOrBusiness: false),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
        cloudSpend: CloudSpendLevel.red,
      );

      expect(decision.target, ComputeTarget.device);
    });

    test('preserves cloud access when cloud spend is RED for Pro/Business user', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.voiceNlGrading, isUserProOrBusiness: true),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
        cloudSpend: CloudSpendLevel.red,
      );

      expect(decision.target, ComputeTarget.cloud);
    });
  });

  group('ComputeRouter: Complex Grading & Rotoscoping', () {
    test('routes to cloud SAM 2 when online', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.complexGradingRotoscope),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.cloud);
    });

    test('falls back to on-device offline pro mode when offline', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.complexGradingRotoscope),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: offlineNet,
      );

      expect(decision.target, ComputeTarget.device);
    });

    test('routes to on-device on Amber cloud spend when phone is high tier', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.complexGradingRotoscope, isUserProOrBusiness: false),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
        cloudSpend: CloudSpendLevel.amber,
      );

      expect(decision.target, ComputeTarget.device);
    });
  });

  group('ComputeRouter: Photo Export', () {
    test('exports standard photo on device', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.photoExport, estimatedMegapixels: 12.0),
        hardwareTier: DeviceHardwareTier.medium,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.device);
    });

    test('offloads huge 50MP photo to Cloud Render on low-tier device', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.photoExport, estimatedMegapixels: 50.0),
        hardwareTier: DeviceHardwareTier.low,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.cloud);
      expect(decision.reason, contains('Cloud Render'));
    });
  });

  group('ComputeRouter: Video Export', () {
    test('exports standard video on hardware encoder', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.videoExport, durationSeconds: 30.0),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.device);
    });

    test('offloads to Cloud Render when device battery is low (<15%)', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.videoExport, durationSeconds: 45.0),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: lowBattery, // 10% battery
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.cloud);
      expect(decision.reason, contains('Low battery'));
    });

    test('offloads to Cloud Render when device is overheating', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.videoExport, durationSeconds: 45.0),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: criticalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.cloud);
      expect(decision.reason, contains('Overheating'));
    });

    test('offloads 4K heavy video on low-tier phone', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.videoExport, durationSeconds: 120.0, estimatedMegapixels: 8.3),
        hardwareTier: DeviceHardwareTier.low,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.cloud);
    });
  });

  group('ComputeRouter: AI Enhance & Policy Overrides', () {
    test('routes AI enhance to cloud GPU normally', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.aiEnhance),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
      );

      expect(decision.target, ComputeTarget.cloud);
    });

    test('routes AI enhance to lighter on-device model when offline on high tier phone', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.aiEnhance),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: offlineNet,
      );

      expect(decision.target, ComputeTarget.deviceLow);
    });

    test('honors Remote Config policy override', () {
      final decision = router.route(
        job: const ComputeJobSpec(taskType: ComputeTaskType.videoExport),
        hardwareTier: DeviceHardwareTier.high,
        thermalSnapshot: nominalThermal,
        batteryState: goodBattery,
        networkQuality: fastWifi,
        dynamicPolicyOverrides: {'override_videoExport': 'cloud'},
      );

      expect(decision.target, ComputeTarget.cloud);
      expect(decision.reason, contains('Remote Config policy override'));
    });
  });
}
