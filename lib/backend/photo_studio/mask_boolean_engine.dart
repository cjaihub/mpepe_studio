import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Represents a requested boolean node in the construction tree.
class BooleanOperationRequest {
  final MaskType targetType;
  final String? targetId; // Specific node ID, if known
  final MaskOperation operation;

  const BooleanOperationRequest({
    required this.targetType,
    this.targetId,
    required this.operation,
  });
}

/// Advanced engine to construct complex, multi-layered Boolean relationships
/// non-destructively within the MaskGraph.
class MaskBooleanEngine {
  
  /// Compiles a new logical MaskGraph node from an ordered list of boolean requests.
  /// 
  /// Example:
  /// Target: PERSON
  /// Requests: [
  ///   (SUBTRACT, HAIR),
  ///   (INTERSECT, SHADOWS)
  /// ]
  /// 
  /// REQUIREMENT: Store operations as a graph, not flattened pixels.
  /// REQUIREMENT: Allow users to reopen and edit every node.
  static MaskGraph constructBooleanGraph({
    required MaskGraph globalGraph,
    required MaskType baseType,
    required String? baseId,
    required List<BooleanOperationRequest> operations,
  }) {
    final Map<String, UniversalMask> compiledNodes = {};
    final List<String> rootIds = [];
    final List<String> childIds = [];

    // Find the base node (e.g. PERSON or SKIN)
    UniversalMask? baseNode;
    if (baseId != null && globalGraph.nodes.containsKey(baseId)) {
      baseNode = globalGraph.nodes[baseId];
    } else {
      // Find first matching type if no specific ID is given
      for (final node in globalGraph.nodes.values) {
        if (node.maskType == baseType) {
          baseNode = node;
          break;
        }
      }
    }

    if (baseNode == null) {
      throw Exception("BOOLEAN ENGINE ERROR: Base target \$baseType not found in current graph.");
    }

    final String rootId = 'BOOLEAN_COMPOSITE_\${DateTime.now().millisecondsSinceEpoch}';

    // 1. Map the Base Node as the starting layer (ADD operation)
    final baseNodeId = '\${baseNode.id}_base';
    compiledNodes[baseNodeId] = baseNode.copyWith(
      id: baseNodeId,
      parentMaskId: rootId,
      operation: MaskOperation.add,
    );
    childIds.add(baseNodeId);

    // 2. Map all requested boolean operations as procedural children
    for (int i = 0; i < operations.length; i++) {
      final req = operations[i];
      
      // Locate the requested node in the global graph
      UniversalMask? targetNode;
      if (req.targetId != null && globalGraph.nodes.containsKey(req.targetId)) {
        targetNode = globalGraph.nodes[req.targetId];
      } else {
        for (final node in globalGraph.nodes.values) {
          if (node.maskType == req.targetType) {
            targetNode = node;
            break;
          }
        }
      }
      
      if (targetNode != null) {
        final opId = '\${targetNode.id}_op_\$i';
        
        // Because these are stored as references in the graph, we do not flatten the pixels.
        // The render pipeline walks these children and applies the math in real-time.
        compiledNodes[opId] = targetNode.copyWith(
          id: opId,
          parentMaskId: rootId,
          operation: req.operation, // e.g., SUBTRACT, INTERSECT, XOR, EXCLUDE
        );
        
        childIds.add(opId);
      } else {
        debugPrint("BOOLEAN ENGINE WARNING: Target \${req.targetType} not found for operation \${req.operation}. Skipping.");
      }
    }

    // 3. Construct the Composite Root
    compiledNodes[rootId] = UniversalMask(
      id: rootId,
      projectId: baseNode.projectId,
      mediaId: baseNode.mediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.ai, // Compiled from AI sources
      childrenIds: childIds,
      trackingReference: baseNode.trackingReference, // Inherit base tracking if applicable
      createdBy: 'mask_boolean_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    rootIds.add(rootId);

    return MaskGraph(
      id: 'BOOLEAN_GRAPH_\${DateTime.now().millisecondsSinceEpoch}',
      nodes: compiledNodes,
      rootNodeIds: rootIds,
    );
  }
}
