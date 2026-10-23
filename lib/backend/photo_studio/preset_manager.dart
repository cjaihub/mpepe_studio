import 'package:flutter/material.dart';
import 'mask_layer_manager.dart';
import 'saved_mask_repository.dart';
import '../mask_engine/universal_mask_models.dart';

/// Represents a targeted adjustment bundle within a larger Studio Preset.
class PresetInstruction {
  /// The semantic target to map this instruction to (e.g. 'face', 'skin', 'background', 'eyes', 'hair')
  final String targetSemantics;
  
  /// The color grading math applied to this semantic target
  final ColorGradingPayload adjustments;
  
  /// Specialized retouching logic (e.g. skin smoothing, texture reduction, clarity boost)
  final Map<String, dynamic> retouchParameters;
  
  /// Defines how the mask should be procedurally constructed if it doesn't already exist.
  final SavedMaskTemplate? proceduralMaskRecipe;

  const PresetInstruction({
    required this.targetSemantics,
    this.adjustments = const ColorGradingPayload(),
    this.retouchParameters = const {},
    this.proceduralMaskRecipe,
  });
}

/// A comprehensive, multi-layer stylistic preset.
class StudioPreset {
  final String id;
  final String name;
  
  /// The individual layers and semantic instructions that make up the preset.
  /// Example: [Instruction(Face: +0.2 exp), Instruction(Background: -0.15 exp)]
  final List<PresetInstruction> instructions;
  
  /// Baseline global color grade applied to the master image beneath the semantic masks.
  final ColorGradingPayload globalAdjustments;

  const StudioPreset({
    required this.id,
    required this.name,
    required this.instructions,
    this.globalAdjustments = const ColorGradingPayload(),
  });
}

/// Engine responsible for unpacking and executing multi-layer presets dynamically.
class PresetEngine {
  
  /// Applies a complex multi-layer preset to the active project.
  /// 
  /// REQUIREMENT: The preset must remain editable.
  static void applyPreset({
    required StudioPreset preset,
    required MaskLayerManager layerManager,
    required String activeMediaId,
    required Function(ColorGradingPayload) onApplyGlobalGrade,
  }) {
    debugPrint("PRESET ENGINE: Applying '\${preset.name}'...");

    // 1. Apply global baselines
    onApplyGlobalGrade(preset.globalAdjustments);

    // 2. Iterate through the complex semantic instructions
    for (final instruction in preset.instructions) {
      
      // Look for an existing layer that matches the target (e.g., "Face")
      final existingLayerIndex = layerManager.layers.indexWhere(
        (l) => l.name.toLowerCase() == instruction.targetSemantics.toLowerCase()
      );

      if (existingLayerIndex != -1) {
        // Layer exists! We simply inject the new adjustments non-destructively.
        final targetLayerId = layerManager.layers[existingLayerIndex].id;
        
        debugPrint("PRESET ENGINE: Updating existing \${instruction.targetSemantics} layer with preset adjustments.");
        
        // This is non-destructive. If the preset adds +0.2 exposure, we update the payload.
        layerManager.updateLayerGrading(targetLayerId, instruction.adjustments);
        
        // In a real implementation, we would also pass the `retouchParameters` 
        // to a dedicated retouch state manager.
        
      } else {
        // Layer doesn't exist! The preset must generate the procedural mask on the fly.
        if (instruction.proceduralMaskRecipe != null) {
          debugPrint("PRESET ENGINE: Generating new \${instruction.targetSemantics} layer from preset recipe...");
          
          // Rehydrate the procedural math from the preset
          final newMask = UniversalMask(
            id: 'PRESET_MASK_\${DateTime.now().millisecondsSinceEpoch}_\${instruction.targetSemantics}',
            projectId: 'auto',
            mediaId: activeMediaId,
            maskType: MaskType.CUSTOM,
            sourceType: MaskSourceType.procedural,
            operation: MaskOperation.values.firstWhere((e) => e.name == instruction.proceduralMaskRecipe!.selectionRecipe, orElse: () => MaskOperation.add),
            parameters: instruction.proceduralMaskRecipe!.parameters,
            createdBy: 'preset_engine',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

          // Add the newly generated layer to the UI
          layerManager.addLayer(
            MaskLayer(
              id: 'PRESET_LAYER_\${DateTime.now().millisecondsSinceEpoch}_\${instruction.targetSemantics}',
              name: instruction.targetSemantics, // e.g. "Hair"
              colorLabel: const Color(0xFFFFFFFF),
              trackingReference: 'preset_auto',
              confidence: 1.0,
              activeMask: newMask,
              grading: instruction.adjustments, // Apply the preset math immediately
            )
          );
        } else {
          debugPrint("PRESET ENGINE: WARNING. Preset requests \${instruction.targetSemantics} but provided no mask recipe, and layer does not exist.");
        }
      }
    }

    debugPrint("PRESET ENGINE: '\${preset.name}' successfully applied. All layers remain non-destructive and editable.");
  }
}
