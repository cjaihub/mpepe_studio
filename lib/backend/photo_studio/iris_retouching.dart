import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// The precise photometric controls available for an isolated Iris mask.
class IrisRetouchParameters {
  final double color; // Hue shift
  final double tint;
  final double saturation;
  final double brightness;
  final double contrast;
  final double detail; // Micro-contrast / texture enhancement
  final double catchlight; // Specular highlight enhancement

  const IrisRetouchParameters({
    this.color = 0.0,
    this.tint = 0.0,
    this.saturation = 0.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.detail = 0.0,
    this.catchlight = 0.0,
  });
}

/// Specialized subsystem for Iris detection and non-destructive retouching.
class IrisRetouchingEngine {
  
  /// Identifies and extracts the Left and Right Iris masks from the active graph.
  static List<UniversalMask> selectIris(MaskGraph eyeGraph) {
    // Traverse the eye graph and locate nodes tagged as MaskType.IRIS
    final List<UniversalMask> irises = [];
    
    for (final node in eyeGraph.nodes.values) {
      if (node.maskType == MaskType.IRIS) {
        irises.add(node);
      }
    }
    
    // Will return Left Iris and Right Iris if both are present in the graph.
    return irises;
  }

  /// Evaluates an iris modification.
  /// REQUIREMENT: Never replace the iris unless the user explicitly selects an AI generation operation.
  /// REQUIREMENT: Preserve natural texture.
  static bool validateIrisModification(bool isGenerativeReplacement) {
    if (isGenerativeReplacement) {
      debugPrint("IRIS ENGINE ERROR: Attempted to replace Iris with generated pixels. Blocked to preserve natural texture. Generative changes require explicit user authorization.");
      return false;
    }
    return true; // Parametric/Photometric changes preserve the original texture
  }

  /// Generates the shader/adjustment payload for the Before/After comparison.
  /// Returns a rendering struct that the UI can use for a slider or split-screen.
  static Map<String, dynamic> generateBeforeAfterPreview({
    required UniversalMask targetIrisMask,
    required IrisRetouchParameters appliedParams,
  }) {
    // 1. Original (Before): The exact pixels extracted via targetIrisMask geometry.
    // 2. Retouched (After): The original pixels run through the photometric shader
    //    mapping hue(color), tint, saturation, brightness, contrast, detail, catchlight.
    
    return {
      'maskId': targetIrisMask.id,
      'original_state': 'unaltered_buffer_reference',
      'retouched_state': 'shader_buffer_reference',
      'parameters_applied': {
        'hue': appliedParams.color,
        'tint': appliedParams.tint,
        'saturation': appliedParams.saturation,
        'brightness': appliedParams.brightness,
        'contrast': appliedParams.contrast,
        'detail': appliedParams.detail,
        'catchlight': appliedParams.catchlight,
      }
    };
  }
}
