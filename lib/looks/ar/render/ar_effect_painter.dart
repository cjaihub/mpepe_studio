import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/ar_effect.dart';
import '../tracking/ar_tracking_models.dart';

/// Where a world-anchored sticker sits, in normalized viewfinder space.
@immutable
class ArWorldPlacement {
  final Offset position;
  final double scale;
  final double rotation;

  const ArWorldPlacement({
    this.position = const Offset(0.5, 0.45),
    this.scale = 1,
    this.rotation = 0,
  });

  ArWorldPlacement copyWith({Offset? position, double? scale, double? rotation}) =>
      ArWorldPlacement(
        position: position ?? this.position,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
      );
}

/// Draws tracked sprites, makeup and world stickers for one frame.
///
/// Sprites follow the head in 3D: they are rolled with the eye line and
/// rotated in perspective by the measured yaw and pitch, so glasses, hats
/// and beards turn with the face instead of sliding flat across it.
class ArEffectPainter extends CustomPainter {
  final ArFrame? frame;
  final List<ArEffect> effects;
  final Map<String, ui.Image> images;
  final Map<String, ArWorldPlacement> world;

  ArEffectPainter({
    required this.frame,
    required this.effects,
    required this.images,
    required this.world,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintEffects(canvas, size, frame, effects, images, world);
  }

  /// Shared with the photo compositor so stills match the preview.
  static void paintEffects(
    Canvas canvas,
    Size size,
    ArFrame? frame,
    List<ArEffect> effects,
    Map<String, ui.Image> images,
    Map<String, ArWorldPlacement> world,
  ) {
    final faces = frame?.faces ?? const <TrackedFace>[];
    // Makeup first so sprites (glasses, masks) sit on top of it.
    for (final e in effects.where((e) => e.kind == ArEffectKind.makeup)) {
      for (final f in faces) {
        _paintMakeup(canvas, size, f, e.makeup);
      }
    }
    for (final e in effects.where((e) => e.kind == ArEffectKind.sprite)) {
      final img = images[e.id];
      if (img == null) continue;
      if (e.isWorld) {
        _paintWorld(canvas, size, img, world[e.id] ?? const ArWorldPlacement(), e.scale);
        continue;
      }
      if (e.anchor == ArAnchor.torso) {
        if (faces.isNotEmpty || frame?.body != null) {
          _paintSprite(canvas, size, img, e, faces.isEmpty ? null : faces.first, frame?.body);
        }
        continue;
      }
      for (final f in faces) {
        _paintSprite(canvas, size, img, e, f, null);
      }
    }
  }

  static void _paintWorld(Canvas canvas, Size size, ui.Image img, ArWorldPlacement p, double scale) {
    final w = size.width * 0.42 * scale * p.scale;
    final h = w * img.height / img.width;
    canvas.save();
    canvas.translate(p.position.dx * size.width, p.position.dy * size.height);
    canvas.rotate(p.rotation);
    _drawImage(canvas, img, Rect.fromCenter(center: Offset.zero, width: w, height: h));
    canvas.restore();
  }

  static void _paintSprite(
    Canvas canvas,
    Size size,
    ui.Image img,
    ArEffect e,
    TrackedFace? f,
    TrackedBody? body,
  ) {
    Offset px(Offset n) => Offset(n.dx * size.width, n.dy * size.height);

    late Offset center;
    late double refW;
    late double roll;
    var yaw = 0.0;
    var pitch = 0.0;
    var baseWidth = 1.0;

    if (e.anchor == ArAnchor.torso && body != null) {
      refW = body.shoulderWidth * size.width;
      roll = body.roll;
      final down = Offset(-math.sin(roll), math.cos(roll));
      center = px(body.shouldersCenter) + down * (refW * 0.55);
      baseWidth = 1.45;
    } else {
      final face = f!;
      refW = face.width * size.width;
      roll = face.roll;
      yaw = face.yaw.clamp(-0.9, 0.9);
      pitch = face.pitch.clamp(-0.7, 0.7);
      final up = Offset(math.sin(roll), -math.cos(roll));
      switch (e.anchor) {
        case ArAnchor.eyes:
          center = px(face.eyesCenter);
          baseWidth = 1.0;
        case ArAnchor.forehead:
          center = px(face.forehead) + up * (refW * 0.05);
          baseWidth = 0.8;
        case ArAnchor.headTop:
          center = px(face.forehead) + up * (refW * 0.42);
          baseWidth = 1.25;
        case ArAnchor.hair:
          center = px(face.forehead) + up * (refW * 0.1);
          baseWidth = 1.6;
        case ArAnchor.nose:
          center = px(face.noseTip);
          baseWidth = 0.4;
        case ArAnchor.mouth:
          center = px(face.mouth);
          baseWidth = 0.5;
        case ArAnchor.chin:
          center = Offset.lerp(px(face.mouth), px(face.chin), 0.45)!;
          baseWidth = 0.95;
        case ArAnchor.face:
          center = Offset.lerp(px(face.forehead), px(face.chin), 0.5)!;
          baseWidth = 1.15;
        case ArAnchor.neck:
          center = px(face.chin) - up * (refW * 0.35);
          baseWidth = 0.8;
        case ArAnchor.torso:
          // No pose yet: estimate the chest from the face.
          center = px(face.chin) - up * (refW * 1.5);
          baseWidth = 2.6;
          yaw = 0;
          pitch = 0;
        case ArAnchor.world:
        case ArAnchor.screen:
          return;
      }
    }

    final right = Offset(math.cos(roll), math.sin(roll));
    final down = Offset(-math.sin(roll), math.cos(roll));
    center = center + right * (e.offsetX * refW) + down * (e.offsetY * refW);
    final w = refW * baseWidth * e.scale;
    if (w < 4) return;
    final h = w * img.height / img.width;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(roll);
    final m = Matrix4.identity()
      ..setEntry(3, 2, 1 / (refW * 2.4))
      ..rotateX(pitch)
      ..rotateY(-yaw);
    canvas.transform(m.storage);
    _drawImage(canvas, img, Rect.fromCenter(center: Offset.zero, width: w, height: h));
    canvas.restore();
  }

  static void _drawImage(Canvas canvas, ui.Image img, Rect dst) {
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  static Path _path(List<Offset> pts, Size size, {bool close = true}) {
    final p = Path();
    if (pts.isEmpty) return p;
    p.moveTo(pts.first.dx * size.width, pts.first.dy * size.height);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx * size.width, o.dy * size.height);
    }
    if (close) p.close();
    return p;
  }

