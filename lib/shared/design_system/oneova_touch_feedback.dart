import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Oneova Emotional Touch Feedback & Glow System.
///
/// Provides:
/// 1. [OneovaTouchGlowOverlay]: A lightweight global pointer overlay that renders
///    a soft, emotional micro-dotted glow highlight in Oneova Blue & Pink on every tap.
/// 2. [OneovaGlowSplashFactory]: A custom Material [InteractiveInkFeatureFactory]
///    replacing harsh Flutter ink splashes with feather-soft dual-tone glows.
/// 3. [OneovaSmoothPageTransitionsBuilder]: Smooth, clean screen transitions globally.
class OneovaTouchGlowOverlay extends StatefulWidget {
  final Widget child;

  const OneovaTouchGlowOverlay({super.key, required this.child});

  @override
  State<OneovaTouchGlowOverlay> createState() => _OneovaTouchGlowOverlayState();
}

class _OneovaTouchGlowOverlayState extends State<OneovaTouchGlowOverlay>
    with SingleTickerProviderStateMixin {
  final List<_TouchImpulse> _activeTouches = [];
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_activeTouches.isEmpty) {
      _ticker?.stop();
      return;
    }

    final now = DateTime.now();
    setState(() {
      _activeTouches.removeWhere((t) =>
          now.difference(t.startTime).inMilliseconds >= _TouchImpulse.durationMs);
    });

    if (_activeTouches.isEmpty) {
      _ticker?.stop();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    // Gentle emotional haptic feedback
    HapticFeedback.selectionClick();

    final impulse = _TouchImpulse(
      position: event.position,
      startTime: DateTime.now(),
    );

    setState(() {
      _activeTouches.add(impulse);
      if (_activeTouches.length > 8) {
        _activeTouches.removeAt(0);
      }
    });

    if (_ticker != null && !_ticker!.isTicking) {
      _ticker!.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_activeTouches.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OneovaTouchGlowPainter(
                    touches: List.unmodifiable(_activeTouches),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TouchImpulse {
  static const int durationMs = 380;
  final Offset position;
  final DateTime startTime;

  _TouchImpulse({required this.position, required this.startTime});

  double get progress {
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    return (elapsed / durationMs).clamp(0.0, 1.0);
  }
}

class _OneovaTouchGlowPainter extends CustomPainter {
  final List<_TouchImpulse> touches;

  _OneovaTouchGlowPainter({required this.touches});

  @override
  void paint(Canvas canvas, Size size) {
    for (final touch in touches) {
      final p = touch.progress;
      if (p >= 1.0) continue;

      final curve = Curves.easeOutCubic.transform(p);
      final fade = (1.0 - curve).clamp(0.0, 1.0);

      // ── 1. Soft Core Radial Glow (Blue -> Pink fade) ──────────────────────
      final coreRadius = 4.0 + (curve * 22.0);
      final corePaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.brandBlue.withValues(alpha: fade * 0.42),
            AppColors.brandPink.withValues(alpha: fade * 0.28),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: touch.position, radius: coreRadius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);

      canvas.drawCircle(touch.position, coreRadius, corePaint);

      // ── 2. Emotional Dotted Highlight Ring (Orbiting Constellation) ───────
      const int dotCount = 8;
      final ringRadius = 6.0 + (curve * 18.0);
      final rotation = curve * 0.35; // gentle micro-rotation
      final dotRadius = (1.0 - curve) * 1.5 + 0.5;

      for (int i = 0; i < dotCount; i++) {
        final angle = (i * 2 * math.pi / dotCount) + rotation;
        final dotX = touch.position.dx + (ringRadius * math.cos(angle));
        final dotY = touch.position.dy + (ringRadius * math.sin(angle));

        final isEven = (i % 2 == 0);
        final dotColor = isEven
            ? AppColors.brandBlue.withValues(alpha: fade * 0.75)
            : AppColors.brandPink.withValues(alpha: fade * 0.75);

        final dotPaint = Paint()
          ..color = dotColor
          ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(dotX, dotY), dotRadius, dotPaint);
      }

      // ── 3. Luminous Central Pinpoint Highlight ─────────────────────────────
      if (p < 0.4) {
        final pinFade = (1.0 - (p / 0.4)).clamp(0.0, 1.0);
        final pinPaint = Paint()
          ..color = Colors.white.withValues(alpha: pinFade * 0.65)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(touch.position, 1.8 * pinFade, pinPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OneovaTouchGlowPainter oldDelegate) => true;
}

/// Custom Material Interactive Ink Feature Factory that delivers
/// soft, non-harsh dual-tone Oneova glow splashes across all buttons and tabs.
class OneovaGlowSplashFactory extends InteractiveInkFeatureFactory {
  const OneovaGlowSplashFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    return _OneovaGlowSplash(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
      textDirection: textDirection,
    );
  }
}

class _OneovaGlowSplash extends InteractiveInkFeature {
  late final AnimationController _animationController;
  late final Animation<double> _radiusAnimation;
  late final Animation<double> _fadeAnimation;
  final Offset _targetPosition;
  final double _targetRadius;
  final BorderRadius? borderRadius;
  @override
  final ShapeBorder? customBorder;
  final RectCallback? rectCallback;
  final bool containedInkWell;
  final TextDirection textDirection;

  _OneovaGlowSplash({
    required super.controller,
    required super.referenceBox,
    required Offset position,
    required super.color,
    required this.containedInkWell,
    this.rectCallback,
    this.borderRadius,
    this.customBorder,
    double? radius,
    super.onRemoved,
    required this.textDirection,
  })  : _targetPosition = position,
        _targetRadius = radius ?? _calcRadius(referenceBox, position) {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: controller.vsync,
    )
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          dispose();
        }
      });

    _radiusAnimation = Tween<double>(
      begin: 4.0,
      end: math.min(_targetRadius, 48.0), // Keep it small and non-harsh
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInCubic,
    ));

    _animationController.forward();
  }

  static double _calcRadius(RenderBox referenceBox, Offset position) {
    final Size size = referenceBox.size;
    final double d1 = size.bottomRight(Offset.zero).distance;
    final double d2 = (position - Offset(size.width / 2, size.height / 2)).distance;
    return (d1 / 2) + d2;
  }

  @override
  void confirm() {
    // Fade smoothly when touch released
    if (!_animationController.isAnimating) {
      dispose();
    }
  }

  @override
  void cancel() {
    dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final double r = _radiusAnimation.value;
    final double fade = _fadeAnimation.value;
    if (r <= 0.0 || fade <= 0.0) return;

    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.brandBlue.withValues(alpha: fade * 0.16),
          AppColors.brandPink.withValues(alpha: fade * 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: _targetPosition, radius: r));

    canvas.save();
    canvas.transform(transform.storage);

    if (containedInkWell) {
      final Rect bounds = rectCallback != null
          ? rectCallback!()
          : Offset.zero & referenceBox.size;

      if (customBorder != null) {
        canvas.clipPath(customBorder!.getOuterPath(bounds, textDirection: textDirection));
      } else if (borderRadius != null) {
        canvas.clipRRect(borderRadius!.toRRect(bounds));
      } else {
        canvas.clipRect(bounds);
      }
      canvas.drawCircle(_targetPosition, r, paint);
    } else {
      canvas.drawCircle(_targetPosition, r, paint);
    }

    canvas.restore();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

