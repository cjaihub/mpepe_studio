import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import 'mask_layer_manager.dart';
import '../mask_engine/universal_mask_models.dart';

enum NlpIntentType {
  createSelection,      // "Select the man"
  narrowSelection,      // "Now only his jacket"
  subtractSelection,    // "Keep his face unselected", "Subtract the background"
  addSelection,         // "Add the hair"
  edgeRefinement,       // "Make the sky selection cleaner"
  trackVideo,           // "Track her for the whole video"
  colorGradeAdjustment  // "Now brighten only the eyes"
}

/// Represents the OpenRouter LLM interpretation of the conversational command.
class NlpCommandResolution {
  final NlpIntentType intent;
  final String semanticTarget;
  final Map<String, dynamic> generatedMath;

  const NlpCommandResolution({
    required this.intent,
    required this.semanticTarget,
    required this.generatedMath,
  });
}

/// Keeps track of the active user session context to allow chaining NLP commands.
class NlpSessionContext {
  String? activeLayerId;
  String? activeSemanticSubject; // e.g., "the man"
}

/// The brain that bridges Conversational NLP to the active Masking Architecture.
class NlpInteractionRouter {
  final NlpSessionContext sessionContext = NlpSessionContext();
  final MaskLayerManager layerManager;

  NlpInteractionRouter({required this.layerManager});

  /// REQUIREMENT: "Every command operates on the current selection context. 
  /// Do not require the user to manually navigate through every panel."
  Future<void> executeCommand(String rawTranscript, String activeMediaId) async {
    debugPrint("NLP ROUTER: Received command: '\$rawTranscript'");

    // 1. Send the transcript and current sessionContext to OpenRouter
    // We pass the context so the LLM understands that "his jacket" refers to "the man" we just selected.
    final resolution = await _mockOpenRouterResolution(rawTranscript, sessionContext);

    // 2. Route the mathematical action directly to the UI engines without requiring panels.
    switch (resolution.intent) {
      
      case NlpIntentType.createSelection:
        debugPrint("NLP ROUTER: Creating base selection for \${resolution.semanticTarget}");
        final newLayer = _generateLayerFromMath(resolution, activeMediaId);
        layerManager.addLayer(newLayer);
        sessionContext.activeLayerId = newLayer.id;
        sessionContext.activeSemanticSubject = resolution.semanticTarget;
        break;

      case NlpIntentType.narrowSelection:
        // "Now only his jacket." (Intersect the existing subject with the jacket)
        if (sessionContext.activeLayerId != null) {
          debugPrint("NLP ROUTER: Narrowing active selection to \${resolution.semanticTarget}");
          // Modifies the active UniversalMask with an INTERSECT boolean operation
          final currentMask = layerManager.layers.firstWhere((l) => l.id == sessionContext.activeLayerId).activeMask;
          if (currentMask != null) {
            // Pseudo-logic to intersect
            currentMask.parameters['intersection_target'] = resolution.semanticTarget;
          }
        }
        break;

      case NlpIntentType.subtractSelection:
        // "Keep his face unselected."
        if (sessionContext.activeLayerId != null) {
          debugPrint("NLP ROUTER: Subtracting \${resolution.semanticTarget} from active selection.");
          final currentMask = layerManager.layers.firstWhere((l) => l.id == sessionContext.activeLayerId).activeMask;
          if (currentMask != null) {
            currentMask.parameters['subtraction_target'] = resolution.semanticTarget;
          }
        }
        break;

      case NlpIntentType.addSelection:
        // "Add the hair."
        if (sessionContext.activeLayerId != null) {
          debugPrint("NLP ROUTER: Adding \${resolution.semanticTarget} to active selection.");
          final currentMask = layerManager.layers.firstWhere((l) => l.id == sessionContext.activeLayerId).activeMask;
          if (currentMask != null) {
            currentMask.parameters['addition_target'] = resolution.semanticTarget;
          }
        }
        break;

      case NlpIntentType.edgeRefinement:
        // "Make the sky selection cleaner."
        if (sessionContext.activeLayerId != null) {
          debugPrint("NLP ROUTER: Applying sub-pixel edge refinement to \${resolution.semanticTarget}.");
          // Triggers the EdgeRefinementEngine math
          final currentMask = layerManager.layers.firstWhere((l) => l.id == sessionContext.activeLayerId).activeMask;
          if (currentMask != null) {
            currentMask.parameters['feather'] = 0.8; // Example LLM output
          }
        }
        break;

      case NlpIntentType.trackVideo:
        // "Track her for the whole video."
        if (sessionContext.activeLayerId != null) {
          debugPrint("NLP ROUTER: Triggering TemporalMaskTracker for \${sessionContext.activeSemanticSubject}.");
          // Instructs the Temporal Engine to begin 4D propagation
        }
        break;

      case NlpIntentType.colorGradeAdjustment:
        // "Now brighten only the eyes."
        // We create a new target ("eyes") if we don't have one, then apply brightness.
        debugPrint("NLP ROUTER: Applying color adjustment to \${resolution.semanticTarget}.");
        
        // Pseudo-logic to apply exposure
        final ColorGradingPayload adjustments = ColorGradingPayload(exposure: 0.3);
        
        final existingLayerIndex = layerManager.layers.indexWhere((l) => l.name.toLowerCase() == resolution.semanticTarget.toLowerCase());
        if (existingLayerIndex != -1) {
          layerManager.updateLayerGrading(layerManager.layers[existingLayerIndex].id, adjustments);
        } else {
           // Create a new localized layer just for this adjustment
           final newLayer = _generateLayerFromMath(resolution, activeMediaId, grading: adjustments);
           layerManager.addLayer(newLayer);
           sessionContext.activeLayerId = newLayer.id;
        }
        break;
    }
  }

