import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/oneova_look.dart';
import '../models/video_color_models.dart';
import '../../photo/models/photo_grading_models.dart';
import '../services/shot_match_service.dart';
import '../services/video_keyframe_interpolator.dart';
import '../services/hardware_export_service.dart';

@immutable
class VideoColorTimelineState {
  final List<ClipColorGrade> clips;
  final String? activeClipId;
  final List<AdjustmentLayerGrade> adjustmentLayers;
  final double playheadSeconds;
  final OneovaLook effectiveLook;
  final VideoExportConfig exportConfig;
  final VideoRenderJob? activeRenderJob;
  final String? referenceClipIdForMatch;
  final ShotMatchResult? lastShotMatchResult;
  final bool isScopesVisible;
  final ScopeType activeScopeType;
  final String? statusMessage;

  const VideoColorTimelineState({
    required this.clips,
    this.activeClipId,
    this.adjustmentLayers = const [],
    this.playheadSeconds = 0.0,
    required this.effectiveLook,
    this.exportConfig = const VideoExportConfig(),
    this.activeRenderJob,
    this.referenceClipIdForMatch,
    this.lastShotMatchResult,
    this.isScopesVisible = false,
    this.activeScopeType = ScopeType.waveform,
    this.statusMessage,
  });

  ClipColorGrade? get activeClip {
    if (activeClipId == null) return clips.isNotEmpty ? clips.first : null;
    return clips.firstWhere((c) => c.clipId == activeClipId, orElse: () => clips.first);
  }

