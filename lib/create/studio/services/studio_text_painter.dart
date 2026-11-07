import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import 'studio_text_animator.dart';

/// What part of a layer to draw (reveal animations and word highlights).
class StudioTextReveal {
  /// Visible characters, or null for all.
  final int? chars;

  /// Visible words, or null for all.
  final int? words;

  /// Highlighted (spoken) word, -1 for none.
  final int activeWord;

  const StudioTextReveal({this.chars, this.words, this.activeWord = -1});

  static const all = StudioTextReveal();

  String get key => '${chars ?? '-'}_${words ?? '-'}_$activeWord';

  @override
  bool operator ==(Object other) => other is StudioTextReveal && other.key == key;

  @override
  int get hashCode => key.hashCode;

  /// Reveal of [t] at output time [ms].
  static StudioTextReveal of(StudioText t, int ms, StudioAnimFrame f) {
    final units = StudioTextAnimator.visibleUnits(t, f, ms);
    return StudioTextReveal(
      chars: f.revealMode == 1 ? units : null,
      words: f.revealMode == 2 || f.revealMode == 3 ? units : null,
      activeWord: StudioTextAnimator.activeWord(t, ms),
    );
  }
}

/// Paints a text / sticker / caption layer. The editor preview and the export
/// both go through [paint], so burned-in text matches what the user placed.
class StudioTextPainter {
  StudioTextPainter._();

  static const _transparent = Color(0x00000000);

