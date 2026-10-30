import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import '../models/device_benchmark_result.dart';
import '../models/device_hardware_tier.dart';
import '../models/surface_ceiling.dart';
import '../services/device_profile_telemetry_service.dart';

/// Enforcement mode for DeviceAdvisor ceilings, controlled via Remote Config key `advisor_enforcement`.
enum AdvisorEnforcementMode {
  enforce,
  warn,
  off;

  static AdvisorEnforcementMode fromString(String? val) {
    if (val == null) return AdvisorEnforcementMode.enforce;
    return switch (val.toLowerCase().trim()) {
      'off' => AdvisorEnforcementMode.off,
      'warn' => AdvisorEnforcementMode.warn,
      _ => AdvisorEnforcementMode.enforce,
    };
  }
}

/// DeviceAdvisor:
/// Merges dynamic hardware probe + silent benchmark + crowd-learned deviceProfiles/{model}
/// to compute safe hardware and thermal operating ceilings per surface (Live, Camera, Editor).
class DeviceAdvisor {
  final HardwareCapabilities capabilities;
  final DeviceBenchmarkResult? benchmark;
  final DeviceCrowdProfile? crowdProfile;
  final AdvisorEnforcementMode enforcementMode;
  final bool proOverride;

  const DeviceAdvisor({
    required this.capabilities,
    this.benchmark,
    this.crowdProfile,
    this.enforcementMode = AdvisorEnforcementMode.enforce,
    this.proOverride = false,
  });

  /// Computes the effective device hardware tier by reconciling probe, benchmark, and crowd data.
  DeviceHardwareTier get effectiveTier {
    // 1. Crowd profile recommendation takes priority if there are sufficient samples
    if (crowdProfile != null && crowdProfile!.sampleCount >= 5) {
      return crowdProfile!.recommendedTier;
    }
    // 2. Local benchmark performance tier
    if (benchmark != null) {
      return benchmark!.benchmarkTier;
    }
    // 3. Probed hardware tier
    return DeviceHardwareTier.fromString(capabilities.hardwareTier);
  }

  /// Safe ceiling for live streaming (sustained load over 30-120 minutes).
  SurfaceCeiling get liveCeiling {
    final tier = effectiveTier;
    final hasKnownThrottling = crowdProfile?.hasKnownThermalThrottling ?? false;

    return switch (tier) {
      DeviceHardwareTier.high when !hasKnownThrottling => SurfaceCeiling(
          surface: SurfaceType.live,
          maxWidth: 1920,
          maxHeight: 1080,
          maxFps: 60,
          maxBeautyLevel: 1.0,
          maxSegmentationFps: 30,
          allowHdr: capabilities.supportsHdrCapture,
          allowSharpen: true,
          maxLutSize: 33,
          maxLutStack: 4,
          allowCloudOffload: true,
          reason: 'High-performance sustained thermal envelope verified.',
        ),
      DeviceHardwareTier.high || DeviceHardwareTier.medium when !hasKnownThrottling => SurfaceCeiling(
          surface: SurfaceType.live,
          maxWidth: 1920,
          maxHeight: 1080,
          maxFps: 30,
          maxBeautyLevel: 0.8,
          maxSegmentationFps: 20,
          allowHdr: false,
          allowSharpen: true,
          maxLutSize: 33,
          maxLutStack: 2,
          allowCloudOffload: true,
          reason: 'Balanced 1080p30 ceiling for sustained broadcast without thermal throttling.',
        ),
      _ => SurfaceCeiling(
          surface: SurfaceType.live,
          maxWidth: 1280,
          maxHeight: 720,
          maxFps: 30,
          maxBeautyLevel: 0.5,
          maxSegmentationFps: 12,
          allowHdr: false,
          allowSharpen: false,
          maxLutSize: 17,
          maxLutStack: 1,
          allowCloudOffload: true,
          reason: 'Efficiency tier: 720p30 capped to protect sustained battery and thermal headroom.',
        ),
    };
  }

  /// Safe ceiling for camera recording (burst capture up to 10 minutes).
  SurfaceCeiling get cameraCeiling {
    final tier = effectiveTier;
    final supports4k = capabilities.supports4KRecording;

    return switch (tier) {
      DeviceHardwareTier.high when supports4k => SurfaceCeiling(
          surface: SurfaceType.camera,
          maxWidth: 3840,
          maxHeight: 2160,
          maxFps: 60,
          maxBeautyLevel: 1.0,
          maxSegmentationFps: 30,
          allowHdr: capabilities.supportsHdrCapture,
          allowSharpen: true,
          maxLutSize: 65,
          maxLutStack: 4,
          allowCloudOffload: false,
          reason: 'Full 4K60 Pro capture supported with hardware HEVC.',
        ),
      DeviceHardwareTier.high => SurfaceCeiling(
          surface: SurfaceType.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          maxFps: 60,
          maxBeautyLevel: 1.0,
          maxSegmentationFps: 30,
          allowHdr: capabilities.supportsHdrCapture,
          allowSharpen: true,
          maxLutSize: 65,
          maxLutStack: 4,
          allowCloudOffload: false,
          reason: 'Pro tier 1080p60 capture supported.',
        ),
      DeviceHardwareTier.medium when supports4k => SurfaceCeiling(
          surface: SurfaceType.camera,
          maxWidth: 3840,
          maxHeight: 2160,
          maxFps: 30,
          maxBeautyLevel: 0.85,
          maxSegmentationFps: 20,
          allowHdr: capabilities.supportsHdrCapture,
          allowSharpen: true,
          maxLutSize: 33,
          maxLutStack: 2,
          allowCloudOffload: false,
          reason: 'Standard tier: 4K30 recording supported.',
        ),
      DeviceHardwareTier.medium => SurfaceCeiling(
          surface: SurfaceType.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          maxFps: 60,
          maxBeautyLevel: 0.85,
          maxSegmentationFps: 20,
          allowHdr: false,
          allowSharpen: true,
          maxLutSize: 33,
          maxLutStack: 2,
          allowCloudOffload: false,
          reason: '1080p60 recording supported.',
        ),
      DeviceHardwareTier.low => SurfaceCeiling(
          surface: SurfaceType.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          maxFps: 30,
          maxBeautyLevel: 0.6,
          maxSegmentationFps: 15,
          allowHdr: false,
          allowSharpen: false,
          maxLutSize: 17,
          maxLutStack: 1,
          allowCloudOffload: false,
          reason: '1080p30 capped to ensure smooth camera preview and recording.',
        ),
    };
  }

