import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../models/studio_project.dart';
import 'studio_media.dart';
import 'studio_project_store.dart';

/// One face, normalized to its frame (0..1, top-left origin).
class StudioFace {
  final double cx, cy, rx, ry;
  final double lex, ley, rex, rey;
  final double nx, ny;
  final double mx, my, mw;

  const StudioFace(this.cx, this.cy, this.rx, this.ry, this.lex, this.ley, this.rex, this.rey, this.nx, this.ny, this.mx, this.my, this.mw);

  List<double> get values => [cx, cy, rx, ry, lex, ley, rex, rey, nx, ny, mx, my, mw];
  factory StudioFace.fromValues(List<double> v) =>
      StudioFace(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12]);

  /// Maps a face from the source frame into the clip's frame (crop, flip,
  /// then clockwise quarter turns), the space the retouch shader runs in.
  StudioFace toClipFrame(StudioClip c) {
    final cw = math.max(0.0001, c.crop.r - c.crop.l), ch = math.max(0.0001, c.crop.b - c.crop.t);
    (double, double) pt(double u, double v) {
      var x = (u - c.crop.l) / cw, y = (v - c.crop.t) / ch;
      if (c.flipH) x = 1 - x;
      if (c.flipV) y = 1 - y;
      switch ((c.rotation ~/ 90) % 4) {
        case 1:
          return (1 - y, x);
        case 2:
          return (1 - x, 1 - y);
        case 3:
          return (y, 1 - x);
      }
      return (x, y);
    }

    final turned = (c.rotation ~/ 90) % 2 == 1;
    final (a, b) = pt(cx, cy);
    final (l1, l2) = pt(lex, ley);
    final (r1, r2) = pt(rex, rey);
    final (n1, n2) = pt(nx, ny);
    final (m1, m2) = pt(mx, my);
    final rxn = rx / cw, ryn = ry / ch, mwn = mw / cw;
    return StudioFace(a, b, turned ? ryn : rxn, turned ? rxn : ryn, l1, l2, r1, r2, n1, n2, m1, m2, turned ? mw / ch : mwn);
  }

  /// 16 shader floats: [valid, cx, cy, rx] [ry, lex, ley, rex] [rey, nx, ny, mx] [my, mw, 0, 0].
  List<double> get shader => [1, cx, cy, rx, ry, lex, ley, rex, rey, nx, ny, mx, my, mw, 0, 0];
}

/// Faces found in a source file over time (source ms, up to two faces each).
class StudioFaceTrack {
  final List<int> timesMs;
  final List<List<StudioFace>> faces;
  const StudioFaceTrack(this.timesMs, this.faces);

  bool get hasFaces => faces.any((f) => f.isNotEmpty);

  Map<String, dynamic> toJson() => {
        't': timesMs,
        'f': [
          for (final list in faces) [for (final f in list) f.values],
        ],
      };

  factory StudioFaceTrack.fromJson(Map<String, dynamic> m) => StudioFaceTrack(
        (m['t'] as List).map((e) => (e as num).toInt()).toList(),
        [
          for (final list in (m['f'] as List))
            [for (final f in (list as List)) StudioFace.fromValues((f as List).map((e) => (e as num).toDouble()).toList())],
        ],
      );
}

/// Finds faces (ML Kit, on device) for the retouch tools and turns them into
/// shader data for the preview and the export.
class StudioFaceTracker {
  StudioFaceTracker._();

  static final Map<String, StudioFaceTrack> _cache = {};

  static String _key(StudioClip c) => '${c.path}|${c.isImage ? 0 : c.startMs}|${c.isImage ? 0 : c.endMs}';

  /// Cached track for [c], if it was analysed already.
  static StudioFaceTrack? cached(StudioClip c) => _cache[_key(c)];

  static Future<File> _disk(StudioClip c) async {
    final dir = await StudioProjectStore.dir('faces');
    final h = _key(c).hashCode.toUnsigned(32).toRadixString(16);
    return File('${dir.path}/$h.json');
  }

  /// Faces in [c] (every ~200 ms of video, at most 240 frames). Cached in
  /// memory and on disk.
  static Future<StudioFaceTrack> track(StudioClip c, {void Function(double progress)? onProgress}) async {
    final key = _key(c);
    final hit = _cache[key];
    if (hit != null) return hit;
    final file = await _disk(c);
    if (await file.exists()) {
      try {
        final t = StudioFaceTrack.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
        return _cache[key] = t;
      } catch (_) {}
    }
    final detector = FaceDetector(
      options: FaceDetectorOptions(enableLandmarks: true, performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.08),
    );
    try {
      final times = <int>[];
      final paths = <String>[];
      if (c.isImage) {
        times.add(0);
        paths.add(c.path);
      } else {
        final span = math.max(1, c.endMs - c.startMs);
        final step = math.max(200, (span / 240).ceil());
        for (var t = c.startMs; t <= c.endMs; t += step) {
          times.add(t);
        }
        final dir = await StudioProjectStore.dir('faces/frames');
        paths.addAll(await OneovaMediaEngine.frames(c.path, timesMs: times, outDir: dir.path, maxSide: 640));
      }
      final faces = <List<StudioFace>>[];
      for (var i = 0; i < paths.length; i++) {
        onProgress?.call(i / paths.length);
        if (paths[i].isEmpty) {
          faces.add(const []);
          continue;
        }
        faces.add(await _detect(detector, paths[i]));
      }
      final t = StudioFaceTrack(times, faces);
      _cache[key] = t;
      try {
        await file.writeAsString(jsonEncode(t.toJson()));
      } catch (_) {}
      return t;
    } finally {
      await detector.close();
    }
  }

