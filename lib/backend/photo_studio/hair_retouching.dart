import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Semantic divisions of hair.
enum HairRegion {
  headHair,
  facialHair,
  flyawayHair, // Stray hairs extending beyond the main geometry
  hairline,
}

/// Parameters specifically tuned for hair stylization and preservation.
class HairRetouchParameters {
  // Color and Light adjustments
  final double colorGrade; // Overall color balance/tint
  final double changeHairColor; // Target dye shift
  final double increaseShine; // Specular highlight targeting
  final double reduceHighlights; // Blowout recovery
  final double darkenRoots; // Spatial gradient at the root base
  final double enhanceTexture; // Micro-contrast for hair strands
  
  // Edge and Geometry Protections
  final bool protectTransparency; // Prevents clipping the alpha channel on semi-transparent hairs
  final bool preserveWispyEdges; // Prevents hard boolean cutoffs
  final double edgeRefinementRadius; // Controls the sub-pixel edge search area

  const HairRetouchParameters({
    this.colorGrade = 0.0,
    this.changeHairColor = 0.0,
    this.increaseShine = 0.0,
    this.reduceHighlights = 0.0,
    this.darkenRoots = 0.0,
    this.enhanceTexture = 0.0,
    this.protectTransparency = true, // Default to preserving natural edges
    this.preserveWispyEdges = true,
    this.edgeRefinementRadius = 1.0,
  });
}

/// Advanced subsystem for precise hair masking, coloring, and edge preservation.
class HairRetouchingEngine {
  
  /// Compiles a professional hair mask that protects fine edges and automatically separates backgrounds.
  /// Operations: select hair -> subtract face -> background separation.
  static MaskGraph compileHairMask({
    required MaskGraph globalGraph,
    required String identityTrackingId,
    required HairRetouchParameters parameters,
  }) {
    final Map<String, UniversalMask> compiledNodes = {};
    final List<String> rootIds = [];
    final List<String> childIds = [];

    List<UniversalMask> hairNodes = [];
    List<UniversalMask> exclusionNodes = [];

    // 1. Traverse Graph to collect targets and exclusions
    for (final node in globalGraph.nodes.values) {
      if (node.trackingReference != identityTrackingId) continue;

      if (node.maskType == MaskType.HAIR) {
        // Collect head hair, facial hair, flyaways, hairline
        hairNodes.add(node);
      } 
      // Subtract Face constraint
      else if (node.maskType == MaskType.FACE || node.maskType == MaskType.SKIN) {
        exclusionNodes.add(node.copyWith(operation: MaskOperation.exclude));
      } 
      // Background separation constraint
      else if (node.maskType == MaskType.BACKGROUND || node.maskType == MaskType.SKY) {
        exclusionNodes.add(node.copyWith(operation: MaskOperation.exclude));
      }
    }

    if (hairNodes.isEmpty) {
      debugPrint("HAIR ENGINE: No hair geometry detected for identity \$identityTrackingId");
      return MaskGraph(id: 'EMPTY', nodes: {}, rootNodeIds: []);
    }

    final String rootId = '\${identityTrackingId}_HAIR_COMPOSITE';

    // 2. Add base hair geometry
    for (var hair in hairNodes) {
      final id = '\${hair.id}_base';
      
      // REQUIREMENT: Hair edges must preserve fine strands, semi-transparent regions, wispy edges.
      // Do not produce a crude hard rectangle around hair.
      // We apply Edge Refinement natively to the mask.
      final refinedHair = hair.copyWith(
        id: id,
        parentMaskId: rootId,
        operation: MaskOperation.add,
        parameters: {
          ...hair.parameters,
          'protectTransparency': parameters.protectTransparency,
          'preserveWispyEdges': parameters.preserveWispyEdges,
          'edgeRefinementRadius': parameters.edgeRefinementRadius,
        },
      );
      
      compiledNodes[id] = refinedHair;
      childIds.add(id);
    }

    // 3. Add Exclusions (Subtract Face & Background)
    for (var exclusion in exclusionNodes) {
      final exId = '\${exclusion.id}_protect';
      compiledNodes[exId] = exclusion.copyWith(
        id: exId,
        parentMaskId: rootId,
        operation: MaskOperation.exclude,
      );
      childIds.add(exId);
    }

    // 4. Construct Composite Root
    compiledNodes[rootId] = UniversalMask(
      id: rootId,
      projectId: 'compile_memory',
      mediaId: 'compile_memory',
      maskType: MaskType.HAIR,
      sourceType: MaskSourceType.ai,
      childrenIds: childIds,
      trackingReference: identityTrackingId,
      createdBy: 'hair_retouching_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    rootIds.add(rootId);

    return MaskGraph(
      id: 'HAIR_GRAPH_\$identityTrackingId',
      nodes: compiledNodes,
      rootNodeIds: rootIds,
    );
  }
}
