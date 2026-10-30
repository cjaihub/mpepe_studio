import '../models/compute_task.dart';
import '../models/device_hardware_tier.dart';
import '../models/thermal_state.dart';

/// ComputeRouter (plan §4.2).
/// Intelligently routes visual compute tasks between phone GPU/NPU, on-device efficiency fallback,
/// and Oneova Cloud GPU services based on hardware tier, thermal state, battery, network, job size,
/// and cloud budget spend level (`opsConfig/cloudSpend`).
class ComputeRouter {
  final Map<String, dynamic> policyOverrides;

  const ComputeRouter({this.policyOverrides = const {}});

  /// Evaluates the complete multi-variable routing matrix for a job.
  ComputeRoutingDecision route({
    required ComputeJobSpec job,
    required DeviceHardwareTier hardwareTier,
    required ThermalSnapshot thermalSnapshot,
    required DeviceBatteryState batteryState,
    required NetworkQuality networkQuality,
    CloudSpendLevel cloudSpend = CloudSpendLevel.green,
    Map<String, dynamic>? dynamicPolicyOverrides,
  }) {
    final overrides = dynamicPolicyOverrides ?? policyOverrides;
    final now = DateTime.now();

    // Check task-specific policy override
    final taskOverrideKey = 'override_${job.taskType.name}';
    if (overrides.containsKey(taskOverrideKey)) {
      final overrideTargetStr = overrides[taskOverrideKey]?.toString();
      if (overrideTargetStr != null) {
        final target = switch (overrideTargetStr.toLowerCase()) {
          'cloud' => ComputeTarget.cloud,
          'device_low' || 'devicelow' => ComputeTarget.deviceLow,
          _ => ComputeTarget.device,
        };
        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: target,
          reason: 'Remote Config policy override ($taskOverrideKey = $overrideTargetStr)',
          timestamp: now,
        );
      }
    }

