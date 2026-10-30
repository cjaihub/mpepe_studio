import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cloud_vision_models.dart';
import '../services/cloud_vision_service_client.dart';

@immutable
class CloudVisionState {
  final VisionTaskType activeTask;
  final CloudVisionQuota quota;
  final CloudVisionJob? activeJob;
  final bool isProcessing;
  final double currentProgress;
  final String? activePreviewUrl;
  final String? activeOutputUrl;
  final String rotoscopePrompt;
  final bool rotoscopeTracking;
  final AiEnhanceMode selectedEnhanceMode;
  final RelightConfig relightConfig;
  final SkyPreset selectedSky;
  final double skyHorizonOffset;
  final double skyAtmosphericBlend;
  final bool compareSplitView;
  final String? errorMessage;

  const CloudVisionState({
    this.activeTask = VisionTaskType.rotoscope,
    required this.quota,
    this.activeJob,
    this.isProcessing = false,
    this.currentProgress = 0.0,
    this.activePreviewUrl,
    this.activeOutputUrl,
    this.rotoscopePrompt = 'isolate main subject',
    this.rotoscopeTracking = true,
    this.selectedEnhanceMode = AiEnhanceMode.upscale2x,
    this.relightConfig = const RelightConfig(),
    required this.selectedSky,
    this.skyHorizonOffset = 0.0,
    this.skyAtmosphericBlend = 0.70,
    this.compareSplitView = false,
    this.errorMessage,
  });

  CloudVisionState copyWith({
    VisionTaskType? activeTask,
    CloudVisionQuota? quota,
    CloudVisionJob? activeJob,
    bool? isProcessing,
    double? currentProgress,
    String? activePreviewUrl,
    String? activeOutputUrl,
    String? rotoscopePrompt,
    bool? rotoscopeTracking,
    AiEnhanceMode? selectedEnhanceMode,
    RelightConfig? relightConfig,
    SkyPreset? selectedSky,
    double? skyHorizonOffset,
    double? skyAtmosphericBlend,
    bool? compareSplitView,
    String? errorMessage,
  }) {
    return CloudVisionState(
      activeTask: activeTask ?? this.activeTask,
      quota: quota ?? this.quota,
      activeJob: activeJob ?? this.activeJob,
      isProcessing: isProcessing ?? this.isProcessing,
      currentProgress: currentProgress ?? this.currentProgress,
      activePreviewUrl: activePreviewUrl ?? this.activePreviewUrl,
      activeOutputUrl: activeOutputUrl ?? this.activeOutputUrl,
      rotoscopePrompt: rotoscopePrompt ?? this.rotoscopePrompt,
      rotoscopeTracking: rotoscopeTracking ?? this.rotoscopeTracking,
      selectedEnhanceMode: selectedEnhanceMode ?? this.selectedEnhanceMode,
      relightConfig: relightConfig ?? this.relightConfig,
      selectedSky: selectedSky ?? this.selectedSky,
      skyHorizonOffset: skyHorizonOffset ?? this.skyHorizonOffset,
      skyAtmosphericBlend: skyAtmosphericBlend ?? this.skyAtmosphericBlend,
      compareSplitView: compareSplitView ?? this.compareSplitView,
      errorMessage: errorMessage,
    );
  }
}

/// Service client provider.
final cloudVisionClientProvider = Provider<CloudVisionServiceClient>((ref) {
  return CloudVisionServiceClient();
});

/// Central Cloud Vision Controller Notifier.
class CloudVisionController extends Notifier<CloudVisionState> {
  StreamSubscription<CloudVisionJob>? _progressSubscription;

  @override
  CloudVisionState build() {
    return CloudVisionState(
      quota: CloudVisionQuota(
        dailyBudgetJobs: 20,
        jobsUsedToday: 4,
        proTierUnlocked: true,
        resetAt: DateTime.now().add(const Duration(hours: 14)),
      ),
      selectedSky: SkyPreset.defaultPresets.first,
    );
  }

  void selectTask(VisionTaskType task) {
    state = state.copyWith(activeTask: task, errorMessage: null);
  }

  void setRotoscopePrompt(String prompt) {
    state = state.copyWith(rotoscopePrompt: prompt);
  }

  void setRotoscopeTracking(bool enable) {
    state = state.copyWith(rotoscopeTracking: enable);
  }

