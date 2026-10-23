import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Professional Photometric Controls for Teeth Retouching.
class TeethRetouchParameters {
  final double whitening; // Desaturation of warm tones
  final double brightness;
  final double neutralizeYellow; // Specific hue targeting
  final double contrast;
  final double localClarity; // Micro-contrast enhancement

  /// Default behavior must be subtle to prevent the "fake glowing teeth" look.
  const TeethRetouchParameters({
    this.whitening = 0.1, // 10%
    this.brightness = 0.05, // 5%
    this.neutralizeYellow = 0.15, // 15%
    this.contrast = 0.0,
    this.localClarity = 0.05, // 5%
  });
  
  /// Provides the UI with the mathematically safe intensity bounds 
  /// before clipping or glowing occurs.
  static Map<String, Map<String, double>> getSafeIntensityRanges() {
    return {
      'whitening': {'min': 0.0, 'max': 0.4, 'warning_threshold': 0.5},
      'brightness': {'min': -0.2, 'max': 0.3, 'warning_threshold': 0.4},
      'neutralizeYellow': {'min': 0.0, 'max': 0.6, 'warning_threshold': 0.7},
      'contrast': {'min': -0.1, 'max': 0.2, 'warning_threshold': 0.3},
      'localClarity': {'min': 0.0, 'max': 0.3, 'warning_threshold': 0.4},
    };
  }
}

/// Advanced subsystem for precise teeth isolation and color correction.
class TeethRetouchingEngine {
  
  /// Compiles a precise Teeth mask that mathematically excludes lips and gums.
  /// REQUIREMENT: Detect teeth region independently from lips and mouth.
  /// REQUIREMENT: Prevent changes to lips and gums.
  static MaskGraph compileTeethMask({
    required MaskGraph faceGraph,
    required String identityTrackingId,
  }) {
    final Map<String, UniversalMask> compiledNodes = {};
    final List<String> rootIds = [];
    
    UniversalMask? baseTeethNode;
    final List<UniversalMask> exclusionNodes = [];

    // Traverse the identity's facial graph
    for (final node in faceGraph.nodes.values) {
      if (node.trackingReference != identityTrackingId) continue;
      
      if (node.maskType == MaskType.TEETH) {
        baseTeethNode = node;
      } else if (node.maskType == MaskType.LIPS || node.maskType == MaskType.MOUTH) {
        // Mouth cavity (inner_mouth) often contains gums. 
        // We explicitly force an exclusion operation to protect them.
        exclusionNodes.add(node.copyWith(operation: MaskOperation.exclude));
      }
    }

    if (baseTeethNode == null) {
      throw Exception("TEETH ENGINE ERROR: No teeth geometry detected for identity \$identityTrackingId.");
    }

    // Build the isolated computation subgraph
    final String rootId = '\${identityTrackingId}_TEETH_COMPOSITE';
    final List<String> childIds = [];

    // Add Base Teeth (Add)
    final baseId = '\${baseTeethNode.id}_base';
    compiledNodes[baseId] = baseTeethNode.copyWith(
      id: baseId, 
      parentMaskId: rootId, 
      operation: MaskOperation.add,
    );
    childIds.add(baseId);

    // Add Protections (Exclude)
    for (var exclusion in exclusionNodes) {
      final exId = '\${exclusion.id}_protect';
      compiledNodes[exId] = exclusion.copyWith(
        id: exId, 
        parentMaskId: rootId, 
        operation: MaskOperation.exclude, // Mathematically chops off bleed
      );
      childIds.add(exId);
    }

    // Root Composite Node
    compiledNodes[rootId] = UniversalMask(
      id: rootId,
      projectId: 'compile_memory',
      mediaId: 'compile_memory',
      maskType: MaskType.TEETH,
      sourceType: MaskSourceType.ai,
      childrenIds: childIds,
      trackingReference: identityTrackingId,
      createdBy: 'teeth_retouching_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    rootIds.add(rootId);

    return MaskGraph(
      id: 'TEETH_GRAPH_\$identityTrackingId',
      nodes: compiledNodes,
      rootNodeIds: rootIds,
    );
  }

  /// Validates applied parameters against the safe intensity range to prevent glowing/clipping.
  static bool validateTeethSafety(TeethRetouchParameters params) {
    final ranges = TeethRetouchParameters.getSafeIntensityRanges();
    
    if (params.brightness > ranges['brightness']!['warning_threshold']! || 
        params.whitening > ranges['whitening']!['warning_threshold']!) {
      
      debugPrint("TEETH ENGINE WARNING: Parameter combination risks pure-white clipping and glowing teeth.");
      // The engine can return false to physically block the slider, 
      // or the UI can use this to show a warning state.
      return false;
    }
    
    return true;
  }
}