    switch (job.taskType) {
      // ---------------------------------------------------------
      // 1. Live & Camera Looks, Beauty, Segmentation
      // Realtime frame pipeline: strictly on-device, NEVER cloud
      // ---------------------------------------------------------
      case ComputeTaskType.liveCameraLooks:
        if (thermalSnapshot.isThrottled ||
            thermalSnapshot.headroom >= 0.85 ||
            batteryState.isPowerSaveMode ||
            hardwareTier.isLow) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.deviceLow,
            reason: thermalSnapshot.isThrottled
                ? 'Thermal Governor active (Tier ${thermalSnapshot.activeMitigationTier}): stepping down realtime quality.'
                : 'Efficiency mode: device tier or battery saver requires lower realtime pipeline cost.',
            timestamp: now,
          );
        }
        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: ComputeTarget.device,
          reason: 'Nominal realtime thermal envelope: full GPU/NPU execution on device.',
          timestamp: now,
        );

      // ---------------------------------------------------------
      // 2. Scopes and Scope Sentinel
      // GPU scopes on downscaled frames: strictly on-device, NEVER cloud
      // ---------------------------------------------------------
      case ComputeTaskType.scopesSentinel:
        if (thermalSnapshot.isCritical || hardwareTier.isLow) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.deviceLow,
            reason: 'Critical thermal state or low hardware tier: reducing scope refresh rate (10Hz).',
            timestamp: now,
          );
        }
        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: ComputeTarget.device,
          reason: 'Full-rate GPU scope monitoring active on device.',
          timestamp: now,
        );

      // ---------------------------------------------------------
      // 3. Natural Language / Voice Grade Commands
      // Gemini Live streaming session online -> On-device LLM offline
      // ---------------------------------------------------------
      case ComputeTaskType.voiceNlGrading:
        if (!networkQuality.isOnline) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.device,
            reason: 'Offline: routing voice/NL grading to on-device LLM (Gemini Nano / LiteRT).',
            timestamp: now,
          );
        }
        if (networkQuality.isSlow) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.device,
            reason: 'Slow network (RTT > 400ms or < 2Mbps): fast on-device LLM fallback.',
            timestamp: now,
          );
        }
        if (cloudSpend == CloudSpendLevel.red && !job.isUserProOrBusiness) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.device,
            reason: 'Cloud spend budget RED: free-tier NL grading routed to on-device model.',
            timestamp: now,
          );
        }
        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: ComputeTarget.cloud,
          reason: 'Streaming conversational Gemini Live API session active.',
          timestamp: now,
        );

      // ---------------------------------------------------------
      // 4. Complex Grading, "Match This", Rotoscoping
      // Cloud Run GPU (SAM 2) -> Offline Pro mode on device
      // ---------------------------------------------------------
      case ComputeTaskType.complexGradingRotoscope:
        if (!networkQuality.isOnline) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.device,
            reason: 'Offline: routing complex grade/rotoscope to on-device Pro mode with Vision masks.',
            timestamp: now,
          );
        }
        if (cloudSpend == CloudSpendLevel.red && !job.isUserProOrBusiness) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.device,
            reason: 'Cloud spend budget RED: free-tier rotoscoping routed to on-device masks.',
            timestamp: now,
          );
        }
        if (cloudSpend == CloudSpendLevel.amber && !job.isUserProOrBusiness && hardwareTier.isHigh) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.device,
            reason: 'Cloud spend budget AMBER: high-tier phone handles rotoscoping locally.',
            timestamp: now,
          );
        }
        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: ComputeTarget.cloud,
          reason: 'Cloud Run GPU SAM 2 precision rotoscoping & reference shot matching.',
          timestamp: now,
        );

      // ---------------------------------------------------------
      // 5. Photo Export
      // Default phone -> Cloud for 50MP+/batch on low-tier/overheated
      // ---------------------------------------------------------
      case ComputeTaskType.photoExport:
        final isHuge = job.isHugePhoto;
        final isBatchHeavy = job.isBatch && job.batchItemCount >= 5;

        if ((isHuge || isBatchHeavy) &&
            (hardwareTier.isLow || thermalSnapshot.isSerious) &&
            networkQuality.isOnline &&
            cloudSpend != CloudSpendLevel.red) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.cloud,
            reason: 'Large photo job (${job.estimatedMegapixels.toStringAsFixed(0)}MP / ${job.batchItemCount} items) on memory-constrained device: Cloud Render.',
            timestamp: now,
          );
        }

        if (thermalSnapshot.isThrottled && !isHuge) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.deviceLow,
            reason: 'Device throttled: tiled export with memory reduction on device.',
            timestamp: now,
          );
        }

        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: ComputeTarget.device,
          reason: 'Full-resolution hardware photo export on device.',
          timestamp: now,
        );

      // ---------------------------------------------------------
      // 6. Video Export
      // Default phone hardware encoder -> Cloud Render for 4K/long/low-battery/hot
      // ---------------------------------------------------------
      case ComputeTaskType.videoExport:
        final isCloudEligible = networkQuality.isOnline &&
            (cloudSpend != CloudSpendLevel.red || job.isUserProOrBusiness);

        // Offload triggers for cloud render
        final needsCloud = isCloudEligible &&
            (batteryState.isLow ||
                thermalSnapshot.isCritical ||
                thermalSnapshot.isSerious ||
                (job.isHeavyVideo && hardwareTier.isLow) ||
                (job.estimatedMegapixels >= 8.0 && hardwareTier.isLow));

        if (needsCloud) {
          final cloudReason = batteryState.isLow
              ? 'Low battery (${batteryState.level}%): offloading video export to Cloud Render.'
              : thermalSnapshot.isSerious || thermalSnapshot.isCritical
                  ? 'Overheating detected (${thermalSnapshot.thermalLevel.name}): protecting device via Cloud Render.'
                  : 'Heavy 4K/long video export on efficiency tier device: Cloud Render.';
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.cloud,
            reason: cloudReason,
            timestamp: now,
          );
        }

        if (batteryState.isPowerSaveMode || thermalSnapshot.isThrottled) {
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.deviceLow,
            reason: 'Device constrained: single-pass hardware encoder export on device.',
            timestamp: now,
          );
        }

        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: ComputeTarget.device,
          reason: 'Hardware Media3/VideoToolbox encoder export on device.',
          timestamp: now,
        );

      // ---------------------------------------------------------
      // 7. AI Enhance (upscale, denoise, relight, sky replace)
      // Default Cloud Run GPU -> lighter on-device model for high-tier
      // ---------------------------------------------------------
      case ComputeTaskType.aiEnhance:
        if (!networkQuality.isOnline || (cloudSpend == CloudSpendLevel.red && !job.isUserProOrBusiness)) {
          if (hardwareTier.isHigh) {
            return ComputeRoutingDecision(
              taskType: job.taskType,
              target: ComputeTarget.deviceLow,
              reason: 'High-tier device offline / cloud budget cap: running distilled on-device AI enhance model.',
              timestamp: now,
            );
          }
          return ComputeRoutingDecision(
            taskType: job.taskType,
            target: ComputeTarget.deviceLow,
            reason: 'Offline fallback: basic contrast and sharpening enhancement.',
            timestamp: now,
          );
        }

        return ComputeRoutingDecision(
          taskType: job.taskType,
          target: ComputeTarget.cloud,
          reason: 'Cloud Run GPU L4 AI enhance (neural upscale, portrait relight, SAM 2 sky replace).',
          timestamp: now,
        );
    }
  }
}
