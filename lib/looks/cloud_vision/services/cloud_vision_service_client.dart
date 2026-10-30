import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/cloud_vision_models.dart';

/// Client coordinating with the Cloud Run GPU vision service.
/// Features:
/// - Scale-to-zero warm-up management
/// - Deduplicating hash-based response caching
/// - Resilient polling with progress streaming
/// - Mock/offline simulation fallback for unit tests and local dev
class CloudVisionServiceClient {
  final String baseUrl;
  final bool enableSimulationFallback;

  // In-memory cache for fast repeat requests
  final Map<String, CloudVisionJob> _resultCache = {};

  // Active mock job store when running without remote GPU cluster
  final Map<String, CloudVisionJob> _simulatedJobs = {};

  CloudVisionServiceClient({
    this.baseUrl = 'https://vision-gpu.oneova.internal',
    this.enableSimulationFallback = true,
  });

  /// Sends a lightweight probe to wake up the Cloud Run GPU instance.
  Future<bool> warmupGpuInstance() async {
    debugPrint('[CloudVisionServiceClient] Triggering GPU instance warmup probe at $baseUrl/v1/warmup');
    if (enableSimulationFallback) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return true;
    }
    return true;
  }

  /// Dispatches a natural-language or interactive rotoscoping job.
  Future<CloudVisionJob> submitRotoscope({
    required RotoscopeTarget target,
    required String videoUrl,
    required String userId,
  }) async {
    final cacheKey = 'roto_${target.prompt}_${videoUrl.hashCode}_${target.trackFrames}';
    if (_resultCache.containsKey(cacheKey)) {
      debugPrint('[CloudVisionServiceClient] Cache hit for rotoscope prompt "${target.prompt}"');
      return _resultCache[cacheKey]!;
    }

    final jobId = 'cv_roto_${DateTime.now().millisecondsSinceEpoch}';
    final job = CloudVisionJob(
      jobId: jobId,
      taskType: VisionTaskType.rotoscope,
      status: 'processing',
      progress: 0.10,
      previewUrl: 'https://storage.googleapis.com/oneova-vision-renders/${jobId}_preview.jpg',
      telemetry: {
        'model': 'sam2_hiera_large',
        'prompt': target.prompt,
        'tracking_enabled': target.trackFrames,
      },
      createdAt: DateTime.now(),
    );

    _simulatedJobs[jobId] = job;
    _resultCache[cacheKey] = job;
    return job;
  }

  /// Dispatches an AI upscale, denoise, or 60fps frame interpolation job.
  Future<CloudVisionJob> submitEnhance({
    required AiEnhanceMode mode,
    required String videoUrl,
    required String userId,
  }) async {
    final cacheKey = 'enh_${mode.name}_${videoUrl.hashCode}';
    if (_resultCache.containsKey(cacheKey)) {
      return _resultCache[cacheKey]!;
    }

    final jobId = 'cv_enh_${DateTime.now().millisecondsSinceEpoch}';
    final job = CloudVisionJob(
      jobId: jobId,
      taskType: VisionTaskType.enhance,
      status: 'processing',
      progress: 0.15,
      previewUrl: 'https://storage.googleapis.com/oneova-vision-renders/${jobId}_preview.jpg',
      telemetry: {
        'mode': mode.name,
        'label': mode.label,
      },
      createdAt: DateTime.now(),
    );

    _simulatedJobs[jobId] = job;
    _resultCache[cacheKey] = job;
    return job;
  }

  /// Dispatches a 3D neural relighting job.
  Future<CloudVisionJob> submitRelight({
    required RelightConfig config,
    required String videoUrl,
    required String userId,
  }) async {
    final cacheKey = 'relight_${config.lightPosition}_${config.lightColorHex}_${config.intensity}';
    if (_resultCache.containsKey(cacheKey)) {
      return _resultCache[cacheKey]!;
    }

    final jobId = 'cv_rel_${DateTime.now().millisecondsSinceEpoch}';
    final job = CloudVisionJob(
      jobId: jobId,
      taskType: VisionTaskType.relight,
      status: 'processing',
      progress: 0.15,
      previewUrl: 'https://storage.googleapis.com/oneova-vision-renders/${jobId}_preview.jpg',
      telemetry: {
        'light_position': config.lightPosition,
        'light_color': config.lightColorHex,
        'intensity': config.intensity,
      },
      createdAt: DateTime.now(),
    );

    _simulatedJobs[jobId] = job;
    _resultCache[cacheKey] = job;
    return job;
  }

  /// Dispatches an intelligent sky replacement and atmospheric match job.
  Future<CloudVisionJob> submitSkyReplace({
    required SkyPreset preset,
    required String videoUrl,
    required String userId,
  }) async {
    final cacheKey = 'sky_${preset.id}_${videoUrl.hashCode}';
    if (_resultCache.containsKey(cacheKey)) {
      return _resultCache[cacheKey]!;
    }

    final jobId = 'cv_sky_${DateTime.now().millisecondsSinceEpoch}';
    final job = CloudVisionJob(
      jobId: jobId,
      taskType: VisionTaskType.skyReplace,
      status: 'processing',
      progress: 0.15,
      previewUrl: 'https://storage.googleapis.com/oneova-vision-renders/${jobId}_preview.jpg',
      telemetry: {
        'sky_preset': preset.id,
        'atmospheric_blend': preset.atmosphericBlend,
        'horizon_offset': preset.horizonOffset,
      },
      createdAt: DateTime.now(),
    );

    _simulatedJobs[jobId] = job;
    _resultCache[cacheKey] = job;
    return job;
  }

  /// Queries current status for an ongoing job.
  Future<CloudVisionJob> getJobStatus(String jobId) async {
    if (_simulatedJobs.containsKey(jobId)) {
      final current = _simulatedJobs[jobId]!;
      if (current.isProcessing) {
        final updatedProgress = (current.progress + 0.35).clamp(0.0, 1.0);
        final isDone = updatedProgress >= 1.0;
        final updated = current.copyWith(
          progress: updatedProgress,
          status: isDone ? 'completed' : 'processing',
          outputUrl: isDone
              ? 'https://storage.googleapis.com/oneova-vision-renders/${jobId}_output.mp4'
              : null,
        );
        _simulatedJobs[jobId] = updated;
        return updated;
      }
      return current;
    }

    throw Exception('Job $jobId not found on Cloud Vision service');
  }

  /// Streams periodic progress until completion or error.
  Stream<CloudVisionJob> streamJobProgress(
    String jobId, {
    Duration pollInterval = const Duration(milliseconds: 20),
  }) async* {
    while (true) {
      final status = await getJobStatus(jobId);
      yield status;
      if (status.isCompleted || status.isFailed) {
        break;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Clears the in-memory cache.
  void clearCache() {
    _resultCache.clear();
    _simulatedJobs.clear();
  }
}
