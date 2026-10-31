import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'ar_tracking_models.dart';

/// Maps one `frame` event from the native AR camera (`OneovaArCamera.frames`)
/// onto [ArFrame]. The native tracker already normalizes, mirrors and
/// smooths everything, so this is only unpacking plus building the mask
/// image with the same soft threshold the Dart tracker uses.
Future<ArFrame> decodeNativeArFrame(Map<Object?, Object?> e) async {
  final faces = <TrackedFace>[];
  for (final raw in (e['faces'] as List?) ?? const []) {
    final f = _face(raw as Map<Object?, Object?>);
    if (f != null) faces.add(f);
  }
  return ArFrame(
    faces: faces,
    body: _body(e['body']),
    mask: await _mask(e['mask']),
    timestampMs: (e['t'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
  );
}

TrackedFace? _face(Map<Object?, Object?> m) {
  final a = m['a'];
  final pose = m['pose'];
  if (a is! Float32List || a.length < 24 || pose is! Float32List || pose.length < 3) return null;
  Offset p(int i) => Offset(a[i * 2], a[i * 2 + 1]);

  final contours = <ArContour, List<Offset>>{};
  final c = (m['c'] as Map?) ?? const {};
  for (final key in ArContour.values) {
    final pts = c[key.name];
    if (pts is! Float32List) continue;
    contours[key] = [for (var i = 0; i + 1 < pts.length; i += 2) Offset(pts[i], pts[i + 1])];
  }

  return TrackedFace(
    leftEye: p(0),
    rightEye: p(1),
    noseTip: p(2),
    forehead: p(3),
    chin: p(4),
    mouth: p(5),
    upperLip: p(6),
    lowerLip: p(7),
    leftCheek: p(8),
    rightCheek: p(9),
    leftBlush: p(10),
    rightBlush: p(11),
    roll: pose[0],
    yaw: pose[1],
    pitch: pose[2],
    contours: contours,
  );
}

TrackedBody? _body(Object? raw) {
  if (raw is! Float32List || raw.length < 8) return null;
  Offset? p(int i) => raw[i].isNaN ? null : Offset(raw[i], raw[i + 1]);
  return TrackedBody(
    leftShoulder: Offset(raw[0], raw[1]),
    rightShoulder: Offset(raw[2], raw[3]),
    leftHip: p(4),
    rightHip: p(6),
  );
}

Future<PersonMask?> _mask(Object? raw) async {
  if (raw is! Map) return null;
  final w = (raw['w'] as num?)?.toInt() ?? 0;
  final h = (raw['h'] as num?)?.toInt() ?? 0;
  final bytes = raw['c'];
  if (w <= 0 || h <= 0 || bytes is! Uint8List || bytes.length < w * h) return null;

  final conf = Float32List(w * h);
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final v = bytes[i] / 255;
    conf[i] = v;
    // Soft threshold so edges stay feathered but the background drops out.
    final a = ((v - 0.35) / 0.4).clamp(0.0, 1.0);
    final o = i * 4;
    rgba[o] = 255;
    rgba[o + 1] = 255;
    rgba[o + 2] = 255;
    rgba[o + 3] = (a * a * (3 - 2 * a) * 255).round();
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
  return PersonMask(image: await completer.future, width: w, height: h, confidences: conf);
}
