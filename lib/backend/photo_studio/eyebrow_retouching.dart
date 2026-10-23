import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Target selection for eyebrow edits.
enum EyebrowSelection {
  left,
  right,
  both,
}

/// Professional Eyebrow Retouching Parameters.
class EyebrowRetouchParameters {
  final double darkenLighten; // Negative to darken, Positive to lighten (Exposure shift)
  final double color; // Hue shift / tinting
  final double contrast;
  final double sharpness; // Definition and micro-contrast
  
  /// Applies a high-frequency separation / AI in-painting to clean up stray hairs 
  /// outside the primary shape boundary.
  final bool cleanupStrays; 
  
  /// Shape-aware edit allows for structural changes (arch lifting, thinning, thickening).
  /// DANGER: Alters geometry and can change facial identity.
  final bool shapeAwareEdit; 

  const EyebrowRetouchParameters({
    this.darkenLighten = 0.0,
    this.color = 0.0,
    this.contrast = 0.0,
    this.sharpness = 0.0,
    this.cleanupStrays = false,
    this.shapeAwareEdit = false,
  });
}

/// Subsystem for precise eyebrow isolation and retouching.
class EyebrowRetouchingEngine {
  
  /// Extracts the required eyebrow masks (Left, Right, or Both) from the identity graph.
  static List<UniversalMask> selectEyebrows({
    required MaskGraph eyeGraph, 
    required EyebrowSelection selection,
  }) {
    final List<UniversalMask> eyebrows = [];
    
    for (final node in eyeGraph.nodes.values) {
      if (node.maskType == MaskType.EYEBROWS) {
        final side = node.parameters['side']; // 'left' or 'right'
        
        if (selection == EyebrowSelection.both) {
          eyebrows.add(node);
        } else if (selection == EyebrowSelection.left && side == 'left') {
          eyebrows.add(node);
        } else if (selection == EyebrowSelection.right && side == 'right') {
          eyebrows.add(node);
        }
      }
    }
    
    return eyebrows;
  }

  /// Verifies if an eyebrow operation is safe for facial identity.
  /// REQUIREMENT: Avoid changing facial identity by default.
  static bool validateIdentitySafety(EyebrowRetouchParameters params, bool isExplicitlyGeometric) {
    // Photometric edits (darken, lighten, color, contrast, sharpness, and stray cleanup) 
    // do not structurally alter the face, so they are always safe.
    
    // Shape-aware edits physically move landmarks (arch, thickness).
    if (params.shapeAwareEdit && !isExplicitlyGeometric) {
      debugPrint("EYEBROW ENGINE ERROR: Blocked a shape-aware edit. Eyebrow shape changes drastically alter facial identity and require explicit user opt-in.");
      return false;
    }
    return true;
  }
}
