import 'dart:ui' as ui;

import '../../looks/adapters/legacy_look_adapters.dart';
import '../../looks/engine/look_compiler.dart';
import '../../looks/engine/pixel_sampler.dart';
import 'photo_studio_models.dart';

/// Professional Color Engine for Photo Studio.
///
/// Every adjustment goes through the shared Oneova Look engine
/// (`shaders/look_engine.frag`), so the preview and the export use the same
/// math as Live, Camera and Video.
class PhotoColorEngine {
  /// Compiles [graph] into a ready-to-bind look (uniforms + LUT/curve
  /// textures) for real-time GPU preview. Bind it with
  /// [LookCompiler.createShader] for a given image and size.
  static Future<CompiledLook?> compileRealtimePreview(EditGraph graph) async {
    final look = LegacyLookAdapters.fromEditGraph(graph);
    return LookCompiler.compile(look);
  }

  /// Eyedropper (white balance): reads the pixels around ([x], [y]) and
  /// returns the temperature (Kelvin), tint (Duv × 1000) and channel gains
  /// that make that spot neutral gray.
  static Future<Map<String, double>> computeWhiteBalanceFromEyedropper(
      ui.Image image, int x, int y) async {
    final rgb = await PixelSampler.sampleAverage(image, x, y);
    return PixelSampler.whiteBalanceFor(rgb);
  }

  /// Point Color: the hue (degrees), saturation and luminance of the selected
  /// spot, used as the center of a targeted color range. [rangeOffset] is the
  /// falloff radius the caller wants around that color.
  static Future<Map<String, dynamic>> samplePointColor(ui.Image image, int x, int y,
      {double rangeOffset = 0.12}) async {
    final hsl = PixelSampler.toHsl(await PixelSampler.sampleAverage(image, x, y));
    return {
      'targetHue': hsl.hue,
      'targetSaturation': hsl.saturation,
      'targetLuminance': hsl.luminance,
      'rangeOffset': rangeOffset,
    };
  }
}
