import 'package:flutter/foundation.dart';
import '../../models/oneova_look.dart';

/// Keyframe curve easing types for color grade interpolation.
enum KeyframeEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut,
}

/// A timestamped keyframe holding Look parameter overrides.
@immutable
class LookKeyframe {
  final double timeSeconds;
  final OneovaLook look;
  final KeyframeEasing easing;

  const LookKeyframe({
    required this.timeSeconds,
    required this.look,
    this.easing = KeyframeEasing.easeInOut,
  });

  Map<String, dynamic> toMap() => {
        'timeSeconds': timeSeconds,
        'look': look.toMap(),
        'easing': easing.name,
      };

  factory LookKeyframe.fromMap(Map<String, dynamic> map) {
    return LookKeyframe(
      timeSeconds: (map['timeSeconds'] as num?)?.toDouble() ?? 0.0,
      look: map['look'] is Map<String, dynamic>
          ? OneovaLook.fromMap(map['look'] as Map<String, dynamic>)
          : const OneovaLook(),
      easing: KeyframeEasing.values.firstWhere(
        (e) => e.name == map['easing'],
        orElse: () => KeyframeEasing.easeInOut,
      ),
    );
  }
}

/// Color grade configuration applied to an individual video clip on the timeline.
@immutable
class ClipColorGrade {
  final String clipId;
  final String clipName;
  final double startTimeSeconds;
  final double durationSeconds;
  final OneovaLook baseLook;
  final double masterIntensity;
  final bool isBypassed;
  final List<LookKeyframe> keyframes;
  final bool isTrackedBeautyEnabled;
  final double trackedBeautySmoothing;

  const ClipColorGrade({
    required this.clipId,
    required this.clipName,
    required this.startTimeSeconds,
    required this.durationSeconds,
    required this.baseLook,
    this.masterIntensity = 1.0,
    this.isBypassed = false,
    this.keyframes = const [],
    this.isTrackedBeautyEnabled = false,
    this.trackedBeautySmoothing = 0.5,
  });

  bool get hasKeyframes => keyframes.isNotEmpty;

  ClipColorGrade copyWith({
    String? clipId,
    String? clipName,
    double? startTimeSeconds,
    double? durationSeconds,
    OneovaLook? baseLook,
    double? masterIntensity,
    bool? isBypassed,
    List<LookKeyframe>? keyframes,
    bool? isTrackedBeautyEnabled,
    double? trackedBeautySmoothing,
  }) {
    return ClipColorGrade(
      clipId: clipId ?? this.clipId,
      clipName: clipName ?? this.clipName,
      startTimeSeconds: startTimeSeconds ?? this.startTimeSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      baseLook: baseLook ?? this.baseLook,
      masterIntensity: masterIntensity ?? this.masterIntensity,
      isBypassed: isBypassed ?? this.isBypassed,
      keyframes: keyframes ?? this.keyframes,
      isTrackedBeautyEnabled: isTrackedBeautyEnabled ?? this.isTrackedBeautyEnabled,
      trackedBeautySmoothing: trackedBeautySmoothing ?? this.trackedBeautySmoothing,
    );
  }

  Map<String, dynamic> toMap() => {
        'clipId': clipId,
        'clipName': clipName,
        'startTimeSeconds': startTimeSeconds,
        'durationSeconds': durationSeconds,
        'baseLook': baseLook.toMap(),
        'masterIntensity': masterIntensity,
        'isBypassed': isBypassed,
        'keyframes': keyframes.map((k) => k.toMap()).toList(),
        'isTrackedBeautyEnabled': isTrackedBeautyEnabled,
        'trackedBeautySmoothing': trackedBeautySmoothing,
      };