  /// Safe ceiling for Photo & Video Editor.
  SurfaceCeiling get editorCeiling {
    final tier = effectiveTier;

    return switch (tier) {
      DeviceHardwareTier.high => SurfaceCeiling(
          surface: SurfaceType.editor,
          maxWidth: 3840,
          maxHeight: 2160,
          maxFps: 60,
          maxBeautyLevel: 1.0,
          maxSegmentationFps: 30,
          allowHdr: true,
          allowSharpen: true,
          maxLutSize: 65,
          maxLutStack: 4,
          allowCloudOffload: true,
          reason: 'Full desktop-grade grading graph active.',
        ),
      DeviceHardwareTier.medium => SurfaceCeiling(
          surface: SurfaceType.editor,
          maxWidth: 1920,
          maxHeight: 1080,
          maxFps: 60,
          maxBeautyLevel: 0.9,
          maxSegmentationFps: 20,
          allowHdr: false,
          allowSharpen: true,
          maxLutSize: 33,
          maxLutStack: 3,
          allowCloudOffload: true,
          reason: '1080p preview with background high-res rendering.',
        ),
      DeviceHardwareTier.low => SurfaceCeiling(
          surface: SurfaceType.editor,
          maxWidth: 1280,
          maxHeight: 720,
          maxFps: 30,
          maxBeautyLevel: 0.7,
          maxSegmentationFps: 10,
          allowHdr: false,
          allowSharpen: false,
          maxLutSize: 17,
          maxLutStack: 2,
          allowCloudOffload: true,
          reason: 'Low memory envelope: 720p interactive preview, cloud render available.',
        ),
    };
  }

  /// Returns safe ceiling for the requested surface.
  SurfaceCeiling ceilingFor(SurfaceType surface) => switch (surface) {
        SurfaceType.live => liveCeiling,
        SurfaceType.camera => cameraCeiling,
        SurfaceType.editor => editorCeiling,
      };

  /// Validates a requested resolution against the surface ceiling, applying enforcement mode and Pro override.
  CeilingValidationResult validateResolution({
    required SurfaceType surface,
    required int width,
    required int height,
  }) {
    if (enforcementMode == AdvisorEnforcementMode.off) {
      return CeilingValidationResult.valid;
    }

    final ceiling = ceilingFor(surface);
    final result = ceiling.validateResolution(
      width: width,
      height: height,
      proOverride: proOverride,
    );

    if (enforcementMode == AdvisorEnforcementMode.warn && !result.isAllowed) {
      return CeilingValidationResult(
        isAllowed: true,
        reason: 'Advisory: ${result.reason}',
        isOverridden: false,
      );
    }

    return result;
  }

  /// Validates a requested FPS against the surface ceiling.
  CeilingValidationResult validateFps({
    required SurfaceType surface,
    required int fps,
  }) {
    if (enforcementMode == AdvisorEnforcementMode.off) {
      return CeilingValidationResult.valid;
    }

    final ceiling = ceilingFor(surface);
    final result = ceiling.validateFps(
      fps: fps,
      proOverride: proOverride,
    );

    if (enforcementMode == AdvisorEnforcementMode.warn && !result.isAllowed) {
      return CeilingValidationResult(
        isAllowed: true,
        reason: 'Advisory: ${result.reason}',
        isOverridden: false,
      );
    }

    return result;
  }

  /// Validates beauty level against the surface ceiling.
  CeilingValidationResult validateBeautyLevel({
    required SurfaceType surface,
    required double level,
  }) {
    if (enforcementMode == AdvisorEnforcementMode.off) {
      return CeilingValidationResult.valid;
    }

    final ceiling = ceilingFor(surface);
    final result = ceiling.validateBeautyLevel(
      level: level,
      proOverride: proOverride,
    );

    if (enforcementMode == AdvisorEnforcementMode.warn && !result.isAllowed) {
      return CeilingValidationResult(
        isAllowed: true,
        reason: 'Advisory: ${result.reason}',
        isOverridden: false,
      );
    }

    return result;
  }
}