  static void _paintMakeup(Canvas canvas, Size size, TrackedFace f, ArMakeup m) {
    final refW = f.width * size.width;
    if (refW < 8) return;

    // Lips: outer ring minus inner ring so an open mouth stays clear.
    final outer = f.contours[ArContour.lipsOuter] ?? const [];
    if (m.lipOpacity > 0 && outer.length > 6) {
      final lips = _path(outer, size)..fillType = PathFillType.evenOdd;
      final inner = f.contours[ArContour.lipsInner] ?? const [];
      if (inner.length > 6) lips.addPath(_path(inner, size), Offset.zero);
      final soft = MaskFilter.blur(BlurStyle.normal, refW * 0.006);
      canvas.drawPath(
        lips,
        Paint()
          ..color = m.lipColor.withValues(alpha: m.lipOpacity * 0.55)
          ..blendMode = BlendMode.multiply
          ..maskFilter = soft,
      );
      canvas.drawPath(
        lips,
        Paint()
          ..color = m.lipColor.withValues(alpha: m.lipOpacity * 0.35)
          ..maskFilter = soft,
      );
    }

    if (m.blushOpacity > 0) {
      for (final c in [f.leftBlush, f.rightBlush]) {
        final o = Offset(c.dx * size.width, c.dy * size.height);
        final r = refW * 0.17;
        canvas.drawCircle(
          o,
          r,
          Paint()
            ..shader = ui.Gradient.radial(o, r, [
              m.blushColor.withValues(alpha: m.blushOpacity * 0.5),
              m.blushColor.withValues(alpha: 0),
            ]),
        );
      }
    }

    for (final key in [ArContour.leftEye, ArContour.rightEye]) {
      final eye = f.contours[key] ?? const [];
      if (eye.length < 6) continue;
      final path = _path(eye, size);
      final bounds = path.getBounds();
      if (m.eyeOpacity > 0) {
        // Tinted iris: a disc at the eye center, clipped to the eye opening.
        canvas.save();
        canvas.clipPath(path);
        final r = bounds.height * 0.62;
        canvas.drawCircle(
          bounds.center,
          r,
          Paint()
            ..shader = ui.Gradient.radial(bounds.center, r, [
              m.eyeColor.withValues(alpha: m.eyeOpacity * 0.8),
              m.eyeColor.withValues(alpha: m.eyeOpacity * 0.5),
              m.eyeColor.withValues(alpha: 0),
            ], [0, 0.7, 1])
            ..blendMode = BlendMode.color,
        );
        canvas.restore();
      }
      if (m.eyeGlow > 0) {
        final glow = Paint()
          ..color = m.eyeColor.withValues(alpha: 0.9 * m.eyeGlow)
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.04);
        canvas.drawCircle(bounds.center, bounds.width * 0.45, glow);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = refW * 0.012
            ..color = m.eyeColor.withValues(alpha: m.eyeGlow)
            ..blendMode = BlendMode.plus
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.01),
        );
      }
      if (m.linerOpacity > 0) {
        final cy = bounds.center.dy / size.height;
        final upper = eye.where((p) => p.dy <= cy).toList()..sort((a, b) => a.dx.compareTo(b.dx));
        if (upper.length > 2) {
          canvas.drawPath(
            _path(upper, size, close: false),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = refW * 0.014
              ..color = m.linerColor.withValues(alpha: m.linerOpacity),
          );
        }
      }
    }

    if (m.browOpacity > 0) {
      for (final key in [ArContour.leftBrow, ArContour.rightBrow]) {
        final brow = f.contours[key] ?? const [];
        if (brow.length < 3) continue;
        canvas.drawPath(
          _path(brow, size, close: false),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = refW * 0.03
            ..color = m.browColor.withValues(alpha: m.browOpacity * 0.6)
            ..blendMode = BlendMode.multiply
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.006),
        );
      }
    }
  }

  @override
  bool shouldRepaint(ArEffectPainter old) =>
      old.frame != frame || old.effects != effects || old.images != images || old.world != world;
}
