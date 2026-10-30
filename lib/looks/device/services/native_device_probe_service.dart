import 'package:flutter/foundation.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import '../models/device_hardware_tier.dart';

/// Service responsible for probing device hardware capabilities and caching the result.
class NativeDeviceProbeService {
  HardwareCapabilities? _cachedCapabilities;

  HardwareCapabilities? get cached => _cachedCapabilities;

  Future<HardwareCapabilities> probe({bool forceRefresh = false}) async {
    if (_cachedCapabilities != null && !forceRefresh) {
      return _cachedCapabilities!;
    }

    try {
      final probed = await DeviceCapabilityBridge.probe();
      _cachedCapabilities = probed;
      debugPrint('[NativeDeviceProbeService] Probed ${probed.model} (${probed.hardwareTier})');
      return probed;
    } catch (e, st) {
      debugPrint('[NativeDeviceProbeService] Failed to probe hardware: $e\n$st');
      // Create fallback
      final fallback = _createFallback();
      _cachedCapabilities = fallback;
      return fallback;
    }
  }

  DeviceHardwareTier getHardwareTier() {
    final caps = _cachedCapabilities;
    if (caps == null) return DeviceHardwareTier.medium;
    return DeviceHardwareTier.fromString(caps.hardwareTier);
  }

  HardwareCapabilities _createFallback() {
    return const HardwareCapabilities(
      model: 'Device',
      manufacturer: 'Generic',
      device: 'oneova_device',
      hardware: 'hardware',
      board: 'board',
      socModel: 'chip',
      osVersion: '',
      sdkInt: 0,
      hardwareTier: 'medium',
      totalRamBytes: 4 * 1024 * 1024 * 1024,
      availRamBytes: 2 * 1024 * 1024 * 1024,
      lowMemory: false,
      cameras: [],
      encoders: [],
      gpu: GpuCapability(
        glEsVersion: '3.0',
        reqGlEsVersion: 0x00030000,
        hasVulkan: false,
        hasUnifiedMemory: true,
      ),
      rawMap: {},
    );
  }
}
