import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A colourist's reference scene drawn on the device (no bundled photo):
/// sky, sun, foliage, water, two skin tones, a saturated object and a grey
/// ramp, so a filter thumbnail shows what it does to each kind of colour.
class FilterReferenceImage {
  FilterReferenceImage._();

  static Future<ui.Image>? _image;

  static Future<ui.Image> load() => _image ??= _draw().catchError((Object e) {
        _image = null; // let the next caller try again
        throw e;
      });

  static Future<ui.Image> _draw() async {
    const w = 240.0, h = 300.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));

    // Sky: deep blue to a warm horizon.
    c.drawRect(
      const Rect.fromLTWH(0, 0, w, 150),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, 150), const [
          Color(0xFF2B5FA8),
          Color(0xFF7FB2E5),
          Color(0xFFF2C28B),
        ], const [0, 0.6, 1]),
    );
    // Sun with a soft glow.
    c.drawCircle(const Offset(184, 112), 34, Paint()..color = const Color(0x55FFE2A8));
    c.drawCircle(const Offset(184, 112), 18, Paint()..color = const Color(0xFFFFE8B0));
    // Hills and foliage.
    final hill = Path()
      ..moveTo(0, 150)
      ..quadraticBezierTo(70, 108, 140, 140)
      ..quadraticBezierTo(200, 162, w, 132)
      ..lineTo(w, 200)
      ..lineTo(0, 200)
      ..close();
    c.drawPath(
      hill,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 120), const Offset(0, 200), const [
          Color(0xFF5E8F3A),
          Color(0xFF2F5A24),
        ]),
    );
    // Water strip.
    c.drawRect(
      const Rect.fromLTWH(0, 196, w, 30),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 196), const Offset(w, 226), const [
          Color(0xFF1C8C9C),
          Color(0xFF3FB7C4),
          Color(0xFF1A6F86),
        ], const [0, 0.5, 1]),
    );
    // Two faces: a deep and a light skin tone, lit from the left.
    void face(Offset o, Color base, Color shade) {
      c.drawOval(
        Rect.fromCenter(center: o, width: 46, height: 58),
        Paint()
          ..shader = ui.Gradient.radial(o.translate(-8, -10), 38, [base, shade]),
      );
      c.drawOval(Rect.fromCenter(center: o.translate(0, 44), width: 66, height: 36), Paint()..color = shade);
    }

    face(const Offset(62, 164), const Color(0xFF9A6240), const Color(0xFF5B3520));
    face(const Offset(124, 170), const Color(0xFFE7B896), const Color(0xFFB98463));
    // A saturated red object and a yellow one.
    c.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(168, 168, 50, 40), const Radius.circular(8)),
      Paint()..color = const Color(0xFFD8322E),
    );
    c.drawCircle(const Offset(206, 160), 11, Paint()..color = const Color(0xFFF3C31B));
    // Grey ramp, black to white.
    for (var i = 0; i < 12; i++) {
      final v = (i / 11 * 255).round();
      c.drawRect(Rect.fromLTWH(i * w / 12, 226, w / 12 + 0.5, 22), Paint()..color = Color.fromARGB(255, v, v, v));
    }
    // Hue ramp.
    for (var i = 0; i < 24; i++) {
      final hue = i / 24 * 360;
      c.drawRect(
        Rect.fromLTWH(i * w / 24, 248, w / 24 + 0.5, 22),
        Paint()..color = HSVColor.fromAHSV(1, hue, 0.85, 0.9).toColor(),
      );
    }
    // Shadow band with fine detail (shows grain, matte and fade).
    c.drawRect(const Rect.fromLTWH(0, 270, w, 30), Paint()..color = const Color(0xFF15161A));
    final rnd = math.Random(7);
    final dot = Paint()..color = const Color(0xFF2A2C33);
    for (var i = 0; i < 140; i++) {
      c.drawCircle(Offset(rnd.nextDouble() * w, 272 + rnd.nextDouble() * 26), 0.9, dot);
    }
    final pic = rec.endRecording();
    return pic.toImage(w.toInt(), h.toInt());
  }
}
