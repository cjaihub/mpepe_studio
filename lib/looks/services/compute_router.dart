import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live cloud spend level maintained by Cloud Billing budget alerts.
enum CloudSpendLevel {
  /// Normal operations: cloud compute permitted across all eligible tiers.
  green,

  /// Budget threshold exceeded (>=80%): free-tier jobs are routed to the phone to cap costs.
  amber,

  /// Budget limit reached (>=100%): only paid/critical jobs use cloud; free and standard pro run locally.
  red;

  static CloudSpendLevel fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'amber':
        return CloudSpendLevel.amber;
      case 'red':
        return CloudSpendLevel.red;
      case 'green':
      default:
        return CloudSpendLevel.green;
    }
  }
}

/// Compute execution target chosen by the router.
enum ComputeTarget {
  /// Execute natively on the local device GPU / NPU / CPU.
  phone,

  /// Execute on Cloud Run GPU or GKE Spot GPU batch worker.
  cloud,

  /// Fallback to on-device offline LLM / LiteRT model.
  offlineFallback,
}

/// Hardware performance tier of the host device.
enum DeviceTier {
  low,
  mid,
  flagship;

  static DeviceTier fromInt(int tier) {
    if (tier <= 1) return DeviceTier.low;
    if (tier == 2) return DeviceTier.mid;
    return DeviceTier.flagship;
  }
}

/// Device thermal headroom classification (from ADPF / iOS thermalState).
enum ThermalHeadroomLevel {
  nominal,
  fair,
  serious,
  critical,
}

/// Types of visual tasks dispatched through the Compute Router.
enum ComputeTaskType {
  liveLook,
  cameraFilter,
  scopesSentinel,
  nlGradeCommand,
  photoExport,
  videoExport,
  rotoscope,
  aiEnhance,
  relight,
  skyReplace,
  batchGrade,
}

/// Telemetry and execution context provided to the Compute Router.
class ComputeRoutingRequest {
  final ComputeTaskType taskType;
  final String userTier; // 'free' | 'pro' | 'biz'
  final DeviceTier deviceTier;
  final ThermalHeadroomLevel thermalState;
  final double batteryLevel; // 0.0 - 1.0
  final bool isCharging;
  final bool isLowPowerMode;
  final bool hasNetwork;
  final int? networkRttMs;
  final int fileSizeBytes;
  final bool isProOverride;
  final bool isNonInteractive;

  const ComputeRoutingRequest({
    required this.taskType,
    this.userTier = 'free',
    this.deviceTier = DeviceTier.mid,
    this.thermalState = ThermalHeadroomLevel.nominal,
    this.batteryLevel = 1.0,
    this.isCharging = false,
    this.isLowPowerMode = false,
    this.hasNetwork = true,
    this.networkRttMs,
    this.fileSizeBytes = 0,
    this.isProOverride = false,
    this.isNonInteractive = false,
  });
}

/// Resulting decision made by the Compute Router.
class ComputeRoutingDecision {
  final ComputeTarget target;
  final String reason;
  final CloudSpendLevel cloudSpendLevel;
  final bool fallbackAllowed;

  const ComputeRoutingDecision({
    required this.target,
    required this.reason,
    required this.cloudSpendLevel,
    this.fallbackAllowed = true,
  });

  @override
  String toString() => 'ComputeRoutingDecision(target: $target, spend: $cloudSpendLevel, reason: $reason)';
}

/// Intelligent Hybrid Compute Router (§4.2, §4.5).
///
/// Dispatches visual computing workloads between phone GPU/NPU and Cloud GPU services.
/// Weighs device tier, thermal headroom forecast, battery state, network quality,
/// user entitlement tier, and the live Cloud Spend budget kill-switch (`opsConfig/cloudSpend`).
class ComputeRouter {
  final FirebaseFirestore _firestore;
  CloudSpendLevel _currentSpendLevel = CloudSpendLevel.green;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _spendSub;

