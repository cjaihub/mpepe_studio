/// Task categories routed by the ComputeRouter (plan §4.2).
enum ComputeTaskType {
  /// Live or camera looks, beauty, segmentation
  liveCameraLooks,

  /// GPU scopes (waveform, vectorscope, histogram) and silent Sentinel
  scopesSentinel,

  /// Natural language / voice grade commands
  voiceNlGrading,

  /// Complex grading, "match this", rotoscoping (SAM 2)
  complexGradingRotoscope,

  /// Photo export at full resolution
  photoExport,

  /// Video export (hardware encoder / Cloud Render)
  videoExport,

  /// AI enhance (upscale, denoise, relight, sky replace)
  aiEnhance;

  String get label => switch (this) {
        ComputeTaskType.liveCameraLooks => 'Live & Camera Realtime Processing',
        ComputeTaskType.scopesSentinel => 'GPU Scopes & Scope Sentinel',
        ComputeTaskType.voiceNlGrading => 'Voice & Natural Language Grading',
        ComputeTaskType.complexGradingRotoscope => 'Complex Grading & Rotoscope',
        ComputeTaskType.photoExport => 'Photo Export',
        ComputeTaskType.videoExport => 'Video Export',
        ComputeTaskType.aiEnhance => 'AI Visual Enhancement',
      };
}

/// Compute target execution environment.
enum ComputeTarget {
  /// Full on-device execution (GPU / NPU)
  device,

  /// Lower on-device quality tier or lighter fallback model
  deviceLow,

  /// Server-side cloud execution (Cloud Run GPU / Gemini / Cloud Render)
  cloud;

  String get label => switch (this) {
        ComputeTarget.device => 'On-Device',
        ComputeTarget.deviceLow => 'On-Device (Efficiency / Low)',
        ComputeTarget.cloud => 'Oneova Cloud GPU',
      };
}

/// Cloud budget spend level written by budget alerts to `opsConfig/cloudSpend`.
enum CloudSpendLevel {
  green,
  amber,
  red;

  static CloudSpendLevel fromString(String? val) {
    if (val == null) return CloudSpendLevel.green;
    return switch (val.toLowerCase().trim()) {
      'red' => CloudSpendLevel.red,
      'amber' => CloudSpendLevel.amber,
      _ => CloudSpendLevel.green,
    };
  }

  bool get isNormal => this == CloudSpendLevel.green;
  bool get isRestricted => this == CloudSpendLevel.amber;
  bool get isCritical => this == CloudSpendLevel.red;
}

/// Network connectivity type.
enum NetworkType {
  wifi,
  cellular,
  ethernet,
  none;

  bool get isConnected => this != NetworkType.none;
}

/// Measured network quality metrics.
class NetworkQuality {
  final NetworkType type;
  final double bandwidthMbps;
  final double roundTripTimeMs;

  const NetworkQuality({
    required this.type,
    this.bandwidthMbps = 25.0,
    this.roundTripTimeMs = 50.0,
  });

  static const offline = NetworkQuality(
    type: NetworkType.none,
    bandwidthMbps: 0.0,
    roundTripTimeMs: 9999.0,
  );

  static const standardWifi = NetworkQuality(
    type: NetworkType.wifi,
    bandwidthMbps: 50.0,
    roundTripTimeMs: 30.0,
  );

  bool get isOnline => type.isConnected;
  bool get isFast => isOnline && (bandwidthMbps >= 10.0 || type == NetworkType.wifi);
  bool get isSlow => isOnline && (bandwidthMbps < 2.0 || roundTripTimeMs > 400.0);
}

/// Device battery state.
class DeviceBatteryState {
  final int level; // 0 to 100
  final bool isCharging;
  final bool isPowerSaveMode;

  const DeviceBatteryState({
    required this.level,
    required this.isCharging,
    required this.isPowerSaveMode,
  });

  bool get isLow => level < 15 && !isCharging;
  bool get isCritical => level < 8 && !isCharging;
}

/// Specification of a compute job to route.
class ComputeJobSpec {
  final ComputeTaskType taskType;
  final double estimatedMegapixels;
  final double durationSeconds;
  final bool isBatch;
  final int batchItemCount;
  final bool isUserProOrBusiness;

  const ComputeJobSpec({
    required this.taskType,
    this.estimatedMegapixels = 12.0,
    this.durationSeconds = 15.0,
    this.isBatch = false,
    this.batchItemCount = 1,
    this.isUserProOrBusiness = false,
  });

  bool get isHeavyVideo =>
      durationSeconds >= 60.0 || (estimatedMegapixels >= 8.0 && durationSeconds >= 30.0);

  bool get isHugePhoto => estimatedMegapixels >= 48.0;
}

/// Decision made by the ComputeRouter.
class ComputeRoutingDecision {
  final ComputeTaskType taskType;
  final ComputeTarget target;
  final String reason;
  final DateTime timestamp;

  const ComputeRoutingDecision({
    required this.taskType,
    required this.target,
    required this.reason,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'taskType': taskType.name,
        'target': target.name,
        'reason': reason,
        'timestampMs': timestamp.millisecondsSinceEpoch,
      };

  @override
  String toString() => '${taskType.name} -> ${target.name} ($reason)';
}
