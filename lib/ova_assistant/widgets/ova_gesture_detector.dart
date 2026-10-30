import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../shared/theme/app_theme.dart';
import '../services/ova_native_service.dart';

/// Wraps any widget and opens Ova on ONE gesture only: drawing an "O" on the
/// screen (it also captures the circled area as context). No other touch
/// opens Ova: taps, double taps, holds, lines and "1" strokes are ignored,
/// so scrolling and tapping around the app never summons it by accident.
class OvaGestureDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onTriggerOva;
  final void Function(Uint8List? screenBytes, Rect? circledRect)? onTriggerOvaWithContext;
  final bool autoVoiceCallMode;

  const OvaGestureDetector({
    super.key,
    required this.child,
    required this.onTriggerOva,
    this.onTriggerOvaWithContext,
    this.autoVoiceCallMode = false,
  });

  @override
  State<OvaGestureDetector> createState() => _OvaGestureDetectorState();
}

class _OvaGestureDetectorState extends State<OvaGestureDetector>
    with TickerProviderStateMixin {
  final OvaNativeService _nativeService = OvaNativeService();
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  bool _isTriggering = false;

  // ─────────────────────────────────────────────────────────────────────────────
  // Draw 'O' (Circle) Gesture Tracking
  // ─────────────────────────────────────────────────────────────────────────────
  final List<Offset> _strokePoints = [];
  bool _isDrawing = false;
  Offset? _detectedCircleCenter;
  double _detectedCircleRadius = 0.0;
  Rect? _detectedCircleRect;

  // "O" trail: shown only once a stroke curves like an O (never for taps,
  // scrolls or swipes), repainted without rebuilding the tree.
  final ValueNotifier<int> _trailTick = ValueNotifier<int>(0);
  bool _trailVisible = false;
  late AnimationController _trailFadeController;

  // Summon animation once an "O" is recognised: the ring closes, pulses and
  // morphs into the Ova orb, then Ova opens.
  late AnimationController _circleSuccessAnimController;
  List<Offset> _summonStroke = const [];
  bool _summonReduceMotion = false;

  Timer? _clearStrokeTimer;
  Timer? _debounceTimer;



  @override
  void initState() {
    super.initState();

    _circleSuccessAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _trailFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );

    // Wake screen & background capabilities
    _nativeService.wakeScreen();
  }

  @override
  void dispose() {
    _clearStrokeTimer?.cancel();
    _debounceTimer?.cancel();
    _circleSuccessAnimController.dispose();
    _trailFadeController.dispose();
    _trailTick.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Pointer Events Pipeline
  // ─────────────────────────────────────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent event) {
    if (_isTriggering) return;
    _trailFadeController.stop();
    _trailFadeController.value = 0;
    _strokePoints.clear();
    _strokePoints.add(event.position);
    _isDrawing = true;
    if (_trailVisible) setState(() => _trailVisible = false);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDrawing) return;
    _strokePoints.add(event.position);
    if (!_trailVisible && _looksLikeO(_strokePoints)) {
      setState(() => _trailVisible = true);
    }
    if (_trailVisible) _trailTick.value++;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDrawing && _strokePoints.length >= 12 && _recognizeCircleGesture(_strokePoints)) {
      _onCircleGestureRecognized();
      return;
    }
    // Not an "O": fade the trail out quietly, trigger nothing.
    if (_isDrawing) {
      _isDrawing = false;
      _fadeOutTrail();
    }
  }

  void _fadeOutTrail() {
    if (!_trailVisible) {
      _strokePoints.clear();
      return;
    }
    _trailFadeController.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || _isDrawing) return;
      setState(() {
        _trailVisible = false;
        _strokePoints.clear();
      });
    });
  }

  /// True once the stroke turns steadily one way (>~100 degrees) over a real
  /// distance: an "O" being drawn, not a tap, scroll or swipe.
  bool _looksLikeO(List<Offset> points) {
    if (points.length < 6) return false;
    double length = 0;
    double turning = 0;
    Offset? prevDir;
    Offset last = points.first;
    for (int i = 1; i < points.length; i++) {
      final seg = points[i] - last;
      if (seg.distance < 4) continue;
      length += seg.distance;
      if (prevDir != null) {
        var d = math.atan2(seg.dy, seg.dx) - math.atan2(prevDir.dy, prevDir.dx);
        while (d > math.pi) {
          d -= 2 * math.pi;
        }
        while (d < -math.pi) {
          d += 2 * math.pi;
        }
        turning += d;
      }
      prevDir = seg;
      last = points[i];
    }
    return length >= 48 && turning.abs() >= 1.75;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_isDrawing) {
      _isDrawing = false;
      _fadeOutTrail();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Screen Snapshot Capture (Gemini Overlay Visual Awareness)
  // ─────────────────────────────────────────────────────────────────────────────
  Future<Uint8List?> _captureCurrentScreen() async {
    // In automated widget test environment, skip toImage to avoid hanging the test harness
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      return null;
    }
    try {
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null && !boundary.debugNeedsPaint) {
        final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
        final ByteData? byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('[OvaGestureDetector] Screen capture exception: $e');
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 'O' (Circle) Gesture Detection Algorithm
  // ─────────────────────────────────────────────────────────────────────────────
  bool _recognizeCircleGesture(List<Offset> points) {
    if (points.length < 12) return false;

    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;
    double totalLength = 0;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
      if (i > 0) {
        totalLength += (p - points[i - 1]).distance;
      }
    }

    final width = maxX - minX;
    final height = maxY - minY;

    // 1. Minimum bounding box dimension (at least 35x35 px)
    if (width < 35 || height < 35) return false;

    // 2. Aspect ratio check (circle should be rounded: 0.40 to 2.40)
    final aspectRatio = width / height;
    if (aspectRatio < 0.40 || aspectRatio > 2.40) return false;

    // 3. Closure distance: start and end points must be reasonably close
    final maxDim = math.max(width, height);
    final closureDist = (points.first - points.last).distance;
    if (closureDist > maxDim * 0.50) return false;

    // 4. Perimeter heuristic: perimeter must correlate with circle circumference
    final avgRadius = (width + height) / 4.0;
    if (totalLength < 3.2 * avgRadius || totalLength > 12.0 * avgRadius) return false;

    // 5. Angular sweep: calculate net angular traversal around the bounding box center
    final center = Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
    double totalAngle = 0;
    double? prevAngle;

    for (final p in points) {
      final angle = math.atan2(p.dy - center.dy, p.dx - center.dx);
      if (prevAngle != null) {
        double delta = angle - prevAngle;
        while (delta > math.pi) {
          delta -= 2 * math.pi;
        }
        while (delta < -math.pi) {
          delta += 2 * math.pi;
        }
        totalAngle += delta;
      }
      prevAngle = angle;
    }

    // A closed 'O' sweeps at least ~250° (4.3 radians) around its center
    if (totalAngle.abs() >= 4.3) {
      _detectedCircleCenter = center;
      _detectedCircleRadius = avgRadius;
      _detectedCircleRect = Rect.fromCircle(center: center, radius: avgRadius);
      return true;
    }

    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // '1' (Vertical Stroke) Gesture Detection Algorithm
  // ─────────────────────────────────────────────────────────────────────────────
  void _onCircleGestureRecognized() async {
    if (_isTriggering) return;
    _isTriggering = true;
    _isDrawing = false;

    HapticFeedback.heavyImpact();
    _nativeService.triggerHapticPulse(90);

    final circledRect = _detectedCircleRect;
    final stroke = List<Offset>.of(_strokePoints);

    // Capture screen context once before triggering (the summon animation
    // sits outside the captured boundary).
    Uint8List? screenBytes;
    try {
      screenBytes = await _captureCurrentScreen();
    } catch (e) {
      debugPrint('[OvaGestureDetector] Screen capture error: $e');
    }
    if (!mounted) return;

    // Settings > Accessibility > Reduce motion: a short fade instead.
    _summonReduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _circleSuccessAnimController.duration =
        Duration(milliseconds: _summonReduceMotion ? 200 : 720);
    setState(() {
      _trailVisible = false;
      _strokePoints.clear();
      _summonStroke = stroke;
    });
    await _circleSuccessAnimController.forward(from: 0.0);
    if (!mounted) return;

    // Trigger assistant overlay once with captured screen context
    _triggerAssistantWithContext(screenBytes, circledRect);
    setState(() {
      _summonStroke = const [];
      _detectedCircleCenter = null;
      _detectedCircleRect = null;
    });

    // Reset triggering debounce guard
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 900), () {
      _isTriggering = false;
    });
  }

  void _triggerAssistantWithContext(Uint8List? screenBytes, Rect? circledRect) {
    try {
      HapticFeedback.heavyImpact();
      _nativeService.wakeScreen();
      // Invoke ONLY ONE callback to guarantee single popup
      if (widget.onTriggerOvaWithContext != null) {
        widget.onTriggerOvaWithContext!(screenBytes, circledRect);
      } else {
        widget.onTriggerOva();
      }
    } catch (e, st) {
      debugPrint('[OvaGestureDetector] Error triggering assistant with context: $e\n$st');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI Builder
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        children: [
          // Wrapped child inside RepaintBoundary for instant Gemini-style screen capture
          RepaintBoundary(
            key: _repaintBoundaryKey,
            child: widget.child,
          ),

          // "O" trail, only while an O is being drawn.
          if (_trailVisible)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: OvaTrailPainter(
                      points: _strokePoints,
                      fade: _trailFadeController,
                      repaint: Listenable.merge([_trailTick, _trailFadeController]),
                    ),
                  ),
                ),
              ),
            ),

          // Summon: ring closes, pulses and becomes the Ova orb.
          if (_detectedCircleCenter != null && _summonStroke.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: OvaSummonPainter(
                      center: _detectedCircleCenter!,
                      radius: _detectedCircleRadius,
                      stroke: _summonStroke,
                      progress: _circleSuccessAnimController,
                      reduceMotion: _summonReduceMotion,
                    ),
                  ),
                ),
              ),
            ),

        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// "O" trail: brand gradient, soft glow, tapered tail, fades out on release.
