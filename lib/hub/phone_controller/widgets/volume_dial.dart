import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';

/// Rotary volume knob with a 270° sweep. Turn it around its centre; every
/// 2% step gives a selection tick and the ends give a firmer bump.
class VolumeDial extends StatefulWidget {
  const VolumeDial({
    super.key,
    required this.value,
    required this.muted,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
    this.size = 236,
  });

  final int value;
  final bool muted;
  final bool enabled;
  final double size;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  State<VolumeDial> createState() => _VolumeDialState();
}

class _VolumeDialState extends State<VolumeDial> {
  static const double _sweep = math.pi * 1.5; // 270°, starting at 135°
  static const int _tickStep = 2;

  late double _value = widget.value.toDouble();
  bool _turning = false;
  double? _lastAngle;
  bool _atEdge = false;

  @override
  void didUpdateWidget(covariant VolumeDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_turning && widget.value != oldWidget.value) {
      _value = widget.value.toDouble();
    }
  }

  double? _angleOf(Offset local) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = local - c;
    if (v.distance < widget.size * 0.11) return null; // unstable near the hub
    return math.atan2(v.dy, v.dx);
  }

  void _onStart(DragStartDetails d) {
    if (!widget.enabled) return;
    _turning = true;
    _lastAngle = _angleOf(d.localPosition);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    final a = _angleOf(d.localPosition);
    if (a == null) return;
    final last = _lastAngle;
    _lastAngle = a;
    if (last == null) return;
    var delta = a - last;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;

    final next = (_value + delta / _sweep * 100).clamp(0.0, 100.0);
    final oldStep = (_value / _tickStep).floor();
    final newStep = (next / _tickStep).floor();
    final edge = next <= 0 || next >= 100;
    if (edge && !_atEdge) {
      HapticFeedback.mediumImpact();
    } else if (newStep != oldStep && !edge) {
      HapticFeedback.selectionClick();
    }
    _atEdge = edge;
    final changed = next.round() != _value.round();
    setState(() => _value = next);
    if (changed) widget.onChanged(next.round());
  }

  void _onEnd([DragEndDetails? _]) {
    if (!_turning) return;
    _turning = false;
    _lastAngle = null;
    widget.onChangeEnd(_value.round());
  }

  @override
  Widget build(BuildContext context) {
    final level = _value.round();
    return Semantics(
      label: 'Computer volume',
      value: '$level percent',
      slider: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onStart,
        onPanUpdate: _onUpdate,
        onPanEnd: _onEnd,
        onPanCancel: _onEnd,
        child: SizedBox.square(
          dimension: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _DialPainter(
                  value: _value,
                  muted: widget.muted,
                  enabled: widget.enabled,
                  track: context.surfaceMid,
                  tickOff: context.border,
                  knobTop: context.surface,
                  knobBottom: context.surfaceMid,
                  knurl: context.textMuted.withValues(alpha: 0.25),
                  hairline: context.border,
                  muteColor: context.textMuted,
                  glowAlpha: context.isDark ? 0.4 : 0.22,
                  shadow: AppColors.brandBlack.withValues(
                    alpha: context.isDark ? 0.6 : 0.16,
                  ),
                  sheen: AppColors.brandWhite.withValues(
                    alpha: context.isDark ? 0.07 : 0.7,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: widget.muted
                        ? const Icon(
                            Icons.volume_off_rounded,
                            key: ValueKey('m'),
                            size: 30,
                            color: AppColors.brandPink,
                          )
                        : Text(
                            '$level',
                            key: const ValueKey('v'),
                            style: GoogleFonts.inter(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              height: 1.0,
                              color: context.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.muted ? 'MUTED' : 'VOLUME',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: widget.muted
                          ? AppColors.brandPink
                          : context.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.value,
    required this.muted,
    required this.enabled,
    required this.track,
    required this.tickOff,
    required this.knobTop,
    required this.knobBottom,
    required this.knurl,
    required this.hairline,
    required this.muteColor,
    required this.glowAlpha,
    required this.shadow,
    required this.sheen,
  });

  final double value;
  final bool muted;
  final bool enabled;
  final Color track;
  final Color tickOff;
  final Color knobTop;
  final Color knobBottom;
  final Color knurl;
  final Color hairline;
  final Color muteColor;
  final double glowAlpha;
  final Color shadow;
  final Color sheen;

  static const double _start = math.pi * 0.75;
  static const double _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final t = value / 100;
    final angle = _start + _sweep * t;
    final active = muted || !enabled ? muteColor : AppColors.brandBlue;

    // Tick ring: 51 ticks, longer every 10%.
    for (var i = 0; i <= 50; i++) {
      final a = _start + _sweep * (i / 50);
      final major = i % 5 == 0;
      final outer = r - 2;
      final inner = r - (major ? 13 : 8);
      final on = i * 2 <= value;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * outer,
        Paint()
          ..color = on ? active : tickOff
          ..strokeWidth = major ? 1.8 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Track + progress arc.
    final arcR = r - 24;
    final arcRect = Rect.fromCircle(center: c, radius: arcR);
    canvas.drawArc(
      arcRect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    if (t > 0.002) {
      canvas.drawArc(
        arcRect,
        _start,
        _sweep * t,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            endAngle: _sweep,
            colors: [active.withValues(alpha: 0.45), active],
            transform: const GradientRotation(_start),
          ).createShader(arcRect),
      );
    }

    // Tip: pink accent bead with a soft glow.
    final tip = c + Offset(math.cos(angle), math.sin(angle)) * arcR;
    if (!muted && enabled) {
      final glowRect = Rect.fromCircle(center: tip, radius: 18);
      canvas.drawCircle(
        tip,
        18,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.brandPink.withValues(alpha: glowAlpha),
              AppColors.brandPink.withValues(alpha: 0),
            ],
          ).createShader(glowRect),
      );
    }
    canvas.drawCircle(
      tip,
      5.5,
      Paint()..color = muted || !enabled ? muteColor : AppColors.brandPink,
    );
    canvas.drawCircle(tip, 2, Paint()..color = knobTop);

    // Knob body with a knurled rim that turns with the value.
    final knobR = r - 40;
    final knobRect = Rect.fromCircle(center: c, radius: knobR);
    // Soft contact shadow so the knob sits on the deck.
    canvas.drawCircle(
      c + const Offset(0, 8),
      knobR - 2,
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      c,
      knobR,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [knobTop, knobBottom],
        ).createShader(knobRect),
    );
    canvas.drawCircle(
      c,
      knobR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );
    // Specular sheen across the upper-left of the cap.
    canvas.drawArc(
      knobRect.deflate(3),
      math.pi * 1.05,
      math.pi * 0.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = sheen,
    );
    final knurlPaint = Paint()
      ..color = knurl
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 72; i++) {
      final a = angle + i * (2 * math.pi / 72);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (knobR - 7), c + dir * (knobR - 2), knurlPaint);
    }

    // Pointer notch.
    final dir = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      c + dir * (knobR - 24),
      c + dir * (knobR - 12),
      Paint()
        ..color = active
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.value != value ||
      old.muted != muted ||
      old.enabled != enabled ||
      old.track != track ||
      old.knobTop != knobTop ||
      old.glowAlpha != glowAlpha ||
      old.shadow != shadow;
}