  VideoColorTimelineState copyWith({
    List<ClipColorGrade>? clips,
    String? activeClipId,
    List<AdjustmentLayerGrade>? adjustmentLayers,
    double? playheadSeconds,
    OneovaLook? effectiveLook,
    VideoExportConfig? exportConfig,
    VideoRenderJob? activeRenderJob,
    String? referenceClipIdForMatch,
    ShotMatchResult? lastShotMatchResult,
    bool? isScopesVisible,
    ScopeType? activeScopeType,
    String? statusMessage,
  }) {
    return VideoColorTimelineState(
      clips: clips ?? this.clips,
      activeClipId: activeClipId ?? this.activeClipId,
      adjustmentLayers: adjustmentLayers ?? this.adjustmentLayers,
      playheadSeconds: playheadSeconds ?? this.playheadSeconds,
      effectiveLook: effectiveLook ?? this.effectiveLook,
      exportConfig: exportConfig ?? this.exportConfig,
      activeRenderJob: activeRenderJob ?? this.activeRenderJob,
      referenceClipIdForMatch: referenceClipIdForMatch ?? this.referenceClipIdForMatch,
      lastShotMatchResult: lastShotMatchResult ?? this.lastShotMatchResult,
      isScopesVisible: isScopesVisible ?? this.isScopesVisible,
      activeScopeType: activeScopeType ?? this.activeScopeType,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class VideoColorTimelineController extends Notifier<VideoColorTimelineState> {
  late final ShotMatchService _shotMatchService;
  late final VideoKeyframeInterpolator _interpolator;
  late final HardwareExportService _exportService;

  @override
  VideoColorTimelineState build() {
    _shotMatchService = ShotMatchService();
    _interpolator = VideoKeyframeInterpolator();
    _exportService = HardwareExportService();

    // Starter sample clips for timeline color grading
    const clip1 = ClipColorGrade(
      clipId: 'clip_01',
      clipName: 'A01_Intro_Wide.mov',
      startTimeSeconds: 0.0,
      durationSeconds: 4.5,
      baseLook: OneovaLook(
        id: 'look_cinematic',
        name: 'Cinematic Daylight',
        primary: LookPrimary(exposure: 0.1, contrast: 1.15),
        color: LookColor(temperature: 12.0),
      ),
    );

    const clip2 = ClipColorGrade(
      clipId: 'clip_02',
      clipName: 'A02_CloseUp_Dialogue.mov',
      startTimeSeconds: 4.5,
      durationSeconds: 6.0,
      baseLook: OneovaLook(
        id: 'look_portrait',
        name: 'Clean Dialogue',
        primary: LookPrimary(contrast: 1.05, shadows: 0.1),
        boostBeauty: BoostBeautyConfig(isEnabled: true, smoothSkin: 0.4),
      ),
      isTrackedBeautyEnabled: true,
    );

    const clip3 = ClipColorGrade(
      clipId: 'clip_03',
      clipName: 'A03_Outdoor_Action.mov',
      startTimeSeconds: 10.5,
      durationSeconds: 5.0,
      baseLook: OneovaLook(
        id: 'look_action',
        name: 'High Contrast Teal/Orange',
        primary: LookPrimary(contrast: 1.25, whites: 0.1),
        color: LookColor(temperature: -15.0, tint: 8.0, saturation: 1.15),
      ),
    );

    return VideoColorTimelineState(
      clips: const [clip1, clip2, clip3],
      activeClipId: 'clip_01',
      effectiveLook: clip1.baseLook,
    );
  }

  /// Selects active clip for color inspection and grading.
  void selectClip(String clipId) {
    final clip = state.clips.firstWhere((c) => c.clipId == clipId, orElse: () => state.clips.first);
    state = state.copyWith(
      activeClipId: clipId,
      effectiveLook: clip.baseLook,
      statusMessage: 'Selected clip: ${clip.clipName}',
    );
  }

  /// Sets timeline playhead position and evaluates keyframed/adjustment layer look.
  void setPlayhead(double seconds) {
    // Find active clip at timestamp
    ClipColorGrade? matchingClip;
    for (final c in state.clips) {
      if (seconds >= c.startTimeSeconds && seconds < (c.startTimeSeconds + c.durationSeconds)) {
        matchingClip = c;
        break;
      }
    }

    matchingClip ??= state.clips.first;

    // Evaluate interpolated look at time
    final interpolatedLook = _interpolator.interpolateAtTime(
      clipGrade: matchingClip,
      currentTimeSeconds: seconds - matchingClip.startTimeSeconds,
    );

    // Apply any active adjustment layer covering this timestamp
    OneovaLook combinedLook = interpolatedLook;
    for (final adj in state.adjustmentLayers) {
      if (adj.isEnabled && seconds >= adj.startTimeSeconds && seconds <= (adj.startTimeSeconds + adj.durationSeconds)) {
        // Blend adjustment layer look
        combinedLook = combinedLook.copyWith(
          primary: LookPrimary(
            exposure: combinedLook.primary.exposure + adj.look.primary.exposure * adj.intensity,
            contrast: combinedLook.primary.contrast * (1.0 + (adj.look.primary.contrast - 1.0) * adj.intensity),
          ),
          color: LookColor(
            temperature: combinedLook.color.temperature + adj.look.color.temperature * adj.intensity,
            tint: combinedLook.color.tint + adj.look.color.tint * adj.intensity,
          ),
        );
      }
    }

    state = state.copyWith(
      playheadSeconds: seconds,
      activeClipId: matchingClip.clipId,
      effectiveLook: combinedLook,
    );
  }

  /// Updates the base look of the currently active clip.
  void updateActiveClipLook(OneovaLook updatedLook) {
    final curId = state.activeClipId;
    if (curId == null) return;

    final updatedClips = state.clips.map((c) {
      if (c.clipId == curId) {
        return c.copyWith(baseLook: updatedLook);
      }
      return c;
    }).toList();

    state = state.copyWith(
      clips: updatedClips,
      effectiveLook: updatedLook,
    );
  }

  /// Updates the overall master intensity of the active clip grade.
  void updateActiveClipIntensity(double intensity) {
    final curId = state.activeClipId;
    if (curId == null) return;

    final updatedClips = state.clips.map((c) {
      if (c.clipId == curId) {
        return c.copyWith(masterIntensity: intensity.clamp(0.0, 1.0));
      }
      return c;
    }).toList();

    state = state.copyWith(clips: updatedClips);
  }

  /// Toggles bypass of active clip color grade.
  void toggleActiveClipBypass() {
    final curId = state.activeClipId;
    if (curId == null) return;

    final updatedClips = state.clips.map((c) {
      if (c.clipId == curId) {
        return c.copyWith(isBypassed: !c.isBypassed);
      }
      return c;
    }).toList();

    state = state.copyWith(clips: updatedClips);
  }

  /// Adds a keyframe at [timeSeconds] on the active clip.
  void addKeyframeToActiveClip({
    required double timeSeconds,
    required OneovaLook look,
    KeyframeEasing easing = KeyframeEasing.easeInOut,
  }) {
    final curId = state.activeClipId;
    if (curId == null) return;

    final updatedClips = state.clips.map((c) {
      if (c.clipId == curId) {
        final existing = c.keyframes.where((k) => (k.timeSeconds - timeSeconds).abs() > 0.05).toList();
        existing.add(LookKeyframe(timeSeconds: timeSeconds, look: look, easing: easing));
        existing.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
        return c.copyWith(keyframes: existing);
      }
      return c;
    }).toList();

    state = state.copyWith(
      clips: updatedClips,
      statusMessage: 'Added keyframe at ${timeSeconds.toStringAsFixed(2)}s',
    );
  }

  /// Removes a keyframe from the active clip.
  void removeKeyframeFromActiveClip(double timeSeconds) {
    final curId = state.activeClipId;
    if (curId == null) return;

    final updatedClips = state.clips.map((c) {
      if (c.clipId == curId) {
        final existing = c.keyframes.where((k) => (k.timeSeconds - timeSeconds).abs() > 0.05).toList();
        return c.copyWith(keyframes: existing);
      }
      return c;
    }).toList();

    state = state.copyWith(clips: updatedClips);
  }

  /// Adds a global adjustment layer spanning all tracks.
  void addAdjustmentLayer({
    required String name,
    required double startTime,
    required double duration,
    required OneovaLook look,
    double intensity = 1.0,
  }) {
    final newLayer = AdjustmentLayerGrade(
      id: 'adj_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      startTimeSeconds: startTime,
      durationSeconds: duration,
      look: look,
      intensity: intensity,
    );

    state = state.copyWith(
      adjustmentLayers: [...state.adjustmentLayers, newLayer],
      statusMessage: 'Added adjustment layer: $name',
    );
  }

  /// Removes an adjustment layer.
  void removeAdjustmentLayer(String id) {
    state = state.copyWith(
      adjustmentLayers: state.adjustmentLayers.where((a) => a.id != id).toList(),
    );
  }

  /// Performs AI Shot Match between reference and target clips.
  ShotMatchResult matchShots({
    required String referenceClipId,
    required String targetClipId,
  }) {
    final refClip = state.clips.firstWhere((c) => c.clipId == referenceClipId);
    final tgtClip = state.clips.firstWhere((c) => c.clipId == targetClipId);

    final result = _shotMatchService.matchShots(
      referenceClipId: referenceClipId,
      targetClipId: targetClipId,
      referenceLook: refClip.baseLook,
      targetLook: tgtClip.baseLook,
    );

    state = state.copyWith(
      referenceClipIdForMatch: referenceClipId,
      lastShotMatchResult: result,
      statusMessage: 'Shot matched with ${(result.confidenceScore * 100).toInt()}% confidence',
    );

    return result;
  }

  /// Applies the computed shot match result to the target clip.
  void applyShotMatchResult() {
    final result = state.lastShotMatchResult;
    if (result == null) return;

    final updatedClips = state.clips.map((c) {
      if (c.clipId == result.targetClipId) {
        return c.copyWith(baseLook: result.matchedLook);
      }
      return c;
    }).toList();

    state = state.copyWith(
      clips: updatedClips,
      effectiveLook: result.matchedLook,
      statusMessage: 'Applied shot match to ${result.targetClipId}',
    );
  }

  /// Sets tracked boost beauty configuration for active clip.
  void setTrackedBeauty({required bool isEnabled, double? smoothing}) {
    final curId = state.activeClipId;
    if (curId == null) return;

    final updatedClips = state.clips.map((c) {
      if (c.clipId == curId) {
        return c.copyWith(
          isTrackedBeautyEnabled: isEnabled,
          trackedBeautySmoothing: smoothing ?? c.trackedBeautySmoothing,
        );
      }
      return c;
    }).toList();

    state = state.copyWith(clips: updatedClips);
  }

  /// Toggles GPU scopes on the video workstation.
  void toggleScopes({bool? visible, ScopeType? type}) {
    state = state.copyWith(
      isScopesVisible: visible ?? !state.isScopesVisible,
      activeScopeType: type ?? state.activeScopeType,
    );
  }

  /// Updates export settings.
  void updateExportConfig(VideoExportConfig config) {
    state = state.copyWith(exportConfig: config);
  }

  /// Dispatches video export through hardware or Cloud Run GPU.
  Future<VideoRenderJob> startExport() async {
    state = state.copyWith(
      activeRenderJob: const VideoRenderJob(
        jobId: 'init',
        status: RenderJobStatus.queued,
        progress: 0.05,
      ),
    );

    try {
      final job = await _exportService.exportVideo(
        clips: state.clips,
        adjustmentLayers: state.adjustmentLayers,
        config: state.exportConfig,
        onProgress: (j) {
          state = state.copyWith(activeRenderJob: j);
        },
      );

      state = state.copyWith(
        activeRenderJob: job,
        statusMessage: 'Export complete: ${job.outputPath ?? job.outputDownloadUrl}',
      );
      return job;
    } catch (e) {
      state = state.copyWith(
        activeRenderJob: VideoRenderJob(
          jobId: 'err',
          status: RenderJobStatus.failed,
          errorMessage: e.toString(),
        ),
        statusMessage: 'Export failed: $e',
      );
      rethrow;
    }
  }
}

final videoColorTimelineControllerProvider =
    NotifierProvider<VideoColorTimelineController, VideoColorTimelineState>(() {
  return VideoColorTimelineController();
});
