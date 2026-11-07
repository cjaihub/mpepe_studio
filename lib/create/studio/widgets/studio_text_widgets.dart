import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/studio_project.dart';
import '../services/studio_text_animator.dart';
import '../services/studio_text_painter.dart';

/// A text layer at output time [ms], moved the way the export moves it
/// (same animator, same painter).
class StudioAnimatedTextLayer extends StatelessWidget {
  final StudioText text;

  /// Canvas the layer is placed on (offsets are fractions of it).
  final Size canvas;
  final int ms;
  final bool selected;

  const StudioAnimatedTextLayer({super.key, required this.text, required this.canvas, required this.ms, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final f = StudioTextAnimator.at(text, ms);
    final reveal = StudioTextReveal.of(text, ms, f);
    Widget child = StudioTextLayer(text: text, canvasWidth: canvas.width, selected: selected, reveal: reveal);
    final moved = f.dx != 0 || f.dy != 0 || f.rot != 0 || f.sx != 1 || f.sy != 1;
    if (moved) {
      child = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(f.dx * canvas.width, f.dy * canvas.height, 0, 1)
          ..rotateZ(f.rot * math.pi / 180)
          ..scaleByDouble(f.sx, f.sy, 1, 1),
        child: child,
      );
    }
    final alpha = f.alpha.clamp(0.0, 1.0);
    if (alpha < 1) child = Opacity(opacity: alpha, child: child);
    return child;
  }
}

/// Loops a layer's animation on a small stage (editor sheet preview).
class StudioTextLoopPreview extends StatefulWidget {
  final StudioText text;
  final double height;
  const StudioTextLoopPreview({super.key, required this.text, this.height = 120});

  @override
  State<StudioTextLoopPreview> createState() => _StudioTextLoopPreviewState();
}

class _StudioTextLoopPreviewState extends State<StudioTextLoopPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _duration)..repeat();

  Duration get _duration {
    final t = widget.text;
    final layer = (t.endMs - t.startMs).clamp(1500, 6000);
    return Duration(milliseconds: layer + 500);
  }

  @override
  void didUpdateWidget(StudioTextLoopPreview old) {
    super.didUpdateWidget(old);
    if (_c.duration != _duration) {
      _c.duration = _duration;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, box) {
        final canvas = Size(math.min(box.maxWidth, widget.height * 9 / 16 * 2.2), widget.height);
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = widget.text;
            final dur = (t.endMs - t.startMs).clamp(1500, 6000);
            // Hold the last frame for half a second before the loop restarts.
            final local = math.min(dur - 1, (_c.value * (_c.duration!.inMilliseconds)).round());
            final preview = t.copyWith(startMs: 0, endMs: dur, words: _spreadWords(t, dur));
            return Center(
              child: SizedBox(
                width: canvas.width,
                height: canvas.height,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: StudioAnimatedTextLayer(text: preview, canvas: canvas, ms: local),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  /// Keeps timed words (captions) in proportion when the preview loops.
  List<StudioWord> _spreadWords(StudioText t, int dur) {
    if (t.words.isEmpty) return const [];
    final span = math.max(1, t.endMs - t.startMs);
    return [
      for (final w in t.words)
        StudioWord(w.text, ((w.startMs - t.startMs) * dur / span).round(), ((w.endMs - t.startMs) * dur / span).round()),
    ];
  }
}
