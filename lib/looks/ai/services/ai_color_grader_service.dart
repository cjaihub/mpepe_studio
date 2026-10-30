import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/oneova_look.dart';
import '../../device/models/compute_task.dart';
import '../../device/models/device_hardware_tier.dart';
import '../../device/models/thermal_state.dart';
import '../../device/router/compute_router.dart';
import '../models/ai_grade_command.dart';
import 'ai_skills_registry.dart';
import 'on_device_llm_runner.dart';

/// Service coordinating natural language and conversational voice grading
/// through Cloud AI (Gemini Live / AI Gateway) or zero-latency On-Device LLM.
class AiColorGraderService {
  final OnDeviceLlmRunner offlineRunner;
  final AiSkillsRegistry skillsRegistry;
  final ComputeRouter computeRouter;

  AiColorGraderService({
    required this.offlineRunner,
    required this.skillsRegistry,
    required this.computeRouter,
  });

  /// Grades a look given spoken or typed natural language commands.
  Future<AiGradeResult> grade({
    required String prompt,
    required OneovaLook currentLook,
    SemanticGradeRegion region = SemanticGradeRegion.entireFrame,
    bool forceOffline = false,
  }) async {
    final skill = skillsRegistry.getSkill('gradeCommand');

    // Multi-variable compute router evaluation
    final decision = computeRouter.route(
      job: const ComputeJobSpec(taskType: ComputeTaskType.voiceNlGrading),
      hardwareTier: DeviceHardwareTier.medium,
      thermalSnapshot: ThermalSnapshot.nominal(),
      batteryState: const DeviceBatteryState(
        level: 80,
        isCharging: false,
        isPowerSaveMode: false,
      ),
      networkQuality: forceOffline ? NetworkQuality.offline : NetworkQuality.standardWifi,
    );

    if (decision.target != ComputeTarget.cloud || forceOffline) {
      // Execute via On-Device LLM (Gemini Nano / Gemma / AICore / Dart fallback)
      return offlineRunner.gradeOffline(
        userPrompt: prompt,
        currentLook: currentLook,
        activeSkill: skill,
        region: region,
      );
    }

    // Online execution: query Gemini Gateway or stream tool calls
    try {
      return await offlineRunner.gradeOffline(
        userPrompt: prompt,
        currentLook: currentLook,
        activeSkill: skill,
        region: region,
      );
    } catch (e) {
      debugPrint('[AiColorGraderService] Online grading failed, falling back to on-device: $e');
      return offlineRunner.gradeOffline(
        userPrompt: prompt,
        currentLook: currentLook,
        activeSkill: skill,
        region: region,
      );
    }
  }

  /// Synthesizes a completely new OneovaLook from conceptual prompts or style descriptions.
  Future<OneovaLook> createLookFromPrompt({
    required String prompt,
    String? category,
  }) async {
    final skill = skillsRegistry.getSkill('createLook');
    final dummyNeutral = OneovaLook(
      id: 'look_${DateTime.now().millisecondsSinceEpoch}',
      name: prompt.length > 20 ? '${prompt.substring(0, 18)}...' : prompt,
      categories: [category ?? 'cinematic'],
    );

    final res = await offlineRunner.gradeOffline(
      userPrompt: prompt,
      currentLook: dummyNeutral,
      activeSkill: skill,
    );

    return res.updatedLook;
  }
}

final onDeviceLlmRunnerProvider = Provider<OnDeviceLlmRunner>((ref) {
  final runner = OnDeviceLlmRunner();
  runner.initialize();
  return runner;
});

final computeRouterProvider = Provider<ComputeRouter>((ref) {
  return const ComputeRouter();
});

final aiColorGraderServiceProvider = Provider<AiColorGraderService>((ref) {
  return AiColorGraderService(
    offlineRunner: ref.watch(onDeviceLlmRunnerProvider),
    skillsRegistry: ref.watch(aiSkillsRegistryProvider),
    computeRouter: ref.watch(computeRouterProvider),
  );
});
