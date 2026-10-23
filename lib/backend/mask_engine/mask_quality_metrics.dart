import 'universal_mask_models.dart';

/// Semantic, user-facing label for mask quality.
/// Prevents displaying deceptive "fake percentages".
enum ConfidenceLabel {
  highConfidence,
  mediumConfidence,
  needsRefinement,
}

extension ConfidenceLabelUI on ConfidenceLabel {
  String get displayString {
    switch (this) {
      case ConfidenceLabel.highConfidence:
        return 'High confidence';
      case ConfidenceLabel.mediumConfidence:
        return 'Medium confidence';
      case ConfidenceLabel.needsRefinement:
        return 'Needs refinement';
    }
  }
}

/// Comprehensive telemetry data for every AI-generated mask.
class MaskQualityMetrics {
  /// Internal raw confidence (0.0 to 1.0).
  /// NEVER display this as a percentage in the UI unless [hasCalibratedConfidence] is true.
  final double _internalConfidence;
  
  /// A measure of structural edge certainty (e.g., how sharp the gradient falloff is).
  final double edgeQuality;
  
  /// The percentage of the total canvas occupied by the mask.
  final double coverage;
  
  /// A measure of logical confusion (e.g., overlapping semantic targets or high entropy regions).
  final double ambiguity;
  
  /// Cross-frame geometric consistency (only applicable for Video temporal tracking).
  final double trackingStability;

  /// True if the underlying AI model (e.g., SAM2) outputs strict, calibrated probabilistic confidence.
  /// False if the confidence was mathematically derived/estimated by ONEROVA.
  final bool hasCalibratedConfidence;

  const MaskQualityMetrics({
    required this._internalConfidence,
    required this.edgeQuality,
    required this.coverage,
    required this.ambiguity,
    required this.trackingStability,
    required this.hasCalibratedConfidence,
  });

  /// REQUIREMENT: Do not show fake percentages.
  /// REQUIREMENT: If the model does not expose calibrated confidence, 
  /// derive a documented quality metric or hide the numeric confidence.
  /// 
  /// This getter categorizes the internal mathematical score into a safe, human-readable bucket.
  ConfidenceLabel get semanticLabel {
    // If ambiguity is incredibly high, or edge quality is terrible, force a refinement request
    if (ambiguity > 0.7 || edgeQuality < 0.3) {
      return ConfidenceLabel.needsRefinement;
    }

    if (_internalConfidence >= 0.85) {
      return ConfidenceLabel.highConfidence;
    } else if (_internalConfidence >= 0.50) {
      return ConfidenceLabel.mediumConfidence;
    } else {
      return ConfidenceLabel.needsRefinement;
    }
  }
}

/// Evaluation subsystem to compute the quality of generated UniversalMask nodes.
class MaskQualityEngine {
  
  /// Evaluates an AI-generated MaskGraph or UniversalMask and calculates
  /// a unified [MaskQualityMetrics] payload.
  static MaskQualityMetrics evaluateMaskQuality({
    required UniversalMask mask,
    // Provide underlying AI model metadata (e.g. from the Python/C++ layer)
    required Map<String, dynamic> rawModelOutput, 
    double? temporalTrackingScore,
  }) {
    // 1. Determine if the model provides strict probabilities.
    // For example, Apple Vision framework provides calibrated confidence for person segmentation.
    final bool isCalibrated = rawModelOutput['is_calibrated_confidence'] ?? false;
    final double modelConfidence = rawModelOutput['model_confidence'] ?? 0.0;

    // 2. Derive mathematical estimates if the model lacked native confidence.
    double derivedConfidence = modelConfidence;
    if (!isCalibrated) {
      // Calculate a documented metric based on edge density and interior solidness
      final double interiorDensity = mask.parameters['interior_density'] ?? 1.0;
      final double edgeFractalScore = mask.parameters['edge_fractal_variance'] ?? 0.0; // High variance = noisy
      derivedConfidence = interiorDensity * (1.0 - edgeFractalScore);
    }

    // 3. Extract or compute operational metrics
    final double edgeQual = rawModelOutput['edge_sharpness'] ?? 0.8;
    final double cov = rawModelOutput['canvas_coverage_ratio'] ?? 0.1;
    final double amb = rawModelOutput['semantic_ambiguity_score'] ?? 0.0;

    return MaskQualityMetrics(
      internalConfidence: derivedConfidence.clamp(0.0, 1.0),
      edgeQuality: edgeQual,
      coverage: cov,
      ambiguity: amb,
      trackingStability: temporalTrackingScore ?? 1.0,
      hasCalibratedConfidence: isCalibrated,
    );
  }
}