  // --- Helpers ---

  MaskLayer _generateLayerFromMath(NlpCommandResolution resolution, String mediaId, {ColorGradingPayload? grading}) {
    return MaskLayer(
      id: 'NLP_LAYER_\${DateTime.now().millisecondsSinceEpoch}',
      name: resolution.semanticTarget,
      colorLabel: AppColors.brandBlue,
      trackingReference: 'nlp_auto',
      confidence: 1.0,
      activeMask: UniversalMask(
        id: 'NLP_MASK_\${DateTime.now().millisecondsSinceEpoch}',
        projectId: 'auto',
        mediaId: mediaId,
        maskType: MaskType.CUSTOM,
        sourceType: MaskSourceType.ai,
        operation: MaskOperation.add,
        parameters: {'semantic_query': resolution.semanticTarget},
        createdBy: 'nlp_router',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      grading: grading ?? const ColorGradingPayload(),
    );
  }

  Future<NlpCommandResolution> _mockOpenRouterResolution(String transcript, NlpSessionContext context) async {
    // In production, OpenRouter parses the text and the previous context.
    // E.g., if context says "activeSemanticSubject: 'the man'", and transcript says "only his jacket",
    // OpenRouter knows 'his' = 'the man'.
    
    final t = transcript.toLowerCase();
    
    if (t.contains("brighten")) return NlpCommandResolution(intent: NlpIntentType.colorGradeAdjustment, semanticTarget: "eyes", generatedMath: {});
    if (t.contains("track")) return NlpCommandResolution(intent: NlpIntentType.trackVideo, semanticTarget: "active", generatedMath: {});
    if (t.contains("cleaner")) return NlpCommandResolution(intent: NlpIntentType.edgeRefinement, semanticTarget: "active", generatedMath: {});
    if (t.contains("subtract") || t.contains("unselected")) return NlpCommandResolution(intent: NlpIntentType.subtractSelection, semanticTarget: "background", generatedMath: {});
    if (t.contains("add")) return NlpCommandResolution(intent: NlpIntentType.addSelection, semanticTarget: "hair", generatedMath: {});
    if (t.contains("only")) return NlpCommandResolution(intent: NlpIntentType.narrowSelection, semanticTarget: "jacket", generatedMath: {});
    
    return NlpCommandResolution(intent: NlpIntentType.createSelection, semanticTarget: "man", generatedMath: {});
  }
}
