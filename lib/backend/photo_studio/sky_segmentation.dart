import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Semantic contextual tags for the detected sky region.
enum SkyCondition {
  clearSky,
  clouds,
  sunset,
  night,
  complexSkyline,
  treesAgainstSky, // High-frequency edge boundary
  buildingsAgainstSky, // Geometric/hard edge boundary
}

/// Parameters for Photometric Sky Enhancement and Generative Replacement.
class SkyRetouchParameters {
  final double exposure;
  final double temperature; // White balance shift (sunset boosting, etc.)
  final double gradient; // Vertical luminance masking (e.g., darker at the top)
  final double color; // Hue shift
  final double cloudContrast; // Micro-contrast specifically targeting cloud formations
  final double dehaze; // Atmospheric haze reduction
  
  /// Fully replaces the sky using a generative model or stock composite.
  /// DANGER: Destructive geometric change.
  final bool replaceSky;

  const SkyRetouchParameters({
    this.exposure = 0.0,
    this.temperature = 0.0,
    this.gradient = 0.0,
    this.color = 0.0,
    this.cloudContrast = 0.0,
    this.dehaze = 0.0,
    this.replaceSky = false, // Must remain false by default
  });
}

/// Advanced subsystem for Sky isolation, atmospheric enhancement, and automatic edge refinement.
class SkySegmentationEngine {
  
  /// Compiles the sky mask with automatic edge refinement to protect complex boundaries.
  static MaskGraph compileSkyMask({
    required MaskGraph globalGraph,
    required SkyRetouchParameters parameters,
  }) {
    final Map<String, UniversalMask> compiledNodes = {};
    final List<String> rootIds = [];

    // Find the primary Sky node
    UniversalMask? skyNode;
    
    for (final node in globalGraph.nodes.values) {
      if (node.maskType == MaskType.SKY) {
        skyNode = node;
        break;
      }
    }

    if (skyNode == null) {
      debugPrint("SKY ENGINE: No sky geometry detected in the current image graph.");
      return MaskGraph(id: 'EMPTY', nodes: {}, rootNodeIds: []);
    }

    final String rootId = 'SKY_COMPOSITE_\${DateTime.now().millisecondsSinceEpoch}';

    // REQUIREMENT: Refine edges automatically.
    // Keep branches, antennae, hair-like structures, building edges separate.
    // We force edge parameters onto the mask to instruct the renderer to run sub-pixel matting.
    final refinedSky = skyNode.copyWith(
      id: '\${skyNode.id}_refined',
      parentMaskId: rootId,
      operation: MaskOperation.add,
      parameters: {
        ...skyNode.parameters,
        'autoEdgeRefinement': true,
        'preserveHighFrequencyEdges': true, // Protects branches, antennae, hair
        'preserveGeometricEdges': true, // Protects building skylines
      }
    );

    compiledNodes[refinedSky.id] = refinedSky;
    
    compiledNodes[rootId] = UniversalMask(
      id: rootId,
      projectId: 'compile_memory',
      mediaId: 'compile_memory',
      maskType: MaskType.SKY,
      sourceType: MaskSourceType.ai,
      childrenIds: [refinedSky.id],
      createdBy: 'sky_segmentation_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    rootIds.add(rootId);

    return MaskGraph(
      id: 'SKY_GRAPH_\${DateTime.now().millisecondsSinceEpoch}',
      nodes: compiledNodes,
      rootNodeIds: rootIds,
    );
  }

  /// Safety verification to prevent unauthorized AI sky replacement.
  /// REQUIREMENT: Never replace sky automatically.
  static bool validateGenerativeSafety(SkyRetouchParameters params, bool explicitReplacementAuthorization) {
    if (params.replaceSky && !explicitReplacementAuthorization) {
      debugPrint("SKY ENGINE ERROR: Blocked an automatic sky replacement.");
      debugPrint("Generative replacement requires explicit user AI action. Automatic actions are restricted to photometric adjustments (exposure, dehaze, etc).");
      return false;
    }
    return true; // Photometric enhancements (exposure, temperature) are always safe.
  }
}
