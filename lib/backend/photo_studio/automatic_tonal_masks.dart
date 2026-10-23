import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../mask_engine/universal_mask_models.dart';
import 'mask_layer_manager.dart';

/// Pre-configured identifiers for the automatic tonal templates
enum TonalMaskTarget {
  faceLight,
  subjectLight,
  backgroundLight,
  rimLight,
  skinTone,
  highlightProtection,
  shadowProtection,
}

/// Advanced subsystem capable of auto-generating complex photometric masks.
class AutomaticTonalMaskEngine {
  
  /// Generates complex, multi-variable procedural masks automatically based on 
  /// the active semantic elements in the image.
  /// 
  /// REQUIREMENT: Do not merely blur the image.
  /// REQUIREMENT: Generate actual masks and apply editable adjustments.
  static MaskLayer generateTonalMask({
    required TonalMaskTarget target,
    required String sourceMediaId,
    // Provide references to the baseline semantic IDs to construct boolean intersections
    String? baseFaceMaskId, 
    String? baseSubjectMaskId,
    String? baseBackgroundMaskId,
  }) {
    
    debugPrint("TONAL ENGINE: Generating automated procedural mask for \${target.name}");

    final String generatedId = 'TONAL_\${target.name.toUpperCase()}_\${DateTime.now().millisecondsSinceEpoch}';
    
    // We construct these masks using non-destructive Boolean logic (INTERSECT).
    // This physically isolates the exact pixels instead of just applying a global blurred blend mode.
    Map<String, dynamic> proceduralParameters = {};
    ColorGradingPayload defaultGrading = const ColorGradingPayload();
    String displayName = '';
    Color layerColor = const Color(0xFFFFFFFF);

    switch (target) {
      case TonalMaskTarget.faceLight:
        displayName = 'Face Light';
        layerColor = const Color(0xFFFFD54F); // Amber
        // Intersection of Face Semantic Mask + High Luminance Range
        proceduralParameters = {
          'base_semantic_id': baseFaceMaskId,
          'boolean_operation': 'intersect',
          'procedural_target': 'luminance_range',
          'luminance_min': 0.6,
          'luminance_max': 1.0,
        };
        // Auto-grade: slightly lift exposure and warmth
        defaultGrading = const ColorGradingPayload(exposure: 0.15, temperature: 0.10);
        break;

      case TonalMaskTarget.subjectLight:
        displayName = 'Subject Light';
        layerColor = const Color(0xFF64B5F6); // Blue
        proceduralParameters = {
          'base_semantic_id': baseSubjectMaskId,
          'boolean_operation': 'intersect',
          'procedural_target': 'luminance_range',
          'luminance_min': 0.4,
          'luminance_max': 1.0,
        };
        defaultGrading = const ColorGradingPayload(exposure: 0.20, contrast: 0.10);
        break;

      case TonalMaskTarget.backgroundLight:
        displayName = 'Background Light';
        layerColor = const Color(0xFF81C784); // Green
        proceduralParameters = {
          'base_semantic_id': baseBackgroundMaskId,
          'boolean_operation': 'intersect',
          'procedural_target': 'luminance_range',
          'luminance_min': 0.0,
          'luminance_max': 0.8,
        };
        defaultGrading = const ColorGradingPayload(exposure: -0.15);
        break;

      case TonalMaskTarget.rimLight:
        displayName = 'Rim Light';
        layerColor = const Color(0xFFBA68C8); // Purple
        // Advanced calculation: Subject mask edge boundary intersected with maximum highlights
        proceduralParameters = {
          'base_semantic_id': baseSubjectMaskId,
          'boolean_operation': 'intersect',
          'procedural_target': 'edge_boundary',
          'edge_thickness': 4.0,
          'secondary_intersect': 'luminance_range',
          'luminance_min': 0.85,
          'luminance_max': 1.0,
        };
        defaultGrading = const ColorGradingPayload(highlights: 0.30, exposure: 0.20);
        break;

      case TonalMaskTarget.skinTone:
        displayName = 'Skin Tone';
        layerColor = const Color(0xFFFF8A65); // Peach
        // Intersection of Face/Body mask + Color Range targeting human skin hues
        proceduralParameters = {
          'base_semantic_id': baseSubjectMaskId,
          'boolean_operation': 'intersect',
          'procedural_target': 'color_range',
          'target_hue_center': 30.0, // Approximating base skin tone hue
          'hue_tolerance': 20.0,
        };
        defaultGrading = const ColorGradingPayload(saturation: 0.10, contrast: 0.05);
        break;

      case TonalMaskTarget.highlightProtection:
        displayName = 'Highlight Protection';
        layerColor = const Color(0xFFE0E0E0); // Grey
        proceduralParameters = {
          'procedural_target': 'luminance_range',
          'luminance_min': 0.90, // Extreme highlights
          'luminance_max': 1.0,
          'smooth_falloff': true,
        };
        // Pulls down highlights to protect details from clipping
        defaultGrading = const ColorGradingPayload(highlights: -0.40);
        break;

      case TonalMaskTarget.shadowProtection:
        displayName = 'Shadow Protection';
        layerColor = const Color(0xFF424242); // Dark Grey
        proceduralParameters = {
          'procedural_target': 'luminance_range',
          'luminance_min': 0.0,
          'luminance_max': 0.10, // Extreme shadows
          'smooth_falloff': true,
        };
        // Lifts crushed blacks
        defaultGrading = const ColorGradingPayload(shadows: 0.25);
        break;
    }

    // Build the underlying logical mask
    final actualMask = UniversalMask(
      id: generatedId,
      projectId: 'auto',
      mediaId: sourceMediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.procedural,
      operation: MaskOperation.add,
      parameters: proceduralParameters,
      createdBy: 'automatic_tonal_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Return the editable layer bound to the actual mask
    return MaskLayer(
      id: 'LAYER_\$generatedId',
      name: displayName,
      colorLabel: layerColor,
      trackingReference: 'auto_tonal',
      confidence: 1.0,
      activeMask: actualMask,
      grading: defaultGrading,
    );
  }
}
