import 'package:flutter/foundation.dart';

/// Vision tasks that run on Cloud Run GPU or accelerated local neural runtime.
enum VisionTaskType {
  rotoscope,
  enhance,
  relight,
  skyReplace,
}

/// AI enhancement modes.
enum AiEnhanceMode {
  upscale2x('2x HD Upscale', 'Real-ESRGAN super-resolution preserving sharp textures'),
  upscale4x('4x Ultra Upscale', 'Maximum detail reconstruction up to 4K resolution'),
  denoise('Neural Denoise', 'Temporal neural noise removal for low-light shots'),
  frameInterpolation60fps('60 FPS Smooth Flow', 'RIFE motion vector interpolation for silky slow-mo');

  final String label;
  final String description;
  const AiEnhanceMode(this.label, this.description);
}

/// Prompt specification for natural-language or interactive rotoscoping.
@immutable
class RotoscopeTarget {
  final String prompt;
  final List<double>? boxCoords; // [ymin, xmin, ymax, xmax]
  final List<List<double>>? pointCoords; // [[x, y], ...]
  final bool trackFrames;

  const RotoscopeTarget({
    required this.prompt,
    this.boxCoords,
    this.pointCoords,
    this.trackFrames = true,
  });

  Map<String, dynamic> toJson({required String videoUrl, required String userId}) {
    return {
      'prompt': prompt,
      'video_url': videoUrl,
      if (boxCoords != null) 'box_coords': boxCoords,
      if (pointCoords != null) 'point_coords': pointCoords,
      'track_frames': trackFrames,
      'user_id': userId,
    };
  }
}

/// Neural relighting parameter configuration.
@immutable
class RelightConfig {
  final List<double> lightPosition; // [x, y, z] normalized
  final String lightColorHex;
  final double intensity; // 0.0 - 3.0
  final double falloff; // 0.0 - 1.0

  const RelightConfig({
    this.lightPosition = const [0.5, 0.3, 1.0],
    this.lightColorHex = '#FFFFFF',
    this.intensity = 1.0,
    this.falloff = 0.5,
  });

  RelightConfig copyWith({
    List<double>? lightPosition,
    String? lightColorHex,
    double? intensity,
    double? falloff,
  }) {
    return RelightConfig(
      lightPosition: lightPosition ?? this.lightPosition,
      lightColorHex: lightColorHex ?? this.lightColorHex,
      intensity: intensity ?? this.intensity,
      falloff: falloff ?? this.falloff,
    );
  }

  Map<String, dynamic> toJson({required String videoUrl, required String userId}) {
    return {
      'video_url': videoUrl,
      'light_position': lightPosition,
      'light_color': lightColorHex,
      'intensity': intensity,
      'falloff': falloff,
      'user_id': userId,
    };
  }
}

/// Catalog preset for sky replacement.
@immutable
class SkyPreset {
  final String id;
  final String name;
  final String category;
  final String previewThumb;
  final double horizonOffset;
  final double atmosphericBlend;

  const SkyPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.previewThumb,
    this.horizonOffset = 0.0,
    this.atmosphericBlend = 0.70,
  });

  static const List<SkyPreset> defaultPresets = [
    SkyPreset(
      id: 'golden_hour_dusk',
      name: 'Golden Hour Dusk',
      category: 'Warm & Dramatic',
      previewThumb: 'assets/sky/golden_hour.jpg',
      atmosphericBlend: 0.75,
    ),
    SkyPreset(
      id: 'neon_twilight',
      name: 'Cyber Twilight',
      category: 'Stylized',
      previewThumb: 'assets/sky/neon_twilight.jpg',
      atmosphericBlend: 0.65,
    ),
    SkyPreset(
      id: 'stormy_drama',
      name: 'Moody Stormclouds',
      category: 'Atmospheric',
      previewThumb: 'assets/sky/stormy.jpg',
      atmosphericBlend: 0.80,
    ),
    SkyPreset(
      id: 'azure_clarity',
      name: 'Clear Azure High-Noon',
      category: 'Natural',
      previewThumb: 'assets/sky/azure.jpg',
      atmosphericBlend: 0.50,
    ),
    SkyPreset(
      id: 'milky_way_astral',
      name: 'Milky Way Galaxy',
      category: 'Cinematic Night',
      previewThumb: 'assets/sky/milky_way.jpg',
      atmosphericBlend: 0.85,
    ),
  ];
}

