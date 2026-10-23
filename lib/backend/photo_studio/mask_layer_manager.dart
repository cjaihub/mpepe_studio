import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../mask_engine/universal_mask_models.dart';



/// A top-level UI and Logic abstraction representing a standalone trackable mask.
/// REQUIREMENT: Each has color label, ID, track, confidence, keyframes.
class MaskLayer {
  final String id;
  final String name;                 // e.g. "Person 1", "Sky", "Car"
  final Color colorLabel;            // UI bounding box and overlay color
  final String trackingReference;    // The 'track' identity linking frames
  final double confidence;
  final List<double> keyframes;      // Array of video timestamps where manual corrections occurred

  /// The active mathematical UniversalMask pointing to the MaskGraph.
  final UniversalMask? activeMask;
  
  /// REQUIREMENT: Users can individually grade Person 1 without affecting the rest.
  final ColorGradingPayload grading;

  const MaskLayer({
    required this.id,
    required this.name,
    required this.colorLabel,
    required this.trackingReference,
    required this.confidence,
    this.keyframes = const [],
    this.activeMask,
    this.grading = const ColorGradingPayload(),
  });

  MaskLayer copyWith({
    String? id,
    String? name,
    Color? colorLabel,
    String? trackingReference,
    double? confidence,
    List<double>? keyframes,
    UniversalMask? activeMask,
    ColorGradingPayload? grading,
  }) {
    return MaskLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      colorLabel: colorLabel ?? this.colorLabel,
      trackingReference: trackingReference ?? this.trackingReference,
      confidence: confidence ?? this.confidence,
      keyframes: keyframes ?? this.keyframes,
      activeMask: activeMask ?? this.activeMask,
      grading: grading ?? this.grading,
    );
  }
}

/// Manages multiple, parallel semantic masks simultaneously.
class MaskLayerManager extends ChangeNotifier {
  final List<MaskLayer> _layers = [];

  List<MaskLayer> get layers => List.unmodifiable(_layers);

  /// Registers a new independent layer (e.g., Person 2) into the project.
  void addLayer(MaskLayer layer) {
    _layers.add(layer);
    notifyListeners();
  }

  /// Updates the grading exclusively for one layer, isolating it from the background/other subjects.
  void updateLayerGrading(String layerId, ColorGradingPayload newGrading) {
    final index = _layers.indexWhere((l) => l.id == layerId);
    if (index != -1) {
      _layers[index] = _layers[index].copyWith(grading: newGrading);
      // Because grading is independent, tweaking Person 1 does not affect the Car or Sky layers.
      notifyListeners();
    }
  }

  /// Appends a newly corrected frame to the layer's keyframe timeline.
  void registerKeyframe(String layerId, double timestamp) {
    final index = _layers.indexWhere((l) => l.id == layerId);
    if (index != -1) {
      final currentKeyframes = List<double>.from(_layers[index].keyframes);
      if (!currentKeyframes.contains(timestamp)) {
        currentKeyframes.add(timestamp);
        currentKeyframes.sort(); // Maintain chronological order
        _layers[index] = _layers[index].copyWith(keyframes: currentKeyframes);
        notifyListeners();
      }
    }
  }
}
