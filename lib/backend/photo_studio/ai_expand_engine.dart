import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';
import 'ai_removal_engine.dart';

/// The direction of the canvas expansion (outpainting).
enum ExpansionDirection {
  left,
  right,
  top,
  bottom,
  allSides,
}

/// The structured payload specifying how the canvas should be expanded.
class ExpansionRequest {
  final ExpansionDirection direction;
  
  /// Target aspect ratio (e.g., 16/9, 9/16, 1.0). Null if expanding by raw pixels.
  final double? ratio;
  
  /// Explicit physical pixel amount to expand. Null if expanding by ratio.
  final int? pixelAmount;
  
  /// Optional semantic guidance for the outpainting generation.
  final String? creativePrompt;

  const ExpansionRequest({
    required this.direction,
    this.ratio,
    this.pixelAmount,
    this.creativePrompt,
  }) : assert(ratio != null || pixelAmount != null, 'Must specify either a ratio or a pixel amount.');
}

/// Advanced engine for Canvas Expansion / Outpainting.
class AIExpandEngine {
  
  /// Flow:
  /// 1. Calculate new canvas bounds
  /// 2. Generate implicit "unknown" mask for the expanded region
  /// 3. Pass source image + context boundary to outpainting model
  /// 4. Generate variations
  /// 5. Yield for Preview
  /// 
  /// REQUIREMENT: Preview before applying.
  /// REQUIREMENT: Maintain perspective, lighting, texture, subject geometry.
  static Future<GenerativeFillSession> executeExpand({
    required String sourceMediaId,
    required ExpansionRequest request,
    int requestedVariations = 3,
  }) async {
    
    debugPrint("AI EXPAND: Calculating expansion bounds for direction: \${request.direction.name}");
    if (request.ratio != null) {
      debugPrint("AI EXPAND: Target Ratio: \${request.ratio}");
    } else {
      debugPrint("AI EXPAND: Target Pixels: \${request.pixelAmount}");
    }

    if (request.creativePrompt != null) {
      debugPrint("AI EXPAND: Semantic Guidance: '\${request.creativePrompt}'");
    }

    // 1. We create a virtual mask representing the newly expanded area.
    // This allows the generative service to treat outpainting identically to inpainting.
    final expansionMask = UniversalMask(
      id: 'EXPANSION_MASK_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: 'auto',
      mediaId: sourceMediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.procedural,
      operation: MaskOperation.add,
      parameters: {
        'type': 'canvas_outpainting_boundary',
        'direction': request.direction.name,
      },
      createdBy: 'ai_expand_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Initialize the tracking session to hold the variations
    final session = GenerativeFillSession(
      sessionId: 'EXPAND_SESSION_\${DateTime.now().millisecondsSinceEpoch}',
      originalMask: expansionMask,
    );

    // Simulate API call to outpainting generative image service
    await Future.delayed(const Duration(seconds: 4));

    for (int i = 0; i < requestedVariations; i++) {
      session.addVariant(
        GenerativeFillVariant(
          id: 'EXPAND_VARIANT_\${session.sessionId}_v\$i',
          sourceMediaId: sourceMediaId,
          maskId: expansionMask.id,
          prompt: request.creativePrompt ?? 'seamlessly extend background, maintaining perspective, lighting, and texture',
          model: 'onerova-outpainting-v2',
          provider: 'onerova-cloud',
          resultImagePath: '/virtual/expand_patches/patch_\${session.sessionId}_v\$i.png',
          seed: '331829\${i}1',
          parameters: {
            // These parameters instruct the model to strictly maintain subject geometry 
            // and avoid hallucinating new focal points.
            'maintain_perspective': true,
            'match_lighting_histogram': true,
            'texture_continuation_weight': 0.95,
            'preserve_subject_geometry': true,
          },
          timestamp: DateTime.now(),
        )
      );
    }

    debugPrint("AI EXPAND: \${session.variants.length} variations generated. Yielding for Preview.");

    // We output a Session. The UI will render the expanded canvas size 
    // and composite Variant 1 into the empty space. 
    // The user MUST click "Accept" to finalize the canvas change.
    return session;
  }
}