  ComputeRouter({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance {
    _initSpendWatch();
  }

  /// Current cloud spend level.
  CloudSpendLevel get currentSpendLevel => _currentSpendLevel;

  /// Visible for testing to set the spend level directly.
  @visibleForTesting
  void setSpendLevelForTesting(CloudSpendLevel level) {
    _currentSpendLevel = level;
  }

  void _initSpendWatch() {
    try {
      _spendSub = _firestore
          .collection('opsConfig')
          .doc('cloudSpend')
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data()!;
          _currentSpendLevel = CloudSpendLevel.fromString(data['level'] as String?);
          debugPrint('[ComputeRouter] Cloud spend level updated: $_currentSpendLevel');
        }
      }, onError: (err) {
        debugPrint('[ComputeRouter] Could not watch opsConfig/cloudSpend: $err');
      });
    } catch (e) {
      debugPrint('[ComputeRouter] Error initializing spend watch: $e');
    }
  }

  /// Disposes background listeners.
  void dispose() {
    _spendSub?.cancel();
  }

  /// Evaluates the optimal compute target for a given task request.
  ComputeRoutingDecision route(ComputeRoutingRequest req) {
    final spend = _currentSpendLevel;

    // Rule 1: Realtime camera/live operations ALWAYS run on phone GPU ($0 cloud cost per frame).
    if (req.taskType == ComputeTaskType.liveLook ||
        req.taskType == ComputeTaskType.cameraFilter ||
        req.taskType == ComputeTaskType.scopesSentinel) {
      return ComputeRoutingDecision(
        target: ComputeTarget.phone,
        reason: 'Realtime camera and live stream operations run on device GPU (\$0 cloud cost).',
        cloudSpendLevel: spend,
      );
    }

    // Rule 2: Without network connectivity, fallback to local/offline.
    if (!req.hasNetwork) {
      return ComputeRoutingDecision(
        target: ComputeTarget.offlineFallback,
        reason: 'No network connection; routing to on-device offline models and shaders.',
        cloudSpendLevel: spend,
      );
    }

    // Rule 3: Budget Guard Kill-Switch RED Level (>=100% budget).
    // Only paid/critical jobs (Biz tier, or Pro with override) are permitted on the cloud.
    if (spend == CloudSpendLevel.red) {
      if (req.userTier != 'biz' && !(req.userTier == 'pro' && req.isProOverride)) {
        return ComputeRoutingDecision(
          target: ComputeTarget.phone,
          reason: 'Cloud compute paused by Budget Guard (RED level). Processing on-device.',
          cloudSpendLevel: spend,
        );
      }
    }

    // Rule 4: Budget Guard AMBER Level (>=80% budget).
    // Free-tier cloud jobs are strictly routed to the phone.
    if (spend == CloudSpendLevel.amber && req.userTier == 'free') {
      return ComputeRoutingDecision(
        target: ComputeTarget.phone,
        reason: 'Free-tier cloud jobs routed to phone by Budget Guard (AMBER level).',
        cloudSpendLevel: spend,
      );
    }

    // Rule 5: Natural language grading commands.
    // Online: Gemini Live / Flash API; Offline or slow network (RTT > 1200ms): on-device LLM.
    if (req.taskType == ComputeTaskType.nlGradeCommand) {
      if (req.networkRttMs != null && req.networkRttMs! > 1200) {
        return ComputeRoutingDecision(
          target: ComputeTarget.offlineFallback,
          reason: 'High network latency (${req.networkRttMs}ms); routing to on-device LLM.',
          cloudSpendLevel: spend,
        );
      }
      return ComputeRoutingDecision(
        target: ComputeTarget.cloud,
        reason: 'Routing to Gemini API with result & context caching.',
        cloudSpendLevel: spend,
      );
    }

    // Rule 6: Heavy vision operations (rotoscope, AI enhance, relight, sky replace).
    // Default to Cloud Run GPU (L4), or phone for flagship if battery allows.
    if (req.taskType == ComputeTaskType.rotoscope ||
        req.taskType == ComputeTaskType.aiEnhance ||
        req.taskType == ComputeTaskType.relight ||
        req.taskType == ComputeTaskType.skyReplace) {
      if (req.userTier == 'free' && spend != CloudSpendLevel.green) {
        return ComputeRoutingDecision(
          target: ComputeTarget.phone,
          reason: 'Heavy vision operation directed to phone due to budget constraints.',
          cloudSpendLevel: spend,
        );
      }
      return ComputeRoutingDecision(
        target: ComputeTarget.cloud,
        reason: 'Heavy vision operation routed to Cloud Run GPU.',
        cloudSpendLevel: spend,
      );
    }

    // Rule 7: Video export.
    // Default: phone hardware encoder (zero cloud cost).
    // Route to Cloud Render only if:
    // - Device thermal state is critical, OR
    // - Battery is low (<15% and not charging), OR
    // - Low device tier with large 4K file (>150MB) and user is Pro/Biz.
    if (req.taskType == ComputeTaskType.videoExport) {
      final isOverheating = req.thermalState == ThermalHeadroomLevel.critical;
      final isLowBattery = req.batteryLevel < 0.15 && !req.isCharging;
      final isWeakDeviceHeavyLoad = req.deviceTier == DeviceTier.low && req.fileSizeBytes > 150 * 1024 * 1024;

      if ((isOverheating || isLowBattery || isWeakDeviceHeavyLoad) &&
          (req.userTier == 'pro' || req.userTier == 'biz')) {
        return ComputeRoutingDecision(
          target: ComputeTarget.cloud,
          reason: 'Export offloaded to Cloud Render (thermal: ${req.thermalState.name}, battery: ${(req.batteryLevel * 100).toInt()}%).',
          cloudSpendLevel: spend,
        );
      }

      return ComputeRoutingDecision(
        target: ComputeTarget.phone,
        reason: 'Video exported using hardware encoder on phone (fast, zero cloud cost).',
        cloudSpendLevel: spend,
      );
    }

    // Rule 8: Photo export.
    if (req.taskType == ComputeTaskType.photoExport) {
      if (req.fileSizeBytes > 50 * 1024 * 1024 &&
          req.deviceTier == DeviceTier.low &&
          req.userTier != 'free') {
        return ComputeRoutingDecision(
          target: ComputeTarget.cloud,
          reason: 'High-resolution photo export offloaded to cloud for low-tier device.',
          cloudSpendLevel: spend,
        );
      }
      return ComputeRoutingDecision(
        target: ComputeTarget.phone,
        reason: 'Photo export rendered locally on phone GPU.',
        cloudSpendLevel: spend,
      );
    }

    // Rule 9: Non-interactive batch jobs (e.g. LookSmith, batch grade).
    if (req.isNonInteractive) {
      return ComputeRoutingDecision(
        target: ComputeTarget.cloud,
        reason: 'Non-interactive batch job routed to GKE Spot GPU queue.',
        cloudSpendLevel: spend,
      );
    }

    // Default to phone
    return ComputeRoutingDecision(
      target: ComputeTarget.phone,
      reason: 'Standard execution on phone.',
      cloudSpendLevel: spend,
    );
  }
}

/// Riverpod provider for ComputeRouter.
final computeRouterProvider = Provider<ComputeRouter>((ref) {
  final router = ComputeRouter();
  ref.onDispose(() => router.dispose());
  return router;
});

/// Riverpod provider streaming the current Cloud Spend level.
final cloudSpendStreamProvider = StreamProvider<CloudSpendLevel>((ref) {
  return FirebaseFirestore.instance
      .collection('opsConfig')
      .doc('cloudSpend')
      .snapshots()
      .map((snap) => CloudSpendLevel.fromString(snap.data()?['level'] as String?));
});
