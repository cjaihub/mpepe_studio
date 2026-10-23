import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../mask_engine/mask_layer_manager.dart';
import '../mask_engine/universal_mask_models.dart';
import '../mask_engine/intersection_orchestrator.dart'; // To combine Semantic + ColorRange

/// Extracts semantic and physical color intent from raw natural language.
class ColorIntentPayload {
  final String rawQuery;
  final String? semanticTarget; // e.g. "shirt", "sky", "background"
  final String? colorModifier; // e.g. "red"
  final String action; // e.g. "deeper", "cooler", "monochrome", "untouched"
  final bool isProtection; // e.g. "untouched" implies masking out
  
  const ColorIntentPayload({
    required this.rawQuery,
    this.semanticTarget,
    this.colorModifier,
    required this.action,
    this.isProtection = false,
  });
}

/// A dedicated orchestrator ensuring natural language commands physically generate
/// the appropriate Mask, Color Range, and Shader combination.
/// 
/// Solves: "Make the red shirt deeper", "Make the sky cooler", "Keep skin untouched"
class NlpColorOrchestrator {
  final MaskLayerManager layerManager;
  final IntersectionOrchestrator intersectionOrchestrator;

  NlpColorOrchestrator({
    required this.layerManager,
    required this.intersectionOrchestrator,
  });

  /// REQUIREMENT: The engine should automatically: 
  /// 1. identify target
  /// 2. create mask
  /// 3. create color range if necessary
  /// 4. apply adjustment
  /// 5. preview
  Future<void> executeColorCommand(String rawCommand, String mediaId) async {
    debugPrint("NLP COLOR ORCHESTRATOR: Processing -> '\$rawCommand'");

    // Step 1: Identify target (Simulated LLM extraction)
    final intent = _mockLlmExtraction(rawCommand);

    if (intent.semanticTarget == null) {
      debugPrint("NLP COLOR ORCHESTRATOR: Failed to identify target. Aborting.");
      return;
    }

    String terminalNodeId;

    // Step 2 & 3: Create mask & create color range if necessary
    if (intent.colorModifier != null) {
      // e.g., "red shirt". Requires Semantic(shirt) ∩ ProceduralColor(red)
      debugPrint("NLP COLOR ORCHESTRATOR: Generating Semantic + Color Range intersection...");
      
      // We route to the intersection orchestrator built previously.
      terminalNodeId = await intersectionOrchestrator.buildCompoundIntersection(
        mediaId: mediaId,
        semanticTarget: intent.semanticTarget!,
        modifierTarget: 'color_\${intent.colorModifier}', // Taps the procedural color range engine
        intentName: '\${intent.colorModifier} \${intent.semanticTarget}',
      );
      
    } else {
      // e.g., "sky", "background". Pure Semantic isolation.
      debugPrint("NLP COLOR ORCHESTRATOR: Generating isolated Semantic Mask...");
      terminalNodeId = 'NODE_SEMANTIC_\${DateTime.now().millisecondsSinceEpoch}';
      
      final semanticMask = UniversalMask(
        id: 'MASK_\$terminalNodeId',
        projectId: 'auto',
        mediaId: mediaId,
        maskType: MaskType.CUSTOM,
        sourceType: MaskSourceType.ai,
        operation: intent.isProtection ? MaskOperation.subtract : MaskOperation.add,
        parameters: {'semantic_target': intent.semanticTarget},
        createdBy: 'color_orchestrator',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      layerManager.layers.add(MaskLayer(
        id: terminalNodeId,
        name: intent.semanticTarget!,
        colorLabel: const Color(0xFF990000),
        activeMask: semanticMask,
        grading: const ColorGradingPayload(),
      ));
    }

    // Step 4: Apply adjustment based on the extracted action
    if (!intent.isProtection) {
      debugPrint("NLP COLOR ORCHESTRATOR: Applying mathematically editable adjustment...");
      _applyActionGrading(terminalNodeId, intent.action);
    } else {
      debugPrint("NLP COLOR ORCHESTRATOR: Target flagged as protected. Subtracting from active pipeline.");
    }

    // Step 5: Preview
    debugPrint("NLP COLOR ORCHESTRATOR: Triggering UI Preview Update.");
    // Triggers standard state listener downstream in the UI.
  }

  void _applyActionGrading(String targetLayerId, String action) {
    ColorGradingPayload grading = const ColorGradingPayload();

    switch (action) {
      case 'deeper':
        // Compress exposure, boost contrast/saturation
        grading = const ColorGradingPayload(exposure: -0.2, contrast: 1.2); 
        break;
      case 'cooler':
        // Shift temperature negative
        grading = const ColorGradingPayload(temperature: -0.4); 
        break;
      case 'monochrome':
        // Kill saturation
        grading = const ColorGradingPayload(saturation: -1.0); 
        break;
      case 'brighter':
        // Lift exposure and highlights
        grading = const ColorGradingPayload(exposure: 0.3, highlights: 0.2); 
        break;
    }

    // Update the layer non-destructively
    layerManager.updateLayerGrading(targetLayerId, grading);
  }

  ColorIntentPayload _mockLlmExtraction(String raw) {
    final t = raw.toLowerCase();
    
    if (t.contains("red shirt")) {
      return ColorIntentPayload(rawQuery: raw, semanticTarget: "shirt", colorModifier: "red", action: "deeper");
    } else if (t.contains("sky")) {
      return ColorIntentPayload(rawQuery: raw, semanticTarget: "sky", action: "cooler");
    } else if (t.contains("skin")) {
      return ColorIntentPayload(rawQuery: raw, semanticTarget: "skin", action: "untouched", isProtection: true);
    } else if (t.contains("background")) {
      return ColorIntentPayload(rawQuery: raw, semanticTarget: "background", action: "monochrome");
    } else if (t.contains("shoes")) {
      return ColorIntentPayload(rawQuery: raw, semanticTarget: "shoes", action: "brighter");
    }
    
    return ColorIntentPayload(rawQuery: raw, semanticTarget: "subject", action: "auto");
  }
}
