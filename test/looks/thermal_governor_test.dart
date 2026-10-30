import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/device/governor/thermal_governor.dart';
import 'package:oneova/looks/device/models/thermal_state.dart';

void main() {
  group('ThermalGovernor Dynamic Step-Down Ladder', () {
    late ThermalGovernor governor;

    setUp(() {
      governor = ThermalGovernor(
        ladderConfig: const ThermalLadderConfig(
          stepDownHeadroomThreshold: 0.85,
          stepUpHeadroomThreshold: 0.65,
          stepUpHoldDurationSeconds: 10,
        ),
      );
    });

    tearDown(() {
      governor.dispose();
    });

    test('initial state is nominal with tier 0 and no mitigations', () {
      final snap = governor.evaluateSnapshot(
        headroom: 0.4,
        forecastHeadroom10s: 0.45,
        thermalLevel: ThermalLevel.nominal,
        isBatterySaver: false,
        batteryLevel: 90,
        isCharging: false,
      );

      expect(snap.activeMitigationTier, 0);
      expect(snap.activeMitigations, isEmpty);
      expect(snap.isThrottled, isFalse);
    });

    test('steps down to tier 1 (ML rate reduction) when headroom forecast is elevated', () {
      final events = <ThermalTransitionEvent>[];
      governor.transitionStream.listen(events.add);

      final snap = governor.evaluateSnapshot(
        headroom: 0.80,
        forecastHeadroom10s: 0.90, // effective: (0.8*0.4 + 0.9*0.6) = 0.86 >= 0.85
        thermalLevel: ThermalLevel.fair,
        isBatterySaver: false,
        batteryLevel: 80,
        isCharging: false,
      );

      expect(snap.activeMitigationTier, 1);
      expect(snap.activeMitigations, contains(MitigationAction.reduceMlRate));
      expect(governor.lastTransitionEvent, isNotNull);
      expect(governor.lastTransitionEvent!.fromTier, 0);
      expect(governor.lastTransitionEvent!.toTier, 1);
      expect(governor.lastTransitionEvent!.crossFadeMs, 300);
    });

    test('progressively steps down ladder on sustained high load', () {
      // Step to tier 1
      governor.evaluateSnapshot(
        headroom: 0.85,
        forecastHeadroom10s: 0.88,
        thermalLevel: ThermalLevel.fair,
        isBatterySaver: false,
        batteryLevel: 75,
        isCharging: false,
      );
      expect(governor.currentTier, 1);

      // Step to tier 2: heavy effects disabled
      governor.evaluateSnapshot(
        headroom: 0.88,
        forecastHeadroom10s: 0.92,
        thermalLevel: ThermalLevel.fair,
        isBatterySaver: false,
        batteryLevel: 70,
        isCharging: false,
      );
      expect(governor.currentTier, 2);
      expect(governor.currentSnapshot.activeMitigations, contains(MitigationAction.disableHeavyEffects));

      // Step to tier 3: background downgraded
      governor.evaluateSnapshot(
        headroom: 0.90,
        forecastHeadroom10s: 0.94,
        thermalLevel: ThermalLevel.fair,
        isBatterySaver: false,
        batteryLevel: 68,
        isCharging: false,
      );
      expect(governor.currentTier, 3);
      expect(governor.currentSnapshot.activeMitigations, contains(MitigationAction.downgradeBackground));
    });

    test('emergency thermal trigger jumps straight to max mitigation', () {
      final snap = governor.evaluateSnapshot(
        headroom: 1.25,
        forecastHeadroom10s: 1.30,
        thermalLevel: ThermalLevel.critical,
        isBatterySaver: false,
        batteryLevel: 60,
        isCharging: false,
      );

      expect(snap.activeMitigationTier, 6); // Max tier
      expect(snap.activeMitigations, contains(MitigationAction.dropResolution));
      expect(snap.activeMitigations, contains(MitigationAction.dropFps));
      expect(snap.isCritical, isTrue);
    });

    test('battery saver triggers step-down to preserve power', () {
      final snap = governor.evaluateSnapshot(
        headroom: 0.40,
        forecastHeadroom10s: 0.42,
        thermalLevel: ThermalLevel.nominal,
        isBatterySaver: true, // Battery saver enabled by user / OS
        batteryLevel: 14,
        isCharging: false,
      );

      expect(snap.activeMitigationTier, 1);
      expect(snap.isBatterySaver, isTrue);
    });
  });

  group('ThermalGovernor Hysteresis and Recovery', () {
    test('does NOT prematurely step up during brief temperature dip (hysteresis protection)', () {
      final governor = ThermalGovernor(
        ladderConfig: const ThermalLadderConfig(
          stepDownHeadroomThreshold: 0.85,
          stepUpHeadroomThreshold: 0.65,
          stepUpHoldDurationSeconds: 15,
        ),
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // 1. Step down to Tier 2
      governor.evaluateSnapshot(
        headroom: 0.9,
        forecastHeadroom10s: 0.95,
        thermalLevel: ThermalLevel.fair,
        isBatterySaver: false,
        batteryLevel: 80,
        isCharging: false,
        timestamp: t0,
      );
      governor.evaluateSnapshot(
        headroom: 0.9,
        forecastHeadroom10s: 0.95,
        thermalLevel: ThermalLevel.fair,
        isBatterySaver: false,
        batteryLevel: 80,
        isCharging: false,
        timestamp: t0.add(const Duration(seconds: 1)),
      );
      expect(governor.currentTier, 2);

      // 2. Temp drops below 0.65, but only 5s have elapsed (threshold is 15s)
      governor.evaluateSnapshot(
        headroom: 0.55,
        forecastHeadroom10s: 0.58,
        thermalLevel: ThermalLevel.nominal,
        isBatterySaver: false,
        batteryLevel: 79,
        isCharging: false,
        timestamp: t0.add(const Duration(seconds: 5)),
      );

      // Still at tier 2 due to hysteresis hold!
      expect(governor.currentTier, 2);

      // 3. Now 16s have elapsed below 0.65 with nominal level
      governor.evaluateSnapshot(
        headroom: 0.50,
        forecastHeadroom10s: 0.52,
        thermalLevel: ThermalLevel.nominal,
        isBatterySaver: false,
        batteryLevel: 78,
        isCharging: false,
        timestamp: t0.add(const Duration(seconds: 21)),
      );

      // Successfully stepped up to tier 1!
      expect(governor.currentTier, 1);

      governor.dispose();
    });
  });
}
