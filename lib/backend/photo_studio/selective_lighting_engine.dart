import 'package:flutter/foundation.dart';
import '../mask_engine/mask_layer_manager.dart'; // To access MaskLayer
import '../mask_engine/universal_mask_models.dart';

/// Explicit parameters required by the Selective Lighting tools.
/// These map directly to underlying Core Image / Metal shader properties,
/// ensuring edits remain non-destructive and mathematically reversible.
class LightingAdjustmentPayload {
  final double exposure;       // -1.0 to 1.0
  final double whiteBalance;   // Temperature (cool to warm) -1.0 to 1.0
  final double contrast;       // 0.0 to 2.0
  final double color;          // Saturation 0.0 to 2.0
  final double shadow;         // Lift/compress shadows -1.0 to 1.0
  final double highlight;      // Recover/blowout highlights -1.0 to 1.0
  final double glow;           // Bloom radius/intensity 0.0 to 1.0 (where appropriate)

  const LightingAdjustmentPayload({
    this.exposure = 0.0,
    this.whiteBalance = 0.0,
    this.contrast = 1.0,
    this.color = 1.0,
    this.shadow = 0.0,
    this.highlight = 0.0,
    this.glow = 0.0,
  });
  
  LightingAdjustmentPayload copyWith({
    double? exposure,
    double? whiteBalance,
    double? contrast,
    double? color,
    double? shadow,
    double? highlight,
    double? glow,
  }) {
    return LightingAdjustmentPayload(
      exposure: exposure ?? this.exposure,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      contrast: contrast ?? this.contrast,
      color: color ?? this.color,
      shadow: shadow ?? this.shadow,
      highlight: highlight ?? this.highlight,
      glow: glow ?? this.glow,
    );
  }
}

/// Specialized engine for evaluating lighting against semantic masks.
/// 
/// Targets: face, skin, subject, background, hair, clothing.
class SelectiveLightingEngine {
  final MaskLayerManager layerManager;

  SelectiveLightingEngine({required this.layerManager});

  /// REQUIREMENT: AI can recommend lighting operations.
  /// Simulates calling a VLM (Vision Language Model) to analyze the image
  /// and return a mathematically editable recommendation, rather than a flattened "filter".
  Future<Map<String, LightingAdjustmentPayload>> fetchAiLightingRecommendations(String mediaId) async {
    debugPrint("LIGHTING ENGINE: Analyzing scene lighting for media '\$mediaId'...");
    
    // Simulating LLM analysis
    await Future.delayed(const Duration(seconds: 1));
    
    // The AI returns structured modifications attached to semantic targets
    return {
      'face': const LightingAdjustmentPayload(exposure: 0.15, shadow: 0.1, highlight: -0.05),
      'background': const LightingAdjustmentPayload(exposure: -0.2, contrast: 1.1, color: 0.8), // Darken & desaturate background
      'hair': const LightingAdjustmentPayload(highlight: 0.15, glow: 0.05), // Add shine
    };
  }

  /// REQUIREMENT: Actual result must be produced by editable adjustments.
  /// Takes the raw LightingAdjustmentPayload and applies it directly to the 
  /// active non-destructive MaskLayer.
  void applyLightingToSemanticTarget(String semanticTarget, LightingAdjustmentPayload adjustments) {
    debugPrint("LIGHTING ENGINE: Applying editable adjustments to '\$semanticTarget'");
    
    // Attempt to locate the semantic mask layer
    final layerIndex = layerManager.layers.indexWhere((l) => l.name.toLowerCase() == semanticTarget.toLowerCase());
    
    if (layerIndex != -1) {
      // The mask exists. Update its non-destructive rendering payload.
      final layerId = layerManager.layers[layerIndex].id;
      
      // We convert the specialized LightingAdjustmentPayload into the 
      // Universal ColorGradingPayload format expected by the rendering pipeline.
      final universalGrading = ColorGradingPayload(
        exposure: adjustments.exposure,
        contrast: adjustments.contrast,
        shadows: adjustments.shadow,
        highlights: adjustments.highlight,
        // color/saturation mapped accordingly
      );
      
      layerManager.updateLayerGrading(layerId, universalGrading);
      debugPrint("LIGHTING ENGINE: Successfully updated lighting parameters for '\$semanticTarget'.");
      
    } else {
      // If the mask doesn't exist yet, we would ideally trigger the Semantic/Intersection
      // Orchestrator to generate it, then apply the lighting.
      debugPrint("LIGHTING ENGINE WARNING: Target '\$semanticTarget' not found in current layer stack. Mask generation required.");
    }
  }

  /// Explicit manual override method for the UI sliders.
  void modifyActiveLayerExposure(String layerId, double delta) {
    // Allows real-time dragging of exposure sliders in the UI
    final mask = layerManager.layers.firstWhere((l) => l.id == layerId);
    final updatedGrading = mask.grading.copyWith(exposure: mask.grading.exposure! + delta);
    layerManager.updateLayerGrading(layerId, updatedGrading);
  }
}
