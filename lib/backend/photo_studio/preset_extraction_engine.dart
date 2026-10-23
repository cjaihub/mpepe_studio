import 'package:flutter/foundation.dart';
import 'mask_layer_manager.dart';
import 'preset_manager.dart';
import 'saved_mask_repository.dart';
import '../mask_engine/universal_mask_models.dart';

/// The final bundle containing the generated preset and AI-authored metadata.
class ExtractedPresetBundle {
  final String presetName;
  final String category;
  final String description;
  final String compatibility;
  
  /// The physical underlying preset architecture (Adjustments, Masks)
  final StudioPreset generatedPreset;

  const ExtractedPresetBundle({
    required this.presetName,
    required this.category,
    required this.description,
    required this.compatibility,
    required this.generatedPreset,
  });
}

/// Advanced engine that analyzes an active project and reverse-engineers it into a reusable Preset.
class PresetExtractionEngine {
  
  /// REQUIREMENT: "Create a preset from this edit."
  /// Analyzes the active layer manager and builds a generalized StudioPreset.
  static Future<ExtractedPresetBundle> extractPresetFromCurrentEdit({
    required MaskLayerManager activeEditState,
    required ColorGradingPayload activeGlobalAdjustments,
    bool isProjectSpecific = false,
  }) async {
    
    debugPrint("PRESET EXTRACTION: Analyzing \${activeEditState.layers.length} active layers...");

    List<PresetInstruction> extractedInstructions = [];
    int generativeMaskCount = 0;
    int deterministicMaskCount = 0;

    // Iterate through the user's active layers
    for (final layer in activeEditState.layers) {
      
      // REQUIREMENT: Exclude source-specific pixel coordinates, unless intentionally project-specific.
      SavedMaskTemplate? extractedRecipe;
      
      if (layer.activeMask != null) {
        if (layer.activeMask!.sourceType == MaskSourceType.bitmap && !isProjectSpecific) {
          debugPrint("PRESET EXTRACTION: Stripping raw bitmap mask from '\${layer.name}' to maintain universal compatibility.");
        } else {
          // Convert the semantic math into a reusable recipe
          final Map<String, dynamic> cleanParameters = Map.from(layer.activeMask!.parameters);
          
          if (!isProjectSpecific) {
            cleanParameters.remove('source_geometry_hash');
            cleanParameters.remove('interaction_history');
          }

          extractedRecipe = SavedMaskTemplate(
            id: 'RECIPE_\${layer.id}',
            name: '\${layer.name} Generator',
            targetSemantics: layer.name.toLowerCase(),
            selectionRecipe: layer.activeMask!.operation.name,
            model: layer.activeMask!.parameters['model'] ?? 'oneova_semantic_engine',
            parameters: cleanParameters,
          );
          
          if (layer.activeMask!.sourceType == MaskSourceType.ai) {
            generativeMaskCount++;
          } else {
            deterministicMaskCount++;
          }
        }
      }

      // Extract the adjustments and strength applied to this specific layer
      extractedInstructions.add(
        PresetInstruction(
          targetSemantics: layer.name,
          adjustments: layer.grading,
          proceduralMaskRecipe: extractedRecipe,
        )
      );
    }

    // AI Semantic Parsing (Simulating OpenRouter call to generate UI metadata)
    debugPrint("PRESET EXTRACTION: Requesting AI to name and categorize the extracted math...");
    await Future.delayed(const Duration(seconds: 1)); // Mock LLM delay
    
    // In production, we'd feed the mathematical JSON to the LLM to get this data:
    final generatedName = _generateIntelligentName(activeGlobalAdjustments, extractedInstructions);
    final description = _generateIntelligentDescription(extractedInstructions);
    
    String compatibility = 'Universal';
    if (isProjectSpecific) {
      compatibility = 'Project Specific (Contains absolute pixel coordinates)';
    } else if (generativeMaskCount > 0) {
      compatibility = 'Semantic (Requires AI Semantic Engine to execute)';
    } else if (deterministicMaskCount > 0) {
      compatibility = 'Procedural (Fast, requires no AI models)';
    }

    final newPreset = StudioPreset(
      id: 'EXTRACTED_PRESET_\${DateTime.now().millisecondsSinceEpoch}',
      name: generatedName,
      globalAdjustments: activeGlobalAdjustments,
      instructions: extractedInstructions,
    );

    return ExtractedPresetBundle(
      presetName: generatedName,
      category: 'User Created',
      description: description,
      compatibility: compatibility,
      generatedPreset: newPreset,
    );
  }

  // --- Mock AI Logic for generating contextual text based on mathematical arrays ---
  
  static String _generateIntelligentName(ColorGradingPayload global, List<PresetInstruction> instructions) {
    if ((global.exposure ?? 0) < -0.1 && (global.contrast ?? 0) > 0.1) return 'Moody Cinematic';
    if (instructions.any((i) => i.targetSemantics.toLowerCase() == 'skin' && (i.adjustments.exposure ?? 0) > 0.1)) return 'Bright Portrait';
    return 'Custom Studio Edit';
  }

  static String _generateIntelligentDescription(List<PresetInstruction> instructions) {
    if (instructions.isEmpty) return 'A basic global color grade.';
    final targets = instructions.map((i) => i.targetSemantics).join(', ');
    return 'A complex, multi-layered preset containing specific adjustments for: $targets. Automatically reconstructs the necessary semantic masks upon application.';
  }
}