  factory ClipColorGrade.fromMap(Map<String, dynamic> map) {
    return ClipColorGrade(
      clipId: map['clipId'] as String? ?? '',
      clipName: map['clipName'] as String? ?? 'Clip',
      startTimeSeconds: (map['startTimeSeconds'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 5.0,
      baseLook: map['baseLook'] is Map<String, dynamic>
          ? OneovaLook.fromMap(map['baseLook'] as Map<String, dynamic>)
          : const OneovaLook(),
      masterIntensity: (map['masterIntensity'] as num?)?.toDouble() ?? 1.0,
      isBypassed: map['isBypassed'] as bool? ?? false,
      keyframes: (map['keyframes'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(LookKeyframe.fromMap)
              .toList() ??
          const [],
      isTrackedBeautyEnabled: map['isTrackedBeautyEnabled'] as bool? ?? false,
      trackedBeautySmoothing: (map['trackedBeautySmoothing'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// An adjustment layer on the timeline that applies a grade to all underlying tracks.
@immutable
class AdjustmentLayerGrade {
  final String id;
  final String name;
  final double startTimeSeconds;
  final double durationSeconds;
  final OneovaLook look;
  final double intensity;
  final bool isEnabled;

  const AdjustmentLayerGrade({
    required this.id,
    required this.name,
    required this.startTimeSeconds,
    required this.durationSeconds,
    required this.look,
    this.intensity = 1.0,
    this.isEnabled = true,
  });

  AdjustmentLayerGrade copyWith({
    String? id,
    String? name,
    double? startTimeSeconds,
    double? durationSeconds,
    OneovaLook? look,
    double? intensity,
    bool? isEnabled,
  }) {
    return AdjustmentLayerGrade(
      id: id ?? this.id,
      name: name ?? this.name,
      startTimeSeconds: startTimeSeconds ?? this.startTimeSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      look: look ?? this.look,
      intensity: intensity ?? this.intensity,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'startTimeSeconds': startTimeSeconds,
        'durationSeconds': durationSeconds,
        'look': look.toMap(),
        'intensity': intensity,
        'isEnabled': isEnabled,
      };

  factory AdjustmentLayerGrade.fromMap(Map<String, dynamic> map) {
    return AdjustmentLayerGrade(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Adjustment Layer',
      startTimeSeconds: (map['startTimeSeconds'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 5.0,
      look: map['look'] is Map<String, dynamic>
          ? OneovaLook.fromMap(map['look'] as Map<String, dynamic>)
          : const OneovaLook(),
      intensity: (map['intensity'] as num?)?.toDouble() ?? 1.0,
      isEnabled: map['isEnabled'] as bool? ?? true,
    );
  }
}

/// Specification and results of an AI Shot Match operation.
@immutable
class ShotMatchResult {
  final String referenceClipId;
  final String targetClipId;
  final double exposureOffset;
  final double contrastOffset;
  final double temperatureDelta;
  final double tintDelta;
  final double saturationRatio;
  final OneovaLook matchedLook;
  final double confidenceScore;

  const ShotMatchResult({
    required this.referenceClipId,
    required this.targetClipId,
    required this.exposureOffset,
    required this.contrastOffset,
    required this.temperatureDelta,
    required this.tintDelta,
    required this.saturationRatio,
    required this.matchedLook,
    required this.confidenceScore,
  });
}

/// Video export configuration supporting native hardware and cloud render paths.
@immutable
class VideoExportConfig {
  final int width;
  final int height;
  final double fps;
  final int bitDepth; // 8, 10
  final bool isHdr;
  final String videoCodec; // 'hevc', 'h264', 'prores'
  final int targetBitrateKbps;
  final bool useCloudRender;
  final String audioCodec;

  const VideoExportConfig({
    this.width = 1920,
    this.height = 1080,
    this.fps = 30.0,
    this.bitDepth = 8,
    this.isHdr = false,
    this.videoCodec = 'hevc',
    this.targetBitrateKbps = 24000,
    this.useCloudRender = false,
    this.audioCodec = 'aac',
  });

  VideoExportConfig copyWith({
    int? width,
    int? height,
    double? fps,
    int? bitDepth,
    bool? isHdr,
    String? videoCodec,
    int? targetBitrateKbps,
    bool? useCloudRender,
    String? audioCodec,
  }) {
    return VideoExportConfig(
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      bitDepth: bitDepth ?? this.bitDepth,
      isHdr: isHdr ?? this.isHdr,
      videoCodec: videoCodec ?? this.videoCodec,
      targetBitrateKbps: targetBitrateKbps ?? this.targetBitrateKbps,
      useCloudRender: useCloudRender ?? this.useCloudRender,
      audioCodec: audioCodec ?? this.audioCodec,
    );
  }
}

/// Status of local or cloud video render jobs.
enum RenderJobStatus {
  idle,
  queued,
  rendering,
  compositing,
  completed,
  failed,
}

@immutable
class VideoRenderJob {
  final String jobId;
  final RenderJobStatus status;
  final double progress; // 0.0 to 1.0
  final int estimatedSecondsRemaining;
  final String? outputPath;
  final String? outputDownloadUrl;
  final String? errorMessage;
  final Duration elapsedDuration;

  const VideoRenderJob({
    required this.jobId,
    this.status = RenderJobStatus.idle,
    this.progress = 0.0,
    this.estimatedSecondsRemaining = 0,
    this.outputPath,
    this.outputDownloadUrl,
    this.errorMessage,
    this.elapsedDuration = Duration.zero,
  });

  bool get isDone => status == RenderJobStatus.completed;
  bool get isFailed => status == RenderJobStatus.failed;
  bool get isRunning => status == RenderJobStatus.rendering || status == RenderJobStatus.compositing;

  VideoRenderJob copyWith({
    String? jobId,
    RenderJobStatus? status,
    double? progress,
    int? estimatedSecondsRemaining,
    String? outputPath,
    String? outputDownloadUrl,
    String? errorMessage,
    Duration? elapsedDuration,
  }) {
    return VideoRenderJob(
      jobId: jobId ?? this.jobId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      estimatedSecondsRemaining: estimatedSecondsRemaining ?? this.estimatedSecondsRemaining,
      outputPath: outputPath ?? this.outputPath,
      outputDownloadUrl: outputDownloadUrl ?? this.outputDownloadUrl,
      errorMessage: errorMessage ?? this.errorMessage,
      elapsedDuration: elapsedDuration ?? this.elapsedDuration,
    );
  }
}