  static FontWeight _weight(int w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

  /// Google font [family] at [fontSize]; Inter if the family is unknown.
  static TextStyle font(String family, {double fontSize = 14, int weight = 700, bool italic = false}) {
    try {
      return GoogleFonts.getFont(family, fontSize: fontSize, fontWeight: _weight(weight), fontStyle: italic ? FontStyle.italic : null);
    } catch (_) {
      return GoogleFonts.inter(fontSize: fontSize, fontWeight: _weight(weight), fontStyle: italic ? FontStyle.italic : null);
    }
  }

  static TextStyle _base(StudioTypeStyle s, double fontSize) => font(s.font, fontSize: fontSize, weight: s.weight, italic: s.italic).copyWith(
        height: s.lineHeight,
        letterSpacing: s.letterSpacing * fontSize,
      );

  static TextAlign _align(StudioTypeStyle s) => switch (s.align) {
        0 => TextAlign.left,
        2 => TextAlign.right,
        _ => TextAlign.center,
      };

  static List<Shadow> _shadows(StudioTypeStyle s, double fontSize) {
    if (s.glow) {
      final c = Color(s.shadowColor);
      final b = math.max(0.1, s.shadowBlur);
      return [
        Shadow(color: c.withValues(alpha: 0.9), blurRadius: fontSize * b),
        Shadow(color: c.withValues(alpha: 0.6), blurRadius: fontSize * b * 2),
      ];
    }
    if (s.shadowBlur <= 0 && s.shadowDx == 0 && s.shadowDy == 0) return const [];
    return [
      Shadow(
        color: Color(s.shadowColor),
        blurRadius: fontSize * s.shadowBlur,
        offset: Offset(fontSize * s.shadowDx, fontSize * s.shadowDy),
      ),
    ];
  }

  /// Text split into words and the whitespace between them.
  static List<(String, bool)> _tokens(String text) {
    final out = <(String, bool)>[];
    final re = RegExp(r'\s+');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) out.add((text.substring(last, m.start), true));
      out.add((m.group(0)!, false));
      last = m.end;
    }
    if (last < text.length) out.add((text.substring(last), true));
    return out;
  }

  /// Builds the spans for one pass ([styleFor] picks each piece's style).
  static TextSpan _spans(String text, StudioTextReveal r, TextStyle Function(bool visible, bool active) styleFor) {
    if (r.chars == null && r.words == null && r.activeWord < 0) {
      return TextSpan(text: text, style: styleFor(true, false));
    }
    final children = <TextSpan>[];
    if (r.chars != null) {
      final runes = text.runes.toList();
      final n = r.chars!.clamp(0, runes.length);
      if (n > 0) children.add(TextSpan(text: String.fromCharCodes(runes.take(n)), style: styleFor(true, false)));
      if (n < runes.length) children.add(TextSpan(text: String.fromCharCodes(runes.skip(n)), style: styleFor(false, false)));
      return TextSpan(children: children);
    }
    var word = 0;
    for (final (piece, isWord) in _tokens(text)) {
      if (!isWord) {
        final visible = r.words == null || word < r.words! || word == 0;
        children.add(TextSpan(text: piece, style: styleFor(visible && (r.words == null || word < r.words!), false)));
        continue;
      }
      final visible = r.words == null || word < r.words!;
      children.add(TextSpan(text: piece, style: styleFor(visible, word == r.activeWord)));
      word++;
    }
    return TextSpan(children: children);
  }

  static TextPainter _layout(TextSpan span, StudioTypeStyle s, double maxWidth) {
    final p = TextPainter(text: span, textAlign: _align(s), textDirection: TextDirection.ltr);
    p.layout(maxWidth: maxWidth);
    return p;
  }

  static bool _boxed(StudioTypeStyle s) =>
      s.bg == StudioTextBg.box || s.bg == StudioTextBg.pill || s.bg == StudioTextBg.bar || s.bg == StudioTextBg.perLine;

  static double _padding(StudioTypeStyle s, double fontSize) {
    var pad = _boxed(s) ? fontSize * 0.38 : fontSize * 0.2;
    if (s.bg == StudioTextBg.bar) pad = fontSize * 0.5;
    if (s.bg == StudioTextBg.frame) pad = fontSize * 0.45;
    pad += s.stroke * fontSize * 0.5;
    final shadow = s.glow ? math.max(0.1, s.shadowBlur) * 2 : s.shadowBlur;
    pad += fontSize * (shadow + math.max(s.shadowDx.abs(), s.shadowDy.abs())) * 0.9;
    return pad;
  }

  /// Size of the layer on a canvas [canvasWidth] wide.
  static Size measure(StudioText t, double canvasWidth) {
    final fontSize = t.size * canvasWidth;
    final pad = _padding(t.type, fontSize);
    final base = _base(t.type, fontSize);
    final p = _layout(TextSpan(text: StudioTextAnimator.display(t), style: base), t.type, canvasWidth * 0.9);
    return Size(p.width + pad * 2, p.height + pad * 2);
  }

  /// Paints the layer with its top-left at the origin.
  static void paint(Canvas canvas, StudioText t, double canvasWidth, {StudioTextReveal reveal = StudioTextReveal.all}) {
    final s = t.type;
    final fontSize = t.size * canvasWidth;
    final pad = _padding(s, fontSize);
    final text = StudioTextAnimator.display(t);
    final base = _base(s, fontSize);
    final shadows = _shadows(s, fontSize);
    final color = Color(s.color);
    final highlight = s.highlightColor == 0 ? null : Color(s.highlightColor);

    final measure = _layout(TextSpan(text: text, style: base), s, canvasWidth * 0.9);
    final size = Size(measure.width + pad * 2, measure.height + pad * 2);
    final textRect = Rect.fromLTWH(pad, pad, measure.width, measure.height);

    // Background.
    final bg = Paint()..color = Color(s.bgColor);
    switch (s.bg) {
      case StudioTextBg.box:
        canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(fontSize * 0.28)), bg);
      case StudioTextBg.pill:
        canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)), bg);
      case StudioTextBg.bar:
        canvas.drawRect(Offset.zero & size, bg);
      case StudioTextBg.underline:
        final h = fontSize * 0.16;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(pad * 0.6, textRect.bottom - h * 0.7, size.width - pad * 1.2, h), Radius.circular(h / 2)),
          bg,
        );
      case StudioTextBg.frame:
        canvas.drawRRect(
          RRect.fromRectAndRadius((Offset.zero & size).deflate(fontSize * 0.05), Radius.circular(fontSize * 0.12)),
          Paint()
            ..color = Color(s.bgColor)
            ..style = PaintingStyle.stroke
            ..strokeWidth = fontSize * 0.07,
        );
      case StudioTextBg.perLine:
        final r = fontSize * 0.2;
        for (final line in measure.computeLineMetrics()) {
          final rect = Rect.fromLTWH(
            pad + line.left - fontSize * 0.25,
            pad + line.baseline - line.ascent - fontSize * 0.08,
            line.width + fontSize * 0.5,
            line.ascent + line.descent + fontSize * 0.16,
          );
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), bg);
        }
      case StudioTextBg.none:
        break;
    }

    final offset = Offset(pad, pad);
    final hasStroke = s.stroke > 0;

    // Outline (carries the shadow so it hugs the outline).
    if (hasStroke) {
      final span = _spans(text, reveal, (visible, active) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = fontSize * s.stroke
          ..strokeJoin = StrokeJoin.round
          ..color = visible ? Color(s.strokeColor) : _transparent;
        return base.copyWith(foreground: paint, shadows: visible ? shadows : const []);
      });
      _layout(span, s, canvasWidth * 0.9).paint(canvas, offset);
    }

    // Fill.
    final gradient = s.color2 != 0
        ? (LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, Color(s.color2)])
            .createShader(textRect))
        : null;
    final span = _spans(text, reveal, (visible, active) {
      if (!visible) return base.copyWith(color: _transparent, shadows: const []);
      final shadow = hasStroke ? const <Shadow>[] : shadows;
      if (active && highlight != null) return base.copyWith(color: highlight, shadows: shadow);
      if (gradient != null) return base.copyWith(foreground: Paint()..shader = gradient, shadows: shadow);
      return base.copyWith(color: color, shadows: shadow);
    });
    _layout(span, s, canvasWidth * 0.9).paint(canvas, offset);
  }

  /// Renders the layer to a transparent PNG at [canvasWidth] scale.
  static Future<File> toPng(StudioText t, double canvasWidth, String outPath, {StudioTextReveal reveal = StudioTextReveal.all}) async {
    final size = measure(t, canvasWidth);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas, t, canvasWidth, reveal: reveal);
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

  /// Waits for every Google font the [texts] use, so exports never render
  /// with a fallback font.
  static Future<void> ensureFonts(Iterable<StudioText> texts) async {
    for (final t in texts) {
      font(t.type.font, weight: t.type.weight, italic: t.type.italic);
    }
    try {
      await GoogleFonts.pendingFonts();
    } catch (e) {
      debugPrint('[StudioTextPainter] font load failed: $e');
    }
  }
}

