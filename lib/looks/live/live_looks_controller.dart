import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';

import '../../backend/live/models/live_models.dart';
import '../adapters/legacy_look_adapters.dart';
import '../device/models/thermal_state.dart';
import '../device/providers/device_providers.dart';
import '../engine/look_compiler.dart';
import '../engine/native_look.dart';
import '../models/look_param_ranges.dart';
import '../models/oneova_look.dart';
import 'models/live_profile.dart';

/// State of the live video stream's real-time look processing pipeline.
@immutable
class LiveLooksState {
  final OneovaLook activeLook;
  final BoostBeautyConfig beauty;
  final BackgroundEffectConfig background;
  final String? attachedTrackId;
  final bool isAttached;
  final LookProcessorStats? latestStats;
  final LiveScene? activeScene;
  final LiveProfile? activeProfile;
  final bool isCompiling;
  final String? lastError;

  const LiveLooksState({
    this.activeLook = const OneovaLook(name: 'Neutral Live'),
    this.beauty = const BoostBeautyConfig(),
    this.background = const BackgroundEffectConfig(),
    this.attachedTrackId,
    this.isAttached = false,
    this.latestStats,
    this.activeScene,
    this.activeProfile,
    this.isCompiling = false,
    this.lastError,
  });

  LiveLooksState copyWith({
    OneovaLook? activeLook,
    BoostBeautyConfig? beauty,
    BackgroundEffectConfig? background,
    String? attachedTrackId,
    bool? isAttached,
    LookProcessorStats? latestStats,
    LiveScene? activeScene,
    LiveProfile? activeProfile,
    bool? isCompiling,
    String? lastError,
  }) {
    return LiveLooksState(
      activeLook: activeLook ?? this.activeLook,
      beauty: beauty ?? this.beauty,
      background: background ?? this.background,
      attachedTrackId: attachedTrackId ?? this.attachedTrackId,
      isAttached: isAttached ?? this.isAttached,
      latestStats: latestStats ?? this.latestStats,
      activeScene: activeScene ?? this.activeScene,
      activeProfile: activeProfile ?? this.activeProfile,
      isCompiling: isCompiling ?? this.isCompiling,
      lastError: lastError,
    );
  }
}

/// Controller managing real-time GPU Look processing on the live camera track.
class LiveLooksController extends Notifier<LiveLooksState> {
  TrackLookProcessor? _processor;
  Timer? _statsTimer;

  @override
  LiveLooksState build() {
    _initThermalListener();
    ref.onDispose(() {
      _stopStatsTimer();
      _processor?.detach();
    });
    return const LiveLooksState();
  }

  void _initThermalListener() {
    ref.listen<ThermalSnapshot>(
      thermalSnapshotStreamProvider.select(
        (asyncVal) => asyncVal.value ?? ref.read(thermalGovernorProvider).currentSnapshot,
      ),
      (prev, next) {
        if (prev?.activeMitigationTier != next.activeMitigationTier) {
          _onThermalMitigationChanged(next);
        }
      },
    );
  }

  /// Installs native GPU Look processor onto the primary camera track ID.
  Future<void> attachCameraTrack(String trackId) async {
    if (state.attachedTrackId == trackId && _processor != null && _processor!.isAttached) {
      return;
    }

    try {
      await detachCameraTrack();

      debugPrint('[LiveLooksController] Attaching TrackLookProcessor to track: $trackId');
      _processor = await TrackLookProcessor.attach(trackId);

      state = state.copyWith(
        attachedTrackId: trackId,
        isAttached: true,
        lastError: null,
      );

      // Re-apply currently active look to the freshly attached track
      await _compileAndDispatchLook(
        state.activeLook,
        crossFade: Duration.zero,
      );

      _startStatsTimer();
    } catch (e) {
      debugPrint('[LiveLooksController] Failed to attach TrackLookProcessor: $e');
      state = state.copyWith(
        isAttached: false,
        lastError: e.toString(),
      );
    }
  }

  /// Detaches processor from the current camera track.
  Future<void> detachCameraTrack() async {
    _stopStatsTimer();
    if (_processor != null) {
      try {
        debugPrint(
            '[LiveLooksController] Detaching TrackLookProcessor from track: ${state.attachedTrackId}');
        await _processor!.detach();
      } catch (e) {
        debugPrint('[LiveLooksController] Error detaching processor: $e');
      } finally {
        _processor = null;
      }
    }
    state = state.copyWith(
      attachedTrackId: null,
      isAttached: false,
    );
  }

