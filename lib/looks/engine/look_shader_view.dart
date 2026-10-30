import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/oneova_look.dart';
import 'look_compiler.dart';

/// Real-time GPU view that renders [image] through [look].
///
/// LUTs and curves compile asynchronously; until they are ready the previous
/// compiled look (or the untouched image on first load) is shown.
class LookShaderView extends StatefulWidget {
  final ui.Image image;
  final OneovaLook look;
  final BoxFit fit;

  /// Caps the composed LUT size (lower on low-tier devices).
  final int maxLutSize;

  const LookShaderView({
    super.key,
    required this.image,
    required this.look,
    this.fit = BoxFit.contain,
    this.maxLutSize = 65,
  });

  @override
  State<LookShaderView> createState() => _LookShaderViewState();
}

class _LookShaderViewState extends State<LookShaderView> {
  ui.FragmentProgram? _program;
  CompiledLook? _compiled;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    LookCompiler.loadProgram().then((p) {
      if (mounted) setState(() => _program = p);
    });
    _compile();
  }

  @override
  void didUpdateWidget(covariant LookShaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.look, widget.look) || oldWidget.maxLutSize != widget.maxLutSize) {
      _compile();
    }
  }

  void _compile() {
    final request = ++_request;
    LookCompiler.compile(widget.look, maxLutSize: widget.maxLutSize).then((c) {
      if (mounted && request == _request) setState(() => _compiled = c);
    }, onError: (Object e) {
      debugPrint('[LookShaderView] compile failed: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    final compiled = _compiled;
    if (program == null || compiled == null) {
      return RawImage(image: widget.image, fit: widget.fit);
    }
    return FittedBox(
      fit: widget.fit,
      child: SizedBox(
        width: widget.image.width.toDouble(),
        height: widget.image.height.toDouble(),
        child: CustomPaint(
          painter: _LookShaderPainter(
            program: program,
            compiled: compiled,
            image: widget.image,
          ),
        ),
      ),
    );
  }
}

class _LookShaderPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final CompiledLook compiled;
  final ui.Image image;

  _LookShaderPainter({required this.program, required this.compiled, required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    final shader = LookCompiler.createShader(program, compiled, image, size);
    // Not disposed here: the recorded frame still references it until raster.
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _LookShaderPainter old) =>
      !identical(old.compiled, compiled) || !identical(old.image, image) || old.program != program;
}

/// Offscreen GPU renderer for full-resolution exports and thumbnails.
class LookImageRenderer {
  LookImageRenderer._();

  /// Renders [inputImage] through [look] at its original resolution.
  /// Throws [StateError] if the shader cannot be loaded, so callers never
  /// export an ungraded image believing it was graded.
  static Future<ui.Image> renderGradedImage({
    required ui.Image inputImage,
    required OneovaLook look,
    int maxLutSize = 65,
  }) async {
    final program = await LookCompiler.loadProgram();
    if (program == null) {
      throw StateError('Look engine shader unavailable');
    }
    final compiled = await LookCompiler.compile(look, maxLutSize: maxLutSize);
    final width = inputImage.width, height = inputImage.height;
    final size = Size(width.toDouble(), height.toDouble());

    final shader = LookCompiler.createShader(program, compiled, inputImage, size);
    final recorder = ui.PictureRecorder();
    Canvas(recorder, Offset.zero & size).drawRect(Offset.zero & size, Paint()..shader = shader);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
      shader.dispose();
    }
  }
}