/// Preview widget for one layer, sized for a canvas [canvasWidth] wide.
class StudioTextLayer extends StatelessWidget {
  final StudioText text;
  final double canvasWidth;
  final bool selected;
  final StudioTextReveal reveal;

  const StudioTextLayer({
    super.key,
    required this.text,
    required this.canvasWidth,
    this.selected = false,
    this.reveal = StudioTextReveal.all,
  });

  @override
  Widget build(BuildContext context) {
    final size = StudioTextPainter.measure(text, canvasWidth);
    return Container(
      decoration: selected
          ? BoxDecoration(
              border: Border.all(color: AppColors.brandWhite.withValues(alpha: 0.9), width: 1),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: CustomPaint(size: size, painter: _LayerPainter(text, canvasWidth, reveal)),
    );
  }
}

class _LayerPainter extends CustomPainter {
  final StudioText text;
  final double canvasWidth;
  final StudioTextReveal reveal;
  _LayerPainter(this.text, this.canvasWidth, this.reveal);

  @override
  void paint(Canvas canvas, Size size) => StudioTextPainter.paint(canvas, text, canvasWidth, reveal: reveal);

  @override
  bool shouldRepaint(_LayerPainter old) => old.text != text || old.canvasWidth != canvasWidth || old.reveal != reveal;
}
