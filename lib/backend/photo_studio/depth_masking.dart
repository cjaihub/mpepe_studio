import '../mask_engine/universal_mask_models.dart';

/// Predefined spatial depth bands, plus custom ranging.
enum DepthPreset {
  near,   // Foreground closest to the lens
  mid,    // Subject plane
  far,    // Background/Infinity
  custom,
}

/// The origin source of the depth map (Native hardware vs AI inference).
enum DepthSourceType {
  nativeMetadata, // LiDAR, Apple TrueDepth, dual-lens parallax
  inferredAI,     // Monocular depth estimation (e.g., Depth Anything V2)
}

/// Stores metadata about the depth generation as required by the prompt.
class DepthGenerationMetadata {
  final DepthSourceType sourceType;
  final String? model;
  final String? modelVersion;
  final double? confidence;

  const DepthGenerationMetadata({
    required this.sourceType,
    this.model,
    this.modelVersion,
    this.confidence,
  });

  Map<String, dynamic> toJson() => {
    'sourceType': sourceType.name,
    if (model != null) 'model': model,
    if (modelVersion != null) 'modelVersion': modelVersion,
    if (confidence != null) 'confidence': confidence,
  };
}

/// Core spatial masking controls and resulting photometric applications.
class DepthMaskParameters {
  // --- Mask Boundary Controls ---
  // Range limits from 0.0 (Lens/Near) to 1.0 (Infinity/Far)
  final double startDepth; 
  final double endDepth;
  
  final double falloff; // Transition width
  final bool invert;    // Flips the selection
  final double smooth;  // Internal masking curve (anti-aliasing)
  final double feather; // Spatial blur applied to the final mask

  // --- Applications ---
  final double depthBlur;         // Synthetic bokeh/shallow depth-of-field
  final double backgroundDarken;  // Exposure shift mapped to depth
  final double cinematicColor;    // Hue shift injected at a specific depth plane
  final double depthSharpening;   // Local contrast enhancement tied to the focal plane

  const DepthMaskParameters({
    this.startDepth = 0.0,
    this.endDepth = 1.0,
    this.falloff = 0.1,
    this.invert = false,
    this.smooth = 0.5,
    this.feather = 0.0,
    this.depthBlur = 0.0,
    this.backgroundDarken = 0.0,
    this.cinematicColor = 0.0,
    this.depthSharpening = 0.0,
  });

  /// Factory constructors for spatial presets
  factory DepthMaskParameters.near() {
    return const DepthMaskParameters(startDepth: 0.0, endDepth: 0.3, falloff: 0.15);
  }

  factory DepthMaskParameters.mid() {
    return const DepthMaskParameters(startDepth: 0.3, endDepth: 0.7, falloff: 0.2);
  }

  factory DepthMaskParameters.far() {
    return const DepthMaskParameters(startDepth: 0.7, endDepth: 1.0, falloff: 0.15);
  }

  Map<String, dynamic> toShaderParameters() {
    return {
      'startDepth': startDepth,
      'endDepth': endDepth,
      'falloff': falloff,
      'invert': invert,
      'smooth': smooth,
      'feather': feather,
    };
  }
}

/// Advanced subsystem for generating and parsing 3D spatial depth maps.
class DepthMaskingEngine {
  
  /// Compiles a procedural Depth mask into the graph.
  /// REQUIREMENT: Do not assume every source contains real depth metadata.
  /// REQUIREMENT: When inferred depth is used, store: model, version, confidence, source.
  static UniversalMask compileDepthMask({
    required String projectId,
    required String mediaId,
    required DepthMaskParameters parameters,
    required DepthGenerationMetadata depthSourceMeta,
  }) {
    
    // We bind the depth sourcing metadata into the graph payload so the renderer
    // knows whether it's executing against an internal Apple Depth map, or 
    // evaluating a monocular tensor output like Depth Anything V2.
    final payload = parameters.toShaderParameters();
    payload['depth_source_meta'] = depthSourceMeta.toJson();

    return UniversalMask(
      id: 'DEPTH_MASK_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: projectId,
      mediaId: mediaId,
      maskType: MaskType.DEPTH,
      sourceType: MaskSourceType.procedural, // The mask boundary is evaluated procedurally
      operation: MaskOperation.add,
      parameters: payload,
      createdBy: 'depth_masking_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Utility to identify if an image requires AI depth inference.
  static bool requiresInferredDepth(Map<String, dynamic> imageMetadata) {
    // If the image contains LiDAR or Portrait mode depth maps (e.g., HEIC depth maps),
    // we use the native hardware data. Otherwise, we must infer it via AI.
    final hasNativeDepth = imageMetadata['hasDepthMap'] ?? false;
    return !hasNativeDepth;
  }
}
