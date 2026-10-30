import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Average sRGB color (0..1) read from a small region of an image.
typedef SampledRgb = ({double r, double g, double b});

/// Reads real pixels for the eyedropper and point-color tools and converts
/// them with standard color science (sRGB → XYZ → CIE 1960 UCS).
class PixelSampler {
  PixelSampler._();

  /// Averages the `(2·radius+1)²` pixels around ([x], [y]). Only that region
  /// is rasterised and read back, never the full image.
  static Future<SampledRgb> sampleAverage(ui.Image image, int x, int y, {int radius = 2}) async {
    final cx = x.clamp(0, image.width - 1);
    final cy = y.clamp(0, image.height - 1);
    final left = math.max(0, cx - radius), top = math.max(0, cy - radius);
    final w = math.min(image.width, cx + radius + 1) - left;
    final h = math.min(image.height, cy + radius + 1) - top;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), w.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    final region = await recorder.endRecording().toImage(w, h);
    try {
      final bytes = await region.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (bytes == null) throw StateError('Pixel readback failed');
      return averageRgba(bytes.buffer.asUint8List());
    } finally {
      region.dispose();
    }
  }

  /// Averages straight-alpha RGBA8 pixels, weighting by alpha.
  @visibleForTesting
  static SampledRgb averageRgba(Uint8List rgba) {
    var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final a = rgba[i + 3] / 255;
      r += rgba[i] * a;
      g += rgba[i + 1] * a;
      b += rgba[i + 2] * a;
      wsum += a;
    }
    if (wsum == 0) return (r: 0, g: 0, b: 0);
    return (r: r / wsum / 255, g: g / wsum / 255, b: b / wsum / 255);
  }

  static double srgbToLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// White balance that neutralises [rgb] as if it were a gray/white surface.
  ///
  /// Returns `temperature` (correlated color temperature in Kelvin, McCamy),
  /// `tint` (Duv × 1000, Ohno 2013; positive = green), and per-channel linear
  /// `rGain`/`gGain`/`bGain` that turn the sample neutral at the same luminance.
  static Map<String, double> whiteBalanceFor(SampledRgb rgb) {
    final r = srgbToLinear(rgb.r), g = srgbToLinear(rgb.g), b = srgbToLinear(rgb.b);
    // Linear sRGB (D65) → XYZ.
    final x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    final z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;
    final sum = x + y + z;
    if (sum <= 1e-6 || y <= 1e-6) {
      // Black sample: no chromaticity to neutralise.
      return {'temperature': 6504, 'tint': 0, 'rGain': 1, 'gGain': 1, 'bGain': 1};
    }
    final cx = x / sum, cy = y / sum;

    final n = (cx - 0.3320) / (0.1858 - cy);
    final cct = (449 * n * n * n + 3525 * n * n + 6823.3 * n + 5520.33).clamp(1000.0, 40000.0);

    // CIE 1960 u,v and Ohno's polynomial distance from the Planckian locus.
    final denom = -2 * cx + 12 * cy + 3;
    final u = 4 * cx / denom, v = 6 * cy / denom;
    final lfp = math.sqrt((u - 0.292) * (u - 0.292) + (v - 0.24) * (v - 0.24));
    final a = math.acos(((u - 0.292) / lfp).clamp(-1.0, 1.0));
    final lbb = -0.00616793 * math.pow(a, 6) +
        0.0893944 * math.pow(a, 5) -
        0.5179722 * math.pow(a, 4) +
        1.5317403 * math.pow(a, 3) -
        2.4243787 * a * a +
        1.925865 * a -
        0.471106;
    final duv = lfp - lbb;

    final lum = y;
    double gain(double c) => c <= 1e-6 ? 1 : lum / c;
    return {
      'temperature': cct,
      'tint': duv * 1000,
      'rGain': gain(r),
      'gGain': gain(g),
      'bGain': gain(b),
    };
  }

  /// Hue (degrees), saturation and lightness (0..1) of an sRGB sample.
  static ({double hue, double saturation, double luminance}) toHsl(SampledRgb rgb) {
    final mx = math.max(rgb.r, math.max(rgb.g, rgb.b));
    final mn = math.min(rgb.r, math.min(rgb.g, rgb.b));
    final l = (mx + mn) / 2;
    final d = mx - mn;
    if (d < 1e-9) return (hue: 0, saturation: 0, luminance: l);
    final s = d / (1 - (2 * l - 1).abs());
    double h;
    if (mx == rgb.r) {
      h = 60 * (((rgb.g - rgb.b) / d) % 6);
    } else if (mx == rgb.g) {
      h = 60 * ((rgb.b - rgb.r) / d + 2);
    } else {
      h = 60 * ((rgb.r - rgb.g) / d + 4);
    }
    if (h < 0) h += 360;
    return (hue: h, saturation: s.clamp(0.0, 1.0), luminance: l);
  }
}
