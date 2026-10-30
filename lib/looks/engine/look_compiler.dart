import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/oneova_look.dart';
import 'cube_lut.dart';
import 'curve_baker.dart';

/// A look prepared for the GPU: scalar uniforms plus the composed LUT atlas
/// and baked curve texture. Reusable across frames and images.
class CompiledLook {
  final OneovaLook look;
  final ui.Image lutAtlas;
  final int lutSize;
  final double lutIntensity;
  final ui.Image curves;
  final double curvesIntensity;

  /// Raw RGBA8 pixels of [lutAtlas] (`lutSize²` × `lutSize`) and [curves]
  /// (256 × 2), uploaded as-is by the native Live/Camera processors.
  final Uint8List lutAtlasRgba;
  final Uint8List curvesRgba;

  /// Number of enabled LUTs that failed to load (rendered without them).
  final int missingLuts;

  const CompiledLook({
    required this.look,
    required this.lutAtlas,
    required this.lutSize,
    required this.lutIntensity,
    required this.curves,
    required this.curvesIntensity,
    required this.lutAtlasRgba,
    required this.curvesRgba,
    this.missingLuts = 0,
  });
}

/// Compiles a [OneovaLook] for `shaders/look_engine.frag`.
class LookCompiler {
  LookCompiler._();

  static const String shaderAsset = 'shaders/look_engine.frag';
  static Future<ui.FragmentProgram?>? _program;
  static final Map<String, Future<CompiledLook>> _cache = {};
  static const int _cacheLimit = 24;

  /// Loads and caches the look engine fragment program.
  static Future<ui.FragmentProgram?> loadProgram() {
    return _program ??= ui.FragmentProgram.fromAsset(shaderAsset).then<ui.FragmentProgram?>(
      (p) => p,
      onError: (Object e) {
        debugPrint('[LookCompiler] Shader asset loading error: $e');
        _program = null;
        return null;
      },
    );
  }

  /// Builds (or reuses) the GPU resources for [look]. Only enabled LUTs are
  /// loaded; the composed LUT size is capped at [maxLutSize] (device tier).
  static Future<CompiledLook> compile(OneovaLook look, {int maxLutSize = 65}) {
    final key = jsonEncode({
      'luts': [
        for (final l in look.lutStack)
          if (l.isEnabled && l.intensity > 0) [l.pathOrUrl, l.intensity, l.size],
      ],
      'curves': look.curves.toMap(),
      'max': maxLutSize,
    });
    final cached = _cache[key];
    if (cached != null) {
      return cached.then((c) => _withLook(c, look));
    }
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    final future = _build(look, maxLutSize);
    _cache[key] = future;
    future.then<void>((_) {}, onError: (Object _) => _cache.remove(key));
    return future;
  }

  static CompiledLook _withLook(CompiledLook c, OneovaLook look) => CompiledLook(
        look: look,
        lutAtlas: c.lutAtlas,
        lutSize: c.lutSize,
        lutIntensity: c.lutIntensity,
        curves: c.curves,
        curvesIntensity: c.curvesIntensity,
        lutAtlasRgba: c.lutAtlasRgba,
        curvesRgba: c.curvesRgba,
        missingLuts: c.missingLuts,
      );