// ─────────────────────────────────────────────────────────────────────────────
class OvaTrailPainter extends CustomPainter {
  final List<Offset> points;
  final Animation<double> fade;

  OvaTrailPainter({required this.points, required this.fade, required Listenable repaint})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = 1.0 - fade.value;
    if (points.length < 2 || opacity <= 0) return;
    paintOvaStroke(canvas, points, opacity);
  }

  @override
  bool shouldRepaint(covariant OvaTrailPainter oldDelegate) => oldDelegate.points != points;
}

/// Shared by the trail and the first phase of the summon animation.
void paintOvaStroke(Canvas canvas, List<Offset> points, double opacity) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (int i = 1; i < points.length; i++) {
    path.lineTo(points[i].dx, points[i].dy);
  }
  // Soft glow under the whole stroke.
  canvas.drawPath(
    path,
    Paint()
      ..color = AppColors.brandBlue.withValues(alpha: 0.30 * opacity)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
  );
  // Tapered core: thin and faint at the tail, thick and bright at the finger.
  final core = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final n = points.length - 1;
  for (int i = 1; i <= n; i++) {
    final t = i / n;
    core
      ..strokeWidth = 2.0 + 5.5 * t
      ..color = Color.lerp(AppColors.brandBlue, AppColors.brandPink, t)!
          .withValues(alpha: (0.30 + 0.70 * t) * opacity);
    canvas.drawLine(points[i - 1], points[i], core);
  }
  // Bright tip.
  canvas.drawCircle(
    points.last,
    9,
    Paint()
      ..color = AppColors.brandPink.withValues(alpha: 0.45 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawCircle(points.last, 3.5, Paint()..color = AppColors.brandWhite.withValues(alpha: 0.95 * opacity));
}

// ─────────────────────────────────────────────────────────────────────────────
// Summon: the drawn ring closes into a perfect circle, pulses, then shrinks
// into the glowing Ova orb. Reduce motion: the ring just fades.
// ─────────────────────────────────────────────────────────────────────────────
class OvaSummonPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final List<Offset> stroke;
  final Animation<double> progress;
  final bool reduceMotion;

  OvaSummonPainter({
    required this.center,
    required this.radius,
    required this.stroke,
    required this.progress,
    required this.reduceMotion,
  }) : super(repaint: progress);

  static double _interval(double t, double begin, double end, [Curve curve = Curves.linear]) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (reduceMotion) {
      _ring(canvas, radius, 1.0 - t, 4, 0);
      return;
    }

    // 1. The hand-drawn stroke fades while a perfect ring closes over it.
    final close = _interval(t, 0.0, 0.35, Curves.easeOutCubic);
    if (close < 1 && stroke.length > 1) paintOvaStroke(canvas, stroke, 1 - close);
    final start = stroke.isEmpty ? -math.pi / 2 : math.atan2(stroke.first.dy - center.dy, stroke.first.dx - center.dx);

    // 2. Pulse.
    final pulse = math.sin(math.pi * _interval(t, 0.30, 0.58));
    // 3. Morph into the orb.
    final morph = _interval(t, 0.55, 1.0, Curves.easeInOutCubic);
    const orbRadius = 26.0;
    final r = ui.lerpDouble(radius * (1 + 0.12 * pulse), orbRadius, morph)!;

    if (morph < 1) {
      final sweep = 2 * math.pi * close;
      _ring(canvas, r, 1.0 - morph * 0.4, 5 + 3 * pulse, t, start: start, sweep: sweep);
    }
    if (morph > 0) {
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawCircle(
        center,
        r * 1.8,
        Paint()
          ..color = AppColors.brandPink.withValues(alpha: 0.35 * morph)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * morph + 1),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            colors: [
              AppColors.brandWhite.withValues(alpha: 0.95 * morph),
              AppColors.brandPink.withValues(alpha: morph),
              AppColors.brandBlue.withValues(alpha: morph),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(rect),
      );
    }
  }

  void _ring(Canvas canvas, double r, double opacity, double width, double spin,
      {double start = -math.pi / 2, double sweep = 2 * math.pi}) {
    if (opacity <= 0 || sweep <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = AppColors.brandBlue.withValues(alpha: 0.4 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..shader = SweepGradient(
          colors: [
            AppColors.brandBlue.withValues(alpha: opacity),
            AppColors.brandPink.withValues(alpha: opacity),
            AppColors.brandBlue.withValues(alpha: opacity),
          ],
          transform: GradientRotation(start + 2 * math.pi * spin),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(covariant OvaSummonPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.reduceMotion != reduceMotion;
}
