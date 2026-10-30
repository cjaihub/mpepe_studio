import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import '../models/ar_effect_package.dart';
import '../services/ar_effect_runtime.dart';

@immutable
class ArEffectState {
  final OneovaEffectPackage? activeEffect;
  final ArCategory activeCategory;
  final List<OneovaEffectPackage> availablePackages;
  final ArRenderState currentRenderState;
  final bool isFaceTracked;
  final bool isHandTracked;
  final String? lastTriggerEvent;
  final bool showLandmarkDebugWireframe;
  final double lipTintOpacity;
  final double blushOpacity;
  final double eyelinerOpacity;
  final double hairHue;

  const ArEffectState({
    this.activeEffect,
    this.activeCategory = ArCategory.trending,
    this.availablePackages = OneovaEffectPackage.starterLenses,
    this.currentRenderState = const ArRenderState(),
    this.isFaceTracked = false,
    this.isHandTracked = false,
    this.lastTriggerEvent,
    this.showLandmarkDebugWireframe = false,
    this.lipTintOpacity = 0.75,
    this.blushOpacity = 0.40,
    this.eyelinerOpacity = 0.90,
    this.hairHue = 330.0, // Brand pink hue
  });

  List<OneovaEffectPackage> get filteredPackages {
    return availablePackages.where((p) => p.category == activeCategory).toList();
  }

  ArEffectState copyWith({
    OneovaEffectPackage? Function()? activeEffect,
    ArCategory? activeCategory,
    List<OneovaEffectPackage>? availablePackages,
    ArRenderState? currentRenderState,
    bool? isFaceTracked,
    bool? isHandTracked,
    String? Function()? lastTriggerEvent,
    bool? showLandmarkDebugWireframe,
    double? lipTintOpacity,
    double? blushOpacity,
    double? eyelinerOpacity,
    double? hairHue,
  }) {
    return ArEffectState(
      activeEffect: activeEffect != null ? activeEffect() : this.activeEffect,
      activeCategory: activeCategory ?? this.activeCategory,
      availablePackages: availablePackages ?? this.availablePackages,
      currentRenderState: currentRenderState ?? this.currentRenderState,
      isFaceTracked: isFaceTracked ?? this.isFaceTracked,
      isHandTracked: isHandTracked ?? this.isHandTracked,
      lastTriggerEvent: lastTriggerEvent != null ? lastTriggerEvent() : this.lastTriggerEvent,
      showLandmarkDebugWireframe: showLandmarkDebugWireframe ?? this.showLandmarkDebugWireframe,
      lipTintOpacity: lipTintOpacity ?? this.lipTintOpacity,
      blushOpacity: blushOpacity ?? this.blushOpacity,
      eyelinerOpacity: eyelinerOpacity ?? this.eyelinerOpacity,
      hairHue: hairHue ?? this.hairHue,
    );
  }
}

/// Runtime service provider.
final arEffectRuntimeProvider = Provider<ArEffectRuntime>((ref) {
  return ArEffectRuntime();
});

/// Riverpod Notifier for AR lenses, tracking, and makeup controls.
class ArEffectController extends Notifier<ArEffectState> {
  late final ArEffectRuntime _runtime;

  @override
  ArEffectState build() {
    _runtime = ref.read(arEffectRuntimeProvider);
    return const ArEffectState();
  }

  void selectCategory(ArCategory category) {
    state = state.copyWith(activeCategory: category);
  }

  void selectEffect(OneovaEffectPackage? effect) {
    _runtime.loadPackage(effect);
    state = state.copyWith(
      activeEffect: () => effect,
      lastTriggerEvent: () => null,
    );
  }

  void clearEffect() {
    selectEffect(null);
  }

  void toggleLandmarkWireframe(bool show) {
    state = state.copyWith(showLandmarkDebugWireframe: show);
  }

  void updateLipstick(double value) {
    state = state.copyWith(lipTintOpacity: value);
    _runtime.setParameter('lipstick_opacity', value);
  }

  void updateBlush(double value) {
    state = state.copyWith(blushOpacity: value);
    _runtime.setParameter('blush_opacity', value);
  }

  void updateEyeliner(double value) {
    state = state.copyWith(eyelinerOpacity: value);
    _runtime.setParameter('eyeliner_opacity', value);
  }

  void updateHairHue(double value) {
    state = state.copyWith(hairHue: value);
    _runtime.setParameter('hair_hue', value);
  }

  void onNewTrackingFrame(TrackingFrame frame) {
    final renderState = _runtime.processFrame(frame);

    String? triggerLabel;
    if (renderState.activeTriggers.isNotEmpty) {
      final firstKey = renderState.activeTriggers.first;
      final triggerType = ArTriggerType.fromKey(firstKey);
      if (triggerType != null) {
        triggerLabel = '${triggerType.label} ${triggerType.emoji}';
      }
    }

    state = state.copyWith(
      currentRenderState: renderState,
      isFaceTracked: frame.hasFace,
      isHandTracked: frame.hasHands,
      lastTriggerEvent: triggerLabel != null ? () => triggerLabel : null,
    );
  }
}

final arEffectControllerProvider =
    NotifierProvider<ArEffectController, ArEffectState>(() {
  return ArEffectController();
});
