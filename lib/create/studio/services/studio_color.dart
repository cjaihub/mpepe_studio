import 'dart:math' as math;

import '../models/studio_project.dart';

/// A named color look. [matrix] is a Flutter ColorFilter.matrix (4x5,
/// row-major, offsets in 0..255). The same matrix drives the live preview
/// and the Media3 export, so what you see is what you post.
class StudioFilter {
  final String id;
  final String name;
  final String group;
  final List<double> matrix;
  const StudioFilter(this.id, this.name, this.group, this.matrix);
}

class StudioColor {
  StudioColor._();

  static const identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static List<double> _saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return [
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _scaleOffset(double rs, double gs, double bs, double ro, double go, double bo) => [
        rs, 0, 0, 0, ro, //
        0, gs, 0, 0, go, //
        0, 0, bs, 0, bo, //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _contrast(double c) {
    final o = 128 * (1 - c);
    return _scaleOffset(c, c, c, o, o, o);
  }

  /// a then b (b ∘ a).
  static List<double> multiply(List<double> b, List<double> a) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += b[row * 5 + k] * a[k * 5 + col];
        }
        if (col == 4) v += b[row * 5 + 4];
        out[row * 5 + col] = v;
      }
    }
    return out;
  }

  static List<double> _chain(List<List<double>> steps) => steps.fold(identity, (acc, m) => multiply(m, acc));

  static List<double> lerp(List<double> a, List<double> b, double t) =>
      [for (var i = 0; i < 20; i++) a[i] + (b[i] - a[i]) * t];

  static final filters = <StudioFilter>[
    const StudioFilter('none', 'None', 'Featured', identity),
    StudioFilter('vivid', 'Vivid', 'Featured', _chain([_saturation(1.45), _contrast(1.12)])),
    StudioFilter('crisp', 'Crisp', 'Featured', _chain([_contrast(1.22), _saturation(1.1), _scaleOffset(1, 1, 1, -6, -6, -6)])),
    StudioFilter('glow', 'Glow', 'Featured', _chain([_scaleOffset(1.08, 1.06, 1.04, 14, 12, 10), _contrast(0.92)])),
    StudioFilter('warm', 'Warm', 'Life', _chain([_scaleOffset(1.08, 1.02, 0.9, 10, 4, -8), _saturation(1.1)])),
    StudioFilter('cool', 'Cool', 'Life', _chain([_scaleOffset(0.92, 1.0, 1.1, -6, 2, 12), _saturation(1.05)])),
    StudioFilter('golden', 'Golden', 'Life', _chain([_scaleOffset(1.12, 1.04, 0.84, 12, 6, -10), _contrast(1.05)])),
    StudioFilter('rose', 'Rose', 'Life', _chain([_scaleOffset(1.08, 0.96, 1.02, 12, 0, 8), _saturation(0.95)])),
    StudioFilter('fade', 'Fade', 'Film', _chain([_contrast(0.82), _saturation(0.8), _scaleOffset(1, 1, 1, 18, 18, 18)])),
    StudioFilter('film', 'Film', 'Film', _chain([_contrast(1.1), _saturation(0.85), _scaleOffset(1.04, 1.0, 0.94, 6, 4, 10)])),
    StudioFilter('vintage', 'Vintage', 'Film', _chain([_saturation(0.6), _scaleOffset(1.1, 1.0, 0.8, 20, 10, -4), _contrast(0.92)])),
    StudioFilter('teal', 'Teal & Gold', 'Film', _chain([_scaleOffset(1.1, 1.0, 0.92, 4, 0, 6), _contrast(1.12), _saturation(1.15)])),
    StudioFilter('landscape', 'Lush', 'Landscape', _chain([_scaleOffset(0.96, 1.1, 1.02, -4, 6, 2), _saturation(1.3)])),
    StudioFilter('sky', 'Sky', 'Landscape', _chain([_scaleOffset(0.94, 1.0, 1.14, 0, 4, 16), _contrast(1.08)])),
    StudioFilter('dusk', 'Dusk', 'Landscape', _chain([_scaleOffset(1.1, 0.94, 1.04, 8, -4, 10), _contrast(1.1)])),
    StudioFilter('mono', 'Mono', 'B&W', _saturation(0)),
    StudioFilter('noir', 'Noir', 'B&W', _chain([_saturation(0), _contrast(1.4), _scaleOffset(1, 1, 1, -10, -10, -10)])),
    StudioFilter('silver', 'Silver', 'B&W', _chain([_saturation(0), _contrast(0.9), _scaleOffset(1, 1, 1, 16, 16, 16)])),
  ];

  static StudioFilter filterById(String id) => filters.firstWhere((f) => f.id == id, orElse: () => filters.first);

  static List<double> adjustMatrix(StudioAdjust a) {
    final steps = <List<double>>[];
    if (a.exposure != 0) {
      final e = math.pow(2, a.exposure).toDouble();
      steps.add(_scaleOffset(e, e, e, 0, 0, 0));
    }
    if (a.brightness != 0) {
      final o = a.brightness * 70;
      steps.add(_scaleOffset(1, 1, 1, o, o, o));
    }
    if (a.contrast != 0) steps.add(_contrast(1 + a.contrast * 0.6));
    if (a.saturation != 0) steps.add(_saturation(1 + a.saturation));
    if (a.warmth != 0) steps.add(_scaleOffset(1, 1, 1, a.warmth * 24, a.warmth * 4, -a.warmth * 24));
    if (a.tint != 0) steps.add(_scaleOffset(1, 1, 1, a.tint * 14, -a.tint * 18, a.tint * 14));
    if (a.fade != 0) {
      final f = a.fade.clamp(0.0, 1.0);
      steps.add(_contrast(1 - f * 0.35));
      steps.add(_scaleOffset(1, 1, 1, f * 26, f * 26, f * 26));
    }
    return _chain(steps);
  }

  /// Filter (at its intensity) followed by the manual adjustments.
  static List<double> clipMatrix(StudioClip clip) {
    final filter = lerp(identity, filterById(clip.filterId).matrix, clip.filterIntensity.clamp(0.0, 1.0));
    return multiply(adjustMatrix(clip.adjust), filter);
  }

  static bool isIdentity(List<double> m) {
    for (var i = 0; i < 20; i++) {
      if ((m[i] - identity[i]).abs() > 1e-4) return false;
    }
    return true;
  }
}
