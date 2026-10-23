import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Semantic parsing categories for clothing and apparel.
enum GarmentType {
  shirt,
  pants,
  dress,
  jacket,
  coat,
  shoes,
  hat,
  accessories,
}

/// Strategy for selecting clothing in the graph.
enum SelectionStrategy {
  singleGarment,         // Target exactly one piece (e.g., the specific jacket tapped)
  garmentCategory,       // Target all instances of a type (e.g., all jackets in the shot)
  colorMatching,         // Target garments matching a specific source color/hue
}

/// Photometric adjustments tailored for fabrics and materials.
class ClothingRetouchParameters {
  final double colorReplacement; // Hue shift specifically for garment dyes
  final double toneCorrection;
  final double texture; // Enhances weave, knit, or leather micro-details
  final double brightness;
  final double contrast;
  final double saturation;
  
  final bool preservePatterns; // Protects plaid, stripes, etc. during color replacement
  final bool alterLogosAndText; // Advanced generative/inpainting operation

  const ClothingRetouchParameters({
    this.colorReplacement = 0.0,
    this.toneCorrection = 0.0,
    this.texture = 0.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.preservePatterns = true, // Default to safely protecting designs
    this.alterLogosAndText = false, // Must remain false by default
  });
}

/// Advanced subsystem for semantic clothing parsing and non-destructive recoloring.
class ClothingSegmentationEngine {
  
  /// Extracts the relevant clothing masks from the graph based on the chosen strategy.
  static List<UniversalMask> selectClothing({
    required MaskGraph globalGraph,
    required SelectionStrategy strategy,
    required List<GarmentType> targets,
    String? targetId, // Required for singleGarment
    double? targetHue, // Required for colorMatching
  }) {
    final List<UniversalMask> garments = [];
    
    for (final node in globalGraph.nodes.values) {
      // Clothing often sits under MaskType.CLOTHING or MaskType.OBJECT for accessories/shoes
      if (node.maskType == MaskType.CLOTHING || node.maskType == MaskType.OBJECT) {
        
        final garmentTypeStr = node.parameters['garmentType'];
        if (garmentTypeStr == null) continue;
        
        final isCategoryMatch = targets.any((t) => t.name == garmentTypeStr);
        
        if (strategy == SelectionStrategy.singleGarment) {
          if (node.id == targetId) garments.add(node);
        } 
        else if (strategy == SelectionStrategy.garmentCategory) {
          if (isCategoryMatch) garments.add(node);
        } 
        else if (strategy == SelectionStrategy.colorMatching) {
          final nodeHue = node.parameters['dominantHue'] as double?;
          // Match hues within a 15-degree tolerance band
          if (nodeHue != null && targetHue != null && (nodeHue - targetHue).abs() <= 15.0) {
            garments.add(node);
          }
        }
      }
    }
    
    return garments;
  }

  /// Safety verification to protect brand IP and textural integrity.
  /// REQUIREMENT: Do not change logos/text unless explicitly requested.
  static bool validateApparelSafety(ClothingRetouchParameters params, bool explicitLogoPermission) {
    if (params.alterLogosAndText && !explicitLogoPermission) {
      debugPrint("CLOTHING ENGINE ERROR: Blocked modification of logos/text.");
      debugPrint("Removing or altering printed text, logos, or IP requires explicit user authorization.");
      return false;
    }
    return true; // Color replacement and tone corrections (with pattern preservation) are safe.
  }
}