  void selectEnhanceMode(AiEnhanceMode mode) {
    state = state.copyWith(selectedEnhanceMode: mode);
  }

  void updateRelightPosition(double x, double y, double z) {
    state = state.copyWith(
      relightConfig: state.relightConfig.copyWith(
        lightPosition: [x, y, z],
      ),
    );
  }

  void updateRelightColor(String hex) {
    state = state.copyWith(
      relightConfig: state.relightConfig.copyWith(lightColorHex: hex),
    );
  }

  void updateRelightIntensity(double intensity) {
    state = state.copyWith(
      relightConfig: state.relightConfig.copyWith(intensity: intensity),
    );
  }

  void updateRelightFalloff(double falloff) {
    state = state.copyWith(
      relightConfig: state.relightConfig.copyWith(falloff: falloff),
    );
  }

  void selectSkyPreset(SkyPreset preset) {
    state = state.copyWith(
      selectedSky: preset,
      skyHorizonOffset: preset.horizonOffset,
      skyAtmosphericBlend: preset.atmosphericBlend,
    );
  }

  void updateSkyHorizon(double offset) {
    state = state.copyWith(skyHorizonOffset: offset);
  }

  void updateSkyBlend(double blend) {
    state = state.copyWith(skyAtmosphericBlend: blend);
  }

  void toggleCompareSplitView(bool enable) {
    state = state.copyWith(compareSplitView: enable);
  }

  Future<void> executeCurrentTask({
    required String videoUrl,
    required String userId,
  }) async {
    if (!state.quota.hasRemainingQuota) {
      state = state.copyWith(
        errorMessage: 'Daily Cloud GPU vision quota reached. Upgrade or wait for reset.',
      );
      return;
    }

    state = state.copyWith(
      isProcessing: true,
      currentProgress: 0.05,
      errorMessage: null,
    );

    final client = ref.read(cloudVisionClientProvider);
    CloudVisionJob job;

    try {
      switch (state.activeTask) {
        case VisionTaskType.rotoscope:
          job = await client.submitRotoscope(
            target: RotoscopeTarget(
              prompt: state.rotoscopePrompt,
              trackFrames: state.rotoscopeTracking,
            ),
            videoUrl: videoUrl,
            userId: userId,
          );
          break;
        case VisionTaskType.enhance:
          job = await client.submitEnhance(
            mode: state.selectedEnhanceMode,
            videoUrl: videoUrl,
            userId: userId,
          );
          break;
        case VisionTaskType.relight:
          job = await client.submitRelight(
            config: state.relightConfig,
            videoUrl: videoUrl,
            userId: userId,
          );
          break;
        case VisionTaskType.skyReplace:
          job = await client.submitSkyReplace(
            preset: state.selectedSky,
            videoUrl: videoUrl,
            userId: userId,
          );
          break;
      }

      state = state.copyWith(
        activeJob: job,
        activePreviewUrl: job.previewUrl,
        currentProgress: job.progress,
      );

      // Listen to progress updates
      await _progressSubscription?.cancel();
      _progressSubscription = client.streamJobProgress(job.jobId).listen(
        (updated) {
          state = state.copyWith(
            activeJob: updated,
            currentProgress: updated.progress,
            activeOutputUrl: updated.outputUrl,
            isProcessing: updated.isProcessing,
          );

          if (updated.isCompleted) {
            // Increment quota usage
            state = state.copyWith(
              quota: state.quota.copyWith(
                jobsUsedToday: state.quota.jobsUsedToday + 1,
              ),
            );
          }
        },
        onError: (err) {
          state = state.copyWith(
            isProcessing: false,
            errorMessage: err.toString(),
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to dispatch cloud task: $e',
      );
    }
  }

  void cancelCurrentJob() {
    _progressSubscription?.cancel();
    state = state.copyWith(
      isProcessing: false,
      currentProgress: 0.0,
      errorMessage: 'Task cancelled by user',
    );
  }

  void resetJob() {
    _progressSubscription?.cancel();
    state = state.copyWith(
      activeJob: null,
      isProcessing: false,
      currentProgress: 0.0,
      activeOutputUrl: null,
      errorMessage: null,
    );
  }
}

final cloudVisionControllerProvider =
    NotifierProvider<CloudVisionController, CloudVisionState>(() {
  return CloudVisionController();
});