  /// Sets the active Look on the stream with cross-fade transition.
  Future<void> applyLook(OneovaLook look, {Duration? crossFade}) async {
    final mergedLook = look.copyWith(
      boostBeauty: state.beauty,
      background: state.background,
    );
    state = state.copyWith(activeLook: mergedLook);
    await _compileAndDispatchLook(mergedLook, crossFade: crossFade);
  }

  /// Adjusts Boost Beauty parameters live on the stream.
  Future<void> applyBeauty(BoostBeautyConfig beauty) async {
    state = state.copyWith(beauty: beauty);
    final mergedLook = state.activeLook.copyWith(boostBeauty: beauty);
    state = state.copyWith(activeLook: mergedLook);
    await _compileAndDispatchLook(mergedLook, crossFade: Duration.zero);
  }

  /// Adapts and applies legacy `LiveBeautyConfig` to the stream.
  Future<void> applyLegacyBeauty(LiveBeautyConfig legacyConfig) async {
    final adaptedBeauty = LegacyLookAdapters.fromLiveBeautyConfig(legacyConfig);
    await applyBeauty(adaptedBeauty);
  }

  /// Switches to a complete Live Scene (Look + beauty + background).
  Future<void> switchScene(LiveScene scene) async {
    final sceneLook = (scene.look ?? state.activeLook).copyWith(
      boostBeauty: scene.beauty,
      background: scene.background,
    );

    state = state.copyWith(
      activeScene: scene,
      activeLook: sceneLook,
      beauty: scene.beauty,
      background: scene.background,
    );

    await _compileAndDispatchLook(
      sceneLook,
      crossFade: scene.transitionDuration,
    );
  }

  /// Applies a full saved Live Profile snapshot.
  Future<void> applyProfile(LiveProfile profile) async {
    final profileLook = (profile.customLook ?? state.activeLook).copyWith(
      boostBeauty: profile.beauty,
    );

    state = state.copyWith(
      activeProfile: profile,
      activeLook: profileLook,
      beauty: profile.beauty,
    );

    await _compileAndDispatchLook(
      profileLook,
      crossFade: const Duration(milliseconds: 300),
    );
  }

  /// Thermal mitigation trigger from ThermalGovernor.
  Future<void> _onThermalMitigationChanged(ThermalSnapshot snapshot) async {
    debugPrint(
        '[LiveLooksController] Thermal tier changed to ${snapshot.activeMitigationTier}; adjusting realtime look');
    await _compileAndDispatchLook(state.activeLook,
        crossFade: const Duration(milliseconds: 150));
  }

  Future<void> _compileAndDispatchLook(OneovaLook look, {Duration? crossFade}) async {
    if (_processor == null || !_processor!.isAttached) {
      return;
    }

    state = state.copyWith(isCompiling: true);

    try {
      final budget = LookRealtimeBudget.fromRemoteConfig();
      final thermalSnap = ref.read(thermalGovernorProvider).currentSnapshot;

      // Restrict LUT size based on thermal mitigation tier
      int effectiveLutSize = budget.maxLutSize;
      if (thermalSnap.activeMitigationTier >= 2) {
        effectiveLutSize = 17; // Reduce LUT edge for lower texture bandwidth
      }

      final compiled = await LookCompiler.compile(
        look,
        maxLutSize: effectiveLutSize,
      );

      final native = compiled.toNative();
      final fade = crossFade ?? Duration(milliseconds: budget.crossFadeMs);

      await _processor!.setLook(native, crossFade: fade);
      state = state.copyWith(isCompiling: false, lastError: null);
    } catch (e) {
      debugPrint('[LiveLooksController] Error compiling/dispatching look: $e');
      state = state.copyWith(isCompiling: false, lastError: e.toString());
    }
  }

  void _startStatsTimer() {
    _stopStatsTimer();
    _statsTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_processor != null && _processor!.isAttached) {
        try {
          final stats = await _processor!.stats();
          state = state.copyWith(latestStats: stats);
        } catch (_) {}
      }
    });
  }

  void _stopStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }
}

/// Provider for LiveLooksController.
final liveLooksControllerProvider =
    NotifierProvider<LiveLooksController, LiveLooksState>(LiveLooksController.new);

/// Stream of latest LookProcessorStats (FPS, graded frames, GPU frame time).
final liveLookStatsProvider = Provider<LookProcessorStats?>((ref) {
  return ref.watch(liveLooksControllerProvider).latestStats;
});
