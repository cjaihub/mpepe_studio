import '../mask_engine/universal_mask_models.dart';

/// Background rendering modes for the High-Zoom Edge Inspector.
enum EdgeInspectorBackground {
  checkerboard, // Standard alpha visibility
  black,        // Reveals light fringing/halos
  white,        // Reveals dark fringing/artifacts
  transparent,  // Composited over the original image
}

/// Dedicated, professional-grade Edge Refinement parameters.
class EdgeRefinementParameters {
  // Spatial Geometry
  final double feather;   // Softens the edge symmetrically
  final double smooth;    // Reduces sharp angles and jagged aliasing
  final double contract;  // Shrinks the geometric boundary
  final double expand;    // Enlarges the geometric boundary
  final double choke;     // Closes holes and tightens the core matte
  final double blur;      // Gaussian blur applied to the alpha channel
  final double density;   // Overall opacity multiplier of the mask

  // Color & Artifact Cleanup
  final double decontaminateEdge; // Analyzes and neutralizes background color bleed on the subject edge
  final double defringe;          // Removes chromatic aberration (purple/green edges)

  // Advanced Alpha Recovery (Crucial for hair/fur)
  final double edgeContrast;       // Hardens the alpha transition
  final double edgeSoftness;       // Diffuses the alpha transition
  final double hairDetail;         // Sub-pixel alpha recovery specifically targeting fine strands
  final double transparencyRecovery; // Boosts density in semi-transparent regions (e.g. glass, smoke)

  const EdgeRefinementParameters({
    this.feather = 0.0,
    this.smooth = 0.0,
    this.contract = 0.0,
    this.expand = 0.0,
    this.choke = 0.0,
    this.blur = 0.0,
    this.density = 1.0,
    this.decontaminateEdge = 0.0,
    this.defringe = 0.0,
    this.edgeContrast = 0.0,
    this.edgeSoftness = 0.0,
    this.hairDetail = 0.0,
    this.transparencyRecovery = 0.0,
  });

  Map<String, dynamic> toShaderParameters() {
    return {
      'feather': feather,
      'smooth': smooth,
      'contract': contract,
      'expand': expand,
      'choke': choke,
      'blur': blur,
      'density': density,
      'decontaminateEdge': decontaminateEdge,
      'defringe': defringe,
      'edgeContrast': edgeContrast,
      'edgeSoftness': edgeSoftness,
      'hairDetail': hairDetail,
      'transparencyRecovery': transparencyRecovery,
    };
  }
}

/// Advanced subsystem for mathematically perfecting mask boundaries.
class EdgeRefinementEngine {
  
  /// Applies advanced edge refinement parameters to an existing mask node non-destructively.
  /// The engine updates the parameters block and ensures the mask will be processed by the 
  /// edge_refine shader phase during rendering.
  static UniversalMask applyEdgeRefinement({
    required UniversalMask sourceMask,
    required EdgeRefinementParameters parameters,
  }) {
    // We clone the mask to preserve graph immutability, injecting the new edge data
    // into its procedural payload.
    final payload = Map<String, dynamic>.from(sourceMask.parameters);
    payload['edge_refinement'] = parameters.toShaderParameters();

    return sourceMask.copyWith(
      // Ensure the render engine knows this mask requires the heavy edge-refinement shader pass
      operation: MaskOperation.edge_refine, 
      parameters: payload,
      feather: parameters.feather, // Hoist common attributes for fast track rendering
      expansion: parameters.expand - parameters.contract, 
      density: parameters.density,
      updatedAt: DateTime.now(),
    );
  }

  /// Generates the payload required by the UI to render the High-Zoom Edge Inspector.
  /// REQUIREMENT: Show a high-zoom edge inspector.
  /// REQUIREMENT: Support checkerboard, black background, white background, transparent preview.
  static Map<String, dynamic> generateEdgeInspectorData({
    required UniversalMask targetMask,
    required EdgeInspectorBackground activeBackground,
    required double zoomLevel,
  }) {
    
    String bgModeStr;
    switch (activeBackground) {
      case EdgeInspectorBackground.checkerboard:
        bgModeStr = 'bg_checkerboard'; break;
      case EdgeInspectorBackground.black:
        bgModeStr = 'bg_black_solid'; break;
      case EdgeInspectorBackground.white:
        bgModeStr = 'bg_white_solid'; break;
      case EdgeInspectorBackground.transparent:
        bgModeStr = 'bg_composite_transparent'; break;
    }

    return {
      'status': 'inspector_ready',
      'mask_id': targetMask.id,
      'render_directive': {
        'viewport_mode': 'high_zoom_tracking',
        'zoom_multiplier': zoomLevel.clamp(2.0, 10.0), // Force 2x-10x magnification
        'background_underlay': bgModeStr,
        'center_on_edge_boundary': true, // Auto-pans the camera to the nearest edge
      }
    };
  }
}
