import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';
import 'mask_layer_manager.dart';

/// The execution strategy recommended by the AI.
enum RelightingStrategy {
  deterministic, // e.g. "make background darker" -> just tweak exposure
  generative,    // e.g. "add cast shadow from venetian blinds" -> requires structural pixel changes
}

/// A structured plan to execute an AI relighting request.
class RelightingPlan {
  final String targetSubject; // e.g., 'face', 'person', 'background', 'specific object'
  final RelightingStrategy strategy;
  
  /// The exact mathematical adjustments to apply if the strategy is deterministic.
  final ColorGradingPayload? deterministicAdjustments;
  
  /// The prompt to pass to the generative AI if conventional editing cannot solve it cleanly.
  final String? generativePrompt;

  const RelightingPlan({
    required this.targetSubject,
    required this.strategy,
    this.deterministicAdjustments,
    this.generativePrompt,
  });
}

/// Advanced engine for interpreting and applying natural language relighting requests.
class AIRelightingEngine {
  
  /// Interprets natural language relighting requests.
  /// 
  /// REQUIREMENT: Prefer deterministic light/color operations when sufficient.
  /// REQUIREMENT: Use generative AI only where conventional editing cannot solve the request cleanly.
  static Future<RelightingPlan> planRelightingCommand(String command) async {
    debugPrint("AI RELIGHTING: Analyzing intent for: '\$command'");
    
    // Simulate natural language intent parsing (e.g., via OpenRouter/Claude).
    // In production, this asks the LLM to choose between modifying exposure/contrast 
    // vs requiring a generative fill.

    final lowerCmd = command.toLowerCase();

    // 1. "Light the face slightly."
    if (lowerCmd.contains('light') && lowerCmd.contains('face')) {
      return const RelightingPlan(
        targetSubject: 'face',
        strategy: RelightingStrategy.deterministic,
        deterministicAdjustments: ColorGradingPayload(
          exposure: 0.15,
          highlights: 0.10,
          shadows: 0.05,
        ),
      );
    }
    
    // 2. "Make the background darker."
    if (lowerCmd.contains('dark') && lowerCmd.contains('background')) {
      return const RelightingPlan(
        targetSubject: 'background',
        strategy: RelightingStrategy.deterministic,
        deterministicAdjustments: ColorGradingPayload(
          exposure: -0.40,
          contrast: 0.15,
          shadows: -0.20,
        ),
      );
    }

    // 3. "Separate subject from background."
    if (lowerCmd.contains('separate') && lowerCmd.contains('background')) {
      // Classic cinematic depth separation: Darken/desaturate background slightly, pop subject.
      return const RelightingPlan(
        targetSubject: 'background', // Usually applied to background to push it back
        strategy: RelightingStrategy.deterministic,
        deterministicAdjustments: ColorGradingPayload(
          exposure: -0.25,
          contrast: -0.10, // Slight atmospheric fade
          saturation: -0.15,
        ),
      );
    }

    // 4. "Add warm sunset light."
    if (lowerCmd.contains('sunset') || lowerCmd.contains('warm')) {
      // If it's just color, we can do it deterministically.
      // But if the prompt implied "add a sunset" it might trigger generative.
      // Let's assume deterministic color grading first as per the rule.
      return const RelightingPlan(
        targetSubject: 'entire_image', // Or specific layer if selected
        strategy: RelightingStrategy.deterministic,
        deterministicAdjustments: ColorGradingPayload(
          exposure: 0.10,
          temperature: 0.40, // Warm
          saturation: 0.20,
        ),
      );
    }

    // 5. Complex structural relighting (e.g., "Add dappled light from a tree branch")
    if (lowerCmd.contains('shadow') || lowerCmd.contains('dappled') || lowerCmd.contains('venetian')) {
      return RelightingPlan(
        targetSubject: 'person',
        strategy: RelightingStrategy.generative,
        generativePrompt: 'relight the subject with \$command, preserving facial identity and core geometry',
      );
    }

    // Fallback: Default deterministic boost
    return const RelightingPlan(
      targetSubject: 'subject',
      strategy: RelightingStrategy.deterministic,
      deterministicAdjustments: ColorGradingPayload(exposure: 0.1),
    );
  }

  /// Evaluates and applies the plan to the active MaskLayerManager.
  static Future<void> executeRelightingPlan({
    required RelightingPlan plan,
    required MaskLayerManager layerManager,
    required String activeMediaId,
  }) async {
    
    // In a real flow, we would match plan.targetSubject to a specific layer ID.
    // For this demonstration, we assume we found the matching layer.
    final String targetLayerId = 'MOCK_LAYER_ID_MATCHING_\${plan.targetSubject.toUpperCase()}';

    if (plan.strategy == RelightingStrategy.deterministic) {
      debugPrint("AI RELIGHTING: Applying deterministic color math to \${plan.targetSubject}.");
      layerManager.updateLayerGrading(targetLayerId, plan.deterministicAdjustments!);
      
    } else {
      debugPrint("AI RELIGHTING: Deterministic math insufficient. Triggering Generative Layer Replacement for \${plan.targetSubject}.");
      // Here we would call AIReplacementEngine.executeReplacement() using plan.generativePrompt
      // and composite the result over the target layer.
    }
  }
}
