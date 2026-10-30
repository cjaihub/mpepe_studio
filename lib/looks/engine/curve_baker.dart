import 'dart:math' as math;
import 'dart:typed_data';

import '../models/oneova_look.dart';

/// Bakes tone curves into a 256×2 RGBA8 texture for the look shader.
/// Row 0 holds the red/green/blue channel curves, row 1 the master curve in
/// every channel. Alpha is opaque so premultiplication never alters values.
class CurveBaker {
  CurveBaker._();

  static const int resolution = 256;

  /// Evaluates a monotone cubic (Fritsch–Carlson) through [points], so curves
  /// never overshoot or invert between control points.
  static Float64List evaluate(List<CurvePoint> points, [int n = resolution]) {
    final out = Float64List(n);
    final pts = [...points]..sort((a, b) => a.x.compareTo(b.x));
    // Drop duplicate x positions (keep the last), clamp into 0..1.
    final xs = <double>[], ys = <double>[];
    for (final p in pts) {
      final x = p.x.clamp(0.0, 1.0), y = p.y.clamp(0.0, 1.0);
      if (xs.isNotEmpty && (x - xs.last).abs() < 1e-9) {
        ys[ys.length - 1] = y;
      } else {
        xs.add(x);
        ys.add(y);
      }
    }
    if (xs.length < 2) {
      for (var i = 0; i < n; i++) {
        out[i] = xs.isEmpty ? i / (n - 1) : ys.first;
      }
      return out;
    }

    final m = xs.length;
    final d = List<double>.generate(m - 1, (i) => (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
    final t = List<double>.filled(m, 0);
    t[0] = d[0];
    t[m - 1] = d[m - 2];
    for (var i = 1; i < m - 1; i++) {
      t[i] = (d[i - 1] * d[i] <= 0) ? 0 : (d[i - 1] + d[i]) / 2;
    }
    for (var i = 0; i < m - 1; i++) {
      if (d[i] == 0) {
        t[i] = 0;
        t[i + 1] = 0;
        continue;
      }
      final a = t[i] / d[i], b = t[i + 1] / d[i];
      final h = a * a + b * b;
      if (h > 9) {
        final k = 3 / math.sqrt(h);
        t[i] = k * a * d[i];
        t[i + 1] = k * b * d[i];
      }
    }

    var seg = 0;
    for (var i = 0; i < n; i++) {
      final x = i / (n - 1);
      if (x <= xs.first) {
        out[i] = ys.first;
        continue;
      }
      if (x >= xs.last) {
        out[i] = ys.last;
        continue;
      }
      while (seg < m - 2 && x > xs[seg + 1]) {
        seg++;
      }
      final h = xs[seg + 1] - xs[seg];
      final s = (x - xs[seg]) / h;
      final s2 = s * s, s3 = s2 * s;
      out[i] = ((2 * s3 - 3 * s2 + 1) * ys[seg] +
              (s3 - 2 * s2 + s) * h * t[seg] +
              (-2 * s3 + 3 * s2) * ys[seg + 1] +
              (s3 - s2) * h * t[seg + 1])
          .clamp(0.0, 1.0);
    }
    return out;
  }

  /// RGBA8 pixels (width [resolution], height 2) for [curves].
  static Uint8List bake(LookCurves curves) {
    final r = evaluate(curves.red), g = evaluate(curves.green), b = evaluate(curves.blue);
    final master = evaluate(curves.master);
    final out = Uint8List(resolution * 2 * 4);
    int q(double v) => (v * 255).round();
    for (var i = 0; i < resolution; i++) {
      final o0 = i * 4, o1 = (resolution + i) * 4;
      out[o0] = q(r[i]);
      out[o0 + 1] = q(g[i]);
      out[o0 + 2] = q(b[i]);
      out[o0 + 3] = 255;
      out[o1] = out[o1 + 1] = out[o1 + 2] = q(master[i]);
      out[o1 + 3] = 255;
    }
    return out;
  }
}