  static Future<List<StudioFace>> _detect(FaceDetector detector, String path) async {
    final (w, h) = await StudioMedia.imageSize(path);
    if (w <= 0 || h <= 0) return const [];
    final found = await detector.processImage(InputImage.fromFilePath(path));
    found.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
    final out = <StudioFace>[];
    for (final f in found.take(2)) {
      final box = f.boundingBox;
      Offset lm(FaceLandmarkType t, Offset fallback) {
        final p = f.landmarks[t]?.position;
        return p == null ? fallback : Offset(p.x.toDouble(), p.y.toDouble());
      }

      final le = lm(FaceLandmarkType.leftEye, Offset(box.left + box.width * 0.68, box.top + box.height * 0.38));
      final re = lm(FaceLandmarkType.rightEye, Offset(box.left + box.width * 0.32, box.top + box.height * 0.38));
      final nose = lm(FaceLandmarkType.noseBase, Offset(box.center.dx, box.top + box.height * 0.62));
      final ml = lm(FaceLandmarkType.leftMouth, Offset(box.left + box.width * 0.64, box.top + box.height * 0.78));
      final mr = lm(FaceLandmarkType.rightMouth, Offset(box.left + box.width * 0.36, box.top + box.height * 0.78));
      final mb = lm(FaceLandmarkType.bottomMouth, Offset(box.center.dx, box.top + box.height * 0.82));
      final mx = (ml.dx + mr.dx) / 2, my = (ml.dy + mr.dy + mb.dy) / 3;
      out.add(StudioFace(
        box.center.dx / w,
        box.center.dy / h,
        box.width / 2 / w,
        box.height / 2 / h,
        le.dx / w,
        le.dy / h,
        re.dx / w,
        re.dy / h,
        nose.dx / w,
        nose.dy / h,
        mx / w,
        my / h,
        (ml.dx - mr.dx).abs() / 2 / w,
      ));
    }
    out.sort((a, b) => a.cx.compareTo(b.cx));
    return out;
  }

  /// 32 shader floats (two faces) for [c] at clip-local output [localMs].
  static List<double> shaderAt(StudioClip c, StudioFaceTrack? t, int localMs) {
    final out = List<double>.filled(32, 0);
    if (t == null || t.timesMs.isEmpty) return out;
    final src = c.isImage ? 0 : c.startMs + localMs * c.speed;
    var i = 0;
    while (i < t.timesMs.length - 1 && t.timesMs[i + 1] <= src) {
      i++;
    }
    final j = math.min(i + 1, t.timesMs.length - 1);
    final span = (t.timesMs[j] - t.timesMs[i]).toDouble();
    final k = j == i || span <= 0 ? 0.0 : ((src - t.timesMs[i]) / span).clamp(0.0, 1.0);
    for (var f = 0; f < 2; f++) {
      final a = f < t.faces[i].length ? t.faces[i][f].toClipFrame(c).shader : null;
      final b = f < t.faces[j].length ? t.faces[j][f].toClipFrame(c).shader : null;
      final use = a == null ? b : (b == null ? a : [for (var n = 0; n < 16; n++) a[n] + (b[n] - a[n]) * k]);
      if (use == null) continue;
      for (var n = 0; n < 16; n++) {
        out[f * 16 + n] = use[n];
      }
    }
    return out;
  }

  /// Native export payload: faces keyed in clip-local output ms.
  static Map<String, Object?> exportSpec(StudioClip c, StudioFaceTrack? t) {
    final keys = <int>[];
    final faces = <double>[];
    if (t != null) {
      for (var i = 0; i < t.timesMs.length; i++) {
        final local = c.isImage ? 0 : ((t.timesMs[i] - c.startMs) / c.speed).round();
        if (local < 0) continue;
        keys.add(local);
        final rec = List<double>.filled(32, 0);
        for (var f = 0; f < math.min(2, t.faces[i].length); f++) {
          final s = t.faces[i][f].toClipFrame(c).shader;
          for (var n = 0; n < 16; n++) {
            rec[f * 16 + n] = s[n];
          }
        }
        faces.addAll(rec);
      }
    }
    return {
      'params': Float32List.fromList(c.retouch.params),
      'keysMs': keys,
      'faces': Float32List.fromList(faces),
    };
  }

  static Future<ui.FragmentProgram?>? _program;
  static Future<ui.FragmentProgram?> program() => _program ??= ui.FragmentProgram.fromAsset('shaders/studio_retouch.frag')
      .then<ui.FragmentProgram?>((p) => p, onError: (Object e) {
        debugPrint('[StudioFaces] shader load failed: $e');
        _program = null;
        return null;
      });

  /// Writes params + faces into [shader] (float index 2 onward).
  static void bind(ui.FragmentShader shader, StudioRetouch r, List<double> faces) {
    final p = r.params;
    final values = [...p, 0.0, 0.0, ...faces];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(2 + i, values[i]);
    }
  }
}

/// Preview of a clip's retouch (same shader as the export).
class StudioRetouchFilter extends StatefulWidget {
  final StudioClip clip;
  final int localMs;
  final Widget child;
  const StudioRetouchFilter({super.key, required this.clip, required this.localMs, required this.child});

  @override
  State<StudioRetouchFilter> createState() => _StudioRetouchFilterState();
}

class _StudioRetouchFilterState extends State<StudioRetouchFilter> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      StudioFaceTracker.program().then((p) {
        if (mounted && p != null) setState(() => _shader = p.fragmentShader());
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    final c = widget.clip;
    if (shader == null || c.retouch.isIdentity) return widget.child;
    StudioFaceTracker.bind(shader, c.retouch, StudioFaceTracker.shaderAt(c, StudioFaceTracker.cached(c), widget.localMs));
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(shader), child: widget.child);
  }
}
