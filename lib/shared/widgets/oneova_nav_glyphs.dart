import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Brand gradient used for active bottom-nav glyphs.
const LinearGradient kOneovaNavGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.brandBlue, AppColors.brandPink],
);

/// Paints any Material icon with the brand gradient.
class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  const GradientIcon(this.icon, {super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => kOneovaNavGradient.createShader(rect),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

/// Two overlapping speech bubbles with a typing indicator.
/// Outlined when idle; gradient-filled with white dots when active.
class ChatGlyph extends StatelessWidget {
  final bool active;
  final Color color;
  final double size;
  const ChatGlyph({super.key, required this.active, required this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChatGlyphPainter(active: active, color: color),
    );
  }
}

class _ChatGlyphPainter extends CustomPainter {
  final bool active;
  final Color color;
  _ChatGlyphPainter({required this.active, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.085;
    final bounds = Offset.zero & size;

    // Front bubble with a tail at the bottom-left.
    final front = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.05, s * 0.27, s * 0.66, s * 0.5),
        Radius.circular(s * 0.19),
      ));
    final tail = Path()
      ..moveTo(s * 0.15, s * 0.70)
      ..lineTo(s * 0.09, s * 0.93)
      ..lineTo(s * 0.34, s * 0.76)
      ..close();
    final frontShape = Path.combine(PathOperation.union, front, tail);

    // Back bubble peeking out top-right, clipped so it sits behind the front.
    final back = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.36, s * 0.07, s * 0.58, s * 0.46),
      Radius.circular(s * 0.17),
    );

    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(bounds), frontShape));
    if (active) {
      canvas.drawRRect(back, Paint()..color = AppColors.brandPink.withValues(alpha: 0.55));
    } else {
      canvas.drawRRect(
        back.deflate(stroke / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = color.withValues(alpha: 0.75),
      );
    }
    canvas.restore();

    if (active) {
      canvas.drawPath(frontShape, Paint()..shader = kOneovaNavGradient.createShader(bounds));
    } else {
      canvas.drawPath(
        frontShape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }

    // Typing dots.
    final dot = Paint()..color = active ? Colors.white : color;
    final cy = s * 0.52;
    for (final x in [0.24, 0.38, 0.52]) {
      canvas.drawCircle(Offset(s * x, cy), s * 0.048, dot);
    }
  }

  @override
  bool shouldRepaint(_ChatGlyphPainter old) => old.active != active || old.color != color;
}

/// Clapper-topped rounded frame with a play triangle.
class ReelsGlyph extends StatelessWidget {
  final bool active;
  final Color color;
  final double size;
  const ReelsGlyph({super.key, required this.active, required this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ReelsGlyphPainter(active: active, color: color),
    );
  }
}

class _ReelsGlyphPainter extends CustomPainter {
  final bool active;
  final Color color;
  _ReelsGlyphPainter({required this.active, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.085;
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.08, s * 0.08, s * 0.84, s * 0.84),
      Radius.circular(s * 0.24),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = active ? Colors.white : color;

    if (active) {
      canvas.drawRRect(frame, Paint()..shader = kOneovaNavGradient.createShader(Offset.zero & size));
    } else {
      canvas.drawRRect(frame.deflate(stroke / 2), line);
    }

    // Clapper band and slashes, clipped to the frame.
    canvas.save();
    canvas.clipRRect(frame);
    final bandY = s * 0.34;
    canvas.drawLine(Offset(s * 0.08, bandY), Offset(s * 0.92, bandY), line);
    canvas.drawLine(Offset(s * 0.34, s * 0.09), Offset(s * 0.44, bandY), line);
    canvas.drawLine(Offset(s * 0.58, s * 0.09), Offset(s * 0.68, bandY), line);
    canvas.restore();

    // Play triangle with softened corners.
    final play = Path()
      ..moveTo(s * 0.42, s * 0.48)
      ..lineTo(s * 0.42, s * 0.76)
      ..lineTo(s * 0.66, s * 0.62)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = active ? Colors.white : color
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      play,
      Paint()
        ..color = active ? Colors.white : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ReelsGlyphPainter old) => old.active != active || old.color != color;
}