  static Future<CompiledLook> _build(OneovaLook look, int maxLutSize) async {
    final stack = <(CubeLut, double)>[];
    var missing = 0;
    for (final item in look.lutStack) {
      if (!item.isEnabled || item.intensity <= 0 || item.pathOrUrl.isEmpty) continue;
      try {
        stack.add((await CubeLutLoader.load(item.pathOrUrl), item.intensity));
      } catch (e) {
        missing++;
        debugPrint('[LookCompiler] LUT "${item.name}" unavailable: $e');
      }
    }

    CubeLut lut;
    double lutIntensity;
    if (stack.isEmpty) {
      lut = CubeLut.identity();
      lutIntensity = 0;
    } else if (stack.length == 1 && stack.first.$1.size <= maxLutSize) {
      // Single LUT: upload as-is and blend its intensity on the GPU.
      lut = stack.first.$1;
      lutIntensity = stack.first.$2.clamp(0.0, 1.0);
    } else {
      // Stack (or oversized LUT): bake intensities into one LUT off the UI thread.
      final size = math.min(maxLutSize, stack.map((e) => e.$1.size).reduce(math.max));
      lut = await compute(_composeIsolate, (stack, size));
      lutIntensity = 1;
    }

    final curvesNeutral = look.curves.master.length <= 2 &&
        look.curves.red.length <= 2 &&
        look.curves.green.length <= 2 &&
        look.curves.blue.length <= 2 &&
        _isIdentityCurve(look.curves.master) &&
        _isIdentityCurve(look.curves.red) &&
        _isIdentityCurve(look.curves.green) &&
        _isIdentityCurve(look.curves.blue);

    final atlasRgba = lut.toAtlasRgba();
    final curvesRgba = CurveBaker.bake(look.curves);
    final atlas = await decodeRgbaImage(atlasRgba, lut.size * lut.size, lut.size);
    final curves = await decodeRgbaImage(curvesRgba, CurveBaker.resolution, 2);

    return CompiledLook(
      look: look,
      lutAtlas: atlas,
      lutSize: lut.size,
      lutIntensity: lutIntensity,
      curves: curves,
      curvesIntensity: curvesNeutral ? 0.0 : 1.0,
      lutAtlasRgba: atlasRgba,
      curvesRgba: curvesRgba,
      missingLuts: missing,
    );
  }

  static CubeLut _composeIsolate((List<(CubeLut, double)>, int) args) =>
      CubeLut.compose(args.$1, size: args.$2);

  static bool _isIdentityCurve(List<CurvePoint> pts) =>
      pts.every((p) => (p.x - p.y).abs() < 1e-6);

  /// Creates a shader bound to [compiled], [image] and [size].
  static ui.FragmentShader createShader(
    ui.FragmentProgram program,
    CompiledLook compiled,
    ui.Image image,
    ui.Size size,
  ) {
    final shader = program.fragmentShader();
    bindUniforms(shader: shader, compiled: compiled, size: size, image: image);
    return shader;
  }

  /// Every float uniform, in the declaration order of look_engine.frag.
  /// The native processors bind the same list (they replace `uSize` with
  /// each frame's size), so all paths grade identically.
  static Float32List uniformValues(CompiledLook compiled, ui.Size size) {
    final look = compiled.look;
    final out = <double>[];
    void f(double v) => out.add(v.isFinite ? v : 0.0);
    void w(ColorWheel c) {
      f(c.r);
      f(c.g);
      f(c.b);
      f(c.lum);
    }

    f(size.width);
    f(size.height);
    f(look.intensity.clamp(0.0, 1.0));

    f(look.primary.exposure);
    f(look.primary.contrast);
    f(look.primary.pivot);
    f(look.primary.highlights);
    f(look.primary.shadows);
    f(look.primary.whites);
    f(look.primary.blacks);

    f(look.color.temperature);
    f(look.color.tint);
    f(look.color.vibrance);
    f(look.color.saturation);

    w(look.wheels.lift);
    w(look.wheels.gamma);
    w(look.wheels.gain);
    w(look.wheels.offset);

    f(look.film.grain);
    f(look.film.fade);
    f(look.optics.vignette);
    f(look.detail.sharpen);

    f(compiled.lutSize.toDouble());
    f(compiled.lutIntensity);
    f(compiled.curvesIntensity);

    final bands = look.hsl.bands.map((e) => e.$2).toList();
    for (final pick in <double Function(HslBand)>[(b) => b.hue, (b) => b.sat, (b) => b.lum]) {
      for (final b in bands) {
        f(pick(b));
      }
    }
    return Float32List.fromList(out);
  }

  /// Writes every uniform, in the declaration order of look_engine.frag.
  static void bindUniforms({
    required ui.FragmentShader shader,
    required CompiledLook compiled,
    required ui.Size size,
    required ui.Image image,
  }) {
    final values = uniformValues(compiled, size);
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }

    shader.setImageSampler(0, image);
    shader.setImageSampler(1, compiled.lutAtlas);
    shader.setImageSampler(2, compiled.curves);
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();
}