/// Blurs a route's page while it enters (and while another page covers it).
/// The wrapper type never changes, so page state survives the transition;
/// the filter is simply disabled when the page is at rest.
class _TransitionBlur extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const _TransitionBlur({required this.animation, required this.secondaryAnimation, required this.child});

  static const double _enterSigma = 8.0;
  static const double _coveredSigma = 3.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        // Entering blur resolves by 80% of the motion so the last frames are crisp.
        final entering = 1.0 - const Interval(0.0, 0.8, curve: Curves.easeOutCubic).transform(animation.value);
        final sigma = entering * _enterSigma + secondaryAnimation.value * _coveredSigma;
        return ImageFiltered(
          enabled: sigma > 0.05,
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
          child: child,
        );
      },
    );
  }
}

/// Global PageTransitionsBuilder providing buttery smooth, luxury iOS/Linear-grade
/// screen transitions.
///
/// - Forward: the new screen glides in 10% from the right while it fades in over
///   the first 60% of the motion (no double-exposure "ghosting").
/// - The covered screen drifts 5% left (parallax) and dims with a cheap color
///   scrim instead of an opacity layer, keeping the transition at 60/120fps.
/// - Back runs the same motion in reverse, slightly quicker so pops feel snappy.
/// - The entering page resolves from a soft blur (and the covered page softens
///   slightly), via [_TransitionBlur].
/// - iOS keeps the native Cupertino slide so the edge swipe-back gesture works.
class OneovaSmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const OneovaSmoothPageTransitionsBuilder();

  static const Duration _forward = Duration(milliseconds: 340);
  static const Duration _reverse = Duration(milliseconds: 280);

  @override
  Duration get transitionDuration => _forward;

  @override
  Duration get reverseTransitionDuration => _reverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Depth-of-field blur: the incoming page resolves from a soft blur while the
    // page it covers softens slightly. Disabled (zero cost) once settled.
    child = _TransitionBlur(animation: animation, secondaryAnimation: secondaryAnimation, child: child);

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return const CupertinoPageTransitionsBuilder()
          .buildTransitions(route, context, animation, secondaryAnimation, child);
    }

    final slideIn = Tween<Offset>(
      begin: const Offset(0.10, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInCubic,
    ));

    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInCubic,
    );
    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.05, 0.0),
    ).animate(secondaryCurved);

    final maxDim = Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.14;

    return SlideTransition(
      position: slideOut,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          SlideTransition(
            position: slideIn,
            child: FadeTransition(opacity: fadeIn, child: child),
          ),
          // Dim scrim over the covered page while a new page is on top of it.
          IgnorePointer(
            child: AnimatedBuilder(
              animation: secondaryCurved,
              builder: (context, _) {
                final v = secondaryCurved.value;
                if (v <= 0.001) return const SizedBox.shrink();
                return ColoredBox(
                  color: Colors.black.withValues(alpha: maxDim * v),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
