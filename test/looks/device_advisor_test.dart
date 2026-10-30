import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/device/advisor/device_advisor.dart';
import 'package:oneova/looks/device/models/device_hardware_tier.dart';
import 'package:oneova/looks/device/models/surface_ceiling.dart';
import 'package:oneova/looks/device/services/device_profile_telemetry_service.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';

HardwareCapabilities _makeCaps({
  String tier = 'high',
  int ramGb = 8,
  bool supports4k = true,
}) {
  return HardwareCapabilities(
    model: 'TestPhone Pro',
    manufacturer: 'TestBrand',
    device: 'test_dev',
    hardware: 'soc9000',
    board: 'board_a',
    socModel: 'TestChip 9000',
    osVersion: '14',
    sdkInt: 34,
    hardwareTier: tier,
    totalRamBytes: ramGb * 1024 * 1024 * 1024,
    availRamBytes: (ramGb ~/ 2) * 1024 * 1024 * 1024,
    lowMemory: false,
    cameras: [
      CameraFormatCapability(
        id: '0',
        facing: 'back',
        resolutions: [
          if (supports4k) const CameraResolution(width: 3840, height: 2160),
          const CameraResolution(width: 1920, height: 1080),
        ],
        maxFps: 60,
        is10BitSupported: true,
        isHdrSupported: true,
      ),
    ],
    encoders: [
      EncoderProfileCapability(
        name: 'test.hevc',
        codec: 'video/hevc',
        isHardwareAccelerated: true,
        maxWidth: supports4k ? 3840 : 1920,
        maxHeight: supports4k ? 2160 : 1080,
        maxBitrateBps: 80000000,
        maxFps: 60,
        supports10Bit: true,
        profileLevels: [],
      ),
    ],
    gpu: const GpuCapability(
      glEsVersion: '3.2',
      reqGlEsVersion: 0x00030002,
      hasVulkan: true,
      hasUnifiedMemory: true,
    ),
    rawMap: {},
  );
}

void main() {
  group('DeviceAdvisor Safe Ceilings', () {
    test('computes high tier ceilings for Pro device', () {
      final caps = _makeCaps(tier: 'high', ramGb: 12, supports4k: true);
      final advisor = DeviceAdvisor(capabilities: caps);

      expect(advisor.effectiveTier, DeviceHardwareTier.high);

      // Live ceiling
      final live = advisor.liveCeiling;
      expect(live.maxWidth, 1920);
      expect(live.maxHeight, 1080);
      expect(live.maxFps, 60);
      expect(live.maxBeautyLevel, 1.0);
      expect(live.maxSegmentationFps, 30);
      expect(live.allowHdr, isTrue);

      // Camera ceiling: 4K60
      final cam = advisor.cameraCeiling;
      expect(cam.maxWidth, 3840);
      expect(cam.maxHeight, 2160);
      expect(cam.maxFps, 60);
      expect(cam.maxLutSize, 65);

      // Editor ceiling
      final editor = advisor.editorCeiling;
      expect(editor.maxWidth, 3840);
      expect(editor.maxHeight, 2160);
    });

    test('computes low tier ceilings for efficiency device', () {
      final caps = _makeCaps(tier: 'low', ramGb: 3, supports4k: false);
      final advisor = DeviceAdvisor(capabilities: caps);

      expect(advisor.effectiveTier, DeviceHardwareTier.low);

      final live = advisor.liveCeiling;
      expect(live.maxWidth, 1280);
      expect(live.maxHeight, 720);
      expect(live.maxFps, 30);
      expect(live.maxBeautyLevel, 0.5);
      expect(live.maxSegmentationFps, 12);
      expect(live.allowHdr, isFalse);

      final cam = advisor.cameraCeiling;
      expect(cam.maxWidth, 1920);
      expect(cam.maxHeight, 1080);
      expect(cam.maxFps, 30);
    });

    test('crowd profile overrides local tier if sufficient samples exist', () {
      final caps = _makeCaps(tier: 'high', ramGb: 8);
      const crowd = DeviceCrowdProfile(
        model: 'TestPhone Pro',
        sampleCount: 15,
        recommendedTier: DeviceHardwareTier.medium, // Crowd discovered thermal issues
        hasKnownThermalThrottling: true,
      );

      final advisor = DeviceAdvisor(capabilities: caps, crowdProfile: crowd);
      expect(advisor.effectiveTier, DeviceHardwareTier.medium);
    });
  });

  group('DeviceAdvisor Enforcement and Pro Override', () {
    test('enforces resolution ceiling and rejects 4K live when enforced', () {
      final caps = _makeCaps(tier: 'low', ramGb: 3);
      final advisor = DeviceAdvisor(
        capabilities: caps,
        enforcementMode: AdvisorEnforcementMode.enforce,
        proOverride: false,
      );

      final result = advisor.validateResolution(
        surface: SurfaceType.live,
        width: 3840,
        height: 2160,
      );

      expect(result.isAllowed, isFalse);
      expect(result.reason, contains('exceeds safe ceiling'));
      expect(result.isOverridden, isFalse);
    });

    test('warns but allows resolution when enforcement mode is warn', () {
      final caps = _makeCaps(tier: 'low', ramGb: 3);
      final advisor = DeviceAdvisor(
        capabilities: caps,
        enforcementMode: AdvisorEnforcementMode.warn,
        proOverride: false,
      );

      final result = advisor.validateResolution(
        surface: SurfaceType.live,
        width: 3840,
        height: 2160,
      );

      expect(result.isAllowed, isTrue);
      expect(result.reason, contains('Advisory:'));
    });

    test('bypasses ceiling when Pro override is enabled', () {
      final caps = _makeCaps(tier: 'low', ramGb: 3);
      final advisor = DeviceAdvisor(
        capabilities: caps,
        enforcementMode: AdvisorEnforcementMode.enforce,
        proOverride: true, // Pro override enabled by user
      );

      final result = advisor.validateResolution(
        surface: SurfaceType.live,
        width: 3840,
        height: 2160,
      );

      expect(result.isAllowed, isTrue);
      expect(result.isOverridden, isTrue);
      expect(result.reason, contains('Bypassed by Pro override'));
    });

    test('validates FPS and beauty limits', () {
      final caps = _makeCaps(tier: 'low', ramGb: 3);
      final advisor = DeviceAdvisor(
        capabilities: caps,
        enforcementMode: AdvisorEnforcementMode.enforce,
        proOverride: false,
      );

      final fpsResult = advisor.validateFps(surface: SurfaceType.live, fps: 60);
      expect(fpsResult.isAllowed, isFalse);
      expect(fpsResult.reason, contains('60fps exceeds safe ceiling of 30fps'));

      final beautyResult = advisor.validateBeautyLevel(surface: SurfaceType.live, level: 0.9);
      expect(beautyResult.isAllowed, isFalse);
      expect(beautyResult.reason, contains('Beauty level 90% exceeds safe ceiling'));
    });
  });
}
