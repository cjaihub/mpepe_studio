import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/device_benchmark_result.dart';
import '../models/device_hardware_tier.dart';

/// Crowd-learned aggregate profile loaded from `deviceProfiles/{model}` in Firestore.
class DeviceCrowdProfile {
  final String model;
  final int sampleCount;
  final DeviceHardwareTier recommendedTier;
  final int? recommendedMaxLiveWidth;
  final int? recommendedMaxLiveHeight;
  final int? recommendedMaxLiveFps;
  final double avgThermalSlope;
  final double avgFrameMs;
  final bool hasKnownThermalThrottling;
  final DateTime? lastUpdated;

  const DeviceCrowdProfile({
    required this.model,
    required this.sampleCount,
    required this.recommendedTier,
    this.recommendedMaxLiveWidth,
    this.recommendedMaxLiveHeight,
    this.recommendedMaxLiveFps,
    this.avgThermalSlope = 0.01,
    this.avgFrameMs = 4.0,
    this.hasKnownThermalThrottling = false,
    this.lastUpdated,
  });

  factory DeviceCrowdProfile.fromDoc(String model, Map<String, dynamic>? data) {
    if (data == null) {
      return DeviceCrowdProfile(
        model: model,
        sampleCount: 0,
        recommendedTier: DeviceHardwareTier.medium,
      );
    }

    final ts = data['lastUpdated'];
    DateTime? updatedDate;
    if (ts is Timestamp) {
      updatedDate = ts.toDate();
    } else if (ts is int) {
      updatedDate = DateTime.fromMillisecondsSinceEpoch(ts);
    }

    return DeviceCrowdProfile(
      model: model,
      sampleCount: (data['sampleCount'] as num?)?.toInt() ?? 1,
      recommendedTier: DeviceHardwareTier.fromString(data['recommendedTier'] as String?),
      recommendedMaxLiveWidth: (data['recommendedMaxLiveWidth'] as num?)?.toInt(),
      recommendedMaxLiveHeight: (data['recommendedMaxLiveHeight'] as num?)?.toInt(),
      recommendedMaxLiveFps: (data['recommendedMaxLiveFps'] as num?)?.toInt(),
      avgThermalSlope: (data['avgThermalSlope'] as num?)?.toDouble() ?? 0.01,
      avgFrameMs: (data['avgFrameMs'] as num?)?.toDouble() ?? 4.0,
      hasKnownThermalThrottling: data['hasKnownThermalThrottling'] as bool? ?? false,
      lastUpdated: updatedDate,
    );
  }
}

/// Service handling telemetry reporting and retrieval of crowd-learned `deviceProfiles/{model}`.
class DeviceProfileTelemetryService {
  final FirebaseFirestore? firestore;

  DeviceProfileTelemetryService({this.firestore});

  FirebaseFirestore? get _effectiveFirestore {
    if (firestore != null) return firestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  static String sanitizeModelId(String rawModel) {
    return rawModel
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  /// Fetches crowd-learned profile from `deviceProfiles/{model}`.
  Future<DeviceCrowdProfile?> fetchProfile(String rawModel) async {
    final modelId = sanitizeModelId(rawModel);
    if (modelId.isEmpty) return null;

    final firestore = _effectiveFirestore;
    if (firestore == null) return null;

    try {
      final doc = await firestore.collection('deviceProfiles').doc(modelId).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return DeviceCrowdProfile.fromDoc(modelId, doc.data());
    } catch (e) {
      debugPrint('[DeviceProfileTelemetryService] Fetch profile failed: $e');
      return null;
    }
  }

  /// Sends anonymous aggregated telemetry from the first-run benchmark to `deviceProfiles/{model}`.
  /// Never contains user IDs, PII, or location data.
  Future<void> sendBenchmarkTelemetry(DeviceBenchmarkResult result) async {
    final modelId = sanitizeModelId(result.deviceModel);
    if (modelId.isEmpty) return;

    final firestore = _effectiveFirestore;
    if (firestore == null) return;

    try {
      final docRef = firestore.collection('deviceProfiles').doc(modelId);
      final payload = {
        'model': result.deviceModel,
        'chip': result.chip,
        'ramMb': result.ramMb,
        'hardwareTier': result.benchmarkTier.name,
        'sampleCount': FieldValue.increment(1),
        'lastReportedFrameMs': result.medianFrameMsTier2,
        'lastReportedThermalSlope': result.thermalSlope,
        'performanceScore': result.performanceScore,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await docRef.set(payload, SetOptions(merge: true));
      debugPrint('[DeviceProfileTelemetryService] Telemetry sent for $modelId');
    } catch (e) {
      // Telemetry failure is completely non-blocking
      debugPrint('[DeviceProfileTelemetryService] Telemetry send failed: $e');
    }
  }
}
