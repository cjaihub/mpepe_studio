import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../advisor/device_advisor.dart';
import '../governor/thermal_governor.dart';
import '../models/compute_task.dart';
import '../models/device_benchmark_result.dart';
import '../models/device_hardware_tier.dart';
import '../models/thermal_state.dart';
import '../router/compute_router.dart';
import '../services/device_benchmark_service.dart';
import '../services/device_profile_telemetry_service.dart';
import '../services/native_device_probe_service.dart';

// -------------------------------------------------------------
// Core Services Providers
// -------------------------------------------------------------

final nativeDeviceProbeServiceProvider = Provider<NativeDeviceProbeService>((ref) {
  return NativeDeviceProbeService();
});

final deviceProfileTelemetryServiceProvider = Provider<DeviceProfileTelemetryService>((ref) {
  return DeviceProfileTelemetryService();
});

final deviceBenchmarkServiceProvider = Provider<DeviceBenchmarkService>((ref) {
  final telemetry = ref.watch(deviceProfileTelemetryServiceProvider);
  return DeviceBenchmarkService(telemetryService: telemetry);
});

// -------------------------------------------------------------
// Hardware Capabilities & Benchmark Providers
// -------------------------------------------------------------

final hardwareCapabilitiesProvider = FutureProvider<HardwareCapabilities>((ref) async {
  final service = ref.watch(nativeDeviceProbeServiceProvider);
  return await service.probe();
});

final deviceHardwareTierProvider = Provider<DeviceHardwareTier>((ref) {
  final capsAsync = ref.watch(hardwareCapabilitiesProvider);
  return capsAsync.maybeWhen(
    data: (caps) => DeviceHardwareTier.fromString(caps.hardwareTier),
    orElse: () => DeviceHardwareTier.medium,
  );
});

final deviceBenchmarkResultProvider = FutureProvider<DeviceBenchmarkResult>((ref) async {
  final benchmarkService = ref.watch(deviceBenchmarkServiceProvider);
  final caps = await ref.watch(hardwareCapabilitiesProvider.future);
  return await benchmarkService.runBenchmark(capabilities: caps);
});

final deviceCrowdProfileProvider = FutureProvider<DeviceCrowdProfile?>((ref) async {
  final caps = await ref.watch(hardwareCapabilitiesProvider.future);
  final telemetry = ref.watch(deviceProfileTelemetryServiceProvider);
  return await telemetry.fetchProfile(caps.model);
});

// -------------------------------------------------------------
// Remote Config: Enforcement Mode & Thermal Ladder
// -------------------------------------------------------------

final advisorEnforcementProvider = Provider<AdvisorEnforcementMode>((ref) {
  try {
    final raw = FirebaseRemoteConfig.instance.getString('advisor_enforcement');
    if (raw.trim().isNotEmpty) {
      return AdvisorEnforcementMode.fromString(raw);
    }
  } catch (_) {}
  return AdvisorEnforcementMode.enforce;
});

final thermalLadderConfigProvider = Provider<ThermalLadderConfig>((ref) {
  try {
    final raw = FirebaseRemoteConfig.instance.getString('thermal_ladder');
    if (raw.trim().isNotEmpty) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ThermalLadderConfig.fromMap(map);
    }
  } catch (e) {
    debugPrint('[thermalLadderConfigProvider] Remote config parse error: $e');
  }
  return const ThermalLadderConfig();
});

// -------------------------------------------------------------
// Pro Override Notifier (Settings -> Camera & Live)
// -------------------------------------------------------------

class ProOverrideNotifier extends Notifier<bool> {
  static const String _prefKey = 'oneova_pro_override_active';

  @override
  bool build() {
    _loadState();
    return false;
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getBool(_prefKey) ?? false;
      state = val;
    } catch (_) {}
  }

  Future<void> setOverride(bool value) async {
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }
}

final proOverrideProvider = NotifierProvider<ProOverrideNotifier, bool>(
  ProOverrideNotifier.new,
);

// -------------------------------------------------------------
// DeviceAdvisor Provider
// -------------------------------------------------------------

final deviceAdvisorProvider = Provider<DeviceAdvisor>((ref) {
  final capsAsync = ref.watch(hardwareCapabilitiesProvider);
  final benchmarkAsync = ref.watch(deviceBenchmarkResultProvider);
  final crowdAsync = ref.watch(deviceCrowdProfileProvider);
  final enforcement = ref.watch(advisorEnforcementProvider);
  final proOverride = ref.watch(proOverrideProvider);

  final caps = capsAsync.value ??
      const HardwareCapabilities(
        model: 'Generic',
        manufacturer: 'Generic',
        device: 'device',
        hardware: 'hardware',
        board: 'board',
        socModel: 'soc',
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

  return DeviceAdvisor(
    capabilities: caps,
    benchmark: benchmarkAsync.value,
    crowdProfile: crowdAsync.value,
    enforcementMode: enforcement,
    proOverride: proOverride,
  );
});

// -------------------------------------------------------------
// Thermal Governor & Live State Stream Providers
// -------------------------------------------------------------

final thermalGovernorProvider = Provider<ThermalGovernor>((ref) {
  final ladder = ref.watch(thermalLadderConfigProvider);
  final governor = ThermalGovernor(ladderConfig: ladder);
  ref.onDispose(() => governor.dispose());
  return governor;
});

final thermalSnapshotStreamProvider = StreamProvider<ThermalSnapshot>((ref) {
  final governor = ref.watch(thermalGovernorProvider);
  return governor.snapshotStream;
});

final thermalMitigationTierProvider = Provider<int>((ref) {
  final snapshotAsync = ref.watch(thermalSnapshotStreamProvider);
  return snapshotAsync.maybeWhen(
    data: (snap) => snap.activeMitigationTier,
    orElse: () => ref.watch(thermalGovernorProvider).currentTier,
  );
});

// -------------------------------------------------------------
// Cloud Spend & Compute Router Providers
// -------------------------------------------------------------

final cloudSpendLevelProvider = StreamProvider<CloudSpendLevel>((ref) {
  try {
    return FirebaseFirestore.instance
        .doc('opsConfig/cloudSpend')
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return CloudSpendLevel.green;
      final level = snap.data()?['level'] as String?;
      return CloudSpendLevel.fromString(level);
    }).handleError((_) => CloudSpendLevel.green);
  } catch (_) {
    return Stream.value(CloudSpendLevel.green);
  }
});

final computePolicyProvider = Provider<Map<String, dynamic>>((ref) {
  try {
    final raw = FirebaseRemoteConfig.instance.getString('compute_policy');
    if (raw.trim().isNotEmpty) {
      return jsonDecode(raw) as Map<String, dynamic>;
    }
  } catch (_) {}
  return const {};
});

final computeRouterProvider = Provider<ComputeRouter>((ref) {
  final policy = ref.watch(computePolicyProvider);
  return ComputeRouter(policyOverrides: policy);
});