/// Daily quotas for cloud GPU vision tasks.
@immutable
class CloudVisionQuota {
  final int dailyBudgetJobs;
  final int jobsUsedToday;
  final bool proTierUnlocked;
  final DateTime resetAt;

  const CloudVisionQuota({
    this.dailyBudgetJobs = 10,
    this.jobsUsedToday = 2,
    this.proTierUnlocked = false,
    required this.resetAt,
  });

  int get jobsRemaining => (dailyBudgetJobs - jobsUsedToday).clamp(0, dailyBudgetJobs);
  bool get hasRemainingQuota => jobsRemaining > 0;
  double get usagePercent => dailyBudgetJobs == 0 ? 1.0 : (jobsUsedToday / dailyBudgetJobs).clamp(0.0, 1.0);

  CloudVisionQuota copyWith({
    int? dailyBudgetJobs,
    int? jobsUsedToday,
    bool? proTierUnlocked,
    DateTime? resetAt,
  }) {
    return CloudVisionQuota(
      dailyBudgetJobs: dailyBudgetJobs ?? this.dailyBudgetJobs,
      jobsUsedToday: jobsUsedToday ?? this.jobsUsedToday,
      proTierUnlocked: proTierUnlocked ?? this.proTierUnlocked,
      resetAt: resetAt ?? this.resetAt,
    );
  }
}

/// Trackable Cloud Vision processing job status.
@immutable
class CloudVisionJob {
  final String jobId;
  final VisionTaskType taskType;
  final String status; // 'queued' | 'processing' | 'completed' | 'failed'
  final double progress; // 0.0 - 1.0
  final String? outputUrl;
  final String? previewUrl;
  final Map<String, dynamic>? telemetry;
  final String? errorMessage;
  final DateTime createdAt;

  const CloudVisionJob({
    required this.jobId,
    required this.taskType,
    required this.status,
    required this.progress,
    this.outputUrl,
    this.previewUrl,
    this.telemetry,
    this.errorMessage,
    required this.createdAt,
  });

  bool get isProcessing => status == 'processing' || status == 'queued';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  CloudVisionJob copyWith({
    String? jobId,
    VisionTaskType? taskType,
    String? status,
    double? progress,
    String? outputUrl,
    String? previewUrl,
    Map<String, dynamic>? telemetry,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return CloudVisionJob(
      jobId: jobId ?? this.jobId,
      taskType: taskType ?? this.taskType,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputUrl: outputUrl ?? this.outputUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      telemetry: telemetry ?? this.telemetry,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CloudVisionJob.fromJson(Map<String, dynamic> json) {
    VisionTaskType type;
    final taskStr = json['task_type'] as String? ?? 'rotoscope';
    switch (taskStr) {
      case 'enhance':
        type = VisionTaskType.enhance;
        break;
      case 'relight':
        type = VisionTaskType.relight;
        break;
      case 'sky_replace':
        type = VisionTaskType.skyReplace;
        break;
      case 'rotoscope':
      default:
        type = VisionTaskType.rotoscope;
    }

    return CloudVisionJob(
      jobId: json['job_id'] as String,
      taskType: type,
      status: json['status'] as String? ?? 'queued',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      outputUrl: json['output_url'] as String?,
      previewUrl: json['preview_url'] as String?,
      telemetry: json['telemetry'] as Map<String, dynamic>?,
      errorMessage: json['error'] as String?,
      createdAt: DateTime.now(),
    );
  }
}
