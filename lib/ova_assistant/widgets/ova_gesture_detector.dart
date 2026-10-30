import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../shared/theme/app_theme.dart';
import '../services/ova_native_service.dart';

/// Wraps any widget and provides system-wide gesture activation for OneOva Assistant:
/// 1. "Draw 'O'" (Circle/Cycle Gesture) over current screen captures screen context like Gemini Overlay.
/// 2. "Double-Tap Anywhere" to activate.
/// 3. Luminous neon particle trail and completion ripple.
class OvaGestureDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onTriggerOva;
  final void Function(Uint8List? screenBytes, Rect? circledRect)? onTriggerOvaWithContext;
  final bool doubleTapEnabled;
  final bool drawOGestureEnabled;
  final bool drawOneGestureEnabled;
  final bool doubleTapHoldEnabled;
  final bool tripleTapHoldEnabled;
  final bool onlyTripleTapHold;
  final int holdDurationSeconds;
  final bool autoVoiceCallMode;

  const OvaGestureDetector({
    super.key,
    required this.child,
    required this.onTriggerOva,
    this.onTriggerOvaWithContext,
    this.doubleTapEnabled = true,
    this.drawOGestureEnabled = true,
    this.drawOneGestureEnabled = true,
    this.doubleTapHoldEnabled = false,
    this.tripleTapHoldEnabled = true,
    this.onlyTripleTapHold = false,
    this.holdDurationSeconds = 3,
    this.autoVoiceCallMode = false,
    // Kept for backward compatibility if passed, but draggable is removed per user request
    bool showFloatingTrigger = false,
  });

  @override
  State<OvaGestureDetector> createState() => _OvaGestureDetectorState();
}

