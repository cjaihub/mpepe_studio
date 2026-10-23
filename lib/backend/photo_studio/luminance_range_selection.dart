import '../mask_engine/universal_mask_models.dart';

/// Predefined tonal bands, plus full custom access.
enum LuminancePreset {
  highlights,
  midtones,
  shadows,
  custom,
}

/// Parameters defining both the Luminance Mask boundaries and the subsequent adjustments.
class LuminanceRangeParameters {
  // --- Mask Boundary Controls ---
  // Range limits from 0.0 (Absolute Black) to 1.0 (Absolute White)
  final double blackPoint; 
  final double whitePoint;
  
  // Transition controls
  final double falloff;    // How quickly the selection drops off past the black/white points
  final double smoothness; // Internal blending curve (Linear, S-Curve, etc.)

  // --- Photometric Adjustments ---
  // These apply exclusively to the pixels isolated by the luminance band
  final double highlightRecovery; // Compresses highlights to restore blown-out detail
  final double shadowGrading;     // Lifts or tints shadows specifically
  final double contrastShaping;   // Micro-contrast injection in the targeted zone
  final double colorGrade;        // Color tint applied to the targeted luminance

  // --- Semantic Protections ---
  /// If true, the system will mathematically subtract the Background from this luminance mask,
  /// preventing sky highlights from being affected when recovering subject highlights.
  final bool protectBackground;

  const LuminanceRangeParameters({
    this.blackPoint = 0.0,
    this.whitePoint = 1.0,
    this.falloff = 0.1,
    this.smoothness = 0.5,
    this.highlightRecovery = 0.0,
    this.shadowGrading = 0.0,
    this.contrastShaping = 0.0,
    this.colorGrade = 0.0,
    this.protectBackground = false,
  });

  /// Factory constructors for rapid preset assignment
  factory LuminanceRangeParameters.highlights() {
    return const LuminanceRangeParameters(blackPoint: 0.7, whitePoint: 1.0, falloff: 0.15);
  }

  factory LuminanceRangeParameters.midtones() {
    return const LuminanceRangeParameters(blackPoint: 0.3, whitePoint: 0.7, falloff: 0.2);
  }

  factory LuminanceRangeParameters.shadows() {
    return const LuminanceRangeParameters(blackPoint: 0.0, whitePoint: 0.3, falloff: 0.15);
  }

  Map<String, dynamic> toShaderParameters() {
    return {
      'blackPoint': blackPoint,
      'whitePoint': whitePoint,
      'falloff': falloff,
      'smoothness': smoothness,
    };
  }
}

/// Advanced subsystem for non-destructive Tonal Selection and Shaping.
class LuminanceRangeSelectionEngine {
  
  /// Compiles a procedural Luminance Range mask, optionally weaving in semantic background protection.
  static MaskGraph compileLuminanceMask({
    required String projectId,
    required String mediaId,
    required MaskGraph globalGraph,
    required LuminanceRangeParameters parameters,
  }) {
    final Map<String, UniversalMask> compiledNodes = {};
    final List<String> rootIds = [];
    final List<String> childIds = [];

    final String rootId = 'LUMINANCE_COMPOSITE_\${DateTime.now().millisecondsSinceEpoch}';

    // 1. Generate the core mathematical/procedural luminance node
    final proceduralLumId = '\${rootId}_procedural';
    final proceduralLumNode = UniversalMask(
      id: proceduralLumId,
      projectId: projectId,
      mediaId: mediaId,
      maskType: MaskType.LUMINANCE,
      sourceType: MaskSourceType.procedural,
      operation: MaskOperation.add,
      parentMaskId: rootId,
      parameters: parameters.toShaderParameters(),
      createdBy: 'luminance_range_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    compiledNodes[proceduralLumId] = proceduralLumNode;
    childIds.add(proceduralLumId);

    // 2. Apply Semantic Background Protection if requested
    // REQUIREMENT: protect background
    if (parameters.protectBackground) {
      for (final node in globalGraph.nodes.values) {
        if (node.maskType == MaskType.BACKGROUND || node.maskType == MaskType.SKY) {
          final exId = '\${node.id}_lum_protect';
          compiledNodes[exId] = node.copyWith(
            id: exId,
            parentMaskId: rootId,
            operation: MaskOperation.exclude, // Protects background from the luminance operation
          );
          childIds.add(exId);
        }
      }
    }

    // 3. Construct Root
    compiledNodes[rootId] = UniversalMask(
      id: rootId,
      projectId: projectId,
      mediaId: mediaId,
      maskType: MaskType.LUMINANCE,
      sourceType: MaskSourceType.ai, // Hybrid AI/Procedural
      childrenIds: childIds,
      createdBy: 'luminance_range_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    rootIds.add(rootId);

    return MaskGraph(
      id: 'LUM_GRAPH_\${DateTime.now().millisecondsSinceEpoch}',
      nodes: compiledNodes,
      rootNodeIds: rootIds,
    );
  }

  /// Generates the mathematical boundaries required by the UI to render real-time histogram feedback.
  /// REQUIREMENT: Provide real-time histogram feedback.
  static Map<String, dynamic> generateHistogramFeedbackData(LuminanceRangeParameters params) {
    return {
      'overlay_type': 'histogram_luminance_band',
      // UI uses these 0.0 - 1.0 values to draw the selection box over the histogram
      'start_point': params.blackPoint,
      'end_point': params.whitePoint,
      // UI uses these to draw the gradient falloff tails extending from the box
      'left_tail_start': (params.blackPoint - params.falloff).clamp(0.0, 1.0),
      'right_tail_end': (params.whitePoint + params.falloff).clamp(0.0, 1.0),
      'curve_type': params.smoothness > 0.5 ? 's_curve' : 'linear',
    };
  }
}
