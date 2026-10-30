/// Normalized thermal level of the device.
enum ThermalLevel {
  nominal,
  fair,
  serious,
  critical;

  static ThermalLevel fromString(String? str) {
    if (str == null) return ThermalLevel.nominal;
    return switch (str.toLowerCase().trim()) {
      'critical' => ThermalLevel.critical,
      'serious' => ThermalLevel.serious,
      'fair' => ThermalLevel.fair,
      _ => ThermalLevel.nominal,
    };
  }

  bool get isCritical => this == ThermalLevel.critical;
  bool get isSerious => this == ThermalLevel.serious;
  bool get isElevated => this != ThermalLevel.nominal;
}

/// Mitigation actions defined in the thermal ladder.
enum MitigationAction {
  reduceMlRate,
  disableHeavyEffects,
  downgradeBackground,
  reduceBeauty,
  dropFps,
  dropResolution;

  String get description => switch (this) {
        MitigationAction.reduceMlRate => 'Adaptive ML segmentation/tracking rate reduced',
        MitigationAction.disableHeavyEffects => 'Heavy post effects (sharpen, grain) bypassed',
        MitigationAction.downgradeBackground => 'Background replaced with lightweight blur',
        MitigationAction.reduceBeauty => 'High-frequency beauty mesh detail relaxed',
        MitigationAction.dropFps => 'Frame rate stepped down to cool thermal envelope',
        MitigationAction.dropResolution => 'Resolution stepped down for emergency thermal protection',
      };
}

/// A single step in the thermal ladder.
class MitigationStep {
  final int tier;
  final MitigationAction action;
  final Map<String, dynamic> parameters;

  const MitigationStep({
    required this.tier,
    required this.action,
    this.parameters = const {},
  });

  factory MitigationStep.fromMap(Map<String, dynamic> map) {
    final actionStr = map['action'] as String? ?? '';
    final action = switch (actionStr) {
      'reduce_ml_rate' => MitigationAction.reduceMlRate,
      'disable_heavy_effects' => MitigationAction.disableHeavyEffects,
      'downgrade_background' => MitigationAction.downgradeBackground,
      'reduce_beauty' => MitigationAction.reduceBeauty,
      'drop_fps' => MitigationAction.dropFps,
      'drop_resolution' => MitigationAction.dropResolution,
      _ => MitigationAction.reduceMlRate,
    };

    return MitigationStep(
      tier: (map['tier'] as num?)?.toInt() ?? 1,
      action: action,
      parameters: Map<String, dynamic>.from(map)..remove('tier')..remove('action'),
    );
  }
}

/// Dynamic ladder configuration loaded from Remote Config key `thermal_ladder`.
class ThermalLadderConfig {
  final double stepDownHeadroomThreshold;
  final double stepUpHeadroomThreshold;
  final int stepUpHoldDurationSeconds;
  final List<MitigationStep> steps;

  const ThermalLadderConfig({
    this.stepDownHeadroomThreshold = 0.85,
    this.stepUpHeadroomThreshold = 0.65,
    this.stepUpHoldDurationSeconds = 15,
    this.steps = const [
      MitigationStep(tier: 1, action: MitigationAction.reduceMlRate, parameters: {'mlFps': 15}),
      MitigationStep(tier: 2, action: MitigationAction.disableHeavyEffects, parameters: {'allowSharpen': false, 'allowGrain': false}),
      MitigationStep(tier: 3, action: MitigationAction.downgradeBackground, parameters: {'allowAiBackground': false}),
      MitigationStep(tier: 4, action: MitigationAction.reduceBeauty, parameters: {'maxBeautyLevel': 0.5}),
      MitigationStep(tier: 5, action: MitigationAction.dropFps, parameters: {'targetFps': 30}),
      MitigationStep(tier: 6, action: MitigationAction.dropResolution, parameters: {'maxResolution': 720}),
    ],
  });

  factory ThermalLadderConfig.fromMap(Map<String, dynamic> map) {
    final rawSteps = map['steps'] as List<dynamic>?;
    final parsedSteps = rawSteps
            ?.whereType<Map<String, dynamic>>()
            .map((m) => MitigationStep.fromMap(m))
            .toList() ??
        const [];

    return ThermalLadderConfig(
      stepDownHeadroomThreshold: (map['stepDownHeadroomThreshold'] as num?)?.toDouble() ?? 0.85,
      stepUpHeadroomThreshold: (map['stepUpHeadroomThreshold'] as num?)?.toDouble() ?? 0.65,
      stepUpHoldDurationSeconds: (map['stepUpHoldDurationSeconds'] as num?)?.toInt() ?? 15,
      steps: parsedSteps.isNotEmpty ? parsedSteps : const [
        MitigationStep(tier: 1, action: MitigationAction.reduceMlRate, parameters: {'mlFps': 15}),
        MitigationStep(tier: 2, action: MitigationAction.disableHeavyEffects, parameters: {'allowSharpen': false, 'allowGrain': false}),
        MitigationStep(tier: 3, action: MitigationAction.downgradeBackground, parameters: {'allowAiBackground': false}),
        MitigationStep(tier: 4, action: MitigationAction.reduceBeauty, parameters: {'maxBeautyLevel': 0.5}),
        MitigationStep(tier: 5, action: MitigationAction.dropFps, parameters: {'targetFps': 30}),
        MitigationStep(tier: 6, action: MitigationAction.dropResolution, parameters: {'maxResolution': 720}),
      ],
    );
  }
}

/// Instantaneous thermal state snapshot with active mitigations.
class ThermalSnapshot {
  final double headroom; // 0.0 to 1.5+
  final double forecastHeadroom10s;
  final ThermalLevel thermalLevel;
  final bool isBatterySaver;
  final int batteryLevel; // 0 to 100
  final bool isCharging;
  final int activeMitigationTier; // 0 = nominal / unmitigated, 1..6 = stepped down
  final List<MitigationAction> activeMitigations;
  final DateTime timestamp;

  const ThermalSnapshot({
    required this.headroom,
    required this.forecastHeadroom10s,
    required this.thermalLevel,
    required this.isBatterySaver,
    required this.batteryLevel,
    required this.isCharging,
    required this.activeMitigationTier,
    required this.activeMitigations,
    required this.timestamp,
  });

  static ThermalSnapshot nominal() => ThermalSnapshot(
        headroom: 0.35,
        forecastHeadroom10s: 0.35,
        thermalLevel: ThermalLevel.nominal,
        isBatterySaver: false,
        batteryLevel: 95,
        isCharging: false,
        activeMitigationTier: 0,
        activeMitigations: const [],
        timestamp: DateTime.now(),
      );

  bool get isThrottled => activeMitigationTier > 0;
  bool get isCritical => thermalLevel == ThermalLevel.critical || headroom >= 1.15;
  bool get isSerious => thermalLevel == ThermalLevel.serious || headroom >= 0.95;

  Map<String, dynamic> toMap() => {
        'headroom': headroom,
        'forecastHeadroom10s': forecastHeadroom10s,
        'thermalLevel': thermalLevel.name,
        'isBatterySaver': isBatterySaver,
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'activeMitigationTier': activeMitigationTier,
        'activeMitigations': activeMitigations.map((a) => a.name).toList(),
        'timestampMs': timestamp.millisecondsSinceEpoch,
      };
}