class _OvaGestureDetectorState extends State<OvaGestureDetector>
    with TickerProviderStateMixin {
  final OvaNativeService _nativeService = OvaNativeService();
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  // ─────────────────────────────────────────────────────────────────────────────
  // Multi-Tap & Gesture Guard Tracking
  // ─────────────────────────────────────────────────────────────────────────────
  DateTime? _lastTapUpTime;
  Offset? _lastTapUpPosition;
  int _tapCount = 0;
  bool _isTriggering = false;
  static const int _doubleTapThresholdMs = 380;
  static const double _doubleTapMaxDistance = 35.0;

  // ─────────────────────────────────────────────────────────────────────────────
  // Draw 'O' (Circle) & '1' (Vertical Stroke) Gesture Tracking
  // ─────────────────────────────────────────────────────────────────────────────
  final List<Offset> _strokePoints = [];
  bool _isDrawing = false;
  Offset? _detectedCircleCenter;
  double _detectedCircleRadius = 0.0;
  Rect? _detectedCircleRect;
  Rect? _detectedStrokeRect;

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

  // ─────────────────────────────────────────────────────────────────────────────
  // Hold / Double-Tap & Hold / Triple-Tap & Hold Tracking
  // ─────────────────────────────────────────────────────────────────────────────
  bool _isHolding = false;
  bool _isDoubleTapHolding = false;
  bool _isTripleTapHolding = false;
  double _holdProgress = 0.0;
  Timer? _holdTimer;
  Timer? _tickTimer;
  Timer? _clearStrokeTimer;
  Timer? _debounceTimer;
  Offset _currentFingerPosition = Offset.zero;
  Offset _pointerDownPosition = Offset.zero;

  late AnimationController _hudAnimController;
  late Animation<double> _hudScale;
  late Animation<double> _hudOpacity;

  static const double _maxSlopForHold = 18.0;

  @override
  void initState() {
    super.initState();

    // Charging HUD Animations
    _hudAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _hudScale = CurvedAnimation(parent: _hudAnimController, curve: Curves.easeOutBack);
    _hudOpacity = CurvedAnimation(parent: _hudAnimController, curve: Curves.easeIn);

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
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    _clearStrokeTimer?.cancel();
    _debounceTimer?.cancel();
    _hudAnimController.dispose();
    _circleSuccessAnimController.dispose();
    _trailFadeController.dispose();
    _trailTick.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Pointer Events Pipeline
  // ─────────────────────────────────────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    _pointerDownPosition = event.position;
    _currentFingerPosition = event.position;

    // Check if this tap constitutes a consecutive tap in a multi-tap sequence
    final isConsecutiveTap = _lastTapUpTime != null &&
        now.difference(_lastTapUpTime!).inMilliseconds <= _doubleTapThresholdMs &&
        _lastTapUpPosition != null &&
        (event.position - _lastTapUpPosition!).distance <= _doubleTapMaxDistance;

    if (isConsecutiveTap) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }

    // 1. Triple-Tap & Hold: User tapped 3 times and is holding finger on 3rd tap
    if (_tapCount >= 3 && widget.tripleTapHoldEnabled) {
      _lastTapUpTime = null;
      _lastTapUpPosition = null;
      _isDrawing = false;
      _strokePoints.clear();
      _startHoldSequence(event.position, isTripleTap: true);
      return;
    }

    // If "Only Triple-Tap & Hold" is enabled (e.g. for Home Page reels feed),
    // ignore double-taps and draw gestures to completely prevent accidental popups!
    if (widget.onlyTripleTapHold) {
      return;
    }

    // 2. Double-Tap Candidate (2nd tap)
    if (_tapCount == 2 && widget.doubleTapEnabled) {
      if (widget.doubleTapHoldEnabled) {
        _lastTapUpTime = null;
        _lastTapUpPosition = null;
        _isDrawing = false;
        _startHoldSequence(event.position, isDoubleTap: true);
        return;
      } else if (!widget.tripleTapHoldEnabled) {
        // Instantaneous Double-Tap if triple-tap hold is disabled
        _lastTapUpTime = null;
        _lastTapUpPosition = null;
        _triggerAssistant(triggerType: 'Double-Tap');
        return;
      }
      // If triple-tap hold is enabled, wait to see if 3rd tap occurs
    }

    // 3. Start drawing path for 'O' or '1' gesture if enabled
    if ((widget.drawOGestureEnabled || widget.drawOneGestureEnabled) && !_isTriggering) {
      _trailFadeController.stop();
      _trailFadeController.value = 0;
      _strokePoints.clear();
      _strokePoints.add(event.position);
      _isDrawing = true;
      if (_trailVisible) setState(() => _trailVisible = false);
    }

  }

  void _onPointerMove(PointerMoveEvent event) {
    _currentFingerPosition = event.position;

    // If finger moves substantially, cancel stationary hold
    if (_isHolding && (event.position - _pointerDownPosition).distance > _maxSlopForHold) {
      _cancelHoldSequence();
      _tapCount = 0;
    }

    // Accumulate points for gesture recognition ('O' or '1') if not in onlyTripleTapHold mode
    if (_isDrawing && !widget.onlyTripleTapHold && (widget.drawOGestureEnabled || widget.drawOneGestureEnabled)) {
      _strokePoints.add(event.position);
      if (!_trailVisible && widget.drawOGestureEnabled && _looksLikeO(_strokePoints)) {
        setState(() => _trailVisible = true);
      }
      if (_trailVisible) _trailTick.value++;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final now = DateTime.now();
    final moveDistance = (event.position - _pointerDownPosition).distance;

    // Cancel in-progress hold sequence if finger was lifted early
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    if (_isHolding) {
      _cancelHoldSequence();
      _tapCount = 0;
    }

    // If finger moved beyond slop (e.g. scrolling/swiping video feeds on home page),
    // reset multi-tap state so reels scrolling never triggers Ova
    if (moveDistance > _doubleTapMaxDistance) {
      _tapCount = 0;
      _lastTapUpTime = null;
      _lastTapUpPosition = null;
    } else {
      _lastTapUpTime = now;
      _lastTapUpPosition = event.position;
    }

    // If "Only Triple-Tap & Hold" is active, bypass double-tap and gesture shapes completely
    if (widget.onlyTripleTapHold) {
      if (_isDrawing) {
        setState(() {
          _isDrawing = false;
          _strokePoints.clear();
        });
      }
      return;
    }

    // Handle standard double-tap if triple-tap hold is enabled
    if (_tapCount == 2 && widget.doubleTapEnabled && !widget.doubleTapHoldEnabled) {
      if (!widget.tripleTapHoldEnabled) {
        _triggerAssistant(triggerType: 'Double-Tap');
        _tapCount = 0;
      } else {
        // Brief window for 3rd tap to arrive; if none arrives, fire double-tap
        Timer(const Duration(milliseconds: 220), () {
          if (!mounted) return;
          if (_tapCount == 2 && !_isHolding && !_isTriggering) {
            _triggerAssistant(triggerType: 'Double-Tap');
            _tapCount = 0;
          }
        });
      }
    }

    // Check if user drew 'O' (circle) or '1' (vertical downward stroke)
    if (_isDrawing && _strokePoints.length >= 8) {
      if (widget.drawOGestureEnabled && _strokePoints.length >= 12 && _recognizeCircleGesture(_strokePoints)) {
        _onCircleGestureRecognized();
        return;
      }
      if (widget.drawOneGestureEnabled && _recognizeOneGesture(_strokePoints)) {
        _onOneGestureRecognized();
        return;
      }
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
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    _cancelHoldSequence();
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
  bool _recognizeOneGesture(List<Offset> points) {
    if (points.length < 8) return false;

    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;

    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final width = maxX - minX;
    final height = maxY - minY;

    // 1. Minimum vertical length (at least 45px)
    if (height < 45) return false;

    // 2. Aspect ratio: vertical orientation (height / width >= 1.8)
    if (width > 0 && (height / width) < 1.8) return false;

    // 3. Direction: downward stroke (end point is significantly lower than start)
    if ((points.last.dy - points.first.dy) < (height * 0.55)) return false;

    // 4. Line straightness: compute perpendicular deviation from start-to-end vector
    final start = points.first;
    final end = points.last;
    final lineVec = end - start;
    final lineLen = lineVec.distance;
    if (lineLen < 40) return false;

    double maxDeviation = 0;
    double sumDeviation = 0;
    for (final p in points) {
      final t = (((p.dx - start.dx) * lineVec.dx + (p.dy - start.dy) * lineVec.dy) /
              (lineLen * lineLen))
          .clamp(0.0, 1.0);
      final proj = Offset(start.dx + t * lineVec.dx, start.dy + t * lineVec.dy);
      final dev = (p - proj).distance;
      if (dev > maxDeviation) maxDeviation = dev;
      sumDeviation += dev;
    }

    final avgDeviation = sumDeviation / points.length;

    // Straight vertical stroke constraint
    if (maxDeviation <= 35 && avgDeviation <= 16) {
      final center = Offset((minX + maxX) / 2.0, (minY + maxY) / 2.0);
      _detectedCircleCenter = center;
      _detectedCircleRadius = math.max(width, height) / 2.0;
      _detectedStrokeRect = Rect.fromLTRB(minX, minY, maxX, maxY);
      return true;
    }

    return false;
  }

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

  void _onOneGestureRecognized() async {
    if (_isTriggering) return;
    _isTriggering = true;
    _isDrawing = false;
    _circleSuccessAnimController.forward(from: 0.0);

    HapticFeedback.heavyImpact();
    _nativeService.triggerHapticPulse(90);

    final strokeRect = _detectedStrokeRect;

    Uint8List? screenBytes;
    try {
      screenBytes = await _captureCurrentScreen();
    } catch (e) {
      debugPrint('[OvaGestureDetector] Screen capture error: $e');
    }

    _triggerAssistantWithContext(screenBytes, strokeRect);

    _clearStrokeTimer?.cancel();
    _clearStrokeTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _strokePoints.clear();
          _detectedCircleCenter = null;
          _detectedStrokeRect = null;
        });
      }
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
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
  // Hold / Double-Tap & Hold / Triple-Tap & Hold HUD Sequence
  // ─────────────────────────────────────────────────────────────────────────────
  void _startHoldSequence(
    Offset position, {
    bool isDoubleTap = false,
    bool isTripleTap = false,
  }) {
    _isHolding = true;
    _isDoubleTapHolding = isDoubleTap;
    _isTripleTapHolding = isTripleTap;
    _holdProgress = 0.0;
    _currentFingerPosition = position;
    _hudAnimController.forward();

    HapticFeedback.mediumImpact();

    final startTime = DateTime.now();
    final effectiveHoldDurationMs = (widget.holdDurationSeconds > 0 ? widget.holdDurationSeconds : 3) * 1000;
    int accumulatedElapsedMs = 0;

    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
      if (_isHolding) {
        HapticFeedback.selectionClick();
      }
    });

    _holdTimer?.cancel();
    const updateIntervalMs = 30;
    _holdTimer = Timer.periodic(const Duration(milliseconds: updateIntervalMs), (timer) {
      if (!_isHolding) {
        timer.cancel();
        return;
      }

      accumulatedElapsedMs += updateIntervalMs;
      final realElapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      final elapsedMs = math.max(accumulatedElapsedMs, realElapsedMs);
      final progress = (elapsedMs / effectiveHoldDurationMs).clamp(0.0, 1.0);

      setState(() {
        _holdProgress = progress;
      });

      if (progress >= 1.0) {
        timer.cancel();
        _tickTimer?.cancel();
        _onHoldSuccess();
      }
    });
  }

  void _cancelHoldSequence() {
    _isHolding = false;
    _isDoubleTapHolding = false;
    _isTripleTapHolding = false;
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    _hudAnimController.reverse();
    setState(() {
      _holdProgress = 0.0;
    });
  }

  void _onHoldSuccess() {
    final wasTripleTap = _isTripleTapHolding;
    final wasDoubleTap = _isDoubleTapHolding;
    _isHolding = false;
    _isDoubleTapHolding = false;
    _isTripleTapHolding = false;
    _tapCount = 0;
    HapticFeedback.heavyImpact();
    _hudAnimController.reverse();
    setState(() {
      _holdProgress = 0.0;
    });
    _triggerAssistant(
      triggerType: wasTripleTap
          ? 'Triple-Tap & Hold'
          : (wasDoubleTap ? 'Double-Tap & Hold' : 'Hold'),
    );
  }

  void _triggerAssistant({required String triggerType}) {
    try {
      HapticFeedback.heavyImpact();
      _nativeService.wakeScreen();
      widget.onTriggerOva();
    } catch (e, st) {
      debugPrint('[OvaGestureDetector] Error triggering assistant: $e\n$st');
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

          // Futuristic Charging Ring HUD overlay when holding
          if (_isHolding || _hudAnimController.value > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _hudOpacity,
                  child: ScaleTransition(
                    scale: _hudScale,
                    child: _buildChargingHUD(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChargingHUD() {
    final screenSize = MediaQuery.of(context).size;
    final hudX = _currentFingerPosition.dx.clamp(90.0, screenSize.width - 90.0);
    final hudY = (_currentFingerPosition.dy - 110.0).clamp(100.0, screenSize.height - 150.0);

    final effectiveHoldSec = widget.holdDurationSeconds > 0 ? widget.holdDurationSeconds : 3;
    final secondsRemaining = (effectiveHoldSec * (1.0 - _holdProgress)).toStringAsFixed(1);

    return Stack(
      children: [
        Container(color: Colors.black.withValues(alpha: 0.35)),
        Positioned(
          left: hudX - 85,
          top: hudY - 85,
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.surface.withValues(alpha: 0.95),
              border: Border.all(
                color: AppColors.brandBlue.withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 8,
                ),
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    value: _holdProgress,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandPink),
                    backgroundColor: AppColors.brandBlue.withValues(alpha: 0.25),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandBlue.withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/oneova_logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ONEOVA',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isTripleTapHolding
                          ? 'Triple-Tap & Hold ${secondsRemaining}s'
                          : (_isDoubleTapHolding
                              ? 'Tap & Hold ${secondsRemaining}s'
                              : 'Hold ${secondsRemaining}s'),
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
