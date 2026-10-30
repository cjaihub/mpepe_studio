import 'package:flutter/foundation.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';
import '../models/ar_effect_package.dart';

/// Computed frame rendering payload for the native GPU Look / AR renderer.
@immutable
class ArRenderState {
  final String? packageId;
  final int activeLayerCount;
  final Set<String> activeTriggers;
  final Map<String, List<double>> anchorTransforms;
  final Map<String, dynamic> makeupParameters;
  final bool hasBodySegmentation;

  const ArRenderState({
    this.packageId,
    this.activeLayerCount = 0,
    this.activeTriggers = const {},
    this.anchorTransforms = const {},
    this.makeupParameters = const {},
    this.hasBodySegmentation = false,
  });
}

/// Runtime engine evaluating AR effect packages on top of real-time MediaPipe tracking frames.
class ArEffectRuntime {
  OneovaEffectPackage? _activePackage;
  final Map<String, dynamic> _runtimeOverrides = {};

  OneovaEffectPackage? get activePackage => _activePackage;

  /// Loads and binds a `.oneovafx` package into the runtime.
  void loadPackage(OneovaEffectPackage? package) {
    _activePackage = package;
    _runtimeOverrides.clear();
    if (package != null) {
      _runtimeOverrides.addAll(package.customParameters);
    }
  }

  /// Sets dynamic parameter overrides (e.g. user adjusted lipstick opacity, blush strength).
  void setParameter(String key, dynamic value) {
    _runtimeOverrides[key] = value;
  }

  /// Evaluates an incoming tracking frame and updates layer transformations and active triggers.
  ArRenderState processFrame(TrackingFrame frame) {
    if (_activePackage == null) {
      return const ArRenderState();
    }

    final activeTriggers = frame.evaluateActiveTriggers();
    final transforms = <String, List<double>>{};
    int visibleCount = 0;

    for (final layer in _activePackage!.layers) {
      // Check trigger conditions
      if (layer.triggerRequired != null && !activeTriggers.contains(layer.triggerRequired)) {
        continue;
      }

      visibleCount++;

      // Compute anchor landmark position
      if (layer.anchorLandmarkIndex != null) {
        final landmark = _resolveAnchorLandmark(frame, layer.anchorLandmarkIndex!);
        if (landmark != null) {
          transforms[layer.id] = [
            landmark.x + layer.offset[0],
            landmark.y + layer.offset[1],
            landmark.z + layer.offset[2],
            layer.scale[0],
            layer.scale[1],
            layer.scale[2],
          ];
        }
      }
    }

    return ArRenderState(
      packageId: _activePackage!.id,
      activeLayerCount: visibleCount,
      activeTriggers: activeTriggers,
      anchorTransforms: transforms,
      makeupParameters: Map<String, dynamic>.unmodifiable(_runtimeOverrides),
      hasBodySegmentation: frame.hasBodySegmentation,
    );
  }

  Landmark3D? _resolveAnchorLandmark(TrackingFrame frame, int index) {
    // Check face mesh points (index < 478)
    if (frame.faces.isNotEmpty) {
      final face = frame.faces.first;
      if (index < face.points.length) {
        return face.points[index];
      }
    }

    // Check hand landmarks (index < 21)
    if (frame.hands.isNotEmpty) {
      final hand = frame.hands.first;
      if (index < hand.points.length) {
        return hand.points[index];
      }
    }

    return null;
  }
}
