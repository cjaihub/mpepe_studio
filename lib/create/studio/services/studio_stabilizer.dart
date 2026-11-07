import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import 'studio_project_store.dart';

/// Camera path of a clip's source range (source ms, cumulative x/y shift as
/// fractions of the frame).
class StudioMotion {
  final List<int> timesMs;
  final List<double> x;
  final List<double> y;
  const StudioMotion(this.timesMs, this.x, this.y);

  Map<String, dynamic> toJson() => {'t': timesMs, 'x': x, 'y': y};
  factory StudioMotion.fromJson(Map<String, dynamic> m) => StudioMotion(
        (m['t'] as List).map((e) => (e as num).toInt()).toList(),
        (m['x'] as List).map((e) => (e as num).toDouble()).toList(),
        (m['y'] as List).map((e) => (e as num).toDouble()).toList(),
      );
}

/// Correction to apply at clip-local output times.
class StudioStabilizePlan {
  final double zoom;
  final List<int> keysMs;
  final List<double> dx;
  final List<double> dy;
  const StudioStabilizePlan(this.zoom, this.keysMs, this.dx, this.dy);

  (double, double) at(int localMs) {
    if (keysMs.isEmpty) return (0, 0);
    var i = 0;
    while (i < keysMs.length - 1 && keysMs[i + 1] <= localMs) {
      i++;
    }
    final j = math.min(i + 1, keysMs.length - 1);
    final span = (keysMs[j] - keysMs[i]).toDouble();
    final k = j == i || span <= 0 ? 0.0 : ((localMs - keysMs[i]) / span).clamp(0.0, 1.0);
    return (dx[i] + (dx[j] - dx[i]) * k, dy[i] + (dy[j] - dy[i]) * k);
  }

  Map<String, Object?> toExport() => {'zoom': zoom, 'keysMs': keysMs, 'x': dx, 'y': dy};
}

/// Stabilize: measures the camera path on the device (native block matching)
/// and smooths it; the preview and the Media3 export apply the same shifts.
class StudioStabilizer {
  StudioStabilizer._();

  static final Map<String, StudioMotion> _cache = {};

  static String _key(StudioClip c) => '${c.path}|${c.startMs}|${c.endMs}';

  static StudioMotion? cached(StudioClip c) => _cache[_key(c)];

  static Future<StudioMotion> analyse(StudioClip c) async {
    final key = _key(c);
    final hit = _cache[key];
    if (hit != null) return hit;
    final dir = await StudioProjectStore.dir('motion');
    final file = File('${dir.path}/${key.hashCode.toUnsigned(32).toRadixString(16)}.json');
    if (await file.exists()) {
      try {
        return _cache[key] = StudioMotion.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    final (t, x, y) = await OneovaMediaEngine.motion(c.path, startMs: c.startMs, endMs: c.endMs);
    final m = StudioMotion(t, x, y);
    _cache[key] = m;
    try {
      await file.writeAsString(jsonEncode(m.toJson()));
    } catch (_) {}
    return m;
  }

  /// Plan for [c] at its stabilize strength, or null when off / not analysed.
  static StudioStabilizePlan? plan(StudioClip c, [StudioMotion? motion]) {
    final m = motion ?? cached(c);
    if (c.isImage || c.stabilize <= 0 || m == null || m.timesMs.length < 2) return null;
    final s = c.stabilize.clamp(0.0, 1.0);
    final zoom = 1.04 + 0.1 * s;
    final margin = (zoom - 1) / (2 * zoom);
    // Gaussian smoothing of the path; window grows with strength.
    final stepMs = (m.timesMs.last - m.timesMs.first) / math.max(1, m.timesMs.length - 1);
    final sigma = math.max(1.0, (400 + 1600 * s) / math.max(1, stepMs) / 2);
    final radius = (sigma * 2.5).ceil();
    List<double> smooth(List<double> v) => [
          for (var i = 0; i < v.length; i++)
            () {
              var sum = 0.0, w = 0.0;
              for (var k = -radius; k <= radius; k++) {
                final j = (i + k).clamp(0, v.length - 1);
                final g = math.exp(-(k * k) / (2 * sigma * sigma));
                sum += v[j] * g;
                w += g;
              }
              return sum / w;
            }(),
        ];
    final sx = smooth(m.x), sy = smooth(m.y);
    return StudioStabilizePlan(
      zoom,
      [for (final t in m.timesMs) ((t - c.startMs) / c.speed).round()],
      [for (var i = 0; i < m.x.length; i++) (sx[i] - m.x[i]).clamp(-margin, margin)],
      [for (var i = 0; i < m.y.length; i++) (sy[i] - m.y[i]).clamp(-margin, margin)],
    );
  }
}
