import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Vector artwork for the built-in AR effects. Each piece is drawn in code
/// into a transparent bitmap at runtime, so built-in effects need no catalog
/// download and render the same in the preview, photos and recorded video.
///
/// Coordinates are fractions of the canvas width ([u]) so every piece scales.
typedef ArtPainter = void Function(Canvas c, Size s);

class BuiltInArt {
  BuiltInArt._();

  static final Map<String, Future<ui.Image>> _cache = {};

  /// Renders [paint] into a transparent image, [width] px wide.
  static Future<ui.Image> render(String key, ArtPainter paint, double aspect, {int width = 512}) {
    return _cache.putIfAbsent('$key@$width', () async {
      final w = width.toDouble();
      final h = (w * aspect).roundToDouble();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
      paint(canvas, Size(w, h));
      return rec.endRecording().toImage(w.toInt(), h.toInt());
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static Paint fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  static Paint stroke(Color c, double width) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  static Paint glow(Color c, double sigma) => Paint()
    ..color = c
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

  static Path heart(Offset c, double r) {
    final p = Path();
    p.moveTo(c.dx, c.dy + r * 0.9);
    p.cubicTo(c.dx - r * 1.4, c.dy, c.dx - r * 0.9, c.dy - r * 1.1, c.dx, c.dy - r * 0.35);
    p.cubicTo(c.dx + r * 0.9, c.dy - r * 1.1, c.dx + r * 1.4, c.dy, c.dx, c.dy + r * 0.9);
    p.close();
    return p;
  }

  static Path star(Offset c, double r, {int points = 5, double inner = 0.45, double rotation = -math.pi / 2}) {
    final p = Path();
    for (var i = 0; i < points * 2; i++) {
      final rr = i.isEven ? r : r * inner;
      final a = rotation + i * math.pi / points;
      final o = c + Offset(math.cos(a), math.sin(a)) * rr;
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p..close();
  }

  static Shader linear(Rect r, List<Color> colors, {bool vertical = true}) => ui.Gradient.linear(
        vertical ? r.topCenter : r.centerLeft,
        vertical ? r.bottomCenter : r.centerRight,
        colors,
        [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)],
      );

  /// Draws [draw] for the left side and its mirror for the right side.
  static void mirrored(Canvas c, Size s, void Function(Canvas c) draw) {
    draw(c);
    c.save();
    c.translate(s.width, 0);
    c.scale(-1, 1);
    draw(c);
    c.restore();
  }

  // ── Glasses (eyes anchor, aspect 0.36; lens centers at 0.5 ± 0.2) ──────

  static void roundGlasses(Canvas c, Size s) {
    final w = s.width;
    final cy = s.height * 0.5;
    final r = w * 0.13;
    final frame = stroke(const Color(0xFFC9A24A), w * 0.012);
    final lens = fill(const Color(0x22B8D8F0));
    for (final x in [0.3, 0.7]) {
      c.drawCircle(Offset(w * x, cy), r, lens);
      c.drawCircle(Offset(w * x, cy), r, frame);
    }
    c.drawArc(Rect.fromCenter(center: Offset(w * 0.5, cy), width: w * 0.14, height: w * 0.08), math.pi, math.pi, false, frame);
    c.drawLine(Offset(w * 0.17, cy - r * 0.2), Offset(w * 0.02, cy - r * 0.35), frame);
    c.drawLine(Offset(w * 0.83, cy - r * 0.2), Offset(w * 0.98, cy - r * 0.35), frame);
  }

  static void aviators(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    Path lens(double cx) {
      final p = Path();
      p.moveTo(cx - w * 0.15, h * 0.28);
      p.quadraticBezierTo(cx, h * 0.2, cx + w * 0.15, h * 0.28);
      p.quadraticBezierTo(cx + w * 0.17, h * 0.78, cx + w * 0.02, h * 0.86);
      p.quadraticBezierTo(cx - w * 0.14, h * 0.86, cx - w * 0.15, h * 0.28);
      return p..close();
    }

    final frame = stroke(const Color(0xFFD4AF37), w * 0.01);
    for (final cx in [w * 0.3, w * 0.7]) {
      final p = lens(cx);
      c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xE6202A36), Color(0xB3546A7E)]));
      c.drawPath(p, frame);
      c.drawLine(Offset(cx - w * 0.08, h * 0.38), Offset(cx - w * 0.02, h * 0.33), stroke(const Color(0x66FFFFFF), w * 0.012));
    }
    c.drawLine(Offset(w * 0.45, h * 0.3), Offset(w * 0.55, h * 0.3), frame);
    c.drawLine(Offset(w * 0.44, h * 0.38), Offset(w * 0.56, h * 0.38), frame);
    c.drawLine(Offset(w * 0.15, h * 0.3), Offset(w * 0.02, h * 0.28), frame);
    c.drawLine(Offset(w * 0.85, h * 0.3), Offset(w * 0.98, h * 0.28), frame);
  }

  static void catEye(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      final p = Path()
        ..moveTo(w * 0.08, h * 0.2)
        ..quadraticBezierTo(w * 0.28, h * 0.22, w * 0.44, h * 0.38)
        ..quadraticBezierTo(w * 0.44, h * 0.82, w * 0.28, h * 0.84)
        ..quadraticBezierTo(w * 0.15, h * 0.84, w * 0.14, h * 0.5)
        ..close();
      c.drawPath(p, fill(const Color(0x40FFB6D9)));
      c.drawPath(p, stroke(const Color(0xFFFF2D87), w * 0.022));
      c.drawCircle(Offset(w * 0.1, h * 0.22), w * 0.012, fill(Colors.white));
    });
    c.drawLine(Offset(w * 0.44, h * 0.42), Offset(w * 0.56, h * 0.42), stroke(const Color(0xFFFF2D87), w * 0.016));
  }

  static void heartShades(Canvas c, Size s) {
    final w = s.width;
    final cy = s.height * 0.52;
    for (final x in [0.3, 0.7]) {
      final p = heart(Offset(w * x, cy), w * 0.13);
      c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xF0FF4F9A), Color(0xD9B0105A)]));
      c.drawPath(p, stroke(const Color(0xFFFF2D87), w * 0.012));
      c.drawCircle(Offset(w * (x - 0.05), cy - w * 0.04), w * 0.018, fill(const Color(0x99FFFFFF)));
    }
    c.drawLine(Offset(w * 0.42, cy - w * 0.04), Offset(w * 0.58, cy - w * 0.04), stroke(const Color(0xFFFF2D87), w * 0.014));
  }

  static void starShades(Canvas c, Size s) {
    final w = s.width;
    final cy = s.height * 0.5;
    for (final x in [0.3, 0.7]) {
      final p = star(Offset(w * x, cy), w * 0.15);
      c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xF0FFE066), Color(0xE6FF9900)]));
      c.drawPath(p, stroke(const Color(0xFFFFFFFF), w * 0.008));
    }
    c.drawLine(Offset(w * 0.42, cy), Offset(w * 0.58, cy), stroke(const Color(0xFFFFD000), w * 0.014));
  }

  static void nerdGlasses(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final frame = stroke(const Color(0xFF111111), w * 0.03);
    for (final x in [0.3, 0.7]) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * x, h * 0.5), width: w * 0.3, height: h * 0.62),
        Radius.circular(w * 0.04),
      );
      c.drawRRect(r, fill(const Color(0x1AFFFFFF)));
      c.drawRRect(r, frame);
    }
    c.drawLine(Offset(w * 0.45, h * 0.42), Offset(w * 0.55, h * 0.42), frame);
    c.drawLine(Offset(w * 0.15, h * 0.35), Offset(w * 0.02, h * 0.3), frame);
    c.drawLine(Offset(w * 0.85, h * 0.35), Offset(w * 0.98, h * 0.3), frame);
  }

  static void cyberVisor(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final band = Path()
      ..moveTo(w * 0.06, h * 0.32)
      ..quadraticBezierTo(w * 0.5, h * 0.12, w * 0.94, h * 0.32)
      ..lineTo(w * 0.9, h * 0.7)
      ..quadraticBezierTo(w * 0.5, h * 0.86, w * 0.1, h * 0.7)
      ..close();
    c.drawPath(band, glow(const Color(0xAA00E5FF), w * 0.03));
    c.drawPath(band, Paint()..shader = linear(band.getBounds(), const [Color(0xE60C4FA8), Color(0xE600E5FF), Color(0xE60C4FA8)], vertical: false));
    for (var i = 0; i < 6; i++) {
      final y = h * (0.36 + i * 0.06);
      c.drawLine(Offset(w * 0.14, y), Offset(w * 0.86, y), stroke(const Color(0x33FFFFFF), w * 0.004));
    }
    c.drawPath(band, stroke(const Color(0xFFBFF6FF), w * 0.008));
  }

  static void pixelShades(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final px = w / 26;
    final black = fill(const Color(0xFF000000));
    final shine = fill(const Color(0xFFFFFFFF));
    final top = h * 0.5 - px * 2;
    c.drawRect(Rect.fromLTWH(px * 1, top, px * 24, px), black);
    for (final x0 in [3.0, 14.0]) {
      c.drawRect(Rect.fromLTWH(px * x0, top + px, px * 9, px), black);
      c.drawRect(Rect.fromLTWH(px * (x0 + 1), top + px * 2, px * 7, px), black);
      c.drawRect(Rect.fromLTWH(px * (x0 + 2), top + px * 3, px * 5, px), black);
      c.drawRect(Rect.fromLTWH(px * (x0 + 1), top + px, px, px), shine);
      c.drawRect(Rect.fromLTWH(px * (x0 + 2), top + px * 2, px, px), shine);
    }
  }

  // ── Head top (aspect varies; bottom edge sits on the hairline) ─────────

  static void crown(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final p = Path()
      ..moveTo(w * 0.12, h * 0.95)
      ..lineTo(w * 0.08, h * 0.3)
      ..lineTo(w * 0.3, h * 0.58)
      ..lineTo(w * 0.5, h * 0.1)
      ..lineTo(w * 0.7, h * 0.58)
      ..lineTo(w * 0.92, h * 0.3)
      ..lineTo(w * 0.88, h * 0.95)
      ..close();
    c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xFFFFE27A), Color(0xFFD4A017), Color(0xFFA6780C)]));
    c.drawPath(p, stroke(const Color(0xFF8A6100), w * 0.01));
    c.drawRect(Rect.fromLTRB(w * 0.12, h * 0.8, w * 0.88, h * 0.95), fill(const Color(0xFFB8860B)));
    for (final g in [
      (0.5, 0.1, const Color(0xFFFF2D87)),
      (0.08, 0.3, const Color(0xFF0C4FA8)),
      (0.92, 0.3, const Color(0xFF0C4FA8)),
    ]) {
      c.drawCircle(Offset(w * g.$1, h * g.$2), w * 0.04, fill(g.$3));
    }
    for (final x in [0.3, 0.5, 0.7]) {
      c.drawCircle(Offset(w * x, h * 0.875), w * 0.03, fill(x == 0.5 ? const Color(0xFFE0115F) : const Color(0xFF2E8B57)));
    }
  }

  static void tiara(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final band = Path()
      ..moveTo(w * 0.05, h * 0.95)
      ..quadraticBezierTo(w * 0.5, h * 0.55, w * 0.95, h * 0.95);
    c.drawPath(band, stroke(const Color(0xFFE8E8F0), w * 0.025));
    for (var i = 0; i <= 8; i++) {
      final t = i / 8;
      final x = w * (0.1 + 0.8 * t);
      final peak = h * (0.95 - 0.55 * math.sin(math.pi * t) - 0.25 * (i == 4 ? 1 : 0));
      final base = h * (0.95 - 0.36 * math.sin(math.pi * t));
      c.drawLine(Offset(x, base), Offset(x, peak), stroke(const Color(0xFFF5F5FF), w * 0.012));
      c.drawCircle(Offset(x, peak), w * (i == 4 ? 0.04 : 0.022), fill(i == 4 ? const Color(0xFFFF8CC6) : const Color(0xFFDDEEFF)));
      c.drawCircle(Offset(x, peak), w * 0.05, glow(const Color(0x66FFFFFF), w * 0.02));
    }
  }

  static void halo(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final r = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.78, height: h * 0.5);
    c.drawOval(r, glow(const Color(0xCCFFF3A0), w * 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06);
    c.drawOval(r, stroke(const Color(0xFFFFF7C2), w * 0.03));
  }

  static void devilHorns(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      final p = Path()
        ..moveTo(w * 0.16, h * 0.98)
        ..quadraticBezierTo(w * 0.08, h * 0.35, w * 0.2, h * 0.02)
        ..quadraticBezierTo(w * 0.26, h * 0.45, w * 0.36, h * 0.98)
        ..close();
      c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xFFFF4D4D), Color(0xFF9E0000)]));
      c.drawPath(p, stroke(const Color(0xFF5C0000), w * 0.008));
    });
  }

  static void catEars(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      final outer = Path()
        ..moveTo(w * 0.08, h * 0.98)
        ..lineTo(w * 0.16, h * 0.05)
        ..lineTo(w * 0.42, h * 0.8)
        ..close();
      final inner = Path()
        ..moveTo(w * 0.14, h * 0.85)
        ..lineTo(w * 0.18, h * 0.28)
        ..lineTo(w * 0.34, h * 0.75)
        ..close();
      c.drawPath(outer, fill(const Color(0xFF2B2B2B)));
      c.drawPath(inner, fill(const Color(0xFFFF9EC7)));
    });
  }

  static void bunnyEars(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      c.save();
      c.translate(w * 0.3, h * 0.98);
      c.rotate(-0.18);
      final outer = Rect.fromLTWH(-w * 0.09, -h * 0.98, w * 0.18, h * 0.98);
      c.drawOval(outer, fill(const Color(0xFFF7F7F7)));
      c.drawOval(outer.deflate(w * 0.035), fill(const Color(0xFFFFC2DA)));
      c.drawOval(outer, stroke(const Color(0x33000000), w * 0.006));
      c.restore();
    });
  }

  static void flowerCrown(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final colors = [const Color(0xFFFF8FB8), const Color(0xFFFFFFFF), const Color(0xFFFFD166), const Color(0xFFC59BFF)];
    c.drawPath(
      Path()
        ..moveTo(w * 0.04, h * 0.85)
        ..quadraticBezierTo(w * 0.5, h * 0.2, w * 0.96, h * 0.85),
      stroke(const Color(0xFF4C8C4A), w * 0.015),
    );
    for (var i = 0; i < 9; i++) {
      final t = i / 8;
      final x = w * (0.08 + 0.84 * t);
      final y = h * (0.85 - 0.55 * math.sin(math.pi * t) * 0.95);
      final r = w * (i.isEven ? 0.05 : 0.038);
      final col = colors[i % colors.length];
      // Leaves.
      c.drawOval(Rect.fromCenter(center: Offset(x + r, y + r * 0.6), width: r * 1.4, height: r * 0.6), fill(const Color(0xFF5DA65A)));
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * math.pi / 5;
        c.drawCircle(Offset(x, y) + Offset(math.cos(a), math.sin(a)) * r * 0.55, r * 0.5, fill(col));
      }
      c.drawCircle(Offset(x, y), r * 0.32, fill(const Color(0xFFFFB300)));
    }
  }

  static void partyHat(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final cone = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.78, h * 0.95)
      ..lineTo(w * 0.22, h * 0.95)
      ..close();
    c.save();
    c.clipPath(cone);
    c.drawPath(cone, fill(const Color(0xFF0C4FA8)));
    for (var i = -6; i < 12; i++) {
      final y = h * (i * 0.12);
      c.drawLine(Offset(0, y), Offset(w, y + h * 0.4), stroke(const Color(0xFFFF2D87), w * 0.04));
    }
    c.restore();
    for (var i = 0; i < 18; i++) {
      final rnd = math.Random(i);
      c.drawCircle(Offset(w * (0.3 + rnd.nextDouble() * 0.4), h * (0.4 + rnd.nextDouble() * 0.5)), w * 0.01,
          fill(i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFFFD166)));
    }
    c.drawCircle(Offset(w * 0.5, h * 0.08), w * 0.06, fill(const Color(0xFFFFD166)));
  }

  static void cap(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final dome = Path()
      ..moveTo(w * 0.1, h * 0.78)
      ..quadraticBezierTo(w * 0.12, h * 0.05, w * 0.5, h * 0.05)
      ..quadraticBezierTo(w * 0.88, h * 0.05, w * 0.9, h * 0.78)
      ..close();
    c.drawPath(dome, Paint()..shader = linear(dome.getBounds(), const [Color(0xFF1C5FC0), Color(0xFF0A3A7E)]));
    c.drawLine(Offset(w * 0.5, h * 0.06), Offset(w * 0.5, h * 0.78), stroke(const Color(0x33FFFFFF), w * 0.008));
    c.drawCircle(Offset(w * 0.5, h * 0.06), w * 0.025, fill(const Color(0xFF0A3A7E)));
    final brim = Path()
      ..moveTo(w * 0.08, h * 0.74)
      ..quadraticBezierTo(w * 0.5, h * 0.62, w * 0.92, h * 0.74)
      ..quadraticBezierTo(w * 0.5, h * 1.02, w * 0.08, h * 0.74)
      ..close();
    c.drawPath(brim, fill(const Color(0xFF082F66)));
  }

  // ── Masks (eyes anchor) ─────────────────────────────────────────────────

  static void butterflyMask(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      final wing = Path()
        ..moveTo(w * 0.5, h * 0.45)
        ..cubicTo(w * 0.35, h * 0.0, w * 0.0, h * 0.0, w * 0.04, h * 0.45)
        ..cubicTo(w * 0.06, h * 0.85, w * 0.32, h * 1.0, w * 0.5, h * 0.62)
        ..close();
      final eye = Rect.fromCenter(center: Offset(w * 0.3, h * 0.5), width: w * 0.2, height: h * 0.3);
      final shape = Path.combine(PathOperation.difference, wing, Path()..addOval(eye));
      c.drawPath(shape, Paint()..shader = linear(shape.getBounds(), const [Color(0xFFB57CFF), Color(0xFFFF2D87)], vertical: false));
      c.drawPath(shape, stroke(const Color(0xFFFFE27A), w * 0.008));
      for (var i = 0; i < 7; i++) {
        final rnd = math.Random(i + 7);
        c.drawCircle(Offset(w * (0.08 + rnd.nextDouble() * 0.12), h * (0.2 + rnd.nextDouble() * 0.5)), w * 0.008, fill(const Color(0xFFFFF7C2)));
      }
    });
  }

  static void heroMask(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final band = Path()
      ..moveTo(w * 0.02, h * 0.42)
      ..quadraticBezierTo(w * 0.5, h * 0.05, w * 0.98, h * 0.42)
      ..quadraticBezierTo(w * 0.9, h * 0.95, w * 0.62, h * 0.8)
      ..quadraticBezierTo(w * 0.5, h * 0.62, w * 0.38, h * 0.8)
      ..quadraticBezierTo(w * 0.1, h * 0.95, w * 0.02, h * 0.42)
      ..close();
    final holes = Path()
      ..addOval(Rect.fromCenter(center: Offset(w * 0.3, h * 0.5), width: w * 0.2, height: h * 0.32))
      ..addOval(Rect.fromCenter(center: Offset(w * 0.7, h * 0.5), width: w * 0.2, height: h * 0.32));
    final mask = Path.combine(PathOperation.difference, band, holes);
    c.drawPath(mask, fill(const Color(0xF2101826)));
    c.drawPath(mask, stroke(const Color(0xFF0C4FA8), w * 0.01));
  }

  // ── Nose / mouth / chin ─────────────────────────────────────────────────

  static void clownNose(Canvas c, Size s) {
    final w = s.width;
    final o = Offset(w * 0.5, s.height * 0.5);
    c.drawCircle(o, w * 0.42, Paint()..shader = ui.Gradient.radial(o - Offset(w * 0.12, w * 0.12), w * 0.5, const [Color(0xFFFF6B6B), Color(0xFFC00000)]));
    c.drawCircle(o - Offset(w * 0.14, w * 0.14), w * 0.08, fill(const Color(0xAAFFFFFF)));
  }

  /// Wide canvas centered on the nose tip: pink nose plus whiskers.
  static void catNose(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final nose = Path()
      ..moveTo(w * 0.44, h * 0.38)
      ..lineTo(w * 0.56, h * 0.38)
      ..quadraticBezierTo(w * 0.56, h * 0.5, w * 0.5, h * 0.56)
      ..quadraticBezierTo(w * 0.44, h * 0.5, w * 0.44, h * 0.38)
      ..close();
    c.drawPath(nose, fill(const Color(0xFFFF8FB8)));
    c.drawPath(nose, stroke(const Color(0xFF3A2A2A), w * 0.006));
    mirrored(c, s, (c) {
      for (final dy in [-0.08, 0.0, 0.08]) {
        c.drawLine(Offset(w * 0.38, h * (0.55 + dy * 0.3)), Offset(w * 0.04, h * (0.48 + dy * 1.6)), stroke(const Color(0xE6222222), w * 0.006));
      }
      c.drawCircle(Offset(w * 0.36, h * 0.56), w * 0.007, fill(const Color(0xFF222222)));
    });
  }

  static void mustache(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      final p = Path()
        ..moveTo(w * 0.5, h * 0.35)
        ..cubicTo(w * 0.36, h * 0.12, w * 0.2, h * 0.3, w * 0.16, h * 0.55)
        ..cubicTo(w * 0.1, h * 0.75, w * 0.0, h * 0.6, w * 0.03, h * 0.4)
        ..cubicTo(w * 0.0, h * 0.85, w * 0.22, h * 0.95, w * 0.32, h * 0.72)
        ..cubicTo(w * 0.4, h * 0.6, w * 0.46, h * 0.62, w * 0.5, h * 0.62)
        ..close();
      c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xFF3B2414), Color(0xFF1C110A)]));
    });
  }

  /// Hair-like strands filling [area], so beards read as hair, not a blob.
  static void _strands(Canvas c, Path area, Rect bounds, Color base, int seed, double len) {
    c.save();
    c.clipPath(area);
    c.drawPath(area, fill(base));
    final rnd = math.Random(seed);
    final n = (bounds.width * bounds.height / (len * len) * 6).clamp(200, 2600).toInt();
    for (var i = 0; i < n; i++) {
      final x = bounds.left + rnd.nextDouble() * bounds.width;
      final y = bounds.top + rnd.nextDouble() * bounds.height;
      final a = math.pi / 2 + (rnd.nextDouble() - 0.5) * 0.9;
      final l = len * (0.5 + rnd.nextDouble());
      final shade = rnd.nextDouble();
      c.drawLine(
        Offset(x, y),
        Offset(x + math.cos(a) * l, y + math.sin(a) * l),
        stroke(Color.lerp(base, shade > 0.5 ? const Color(0xFF6B4A2E) : const Color(0xFF0E0906), shade * 0.6)!, len * 0.12),
      );
    }
    c.restore();
  }

  /// Chin anchor, aspect 0.9: jaw-shaped beard with a mouth opening.
  static void fullBeard(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final beard = Path()
      ..moveTo(w * 0.0, h * 0.0)
      ..quadraticBezierTo(w * 0.04, h * 0.7, w * 0.5, h * 1.0)
      ..quadraticBezierTo(w * 0.96, h * 0.7, w * 1.0, h * 0.0)
      ..lineTo(w * 0.86, h * 0.02)
      ..quadraticBezierTo(w * 0.8, h * 0.3, w * 0.66, h * 0.2)
      ..quadraticBezierTo(w * 0.5, h * 0.1, w * 0.34, h * 0.2)
      ..quadraticBezierTo(w * 0.2, h * 0.3, w * 0.14, h * 0.02)
      ..close();
    final mouth = Path()..addOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.26), width: w * 0.3, height: h * 0.14));
    final area = Path.combine(PathOperation.difference, beard, mouth);
    _strands(c, area, area.getBounds(), const Color(0xFF2A1A0E), 11, w * 0.035);
  }

  static void goatee(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final p = Path()
      ..moveTo(w * 0.32, h * 0.25)
      ..quadraticBezierTo(w * 0.5, h * 0.36, w * 0.68, h * 0.25)
      ..quadraticBezierTo(w * 0.66, h * 0.9, w * 0.5, h * 0.98)
      ..quadraticBezierTo(w * 0.34, h * 0.9, w * 0.32, h * 0.25)
      ..close();
    _strands(c, p, p.getBounds(), const Color(0xFF24160C), 23, w * 0.03);
  }

  // ── Face paint (face anchor, aspect 1.25) ──────────────────────────────

  static void freckles(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final rnd = math.Random(5);
    mirrored(c, s, (c) {
      for (var i = 0; i < 26; i++) {
        final x = w * (0.22 + rnd.nextDouble() * 0.2);
        final y = h * (0.5 + rnd.nextDouble() * 0.1);
        c.drawCircle(Offset(x, y), w * (0.004 + rnd.nextDouble() * 0.004), fill(const Color(0x8C7A4424)));
      }
    });
    c.drawPath(heart(Offset(w * 0.27, h * 0.62), w * 0.03), fill(const Color(0xCCFF2D87)));
  }

  static void tigerPaint(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      for (var i = 0; i < 4; i++) {
        final y = h * (0.28 + i * 0.12);
        final p = Path()
          ..moveTo(w * 0.06, y)
          ..quadraticBezierTo(w * 0.16, y - h * 0.03, w * (0.24 - i * 0.015), y + h * 0.01)
          ..quadraticBezierTo(w * 0.14, y + h * 0.02, w * 0.07, y + h * 0.035)
          ..close();
        c.drawPath(p, fill(const Color(0xD9111111)));
      }
    });
    c.drawPath(
      Path()
        ..moveTo(w * 0.46, h * 0.08)
        ..lineTo(w * 0.5, h * 0.24)
        ..lineTo(w * 0.54, h * 0.08)
        ..close(),
      fill(const Color(0xD9111111)),
    );
  }

  static void glitterTears(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final rnd = math.Random(9);
    mirrored(c, s, (c) {
      for (var i = 0; i < 40; i++) {
        final t = rnd.nextDouble();
        final x = w * (0.3 + (rnd.nextDouble() - 0.5) * 0.04);
        final y = h * (0.42 + t * 0.22);
        final r = w * (0.003 + rnd.nextDouble() * 0.006);
        c.drawCircle(Offset(x, y), r * 2.2, glow(const Color(0x66C59BFF), r * 2));
        c.drawPath(star(Offset(x, y), r * 1.6, points: 4, inner: 0.3), fill(i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFFFC2F0)));
      }
    });
  }

  // ── Neck ────────────────────────────────────────────────────────────────

  static void goldChain(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    for (var i = 0; i <= 28; i++) {
      final t = i / 28;
      final x = w * (0.05 + 0.9 * t);
      final y = h * (0.1 + 0.7 * math.sin(math.pi * t));
      c.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w * 0.04, height: w * 0.028),
        stroke(i.isEven ? const Color(0xFFFFD66B) : const Color(0xFFC99A1B), w * 0.009),
      );
    }
  }

  static void pearls(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    for (var i = 0; i <= 22; i++) {
      final t = i / 22;
      final o = Offset(w * (0.05 + 0.9 * t), h * (0.1 + 0.7 * math.sin(math.pi * t)));
      c.drawCircle(o, w * 0.022, Paint()..shader = ui.Gradient.radial(o - Offset(w * 0.008, w * 0.008), w * 0.026, const [Color(0xFFFFFFFF), Color(0xFFE3DCD2)]));
    }
  }

  static void bowTie(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    mirrored(c, s, (c) {
      final p = Path()
        ..moveTo(w * 0.42, h * 0.5)
        ..lineTo(w * 0.08, h * 0.12)
        ..quadraticBezierTo(w * 0.02, h * 0.5, w * 0.08, h * 0.88)
        ..close();
      c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xFF0C4FA8), Color(0xFF062A5C)], vertical: false));
    });
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.18, height: h * 0.42), Radius.circular(w * 0.03)),
      fill(const Color(0xFF0A3A7E)),
    );
  }

  // ── World stickers (aspect 1) ───────────────────────────────────────────

  static void floatingHearts(Canvas c, Size s) {
    final w = s.width;
    final rnd = math.Random(3);
    for (var i = 0; i < 9; i++) {
      final o = Offset(w * (0.15 + rnd.nextDouble() * 0.7), s.height * (0.15 + rnd.nextDouble() * 0.7));
      final r = w * (0.05 + rnd.nextDouble() * 0.07);
      final p = heart(o, r);
      c.drawPath(p, glow(const Color(0x66FF2D87), r * 0.4));
      c.drawPath(p, Paint()..shader = linear(p.getBounds(), const [Color(0xFFFF7AB6), Color(0xFFFF2D87)]));
    }
  }

  static void sparkles(Canvas c, Size s) {
    final w = s.width;
    final rnd = math.Random(4);
    for (var i = 0; i < 14; i++) {
      final o = Offset(w * (0.1 + rnd.nextDouble() * 0.8), s.height * (0.1 + rnd.nextDouble() * 0.8));
      final r = w * (0.025 + rnd.nextDouble() * 0.05);
      c.drawCircle(o, r * 1.2, glow(const Color(0x88FFF3A0), r));
      c.drawPath(star(o, r, points: 4, inner: 0.25), fill(const Color(0xFFFFFDE7)));
    }
  }

  static void bubbles(Canvas c, Size s) {
    final w = s.width;
    final rnd = math.Random(8);
    for (var i = 0; i < 12; i++) {
      final o = Offset(w * (0.1 + rnd.nextDouble() * 0.8), s.height * (0.1 + rnd.nextDouble() * 0.8));
      final r = w * (0.03 + rnd.nextDouble() * 0.07);
      c.drawCircle(o, r, fill(const Color(0x1A9AD8FF)));
      c.drawCircle(o, r, stroke(const Color(0x99D9F2FF), r * 0.08));
      c.drawCircle(o - Offset(r * 0.35, r * 0.35), r * 0.18, fill(const Color(0xCCFFFFFF)));
    }
  }

  static void neonLove(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final tp = TextPainter(
      text: TextSpan(
        text: 'LOVE',
        style: TextStyle(fontSize: w * 0.26, fontWeight: FontWeight.w900, letterSpacing: w * 0.02, color: const Color(0xFFFFE3F1)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final o = Offset((w - tp.width) / 2, (h - tp.height) / 2);
    final glowTp = TextPainter(
      text: TextSpan(
        text: 'LOVE',
        style: TextStyle(
          fontSize: w * 0.26,
          fontWeight: FontWeight.w900,
          letterSpacing: w * 0.02,
          foreground: glow(const Color(0xFFFF2D87), w * 0.03),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glowTp.paint(c, o);
    tp.paint(c, o);
    final frame = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.06, h * 0.22, w * 0.88, h * 0.56), Radius.circular(w * 0.06));
    c.drawRRect(frame, glow(const Color(0xAA0C4FA8), w * 0.02)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02);
    c.drawRRect(frame, stroke(const Color(0xFF8FC1FF), w * 0.008));
  }

  // ── Backgrounds (aspect 16:9 portrait, opaque) ──────────────────────────

  static void bgStudioBlue(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = ui.Gradient.radial(Offset(s.width * 0.5, s.height * 0.4), s.height * 0.7, const [Color(0xFF2F7BE0), Color(0xFF0C4FA8), Color(0xFF041C40)], [0, 0.45, 1]));
  }

  static void bgSunset(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = linear(r, const [Color(0xFF2B1055), Color(0xFFD53369), Color(0xFFFF9A3C), Color(0xFFFFD27A)]));
    c.drawCircle(Offset(s.width * 0.5, s.height * 0.68), s.width * 0.22, fill(const Color(0xE6FFF0B3)));
    c.drawRect(Rect.fromLTWH(0, s.height * 0.74, s.width, s.height * 0.26), Paint()..shader = linear(Rect.fromLTWH(0, s.height * 0.74, s.width, s.height * 0.26), const [Color(0xFF5B2A86), Color(0xFF1B0B33)]));
  }

  static void bgNeonGrid(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = linear(r, const [Color(0xFF0B0221), Color(0xFF2A0845), Color(0xFF0B0221)]));
    final horizon = s.height * 0.58;
    c.drawCircle(Offset(s.width * 0.5, horizon), s.width * 0.3, Paint()..shader = linear(Rect.fromCircle(center: Offset(s.width * 0.5, horizon), radius: s.width * 0.3), const [Color(0xFFFFD319), Color(0xFFFF2D87)]));
    c.drawRect(Rect.fromLTWH(0, horizon, s.width, s.height - horizon), fill(const Color(0xFF0B0221)));
    final line = stroke(const Color(0xCCFF2D87), s.width * 0.004);
    for (var i = 1; i < 14; i++) {
      final t = i / 14;
      final y = horizon + (s.height - horizon) * t * t;
      c.drawLine(Offset(0, y), Offset(s.width, y), line);
    }
    for (var i = -10; i <= 10; i++) {
      c.drawLine(Offset(s.width * 0.5 + i * s.width * 0.03, horizon), Offset(s.width * 0.5 + i * s.width * 0.25, s.height), line);
    }
  }

  static void bgBokeh(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = linear(r, const [Color(0xFF14101F), Color(0xFF2B1B3D)]));
    final rnd = math.Random(12);
    const cols = [Color(0xFFFFC46B), Color(0xFFFF8FB8), Color(0xFF8FC1FF), Color(0xFFFFF3A0)];
    for (var i = 0; i < 60; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
      final rr = s.width * (0.02 + rnd.nextDouble() * 0.08);
      c.drawCircle(o, rr, glow(cols[i % cols.length].withValues(alpha: 0.25 + rnd.nextDouble() * 0.35), rr * 0.3));
    }
  }

  static void bgStarryNight(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = linear(r, const [Color(0xFF020611), Color(0xFF0B1E4A), Color(0xFF1B3A7A)]));
    final rnd = math.Random(21);
    for (var i = 0; i < 260; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * 0.85);
      c.drawCircle(o, s.width * (0.0008 + rnd.nextDouble() * 0.0025), fill(Colors.white.withValues(alpha: 0.4 + rnd.nextDouble() * 0.6)));
    }
    c.drawCircle(Offset(s.width * 0.75, s.height * 0.16), s.width * 0.09, glow(const Color(0x66FFF7D6), s.width * 0.05));
    c.drawCircle(Offset(s.width * 0.75, s.height * 0.16), s.width * 0.07, fill(const Color(0xFFFFF7D6)));
  }

  static void bgWhiteStudio(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = ui.Gradient.radial(Offset(s.width * 0.5, s.height * 0.42), s.height * 0.75, const [Color(0xFFFFFFFF), Color(0xFFE9EDF2), Color(0xFFC9D0D9)], [0, 0.6, 1]));
  }

  static void bgPastel(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = linear(r, const [Color(0xFFFFD6E8), Color(0xFFE5D4FF), Color(0xFFCCE7FF)]));
    final rnd = math.Random(30);
    for (var i = 0; i < 10; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
      c.drawCircle(o, s.width * (0.12 + rnd.nextDouble() * 0.2), glow(Colors.white.withValues(alpha: 0.35), s.width * 0.08));
    }
  }

  static void bgNebula(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, fill(const Color(0xFF05030F)));
    final rnd = math.Random(41);
    const cols = [Color(0x55FF2D87), Color(0x550C4FA8), Color(0x55B57CFF), Color(0x4400E5FF)];
    for (var i = 0; i < 14; i++) {
      final o = Offset(s.width * (0.2 + rnd.nextDouble() * 0.6), s.height * (0.15 + rnd.nextDouble() * 0.6));
      c.drawCircle(o, s.width * (0.15 + rnd.nextDouble() * 0.25), glow(cols[i % cols.length], s.width * 0.12));
    }
    for (var i = 0; i < 200; i++) {
      c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height), s.width * rnd.nextDouble() * 0.002, fill(Colors.white.withValues(alpha: rnd.nextDouble())));
    }
  }

  static void bgOcean(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = linear(r, const [Color(0xFF8FD3FF), Color(0xFF2E8BD8), Color(0xFF0A3A7E), Color(0xFF041C40)]));
    final line = stroke(const Color(0x33FFFFFF), s.width * 0.006);
    for (var i = 0; i < 16; i++) {
      final y = s.height * (0.45 + i * 0.035);
      final p = Path()..moveTo(0, y);
      for (var x = 0.0; x <= s.width; x += s.width / 12) {
        p.quadraticBezierTo(x + s.width / 24, y - s.height * 0.006, x + s.width / 12, y);
      }
      c.drawPath(p, line);
    }
  }
}
