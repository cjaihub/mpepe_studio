import 'package:flutter/foundation.dart';
import 'universal_mask_models.dart';

/// Interprets compound semantic constraints and orchestrates them into
/// non-destructive Boolean Intersection Nodes in the Mask Graph.
/// 
/// Solves workflows like:
/// - "Brighten only the person in the foreground" (Person ∩ Near depth)
/// - "Blur the background but preserve the nearby object" (Background ∩ Far depth)
class IntersectionOrchestrator {
  final MaskGraph activeGraph;

  IntersectionOrchestrator({required this.activeGraph});

  /// REQUIREMENT: "Allow: Person ∩ Near depth"
  /// REQUIREMENT: "Depth and semantic masks must remain separate nodes."
  Future<String> buildCompoundIntersection({
    required String mediaId,
    required String semanticTarget, // e.g., 'person'
    required String modifierTarget, // e.g., 'near_depth', 'highlight'
    required String intentName, // e.g., 'Person in foreground'
  }) async {
    debugPrint("INTERSECTION ORCHESTRATOR: Constructing compound graph for '\$intentName'...");

    // 1. Create the isolated Semantic Node
    // This node calculates ONLY the semantic outline (e.g., the Person)
    final _ = 'NODE_SEMANTIC_\${DateTime.now().millisecondsSinceEpoch}';
    final semanticMask = UniversalMask(
      id: 'MASK_\$semanticNodeId',
      projectId: 'auto',
      mediaId: mediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.ai, // Output of SAM / Semantic model
      operation: MaskOperation.add,
      parameters: {'semantic_target': semanticTarget},
      createdBy: 'orchestrator',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    activeGraph.addNode(semanticMask);
    debugPrint("INTERSECTION ORCHESTRATOR: Added independent Semantic Node: \$semanticTarget");

    // 2. Create the isolated Modifier Node (Depth or Luminance)
    // This node calculates ONLY the mathematical gradient (e.g., Z-Depth or Luma)
    final _ = 'NODE_MODIFIER_\${DateTime.now().millisecondsSinceEpoch}';
    
    MaskType modifierType = MaskType.CUSTOM;
    Map<String, dynamic> modifierParams = {};
    
    if (modifierTarget == 'near_depth') {
      modifierType = MaskType.DEPTH;
      modifierParams = {'min_depth': 0.0, 'max_depth': 0.3}; // Near plane
    } else if (modifierTarget == 'far_depth') {
      modifierType = MaskType.DEPTH;
      modifierParams = {'min_depth': 0.7, 'max_depth': 1.0}; // Far plane
    } else if (modifierTarget == 'highlight') {
      modifierType = MaskType.LUMINANCE;
      modifierParams = {'min_luma': 0.8, 'max_luma': 1.0}; // Highlights
    }

    final modifierMask = UniversalMask(
      id: 'MASK_\$modifierNodeId',
      projectId: 'auto',
      mediaId: mediaId,
      maskType: modifierType,
      sourceType: MaskSourceType.generated, // Output of MiDaS or Luma engine
      operation: MaskOperation.add,
      parameters: modifierParams,
      createdBy: 'orchestrator',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    activeGraph.addNode(modifierMask);
    debugPrint("INTERSECTION ORCHESTRATOR: Added independent Modifier Node: \$modifierTarget");

    // 3. Create the strictly boolean Intersection Node
    // This node holds no raster data. It simply multiplies the outputs of its parents.
    final intersectionNodeId = 'NODE_INTERSECT_\${DateTime.now().millisecondsSinceEpoch}';
    final intersectionNode = UniversalMask(
      id: 'MASK_\$intersectionNodeId',
      projectId: 'auto',
      mediaId: mediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.generated, // Pure boolean math
      operation: MaskOperation.intersect,
      parameters: {'intent': intentName},
      createdBy: 'orchestrator',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Physically wire the graph dependencies
    activeGraph.addNode(intersectionNode);
    activeGraph.addEdge('MASK_\$semanticNodeId', 'MASK_\$intersectionNodeId');
    activeGraph.addEdge('MASK_\$modifierNodeId', 'MASK_\$intersectionNodeId');

    debugPrint("INTERSECTION ORCHESTRATOR: Successfully wired Intersection Node -> \$intersectionNodeId");
    
    // Return the terminal node ID so the rendering engine can pull the final pixels
    return intersectionNodeId;
  }
}
