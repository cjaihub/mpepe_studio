import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Highly specific anatomical divisions of the mouth area.
enum MouthAnatomy {
  upperLip,
  lowerLip,
  lipContour, // The outer boundary/edge of the lips
  innerMouth, // The oral cavity
}

/// Parameters for Photometric and Generative Mouth Edits.
class MouthRetouchParameters {
  // Photometric Controls (Always safe for identity)
  final double color; // Hue shift (safe tinting)
  final double brightness;
  final double saturation;
  final double contrast;
  final double texture;
  final double sharpness;

  // Generative / Geometric Controls (Alters identity, requires explicit opt-in)
  final bool applyLipMakeup; // AI-driven texture/gloss generation
  final double smileAdjustment; // Geometric morph of the mouth corners

  const MouthRetouchParameters({
    this.color = 0.0,
    this.brightness = 0.0,
    this.saturation = 0.0,
    this.contrast = 0.0,
    this.texture = 0.0,
    this.sharpness = 0.0,
    this.applyLipMakeup = false,
    this.smileAdjustment = 0.0,
  });
}

/// Advanced subsystem for Lips and Mouth editing.
class MouthRetouchingEngine {
  
  /// Extracts specific mouth regions from the identity graph.
  static List<UniversalMask> selectMouthAnatomy({
    required MaskGraph faceGraph,
    required List<MouthAnatomy> targets,
  }) {
    final List<UniversalMask> regions = [];
    
    // In a real implementation, the face_segmentation engine would tag these micro-regions
    // as children of the LIPS and MOUTH nodes.
    for (final node in faceGraph.nodes.values) {
      if (node.maskType == MaskType.LIPS || node.maskType == MaskType.MOUTH) {
        final anatomyString = node.parameters['anatomy'];
        
        if (anatomyString != null) {
          final isMatch = targets.any((t) => t.name == anatomyString);
          if (isMatch) regions.add(node);
        } else {
          // Fallback if micro-parsing isn't available, return the whole lip/mouth
          regions.add(node);
        }
      }
    }
    
    return regions;
  }

  /// Safety verification to prevent accidental destruction of facial identity.
  /// REQUIREMENT: Do not change facial identity automatically.
  /// Generative editing (lip makeup, smile adjustment) is only allowed when explicitly requested.
  static bool validateIdentitySafety(MouthRetouchParameters params, bool isExplicitlyGenerative) {
    if ((params.applyLipMakeup || params.smileAdjustment != 0.0) && !isExplicitlyGenerative) {
      debugPrint("MOUTH ENGINE ERROR: Blocked a generative/geometric mouth edit.");
      debugPrint("Smile adjustments and AI Lip Makeup alter facial identity and require explicit user authorization.");
      return false;
    }
    
    // Standard photometric color/brightness changes are always safe.
    return true;
  }
}
