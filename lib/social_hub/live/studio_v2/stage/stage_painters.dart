import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/live_studio_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainters for the world layer. All shapes reproduce the prototype SVGs
// (viewBox 0 0 100 100, preserveAspectRatio="xMidYMax meet").
// ─────────────────────────────────────────────────────────────────────────────

/// Maps the 100×100 SVG viewBox into [size] with xMidYMax meet.
void _meet(Canvas canvas, Size size) {
  final s = math.min(size.width, size.height) / 100;
  canvas.translate((size.width - 100 * s) / 2, size.height - 100 * s);
  canvas.scale(s);
}

/// CSS `saturate(s)` as a color matrix.
ColorFilter saturateFilter(double s) => ColorFilter.matrix(<double>[
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);

/// The guest cartoon avatar in the user's [accent]. [muted] = opacity .78 +
/// saturate(.7) (SPEC §3).
class CartoonAvatarPainter extends CustomPainter {
  CartoonAvatarPainter({required this.accent, this.muted = false});
  final Color accent;
  final bool muted;

  static final Path _body = Path()
    ..moveTo(14, 100)
    ..cubicTo(14, 75, 30, 63, 50, 63)
    ..cubicTo(70, 63, 86, 75, 86, 100)
    ..close();
  static final Path _collar = Path()
    ..moveTo(38, 66)
    ..cubicTo(41, 71, 45, 73, 50, 73)
    ..cubicTo(55, 73, 59, 71, 62, 66);
  static final Path _hair = Path()
    ..moveTo(29, 38)
    ..cubicTo(30, 25, 39, 18, 50, 18)
    ..cubicTo(61, 18, 70, 25, 71, 38)
    ..cubicTo(65, 32, 58, 30, 50, 30)
    ..cubicTo(42, 30, 35, 32, 29, 38)
    ..close();
  static final Path _smile = Path()
    ..moveTo(44, 50.5)
    ..cubicTo(47.5, 53.7, 52.5, 53.7, 56, 50.5);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (muted) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..colorFilter = saturateFilter(0.7)
          ..color = LiveStudioAccent.white.withValues(alpha: 0.78),
      );
    }
    _meet(canvas, size);
    final fill = Paint()..isAntiAlias = true;
    canvas.drawPath(_body, fill..color = accent);
    canvas.drawPath(
      _collar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = LiveStudioAccent.white.withValues(alpha: 0.5),
    );
    canvas.drawCircle(const Offset(50, 40), 21, Paint()..color = LiveStudioWorld.avatarSkin);
    canvas.drawPath(_hair, Paint()..color = accent.withValues(alpha: 0.85 * accent.a));
    final ink = Paint()..color = LiveStudioWorld.avatarInk;
    canvas.drawCircle(const Offset(42.5, 43), 2.6, ink);
    canvas.drawCircle(const Offset(57.5, 43), 2.6, ink);
    canvas.drawPath(
      _smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = LiveStudioWorld.avatarInk,
    );
    final blush = Paint()..color = LiveStudioWorld.avatarBlush;
    canvas.drawCircle(const Offset(37, 49), 3.4, blush);
    canvas.drawCircle(const Offset(63, 49), 3.4, blush);
    if (muted) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(CartoonAvatarPainter old) => old.accent != accent || old.muted != muted;
}

/// The host silhouette used on the center screen and person pop-outs.
class HostSilhouettePainter extends CustomPainter {
  const HostSilhouettePainter();

  static final Path _body = Path()
    ..moveTo(16, 100)
    ..cubicTo(16, 76, 31, 64, 50, 64)
    ..cubicTo(69, 64, 84, 76, 84, 100)
    ..close();
  static final Path _arc = Path()
    ..moveTo(36, 33)
    ..arcToPoint(const Offset(64, 29), radius: const Radius.circular(15), clockwise: true);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    _meet(canvas, size);
    canvas.drawCircle(const Offset(50, 42), 15, Paint()..color = LiveStudioWorld.hostSilhouetteHead);
    canvas.drawPath(_body, Paint()..color = LiveStudioWorld.hostSilhouetteBody);
    canvas.drawPath(
      _arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = LiveStudioAccent.pinkA(0.55),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(HostSilhouettePainter old) => false;
}

/// CSS `radial-gradient(rx% ry% at cx% cy%, …)` — an ellipse, which
/// Flutter's circular [RadialGradient] cannot express directly.
class EllipseGradientPainter extends CustomPainter {
  const EllipseGradientPainter({
    required this.center,
    required this.radii,
    required this.colors,
    required this.stops,
  });

  /// Fractions of the box.
  final Offset center;
  final Offset radii;
  final List<Color> colors;
  final List<double> stops;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rx = radii.dx * size.width, ry = radii.dy * size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(center.dx * size.width, center.dy * size.height);
    canvas.scale(rx, ry);
    final shader = ui.Gradient.radial(Offset.zero, 1, colors, stops);
    canvas.drawRect(
      Rect.fromLTRB(-center.dx * size.width / rx, -center.dy * size.height / ry,
          (1 - center.dx) * size.width / rx, (1 - center.dy) * size.height / ry),
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(EllipseGradientPainter old) =>
      old.center != center || old.radii != radii || !_listEq(old.colors, colors) || !_listEq(old.stops, stops);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Drop shadows of the host screen shape (the prototype's wall-layer
/// `filter: drop-shadow(…) drop-shadow(…)`), painted under the clipped host.
class PathShadowPainter extends CustomPainter {
  const PathShadowPainter(this.path, this.shadows);
  final Path path;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in shadows) {
      canvas.drawPath(
        path.shift(s.offset),
        Paint()
          ..color = s.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma),
      );
    }
  }

  @override
  bool shouldRepaint(PathShadowPainter old) => old.path != path || old.shadows != shadows;
}

/// Pink rim under the frame-color stroke (SPEC §2). Painted inside the host
/// clip, so only the inner half of each stroke shows — like the prototype.
class HostRimPainter extends CustomPainter {
  const HostRimPainter({
    required this.path,
    required this.rimWidth,
    required this.strokeWidth,
    required this.frameColor,
  });
  final Path path;
  final double rimWidth;
  final double strokeWidth;
  final Color frameColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..color = LiveStudioWorld.pinkRim,
    );
    if (strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = frameColor,
      );
    }
  }

  @override
  bool shouldRepaint(HostRimPainter old) =>
      old.path != path || old.rimWidth != rimWidth || old.strokeWidth != strokeWidth || old.frameColor != frameColor;
}

/// Clips a widget to an arbitrary path (host screen).
class PathClipper extends CustomClipper<Path> {
  const PathClipper(this.path);
  final Path path;
  @override
  Path getClip(Size size) => path;
  @override
  bool shouldReclip(PathClipper old) => old.path != path;
}

/// Stand beam trapezoid: polygon(0 100%, 100% 100%, 80% 0, 20% 0).
class BeamClipper extends CustomClipper<Path> {
  const BeamClipper();
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, s.height)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width * 0.8, 0)
    ..lineTo(s.width * 0.2, 0)
    ..close();
  @override
  bool shouldReclip(BeamClipper old) => false;
}

/// Inner glow of an ellipse (`inset 0 0 blur color`).
class EllipseInsetGlowPainter extends CustomPainter {
  const EllipseInsetGlowPainter(this.color, this.blur);
  final Color color;
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.save();
    canvas.clipPath(Path()..addOval(r));
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = blur
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(EllipseInsetGlowPainter old) => old.color != color || old.blur != blur;
}
