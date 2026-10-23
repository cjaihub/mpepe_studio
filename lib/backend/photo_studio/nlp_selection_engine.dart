import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// Represents the structured intent parsed from a natural language prompt.
class NLPSelectionIntent {
  final List<String> semanticTargets;     // e.g., ['woman', 'hair', 'sky', 'background']
  final Map<String, dynamic> constraints; // e.g., {'color': 'red', 'garment': 'shirt', 'luminance': 'brightest'}
  final List<String> candidateIds;        // The node IDs from the graph that match this intent
  final MaskOperation primaryOperation;   // e.g., add (Select the sky) or exclude (except the person)
  
  /// Identifies if the prompt has an exclusion clause ("except the person")
  final List<String> exclusionTargets;

  const NLPSelectionIntent({
    required this.semanticTargets,
    required this.constraints,
    required this.candidateIds,
    required this.primaryOperation,
    this.exclusionTargets = const [],
  });
}

/// Advanced Natural Language Selection Engine.
class NLPSelectionEngine {
  
  /// Parses the natural language prompt against the current visual graph.
  /// 
  /// REQUIREMENT: Convert the instruction into: semantic target, 
  /// selection constraints, candidate objects, mask operation.
  static Future<NLPSelectionIntent> parseInstruction({
    required String prompt,
    required MaskGraph globalGraph,
  }) async {
    
    // In a production environment, the prompt + a JSON summary of the globalGraph's 
    // nodes (colors, types, labels) are sent to an LLM (e.g. Gemini 1.5 Pro) with structured JSON output.
    
    debugPrint("NLP ENGINE: Parsing prompt -> '\$prompt'");
    
    // Mock parsing logic based on the user's examples
    List<String> targets = [];
    Map<String, dynamic> constraints = {};
    List<String> exclusions = [];
    MaskOperation operation = MaskOperation.add;
    
    final lowerPrompt = prompt.toLowerCase();
    
    if (lowerPrompt.contains('woman') && lowerPrompt.contains('red shirt')) {
      targets = ['PERSON', 'CLOTHING'];
      constraints = {'color': 'red', 'garmentType': 'shirt', 'gender': 'female'};
    } 
    else if (lowerPrompt.contains('background except the person')) {
      targets = ['BACKGROUND'];
      exclusions = ['PERSON', 'SUBJECT'];
      operation = MaskOperation.add; // Add background, exclude person later
    }
    else if (lowerPrompt.contains('brightest parts')) {
      targets = ['LUMINANCE'];
      constraints = {'luminanceBand': 'highlights'};
    }
    
    // Match candidates in the graph based on the parsed targets
    final List<String> candidates = [];
    for (final node in globalGraph.nodes.values) {
      if (targets.contains(node.maskType.name.toUpperCase())) {
        candidates.add(node.id);
      }
    }

    return NLPSelectionIntent(
      semanticTargets: targets,
      constraints: constraints,
      candidateIds: candidates,
      primaryOperation: operation,
      exclusionTargets: exclusions,
    );
  }

  /// Generates a preview mask from the parsed intent without permanently modifying the active project state.
  /// REQUIREMENT: Preview before applying.
  static Map<String, dynamic> generateSelectionPreview({
    required NLPSelectionIntent intent,
    required MaskGraph globalGraph,
  }) {
    
    final Map<String, UniversalMask> previewNodes = {};
    final String rootId = 'NLP_PREVIEW_\${DateTime.now().millisecondsSinceEpoch}';
    final List<String> childIds = [];

    // 1. Add Candidates
    for (final id in intent.candidateIds) {
      if (globalGraph.nodes.containsKey(id)) {
        final node = globalGraph.nodes[id]!;
        final previewId = '\${id}_preview';
        previewNodes[previewId] = node.copyWith(
          id: previewId,
          parentMaskId: rootId,
          operation: intent.primaryOperation,
        );
        childIds.add(previewId);
      }
    }

    // 2. Add Exclusions (e.g. "except the person")
    if (intent.exclusionTargets.isNotEmpty) {
      for (final node in globalGraph.nodes.values) {
        if (intent.exclusionTargets.contains(node.maskType.name.toUpperCase())) {
          final exId = '\${node.id}_exclude_preview';
          previewNodes[exId] = node.copyWith(
            id: exId,
            parentMaskId: rootId,
            operation: MaskOperation.exclude,
          );
          childIds.add(exId);
        }
      }
    }

    // Return a UI-consumable payload that triggers the red-overlay preview
    return {
      'status': 'preview_ready',
      'intent_summary': "Targets: \${intent.semanticTargets.join(', ')} | Excludes: \${intent.exclusionTargets.join(', ')}",
      'requires_user_confirmation': true, // Forces UI to show accept/reject buttons
      'preview_graph': MaskGraph(
        id: 'PREVIEW_ROOT',
        nodes: previewNodes,
        rootNodeIds: [rootId],
      ),
    };
  }
}
