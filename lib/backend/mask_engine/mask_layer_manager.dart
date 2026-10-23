import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'universal_mask_models.dart';

/// Represents the visual representation and state of a Mask within the UI layer stack.
class MaskLayer {
  final String id;
  final String name;
  final Color colorLabel;
  final UniversalMask? activeMask;
  final ColorGradingPayload grading;
  final bool isVisible;
  final bool isLocked;

  const MaskLayer({
    required this.id,
    required this.name,
    this.colorLabel = const Color(0xFF990000),
    this.activeMask,
    this.grading = const ColorGradingPayload(),
    this.isVisible = true,
    this.isLocked = false,
  });

  MaskLayer copyWith({
    String? id,
    String? name,
    Color? colorLabel,
    UniversalMask? activeMask,
    ColorGradingPayload? grading,
    bool? isVisible,
    bool? isLocked,
  }) {
    return MaskLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      colorLabel: colorLabel ?? this.colorLabel,
      activeMask: activeMask ?? this.activeMask,
      grading: grading ?? this.grading,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

enum MaskDisplayMode {
  normal,
  overlay,
  maskOnly,
  edge,
  matting,
  checkerboard,
  beforeAfter,
}

/// Central manager orchestrating the stack of MaskLayers for the UI and render engine.
class MaskLayerManager extends ChangeNotifier {
  List<MaskLayer> layers = [];
  String? activeLayerId;
  MaskDisplayMode displayMode = MaskDisplayMode.overlay;

  void setDisplayMode(MaskDisplayMode mode) {
    if (displayMode != mode) {
      displayMode = mode;
      notifyListeners();
    }
  }

  void addLayer(MaskLayer layer) {
    layers.add(layer);
    activeLayerId = layer.id; // Auto-select new layer
    notifyListeners();
  }

  void selectLayer(String layerId) {
    if (activeLayerId != layerId) {
      activeLayerId = layerId;
      notifyListeners();
    }
  }

  void toggleLayerVisibility(String layerId) {
    final index = layers.indexWhere((l) => l.id == layerId);
    if (index != -1) {
      layers[index] = layers[index].copyWith(isVisible: !layers[index].isVisible);
      notifyListeners();
    }
  }

  void toggleLayerLock(String layerId) {
    final index = layers.indexWhere((l) => l.id == layerId);
    if (index != -1) {
      layers[index] = layers[index].copyWith(isLocked: !layers[index].isLocked);
      notifyListeners();
    }
  }

  void updateLayerGrading(String layerId, ColorGradingPayload grading) {
    final index = layers.indexWhere((l) => l.id == layerId);
    if (index != -1) {
      layers[index] = layers[index].copyWith(grading: grading);
      notifyListeners();
    }
  }

  void rehydrateState(List<dynamic> serializedState) {
    // In production, maps the snapshot layer states back to living objects
    // ... logic
    notifyListeners();
  }
}
