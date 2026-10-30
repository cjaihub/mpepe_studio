import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/device/governor/thermal_governor.dart';
import 'package:oneova/looks/device/models/thermal_state.dart';

void main() {
  group('ThermalGovernor 20-Minute Live Soak Test', () {
    test('sustains 20-minute live broadcast load without thermal throttling spikes', () {
      final governor = ThermalGovernor(
        ladderConfig: const ThermalLadderConfig(
          stepDownHeadroomThreshold: 0.85,
          stepUpHeadroomThreshold: 0.65,
          stepUpHoldDurationSeconds: 15,
        ),
      );

      final soakLog = <String>[];
      final transitionEvents = <ThermalTransitionEvent>[];
      governor.transitionStream.listen(transitionEvents.add);

      final startTime = DateTime(2026, 4, 1, 14, 0, 0);
      const totalDurationSeconds = 1200; // 20 minutes
      const stepIntervalSeconds = 5; // 5-second sampling intervals = 240 steps

      int criticalSpikeCount = 0;
      double peakHeadroom = 0.0;
      int tier1Count = 0;
      int tier2Count = 0;

      // Simulated physical thermal model with heat generation and dissipation
      double currentHeadroom = 0.35; // Initial room temperature baseline

      soakLog.add('=== ONEOVA LOOKS 20-MINUTE LIVE SOAK TEST START ===');
      soakLog.add('Initial state: Headroom 0.35, Nominal, 1080p60 Live Broadcast');

      for (int t = 0; t <= totalDurationSeconds; t += stepIntervalSeconds) {
        final currentTime = startTime.add(Duration(seconds: t));
        final minute = (t / 60.0).toStringAsFixed(1);

        // Simulated broadcast phases:
        // 0-3 min: Initial warm-up
        // 3-12 min: Peak live streaming with high AR/beauty & outdoor ambient load
        // 12-16 min: Governor mitigates, stabilizing temperature
        // 16-20 min: Indoor talking head session (cool down and recovery)
        final isCoolDownPhase = t >= 960;
        final baseHeat = isCoolDownPhase ? 0.0020 : 0.0050;
        final activeTier = governor.currentTier;
        final heatGenerationRate = switch (activeTier) {
          0 => baseHeat * 1.35,
          1 => baseHeat * 1.0,
          2 => baseHeat * 0.70,
          3 => baseHeat * 0.50,
          _ => baseHeat * 0.35,
        };

        // Environment thermal drift (e.g. user holds phone outdoors / warm room)
        final environmentalLoad = (!isCoolDownPhase && t >= 240 && t <= 720) ? 0.0015 : 0.0;
        final ambientDissipationRate = isCoolDownPhase ? 0.0040 : 0.0028;

        // Dynamic headroom delta
        final netSlope = heatGenerationRate + environmentalLoad - ambientDissipationRate;
        currentHeadroom = (currentHeadroom + (netSlope * stepIntervalSeconds)).clamp(0.20, 1.30);

        if (currentHeadroom > peakHeadroom) {
          peakHeadroom = currentHeadroom;
        }

        // 10s forecast
        final forecast10s = (currentHeadroom + (netSlope * 10)).clamp(0.20, 1.30);

        final thermalLevel = currentHeadroom >= 1.15
            ? ThermalLevel.critical
            : (currentHeadroom >= 0.95
                ? ThermalLevel.serious
                : (currentHeadroom >= 0.75 ? ThermalLevel.fair : ThermalLevel.nominal));

        if (thermalLevel == ThermalLevel.critical) {
          criticalSpikeCount++;
        }

        // Evaluate governor
        final snap = governor.evaluateSnapshot(
          headroom: currentHeadroom,
          forecastHeadroom10s: forecast10s,
          thermalLevel: thermalLevel,
          isBatterySaver: false,
          batteryLevel: max(20, 95 - (t ~/ 25)), // Battery slowly draining
          isCharging: false,
          timestamp: currentTime,
        );

        if (snap.activeMitigationTier == 1) tier1Count++;
        if (snap.activeMitigationTier >= 2) tier2Count++;

        // Log sample milestones every minute
        if (t % 60 == 0) {
          soakLog.add(
            '[$minute min] Headroom: ${(currentHeadroom * 100).toStringAsFixed(1)}% | '
            'Forecast10s: ${(forecast10s * 100).toStringAsFixed(1)}% | '
            'Level: ${thermalLevel.name} | '
            'Tier: ${snap.activeMitigationTier} | '
            'Mitigations: ${snap.activeMitigations.map((m) => m.name).join(", ")}',
          );
        }
      }

      soakLog.add('=== SOAK TEST SUMMARY ===');
      soakLog.add('Total duration: 20 minutes (1200 seconds)');
      soakLog.add('Peak Headroom: ${(peakHeadroom * 100).toStringAsFixed(1)}%');
      soakLog.add('Critical Throttling Spikes: $criticalSpikeCount (Target: 0)');
      soakLog.add('Mitigation Transitions: ${governor.transitionHistory.length}');
      soakLog.add('Final Tier: ${governor.currentTier} (Recovered to nominal)');

      for (final event in governor.transitionHistory) {
        soakLog.add('  -> Transition: Tier ${event.fromTier} to ${event.toTier} (${event.reason})');
      }

      // Assertions for soak test success
      expect(criticalSpikeCount, 0, reason: 'No critical thermal throttling spikes allowed during soak test');
      expect(peakHeadroom, lessThan(1.0), reason: 'Headroom must stay below emergency 1.0 threshold');
      expect(tier1Count, greaterThan(0), reason: 'Governor should adaptively step into mitigation tiers during peak heat');
      expect(tier2Count, greaterThan(0), reason: 'Governor should escalate mitigation tiers as heat rises');
      expect(governor.transitionHistory, isNotEmpty, reason: 'Governor should adaptively mitigate during peak heat');
      expect(governor.currentTier, lessThanOrEqualTo(1), reason: 'Governor must recover when cooled');

      governor.dispose();
    });
  });
}
