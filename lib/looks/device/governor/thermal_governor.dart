import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import '../models/thermal_state.dart';

/// Event emitted during smooth transitions between mitigation tiers.
class ThermalTransitionEvent {
  final int fromTier;
  final int toTier;
  final int crossFadeMs;
  final List<MitigationAction> activeMitigations;
  final String reason;
  final DateTime timestamp;

  const ThermalTransitionEvent({
    required this.fromTier,
    required this.toTier,
    required this.crossFadeMs,
    required this.activeMitigations,
    required this.reason,
    required this.timestamp,
  });
}

/// Predictive Thermal Governor.
/// Continuously monitors Android ADPF / iOS thermalState and battery levels,
/// dynamically stepping down/up quality via the Remote Config thermal ladder with hysteresis.
class ThermalGovernor {
  ThermalLadderConfig _ladderConfig;
  int _currentTier = 0; // 0 = unmitigated full quality, 1..6 = stepped down
  DateTime? _belowThresholdSince;
  Timer? _pollingTimer;

  final StreamController<ThermalSnapshot> _snapshotController =
      StreamController<ThermalSnapshot>.broadcast();
  final StreamController<ThermalTransitionEvent> _transitionController =
      StreamController<ThermalTransitionEvent>.broadcast();

  ThermalSnapshot _lastSnapshot = ThermalSnapshot.nominal();
  ThermalTransitionEvent? lastTransitionEvent;
  final List<ThermalTransitionEvent> transitionHistory = [];

  ThermalGovernor({ThermalLadderConfig? ladderConfig})
      : _ladderConfig = ladderConfig ?? const ThermalLadderConfig();

  ThermalLadderConfig get ladderConfig => _ladderConfig;
  int get currentTier => _currentTier;
  ThermalSnapshot get currentSnapshot => _lastSnapshot;

  Stream<ThermalSnapshot> get snapshotStream => _snapshotController.stream;
  Stream<ThermalTransitionEvent> get transitionStream => _transitionController.stream;

  void updateLadderConfig(ThermalLadderConfig config) {
    _ladderConfig = config;
  }

  /// Starts periodic thermal polling (e.g. every 2 seconds during active camera / live).
  void startMonitoring({Duration interval = const Duration(seconds: 2)}) {
    stopMonitoring();
    _pollingTimer = Timer.periodic(interval, (_) async {
      await pollThermalState();
    });
  }

  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Polls native platform thermal sensors and evaluates dynamic ladder transitions.
  Future<ThermalSnapshot> pollThermalState() async {
    try {
      final probeSnap = await ThermalProbe.getThermalSnapshot();
      return evaluateSnapshot(
        headroom: probeSnap.headroom,
        forecastHeadroom10s: probeSnap.forecastHeadroom10s,
        thermalLevel: ThermalLevel.fromString(probeSnap.thermalLevel),
        isBatterySaver: probeSnap.isPowerSaveMode,
        batteryLevel: probeSnap.batteryLevel,
        isCharging: probeSnap.isCharging,
      );
    } catch (e) {
      debugPrint('[ThermalGovernor] Failed to poll thermal state: $e');
      return _lastSnapshot;
    }
  }

  /// Evaluates new thermal readings and computes hysteresis-safe ladder transitions.
  ThermalSnapshot evaluateSnapshot({
    required double headroom,
    required double forecastHeadroom10s,
    required ThermalLevel thermalLevel,
    required bool isBatterySaver,
    required int batteryLevel,
    required bool isCharging,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final effectiveHeadroom = (headroom * 0.4) + (forecastHeadroom10s * 0.6);

    // Emergency thermal condition: critical OS state or headroom >= 1.15
    final isCritical = thermalLevel == ThermalLevel.critical || headroom >= 1.15;
    final isSerious = thermalLevel == ThermalLevel.serious || headroom >= 0.95;

    int targetTier = _currentTier;
    String transitionReason = '';

    if (isCritical) {
      // Immediate emergency step-down to tier 5 or 6 (fps/resolution drop)
      targetTier = _ladderConfig.steps.length; // Max mitigation
      transitionReason = 'Emergency thermal protection: device reached critical threshold.';
    } else if (isSerious) {
      // Step down to at least tier 3 or 4
      targetTier = (_currentTier + 2).clamp(3, _ladderConfig.steps.length);
      transitionReason = 'Elevated thermal state: fast step-down to protect device.';
    } else if (effectiveHeadroom >= _ladderConfig.stepDownHeadroomThreshold || isBatterySaver) {
      // Predictive step-down: headroom trending high
      targetTier = (_currentTier + 1).clamp(0, _ladderConfig.steps.length);
      transitionReason = isBatterySaver
          ? 'Battery saver active: stepping down quality to preserve power.'
          : 'Thermal headroom forecast exceeds threshold (${effectiveHeadroom.toStringAsFixed(2)} >= ${_ladderConfig.stepDownHeadroomThreshold}).';
      _belowThresholdSince = null;
    } else if (effectiveHeadroom <= _ladderConfig.stepUpHeadroomThreshold &&
        thermalLevel == ThermalLevel.nominal &&
        !isBatterySaver) {
      // Candidate for stepping back up (cooling down)
      _belowThresholdSince ??= now;
      final coolDuration = now.difference(_belowThresholdSince!);

      if (coolDuration.inSeconds >= _ladderConfig.stepUpHoldDurationSeconds && _currentTier > 0) {
        // Hysteresis satisfied: step up one tier
        targetTier = (_currentTier - 1).clamp(0, _ladderConfig.steps.length);
        transitionReason = 'Thermal headroom stabilized below recovery threshold for ${coolDuration.inSeconds}s.';
        _belowThresholdSince = now; // Reset timer for next step-up
      }
    } else {
      // In deadband zone between stepDown and stepUp: maintain current tier
      _belowThresholdSince = null;
    }

    final previousTier = _currentTier;
    _currentTier = targetTier;

    // Collect active mitigations based on current tier
    final activeMitigations = <MitigationAction>[];
    for (final step in _ladderConfig.steps) {
      if (step.tier <= _currentTier) {
        activeMitigations.add(step.action);
      }
    }

    final snapshot = ThermalSnapshot(
      headroom: headroom,
      forecastHeadroom10s: forecastHeadroom10s,
      thermalLevel: thermalLevel,
      isBatterySaver: isBatterySaver,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      activeMitigationTier: _currentTier,
      activeMitigations: activeMitigations,
      timestamp: now,
    );

    _lastSnapshot = snapshot;
    _snapshotController.add(snapshot);

    // If tier transitioned, emit smooth transition event
    if (previousTier != targetTier) {
      final transitionEvent = ThermalTransitionEvent(
        fromTier: previousTier,
        toTier: targetTier,
        crossFadeMs: 300, // Smooth cross-fade duration
        activeMitigations: activeMitigations,
        reason: transitionReason,
        timestamp: now,
      );
      lastTransitionEvent = transitionEvent;
      transitionHistory.add(transitionEvent);
      _transitionController.add(transitionEvent);
      debugPrint('[ThermalGovernor] Step transition: Tier $previousTier -> $targetTier ($transitionReason)');
    }

    return snapshot;
  }

  /// Reports frame execution duration to Android ADPF hint session.
  Future<void> reportFrameDuration(Duration duration) async {
    await ThermalProbe.reportActualDuration(
      actualDurationNanos: duration.inMicroseconds * 1000,
    );
  }

  void dispose() {
    stopMonitoring();
    _snapshotController.close();
    _transitionController.close();
  }
}
