import '../mask_engine/universal_mask_models.dart';

/// Represents a single sampled point in HSL space.
class HSLColorSample {
  final double hue;        // 0.0 to 360.0
  final double saturation; // 0.0 to 1.0
  final double luminance;  // 0.0 to 1.0

  const HSLColorSample({
    required this.hue,
    required this.saturation,
    required this.luminance,
  });

  Map<String, dynamic> toJson() => {
    'h': hue,
    's': saturation,
    'l': luminance,
  };
}

/// Operation mode for how new samples interact with the current range.
enum ColorSampleMode {
  add,
  subtract,
  intersect,
}

/// Professional Color Range parameters that drive the GPU shader mathematically.
class ColorRangeSelectionParameters {
  final List<HSLColorSample> samples;
  
  // Tolerance (Fuzziness/Width of the selection band)
  final double hueTolerance;        // e.g. ±15 degrees
  final double saturationTolerance; // e.g. ±0.2
  final double luminanceTolerance;  // e.g. ±0.15
  
  // Edge transitions
  final double smoothness; // Internal falloff / anti-aliasing of the color band
  final double feather;    // Spatial blur applied to the final output mask

  const ColorRangeSelectionParameters({
    this.samples = const [],
    this.hueTolerance = 15.0,
    this.saturationTolerance = 0.2,
    this.luminanceTolerance = 0.15,
    this.smoothness = 0.5,
    this.feather = 0.0,
  });

  Map<String, dynamic> toShaderParameters() {
    return {
      'samples': samples.map((s) => s.toJson()).toList(),
      'hueTolerance': hueTolerance,
      'saturationTolerance': saturationTolerance,
      'luminanceTolerance': luminanceTolerance,
      'smoothness': smoothness,
      'feather': feather,
    };
  }
}

/// Advanced subsystem for non-destructive Color and Luminance selection.
class ColorRangeSelectionEngine {
  
  /// Generates a non-destructive Color Range mask node.
  /// REQUIREMENT: Do not convert the project to a destructive selection.
  /// By creating a UniversalMask with mathematical parameters, the GPU 
  /// calculates this live at 60fps without ever rasterizing a bitmap destructively.
  static UniversalMask createColorRangeMask({
    required String projectId,
    required String mediaId,
    required ColorRangeSelectionParameters parameters,
    required ColorSampleMode operationMode,
  }) {
    
    // Map the UI operation mode to the canonical MaskOperation
    MaskOperation graphOp;
    switch (operationMode) {
      case ColorSampleMode.add:
        graphOp = MaskOperation.add;
        break;
      case ColorSampleMode.subtract:
        graphOp = MaskOperation.subtract;
        break;
      case ColorSampleMode.intersect:
        graphOp = MaskOperation.intersect;
        break;
    }

    return UniversalMask(
      id: 'COLOR_RANGE_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: projectId,
      mediaId: mediaId,
      maskType: MaskType.COLOR,
      sourceType: MaskSourceType.procedural, // Procedural means computed mathematically
      operation: graphOp,
      parameters: parameters.toShaderParameters(),
      createdBy: 'color_range_engine',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Helper to generate the payload the UI needs to render the preview.
  /// REQUIREMENT: UI should show: color range preview, selected area, falloff.
  static Map<String, dynamic> generateUIPreviewData(ColorRangeSelectionParameters params) {
    return {
      'preview_type': 'color_range_overlay',
      'active_samples_count': params.samples.length,
      'hue_band': [
        // Calculate the lowest and highest hue points being captured
        if (params.samples.isNotEmpty)
          params.samples.map((s) => s.hue - params.hueTolerance).reduce((a, b) => a < b ? a : b),
        if (params.samples.isNotEmpty)
          params.samples.map((s) => s.hue + params.hueTolerance).reduce((a, b) => a > b ? a : b),
      ],
      'falloff_curve': params.smoothness, // Instructs UI to show the gradient curve widget
      'spatial_feather': params.feather,
    };
  }
}
