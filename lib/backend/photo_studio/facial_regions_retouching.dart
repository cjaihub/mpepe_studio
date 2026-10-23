import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Highly targeted semantic facial regions for local adjustments.
enum SemanticFacialRegion {
  nose,
  ears,
  mustache,
  beard,
  sideburns,
}

/// Professional Photometric Controls for targeted semantic regions.
class FacialRegionRetouchParameters {
  final double tone; // Exposure / Contrast balancing
  final double sharpness;
  final double color; // Hue shift / Saturation
  final double texture; // Micro-contrast preservation or smoothing
  final double lighting; // Localized dodging and burning
  
  /// Geometric reshaping (e.g. thinning the nose, pinning ears back).
  /// DANGER: Drastically alters facial identity.
  final bool reshapeGeometry;

  const FacialRegionRetouchParameters({
    this.tone = 0.0,
    this.sharpness = 0.0,
    this.color = 0.0,
    this.texture = 0.0,
    this.lighting = 0.0,
    this.reshapeGeometry = false,
  });
}

/// Advanced subsystem for precise semantic facial regions (Nose, Ears, Facial Hair).
class FacialRegionsRetouchingEngine {
  
  /// Extracts the specific semantic regions from the identity graph.
  static List<UniversalMask> selectSemanticRegions({
    required MaskGraph faceGraph,
    required List<SemanticFacialRegion> targets,
  }) {
    final List<UniversalMask> regions = [];
    
    for (final node in faceGraph.nodes.values) {
      if (node.maskType == MaskType.NOSE && targets.contains(SemanticFacialRegion.nose)) {
        regions.add(node);
      } 
      else if (node.maskType == MaskType.EARS && targets.contains(SemanticFacialRegion.ears)) {
        regions.add(node);
      } 
      // Facial hair is technically tracked under HAIR but with specific parameters
      else if (node.maskType == MaskType.HAIR && node.parameters['feature'] == 'facialHair') {
        final subType = node.parameters['facialHairType']; // 'mustache', 'beard', 'sideburns'
        
        if (subType == 'mustache' && targets.contains(SemanticFacialRegion.mustache)) {
          regions.add(node);
        } else if (subType == 'beard' && targets.contains(SemanticFacialRegion.beard)) {
          regions.add(node);
        } else if (subType == 'sideburns' && targets.contains(SemanticFacialRegion.sideburns)) {
          regions.add(node);
        } else if (subType == null && (targets.contains(SemanticFacialRegion.mustache) || 
                                       targets.contains(SemanticFacialRegion.beard) || 
                                       targets.contains(SemanticFacialRegion.sideburns))) {
          // Fallback if the facial hair isn't micro-segmented
          regions.add(node);
        }
      }
    }
    
    return regions;
  }

  /// Safety verification to prevent accidental destruction of facial geometry.
  /// REQUIREMENT: Do not automatically reshape geometry.
  /// REQUIREMENT: Geometry tools must require a separate explicit action.
  static bool validateGeometrySafety(FacialRegionRetouchParameters params, bool hasExplicitGeometryAction) {
    if (params.reshapeGeometry && !hasExplicitGeometryAction) {
      debugPrint("FACIAL REGION ENGINE ERROR: Blocked a geometric reshape operation.");
      debugPrint("Reshaping geometry (e.g., thinning nose, pinning ears) requires a separate, explicit user action and cannot be triggered automatically via presets.");
      return false;
    }
    
    // Photometric changes (tone, color, texture, lighting) are always safe.
    return true;
  }
}
