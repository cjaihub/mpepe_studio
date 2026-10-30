import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// A parsed 3D LUT. [data] holds `size³` RGB triples, red varying fastest
/// (the order used by the .cube format).
@immutable
class CubeLut {
  final int size;
  final Float32List data;
  final String title;

  const CubeLut({required this.size, required this.data, this.title = ''});

  /// Exact identity LUT (size 2 is lossless under trilinear interpolation).
  factory CubeLut.identity([int size = 2]) {
    final data = Float32List(size * size * size * 3);
    var i = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          data[i++] = r / (size - 1);
          data[i++] = g / (size - 1);
          data[i++] = b / (size - 1);
        }
      }
    }
    return CubeLut(size: size, data: data, title: 'identity');
  }

  /// Parses Adobe/Resolve `.cube` text. Throws [FormatException] when invalid.
  factory CubeLut.parse(String text) {
    var size = 0;
    var title = '';
    var domainMin = const [0.0, 0.0, 0.0];
    var domainMax = const [1.0, 1.0, 1.0];
    final values = <double>[];

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      final key = parts.first.toUpperCase();
      if (key == 'TITLE') {
        title = line.substring(5).trim().replaceAll('"', '');
      } else if (key == 'LUT_3D_SIZE') {
        size = int.parse(parts[1]);
      } else if (key == 'LUT_1D_SIZE') {
        throw const FormatException('1D .cube LUTs are not supported as 3D looks');
      } else if (key == 'DOMAIN_MIN') {
        domainMin = parts.skip(1).take(3).map(double.parse).toList();
      } else if (key == 'DOMAIN_MAX') {
        domainMax = parts.skip(1).take(3).map(double.parse).toList();
      } else if (key == 'LUT_3D_INPUT_RANGE') {
        final lo = double.parse(parts[1]), hi = double.parse(parts[2]);
        domainMin = [lo, lo, lo];
        domainMax = [hi, hi, hi];
      } else if (RegExp(r'^[-+0-9.eE]').hasMatch(parts.first)) {
        if (parts.length < 3) {
          throw FormatException('Malformed LUT row: "$line"');
        }
        values
          ..add(double.parse(parts[0]))
          ..add(double.parse(parts[1]))
          ..add(double.parse(parts[2]));
      }
      // Other keywords (e.g. LUT_IN_VIDEO_RANGE) carry no data we use.
    }

    if (size < 2 || size > 256) {
      throw FormatException('LUT_3D_SIZE missing or invalid ($size)');
    }
    final expected = size * size * size * 3;
    if (values.length != expected) {
      throw FormatException(
          'Expected ${expected ~/ 3} LUT rows for size $size, found ${values.length ~/ 3}');
    }

    // Normalise output values from the declared domain into 0..1.
    final data = Float32List(expected);
    for (var i = 0; i < expected; i++) {
      final c = i % 3;
      final span = domainMax[c] - domainMin[c];
      data[i] = span == 0 ? values[i] : (values[i] - domainMin[c]) / span;
    }
    return CubeLut(size: size, data: data, title: title);
  }

  /// Trilinear lookup of an RGB triple in 0..1.
  (double, double, double) sample(double r, double g, double b) {
    final n = size - 1;
    double cl(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);
    final fr = cl(r) * n, fg = cl(g) * n, fb = cl(b) * n;
    final r0 = fr.floor().clamp(0, n), g0 = fg.floor().clamp(0, n), b0 = fb.floor().clamp(0, n);
    final r1 = math.min(r0 + 1, n), g1 = math.min(g0 + 1, n), b1 = math.min(b0 + 1, n);
    final dr = fr - r0, dg = fg - g0, db = fb - b0;

    var outR = 0.0, outG = 0.0, outB = 0.0;
    for (final (bi, wb) in [(b0, 1 - db), (b1, db)]) {
      for (final (gi, wg) in [(g0, 1 - dg), (g1, dg)]) {
        for (final (ri, wr) in [(r0, 1 - dr), (r1, dr)]) {
          final w = wb * wg * wr;
          if (w == 0) continue;
          final idx = ((bi * size + gi) * size + ri) * 3;
          outR += data[idx] * w;
          outG += data[idx + 1] * w;
          outB += data[idx + 2] * w;
        }
      }
    }
    return (outR, outG, outB);
  }

  /// Applies a stack of `(lut, intensity)` in order and bakes the result into
  /// one LUT of [size], so the GPU always samples a single texture.
  static CubeLut compose(List<(CubeLut, double)> stack, {required int size}) {
    final data = Float32List(size * size * size * 3);
    var i = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          var cr = r / (size - 1), cg = g / (size - 1), cb = b / (size - 1);
          for (final (lut, intensity) in stack) {
            final k = intensity.clamp(0.0, 1.0);
            if (k == 0) continue;
            final (lr, lg, lb) = lut.sample(cr, cg, cb);
            cr += (lr - cr) * k;
            cg += (lg - cg) * k;
            cb += (lb - cb) * k;
          }
          data[i++] = cr;
          data[i++] = cg;
          data[i++] = cb;
        }
      }
    }
    return CubeLut(size: size, data: data, title: 'composite');
  }

  /// RGBA8 atlas: width `size²`, height `size`. Blue selects the slice
  /// (x = b·size + r), green is the row. Alpha is opaque so premultiplication
  /// never alters the stored colors.
  Uint8List toAtlasRgba() {
    final w = size * size;
    final out = Uint8List(w * size * 4);
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final src = ((b * size + g) * size + r) * 3;
          final dst = (g * w + b * size + r) * 4;
          out[dst] = (data[src].clamp(0.0, 1.0) * 255).round();
          out[dst + 1] = (data[src + 1].clamp(0.0, 1.0) * 255).round();
          out[dst + 2] = (data[src + 2].clamp(0.0, 1.0) * 255).round();
          out[dst + 3] = 255;
        }
      }
    }
    return out;
  }

  Future<ui.Image> toAtlasImage() =>
      decodeRgbaImage(toAtlasRgba(), size * size, size);
}

/// Decodes raw RGBA8 pixels into a GPU image.
Future<ui.Image> decodeRgbaImage(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// Loads `.cube` files from assets (`assets/...`), local files, or http(s)
/// URLs, with an in-memory cache keyed by location.
class CubeLutLoader {
  CubeLutLoader._();

  static final Map<String, Future<CubeLut>> _cache = {};

  static Future<CubeLut> load(String location) {
    return _cache.putIfAbsent(location, () async {
      try {
        final text = await _readText(location);
        return await compute(CubeLut.parse, text);
      } catch (e) {
        _cache.remove(location);
        rethrow;
      }
    });
  }

  static Future<String> _readText(String location) async {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      final res = await http.get(Uri.parse(location));
      if (res.statusCode != 200) {
        throw HttpException('LUT download failed (${res.statusCode})', uri: Uri.parse(location));
      }
      return res.body;
    }
    if (location.startsWith('assets/') || location.startsWith('packages/')) {
      return rootBundle.loadString(location);
    }
    final path = location.startsWith('file://') ? Uri.parse(location).toFilePath() : location;
    return File(path).readAsString();
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();
}
