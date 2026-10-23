import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

/// Detects a hand-drawn circle anywhere on [child].
///
/// Uses raw pointer events, so it never enters the gesture arena: vertical
/// reel scrolling, taps and double-tap likes keep working untouched. While a
/// stroke is in progress a faint brand-pink trail follows the finger.
class OneovaCircleGesture extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback onCircle;

  const OneovaCircleGesture({
    super.key,
    required this.child,
    required this.onCircle,
    this.enabled = true,
  });

  /// Pure shape test, exposed for unit tests. True when [pts] form a roughly
  /// round, closed loop of at least ~300 degrees of rotation.
  static bool isCircle(List<Offset> pts) {
    if (pts.length < 12) return false;
    double minX = pts.first.dx, maxX = pts.first.dx, minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = maxX - minX, h = maxY - minY;
    if (w < 70 || h < 70) return false;
    final aspect = w / h;
    if (aspect < 0.5 || aspect > 2.0) return false;

    // Closed: the stroke ends near where it started.
    final diag = math.sqrt(w * w + h * h);
    if ((pts.last - pts.first).distance > diag * 0.38) return false;

    // Round: every point sits at a similar distance from the centre.
    final c = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final r = (w + h) / 4;
    for (final p in pts) {
      final d = (p - c).distance;
      if (d < r * 0.45 || d > r * 1.65) return false;
    }

    // Total signed rotation around the centre.
    double total = 0;
    for (var i = 1; i < pts.length; i++) {
      final a = (pts[i - 1] - c).direction;
      final b = (pts[i] - c).direction;
      var d = b - a;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      total += d;
    }
    return total.abs() >= 5.2; // ~300 degrees
  }

  @override
  State<OneovaCircleGesture> createState() => _OneovaCircleGestureState();
}

class _OneovaCircleGestureState extends State<OneovaCircleGesture> {
  final List<Offset> _pts = [];
  int? _pointer;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  void _reset() {
    _pts.clear();
    _pointer = null;
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _pts
          ..clear()
          ..add(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer != _pointer) return;
        _pts.add(e.localPosition);
        _repaint.value++;
      },
      onPointerUp: (e) {
        if (e.pointer != _pointer) return;
        final hit = OneovaCircleGesture.isCircle(List<Offset>.of(_pts));
        _reset();
        if (hit) widget.onCircle();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _reset();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: CustomPaint(painter: _TrailPainter(_pts, _repaint)),
          ),
        ],
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  final List<Offset> pts;
  _TrailPainter(this.pts, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    // Only the tail of the stroke is drawn, fading toward its start.
    final start = math.max(0, pts.length - 40);
    for (var i = start + 1; i < pts.length; i++) {
      final t = (i - start) / (pts.length - start);
      canvas.drawLine(
        pts[i - 1],
        pts[i],
        Paint()
          ..color = AppColors.brandPink.withValues(alpha: 0.75 * t)
          ..strokeWidth = 2.0 + 3.0 * t
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) => true;
}
