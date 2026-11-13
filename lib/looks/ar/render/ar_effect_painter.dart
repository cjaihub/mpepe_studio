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

  /// Each tracked person wears a different face effect.
  final bool perPerson;

  ArEffectPainter({
    required this.frame,
    required this.effects,
    required this.images,
    required this.world,
    this.perPerson = false,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintEffects(canvas, size, frame, effects, images, world, perPerson: perPerson);
  }

  /// Shared with the photo compositor so stills match the preview.
  static void paintEffects(
    Canvas canvas,
    Size size,
    ArFrame? frame,
    List<ArEffect> effects,
    Map<String, ui.Image> images,
    Map<String, ArWorldPlacement> world, {
    bool perPerson = false,
  }) {
    final faces = frame?.faces ?? const <TrackedFace>[];
    // Light-aware: stickers dim in a dark room and lift in bright light so
    // they sit in the scene instead of glowing on top of it.
    _light = frame == null ? 1.0 : (0.62 + frame.light * 0.6).clamp(0.7, 1.08);
    final faceSprites = effects
        .where((e) => e.kind == ArEffectKind.sprite && !e.isWorld && e.anchor != ArAnchor.torso && images[e.id] != null)
        .toList();
    final split = perPerson && faceSprites.length > 1 && faces.length > 1;
    // Makeup first so sprites (glasses, masks) sit on top of it.
    for (final e in effects.where((e) => e.kind == ArEffectKind.makeup)) {
      for (final f in faces) {
        _paintMakeup(canvas, size, f, e.makeup);
      }
    }
    // CapCut / TikTok-style procedural VFX (body aura, cyber scanner, halo, clone, hand sparks).
    for (final e in effects.where((e) => e.kind == ArEffectKind.vfx)) {
      _paintVfx(canvas, size, e.id, faces, frame?.body);
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
      for (var i = 0; i < faces.length; i++) {
        // One effect per person: person n wears the n-th face effect.
        if (split && faceSprites[i % faceSprites.length].id != e.id) continue;
        _paintSprite(canvas, size, img, e, faces[i], null);
      }
    }
    _light = 1.0;
  }

  static double _light = 1.0;

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
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = _light == 1.0
            ? null
            : ColorFilter.matrix(<double>[_light, 0, 0, 0, 0, 0, _light, 0, 0, 0, 0, 0, _light, 0, 0, 0, 0, 0, 1, 0]),
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

  /// Skin area: the face oval minus eyes and lips (even-odd). Used for
  /// foundation and, in the viewfinder, for skin smoothing.
  static Path? skinPath(TrackedFace f, Size size) {
    final oval = f.contours[ArContour.faceOval] ?? const [];
    if (oval.length < 10) return null;
    final p = _path(oval, size)..fillType = PathFillType.evenOdd;
    for (final key in [ArContour.leftEye, ArContour.rightEye, ArContour.lipsOuter]) {
      final c = f.contours[key] ?? const [];
      if (c.length > 5) p.addPath(_path(_grow(c, 1.25), size), Offset.zero);
    }
    return p;
  }

  /// Scales a contour about its centroid (gives eyes/lips a safety margin).
  static List<Offset> _grow(List<Offset> pts, double k) {
    var cx = 0.0, cy = 0.0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    final c = Offset(cx / pts.length, cy / pts.length);
    return [for (final p in pts) c + (p - c) * k];
  }

  static Offset _px(Offset n, Size size) => Offset(n.dx * size.width, n.dy * size.height);

  /// Upper half of an eye contour, sorted along the eye line.
  static List<Offset> _upperLid(List<Offset> eye) {
    var cy = 0.0;
    for (final p in eye) {
      cy += p.dy;
    }
    cy /= eye.length;
    return eye.where((p) => p.dy <= cy).toList()..sort((a, b) => a.dx.compareTo(b.dx));
  }

  static void _paintMakeup(Canvas canvas, Size size, TrackedFace f, ArMakeup m) {
    final refW = f.width * size.width;
    if (refW < 8) return;
    final roll = f.roll;
    final up = Offset(math.sin(roll), -math.cos(roll));
    final oval = f.contours[ArContour.faceOval] ?? const [];
    final ovalPath = oval.length > 10 ? _path(oval, size) : null;

    // Foundation: an even skin tint with a feathered edge.
    if (m.foundationOpacity > 0) {
      final skin = skinPath(f, size);
      if (skin != null) {
        canvas.drawPath(
          skin,
          Paint()
            ..color = m.foundationColor.withValues(alpha: m.foundationOpacity * 0.42)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.025),
        );
      }
    }

    // Contour: shade along the jaw/temples and under the cheekbones.
    if (m.contourOpacity > 0 && ovalPath != null) {
      const shade = Color(0xFF5A3A2A);
      canvas.save();
      canvas.clipPath(ovalPath);
      canvas.drawPath(
        ovalPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = refW * 0.14
          ..color = shade.withValues(alpha: m.contourOpacity * 0.32)
          ..blendMode = BlendMode.multiply
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.05),
      );
      for (final cheek in [f.leftCheek, f.rightCheek]) {
        final c = Offset.lerp(_px(cheek, size), _px(f.mouth, size), 0.3)! - up * (refW * 0.02);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(roll + (cheek == f.leftCheek ? 0.35 : -0.35));
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: refW * 0.32, height: refW * 0.09),
          Paint()
            ..color = shade.withValues(alpha: m.contourOpacity * 0.3)
            ..blendMode = BlendMode.multiply
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.04),
        );
        canvas.restore();
      }
      canvas.restore();
    }

    // Highlight: nose bridge, cheekbones, forehead and chin.
    if (m.highlightOpacity > 0) {
      final glow = Paint()
        ..color = const Color(0xFFFFF4E6).withValues(alpha: m.highlightOpacity * 0.38)
        ..blendMode = BlendMode.screen
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.03);
      final bridgeTop = _px(f.eyesCenter, size);
      final bridgeEnd = Offset.lerp(bridgeTop, _px(f.noseTip, size), 0.8)!;
      canvas.drawLine(bridgeTop, bridgeEnd, glow..strokeWidth = refW * 0.05..strokeCap = StrokeCap.round);
      for (final b in [f.leftBlush, f.rightBlush]) {
        final eye = b == f.leftBlush ? f.leftEye : f.rightEye;
        canvas.drawCircle(Offset.lerp(_px(b, size), _px(eye, size), 0.45)!, refW * 0.06, glow);
      }
      canvas.drawCircle(_px(f.forehead, size) - up * (refW * 0.12), refW * 0.07, glow);
      canvas.drawCircle(Offset.lerp(_px(f.lowerLip, size), _px(f.chin, size), 0.65)!, refW * 0.04, glow);
    }

    // Blush.
    if (m.blushOpacity > 0) {
      for (final c in [f.leftBlush, f.rightBlush]) {
        final o = _px(c, size);
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

    // Eyes: shadow on the lid, iris tint, glow, liner with optional wing.
    final noseX = f.noseTip.dx * size.width;
    for (final key in [ArContour.leftEye, ArContour.rightEye]) {
      final eye = f.contours[key] ?? const [];
      if (eye.length < 6) continue;
      final path = _path(eye, size);
      final bounds = path.getBounds();
      final lid = _upperLid(eye).map((p) => _px(p, size)).toList();

      if (m.shadowOpacity > 0 && lid.length > 2) {
        final lift = up * (bounds.height * 1.5 + refW * 0.02);
        final shadow = Path()..moveTo(lid.first.dx, lid.first.dy);
        for (final p in lid.skip(1)) {
          shadow.lineTo(p.dx, p.dy);
        }
        for (var i = lid.length - 1; i >= 0; i--) {
          // Taper toward the corners so the lid shape stays almond.
          final t = math.sin(math.pi * i / (lid.length - 1));
          final q = lid[i] + lift * (0.35 + 0.65 * t);
          shadow.lineTo(q.dx, q.dy);
        }
        shadow.close();
        final soft = MaskFilter.blur(BlurStyle.normal, refW * 0.018);
        canvas.drawPath(
          shadow,
          Paint()
            ..color = m.shadowColor.withValues(alpha: m.shadowOpacity * 0.45)
            ..blendMode = BlendMode.multiply
            ..maskFilter = soft,
        );
        canvas.drawPath(
          shadow,
          Paint()
            ..color = m.shadowColor.withValues(alpha: m.shadowOpacity * 0.25)
            ..maskFilter = soft,
        );
      }

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
      if (m.linerOpacity > 0 && lid.length > 2) {
        final liner = Path()..moveTo(lid.first.dx, lid.first.dy);
        for (final p in lid.skip(1)) {
          liner.lineTo(p.dx, p.dy);
        }
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = refW * (0.006 + 0.02 * m.linerWidth)
          ..color = m.linerColor.withValues(alpha: m.linerOpacity);
        canvas.drawPath(liner, paint);
        if (m.linerWing > 0) {
          // The outer corner is the lid end farther from the nose.
          final outer = (lid.first.dx - noseX).abs() > (lid.last.dx - noseX).abs() ? lid.first : lid.last;
          final outward = outer == lid.first ? -1.0 : 1.0;
          final dir = Offset(math.cos(roll) * outward, math.sin(roll) * outward) * 0.85 + up * 0.5;
          final tip = outer + dir * (refW * 0.1 * m.linerWing);
          final base = outer - up * (paint.strokeWidth * 0.5);
          canvas.drawPath(
            Path()
              ..moveTo(base.dx, base.dy)
              ..lineTo(tip.dx, tip.dy)
              ..lineTo(outer.dx + up.dx * paint.strokeWidth, outer.dy + up.dy * paint.strokeWidth)
              ..close(),
            Paint()..color = m.linerColor.withValues(alpha: m.linerOpacity),
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
            ..strokeWidth = refW * (0.015 + 0.035 * m.browWidth)
            ..color = m.browColor.withValues(alpha: m.browOpacity * 0.6)
            ..blendMode = BlendMode.multiply
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.006),
        );
      }
    }

    // Lips last, so they sit over foundation; gloss adds a wet highlight.
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
      if (m.lipGloss > 0) {
        final bottom = outer.reduce((a, b) => (a - f.chin).distance < (b - f.chin).distance ? a : b);
        final c = Offset.lerp(_px(f.lowerLip, size), _px(bottom, size), 0.45)!;
        canvas.save();
        canvas.clipPath(lips);
        canvas.translate(c.dx, c.dy);
        canvas.rotate(roll);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: refW * 0.16, height: refW * 0.03),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55 * m.lipGloss)
            ..blendMode = BlendMode.screen
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.008),
        );
        canvas.restore();
      }
    }
  }

  static void _paintVfx(
    Canvas canvas,
    Size size,
    String rawId,
    List<TrackedFace> faces,
    TrackedBody? body,
  ) {
    final id = rawId.startsWith('builtin_') ? rawId.substring(8) : rawId;
    const pink = Color(0xFFFF2D87);
    const blue = Color(0xFF0C4FA8);
    const cyan = Color(0xFF38BDF8);
    Offset px(Offset n) => _px(n, size);

    switch (id) {
      case 'vfx_neon_aura':
        for (final f in faces) {
          final oval = f.contours[ArContour.faceOval] ?? const [];
          if (oval.length < 10) continue;
          final p = _path(_grow(oval, 1.08), size);
          final refW = f.width * size.width;
          canvas.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = refW * 0.045
              ..color = pink.withValues(alpha: 0.8)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.04),
          );
          canvas.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = refW * 0.014
              ..color = Colors.white,
          );
        }
        if (body != null) {
          final ls = px(body.leftShoulder);
          final rs = px(body.rightShoulder);
          final sw = math.max((rs - ls).distance, size.width * 0.15);
          final skel = Path()
            ..moveTo(ls.dx, ls.dy)
            ..lineTo(rs.dx, rs.dy);
          if (body.leftElbow != null) {
            final le = px(body.leftElbow!);
            skel.moveTo(ls.dx, ls.dy);
            skel.lineTo(le.dx, le.dy);
            if (body.leftWrist != null) {
              final lw = px(body.leftWrist!);
              skel.lineTo(lw.dx, lw.dy);
            }
          }
          if (body.rightElbow != null) {
            final re = px(body.rightElbow!);
            skel.moveTo(rs.dx, rs.dy);
            skel.lineTo(re.dx, re.dy);
            if (body.rightWrist != null) {
              final rw = px(body.rightWrist!);
              skel.lineTo(rw.dx, rw.dy);
            }
          }
          if (body.leftHip != null && body.rightHip != null) {
            final lh = px(body.leftHip!);
            final rh = px(body.rightHip!);
            skel
              ..moveTo(ls.dx, ls.dy)
              ..lineTo(lh.dx, lh.dy)
              ..lineTo(rh.dx, rh.dy)
              ..lineTo(rs.dx, rs.dy);
          }
          canvas.drawPath(
            skel,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = sw * 0.08
              ..color = blue.withValues(alpha: 0.85)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw * 0.05),
          );
          canvas.drawPath(
            skel,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = sw * 0.022
              ..color = cyan.withValues(alpha: 0.95),
          );
        }
      case 'vfx_cyber_hud':
        for (final f in faces) {
          final refW = f.width * size.width;
          if (refW < 12) continue;
          final hudStroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(refW * 0.01, 1.5)
            ..color = cyan.withValues(alpha: 0.85);
          for (final key in [
            ArContour.faceOval,
            ArContour.leftEye,
            ArContour.rightEye,
            ArContour.leftBrow,
            ArContour.rightBrow,
            ArContour.lipsOuter,
          ]) {
            final pts = f.contours[key] ?? const [];
            if (pts.length > 3) {
              canvas.drawPath(
                _path(pts, size, close: key != ArContour.leftBrow && key != ArContour.rightBrow),
                hudStroke,
              );
            }
          }
          for (final eye in [f.leftEye, f.rightEye]) {
            final ep = px(eye);
            canvas.drawCircle(
              ep,
              refW * 0.14,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(refW * 0.01, 1.5)
                ..color = pink.withValues(alpha: 0.85),
            );
            canvas.drawCircle(ep, refW * 0.025, Paint()..color = pink);
          }
        }
      case 'vfx_angel_glow':
        for (final f in faces) {
          final refW = f.width * size.width;
          final fh = px(f.forehead);
          final up = Offset(math.sin(f.roll), -math.cos(f.roll));
          final center = fh + up * (refW * 0.36);
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(f.roll);
          final halo = Rect.fromCenter(center: Offset.zero, width: refW * 0.96, height: refW * 0.26);
          canvas.drawOval(
            halo,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = refW * 0.08
              ..color = const Color(0xFFFFE57F).withValues(alpha: 0.78)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.05),
          );
          canvas.drawOval(
            halo,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = refW * 0.024
              ..color = Colors.white,
          );
          canvas.restore();
        }
      case 'vfx_soul_clone':
        for (final f in faces) {
          final oval = f.contours[ArContour.faceOval] ?? const [];
          if (oval.length < 10) continue;
          final refW = f.width * size.width;
          for (final (dx, col) in [(-refW * 0.28, pink), (refW * 0.28, blue)]) {
            canvas.save();
            canvas.translate(dx, -refW * 0.06);
            final p = _path(_grow(oval, 1.05), size);
            canvas.drawPath(
              p,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = refW * 0.03
                ..color = col.withValues(alpha: 0.75)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, refW * 0.025),
            );
            for (final key in [ArContour.leftEye, ArContour.rightEye, ArContour.lipsOuter]) {
              final c = f.contours[key] ?? const [];
              if (c.length > 4) {
                canvas.drawPath(
                  _path(c, size),
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = refW * 0.015
                    ..color = col.withValues(alpha: 0.85),
                );
              }
            }
            canvas.restore();
          }
        }
      case 'vfx_hand_sparks':
        final pts = <Offset>[
          if (body?.leftWrist != null) px(body!.leftWrist!),
          if (body?.rightWrist != null) px(body!.rightWrist!),
        ];
        if (pts.isEmpty) {
          for (final f in faces) {
            pts.add(px(f.leftEye));
            pts.add(px(f.rightEye));
          }
        }
        final r = size.width * 0.09;
        for (var i = 0; i < pts.length; i++) {
          final pt = pts[i];
          final col = i.isEven ? pink : blue;
          canvas.drawCircle(
            pt,
            r,
            Paint()
              ..shader = ui.Gradient.radial(
                pt,
                r,
                [Colors.white, col.withValues(alpha: 0.85), col.withValues(alpha: 0)],
                const [0.0, 0.45, 1.0],
              ),
          );
          canvas.drawCircle(
            pt,
            r * 0.65,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size.width * 0.008
              ..color = Colors.white,
          );
        }
    }
  }

  @override
  bool shouldRepaint(ArEffectPainter old) =>
      old.frame != frame || old.effects != effects || old.images != images || old.world != world;
}
