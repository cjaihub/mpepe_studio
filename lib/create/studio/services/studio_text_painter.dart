import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/studio_project.dart';

/// Paints a text / sticker / caption layer. The editor preview and the export
/// both go through [paint], so burned-in text matches what the user placed.
class StudioTextPainter {
  StudioTextPainter._();

  static TextStyle _style(StudioText t, double fontSize, {Paint? foreground}) {
    final color = Color(t.color);
    final weight = switch (t.style) {
      StudioTextStyle.bold => FontWeight.w900,
      StudioTextStyle.plain => FontWeight.w700,
      _ => FontWeight.w800,
    };
    final shadows = switch (t.style) {
      StudioTextStyle.plain => [Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: fontSize * 0.18)],
      StudioTextStyle.glow => [
          Shadow(color: color.withValues(alpha: 0.9), blurRadius: fontSize * 0.45),
          Shadow(color: color.withValues(alpha: 0.6), blurRadius: fontSize * 0.9),
        ],
      StudioTextStyle.bold => [Shadow(color: Colors.black, offset: Offset(fontSize * 0.06, fontSize * 0.08))],
      _ => const <Shadow>[],
    };
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: weight,
      height: 1.18,
      color: foreground == null ? color : null,
      foreground: foreground,
      shadows: foreground == null ? shadows : null,
      letterSpacing: t.style == StudioTextStyle.bold ? -0.5 : -0.2,
    );
  }

  static TextPainter _layout(String text, TextStyle style, double maxWidth) {
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    p.layout(maxWidth: maxWidth);
    return p;
  }

  static double _padding(StudioText t, double fontSize) => t.style == StudioTextStyle.box ? fontSize * 0.38 : fontSize * 0.2;

  /// Size of the layer on a canvas [canvasWidth] wide.
  static Size measure(StudioText t, double canvasWidth) {
    final fontSize = t.size * canvasWidth;
    final pad = _padding(t, fontSize);
    final p = _layout(t.text.isEmpty ? ' ' : t.text, _style(t, fontSize), canvasWidth * 0.9);
    return Size(p.width + pad * 2, p.height + pad * 2);
  }

  /// Paints the layer with its top-left at the origin.
  static void paint(Canvas canvas, StudioText t, double canvasWidth) {
    final fontSize = t.size * canvasWidth;
    final pad = _padding(t, fontSize);
    final text = t.text.isEmpty ? ' ' : t.text;
    final fill = _layout(text, _style(t, fontSize), canvasWidth * 0.9);
    final size = Size(fill.width + pad * 2, fill.height + pad * 2);

    if (t.style == StudioTextStyle.box) {
      final light = Color(t.color).computeLuminance() > 0.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(fontSize * 0.28)),
        Paint()..color = (light ? Colors.black : Colors.white).withValues(alpha: 0.72),
      );
    }
    if (t.style == StudioTextStyle.outline || t.style == StudioTextStyle.bold) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fontSize * (t.style == StudioTextStyle.bold ? 0.16 : 0.1)
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black;
      _layout(text, _style(t, fontSize, foreground: stroke), canvasWidth * 0.9).paint(canvas, Offset(pad, pad));
    }
    fill.paint(canvas, Offset(pad, pad));
  }

  /// Renders the layer to a transparent PNG at [canvasWidth] scale.
  static Future<File> toPng(StudioText t, double canvasWidth, String outPath) async {
    final size = measure(t, canvasWidth);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas, t, canvasWidth);
    final picture = recorder.endRecording();
    final image = await picture.toImage(math.max(1, size.width.ceil()), math.max(1, size.height.ceil()));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final file = File(outPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    return file;
  }
}

/// Preview widget for one layer, sized for a canvas [canvasWidth] wide.
class StudioTextLayer extends StatelessWidget {
  final StudioText text;
  final double canvasWidth;
  final bool selected;

  const StudioTextLayer({super.key, required this.text, required this.canvasWidth, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final size = StudioTextPainter.measure(text, canvasWidth);
    return Container(
      decoration: selected
          ? BoxDecoration(border: Border.all(color: Colors.white, width: 1), borderRadius: BorderRadius.circular(4))
          : null,
      child: CustomPaint(size: size, painter: _LayerPainter(text, canvasWidth)),
    );
  }
}

class _LayerPainter extends CustomPainter {
  final StudioText text;
  final double canvasWidth;
  _LayerPainter(this.text, this.canvasWidth);

  @override
  void paint(Canvas canvas, Size size) => StudioTextPainter.paint(canvas, text, canvasWidth);

  @override
  bool shouldRepaint(_LayerPainter old) => old.text != text || old.canvasWidth != canvasWidth;
}
