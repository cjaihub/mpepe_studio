import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

enum OvaOrbMode {
  idle,
  listening,
  thinking,
  speaking,
  paused,
}

/// Fluid luminous 3D-shaded voice orb for Ova Live Voice (Main & Overlay).
///
/// Renders multi-layered silk wave ribbons inside a glass sphere using
/// Oneova's signature [AppColors.brandBlue] and [AppColors.brandPink] palette,
/// adapting cleanly to both Light and Dark themes.
class OvaFluidVoiceOrb extends StatefulWidget {
  final double size;
  final double amplitude; // 0.0 .. 1.0
  final OvaOrbMode mode;
  final VoidCallback? onTap;

  const OvaFluidVoiceOrb({
    super.key,
    this.size = 176,
    this.amplitude = 0.0,
    this.mode = OvaOrbMode.listening,
    this.onTap,
  });

  @override
  State<OvaFluidVoiceOrb> createState() => _OvaFluidVoiceOrbState();
}

class _OvaFluidVoiceOrbState extends State<OvaFluidVoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant OvaFluidVoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode == OvaOrbMode.paused && _controller.isAnimating) {
      _controller.stop();
    } else if (widget.mode != OvaOrbMode.paused && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final outerSize = widget.size * 1.60;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _controller.value * 2 * math.pi;
            final activeEnergy = switch (widget.mode) {
              OvaOrbMode.speaking => 0.45 + 0.35 * (0.5 + 0.5 * math.sin(phase * 3)),
              OvaOrbMode.listening => (0.18 + widget.amplitude * 0.75).clamp(0.18, 1.0),
              OvaOrbMode.thinking => 0.32 + 0.18 * math.sin(phase * 4),
              OvaOrbMode.idle => 0.12,
              OvaOrbMode.paused => 0.05,
            };

            final breathScale = 1.0 +
                activeEnergy * 0.045 * math.sin(phase * 2) +
                widget.amplitude * 0.05;

            return CustomPaint(
              painter: _FluidOrbPainter(
                phase: phase,
                energy: activeEnergy,
                orbDiameter: widget.size * breathScale,
                mode: widget.mode,
                isDark: isDark,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FluidOrbPainter extends CustomPainter {
  final double phase;
  final double energy;
  final double orbDiameter;
  final OvaOrbMode mode;
  final bool isDark;

  _FluidOrbPainter({
    required this.phase,
    required this.energy,
    required this.orbDiameter,
    required this.mode,
    required this.isDark,
  });

  static const Color _cyanHighlight = Color(0xFF38BDF8);
  static const Color _skyRibbon = Color(0xFF60A5FA);
  static const Color _deepCore = Color(0xFF072B61);
  static const Color _auroraPurple = Color(0xFF8B5CF6);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = orbDiameter / 2;

    // 1. Soft outer ambient aura
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _cyanHighlight.withValues(alpha: isDark ? 0.24 : 0.14),
          _auroraPurple.withValues(alpha: isDark ? 0.15 : 0.08),
          AppColors.brandPink.withValues(alpha: isDark ? 0.06 : 0.03),
          Colors.transparent,
        ],
        stops: const [0.30, 0.65, 0.85, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.55));
    canvas.drawCircle(center, radius * 1.55, auraPaint);

    // 2. Three delicate celestial concentric acoustic/orbital rings
    final ringMultipliers = [1.18, 1.35, 1.52];
    for (var i = 0; i < ringMultipliers.length; i++) {
      final mult = ringMultipliers[i];
      final pulse = math.sin(phase + i * 1.2) * 0.02 * (0.5 + energy * 0.5);
      final ringRadius = radius * (mult + pulse);
      final baseAlpha = isDark ? 0.22 - (i * 0.05) : 0.18 - (i * 0.04);
      final dynamicAlpha = (baseAlpha * (0.8 + energy * 0.3)).clamp(0.04, 0.35);

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            _cyanHighlight.withValues(alpha: dynamicAlpha),
            _auroraPurple.withValues(alpha: dynamicAlpha * 0.8),
            AppColors.brandPink.withValues(alpha: dynamicAlpha * 0.6),
            _cyanHighlight.withValues(alpha: dynamicAlpha),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: ringRadius));
      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    // 3. Main clipped liquid-glass sphere
    final sphereRect = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(sphereRect));

    // Base deep translucent oceanic sphere fill
    final basePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.30),
        radius: 1.15,
        colors: [
          _skyRibbon,
          AppColors.brandBlue,
          _deepCore,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(sphereRect);
    canvas.drawRect(sphereRect, basePaint);

    // Warm pink-violet subsurface glow on right hemisphere
    final accentBlobCenter = Offset(
      center.dx + radius * 0.35 * math.cos(phase * 0.8),
      center.dy + radius * 0.22 * math.sin(phase * 1.1),
    );
    final accentPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        colors: [
          AppColors.brandPink.withValues(alpha: mode == OvaOrbMode.paused ? 0.22 : 0.65),
          _auroraPurple.withValues(alpha: mode == OvaOrbMode.paused ? 0.15 : 0.40),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: accentBlobCenter, radius: radius * 0.95));
    canvas.drawCircle(accentBlobCenter, radius * 0.95, accentPaint);

    // Central bright glowing energy nucleus
    final nucleusCenter = Offset(
      center.dx - radius * 0.12 * math.sin(phase * 0.9),
      center.dy - radius * 0.14 * math.cos(phase * 0.7),
    );
    final nucleusPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.65 + energy * 0.25),
          _cyanHighlight.withValues(alpha: 0.45 + energy * 0.30),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: nucleusCenter, radius: radius * 0.55));
    canvas.drawCircle(nucleusCenter, radius * 0.55, nucleusPaint);

    // 4. Flowing silk aurora wave ribbons inside the sphere
    _drawSilkRibbon(
      canvas: canvas,
      rect: sphereRect,
      amplitudeFactor: 0.18 + energy * 0.20,
      frequency: 1.5,
      phaseShift: phase,
      yOffsetFactor: -0.05,
      topColor: _cyanHighlight.withValues(alpha: 0.75),
      bottomColor: AppColors.brandBlue.withValues(alpha: 0.05),
    );

    _drawSilkRibbon(
      canvas: canvas,
      rect: sphereRect,
      amplitudeFactor: 0.15 + energy * 0.22,
      frequency: 2.0,
      phaseShift: -phase * 1.3 + 1.2,
      yOffsetFactor: 0.08,
      topColor: AppColors.brandPink.withValues(alpha: mode == OvaOrbMode.paused ? 0.20 : 0.62),
      bottomColor: _auroraPurple.withValues(alpha: 0.04),
    );

    _drawSilkRibbon(
      canvas: canvas,
      rect: sphereRect,
      amplitudeFactor: 0.12 + energy * 0.16,
      frequency: 2.5,
      phaseShift: phase * 1.7 + 2.2,
      yOffsetFactor: 0.0,
      topColor: AppColors.brandWhite.withValues(alpha: 0.50),
      bottomColor: _skyRibbon.withValues(alpha: 0.0),
    );

    // 5. Specular curved glass sheen on top-left rim
    final sheenRect = Rect.fromCircle(
      center: Offset(center.dx - radius * 0.30, center.dy - radius * 0.34),
      radius: radius * 0.68,
    );
    final sheenPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.brandWhite.withValues(alpha: 0.36),
          AppColors.brandWhite.withValues(alpha: 0.0),
        ],
      ).createShader(sheenRect);
    canvas.drawCircle(sheenRect.center, radius * 0.68, sheenPaint);

    canvas.restore();

    // 6. Crisp 1px outer glass rim
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.brandWhite.withValues(alpha: isDark ? 0.60 : 0.90),
          _cyanHighlight.withValues(alpha: 0.45),
          AppColors.brandPink.withValues(alpha: 0.45),
        ],
      ).createShader(sphereRect);
    canvas.drawCircle(center, radius, rimPaint);
  }

  void _drawSilkRibbon({
    required Canvas canvas,
    required Rect rect,
    required double amplitudeFactor,
    required double frequency,
    required double phaseShift,
    required double yOffsetFactor,
    required Color topColor,
    required Color bottomColor,
  }) {
    final path = Path();
    final width = rect.width;
    final height = rect.height;
    final midY = rect.center.dy + height * yOffsetFactor;
    final amp = height * amplitudeFactor;

    path.moveTo(rect.left, rect.bottom);
    const steps = 36;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = rect.left + width * t;
      final envelope = math.sin(t * math.pi);
      final wave = math.sin(t * math.pi * frequency + phaseShift) * amp * (0.45 + 0.55 * envelope) +
          math.cos(t * math.pi * (frequency * 0.7) - phaseShift * 0.6) * (amp * 0.35);
      final y = midY + wave;
      if (i == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(rect.right, rect.bottom);
    path.close();

    final ribbonPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, bottomColor],
      ).createShader(rect);
    canvas.drawPath(path, ribbonPaint);
  }

  @override
  bool shouldRepaint(covariant _FluidOrbPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.energy != energy ||
        oldDelegate.orbDiameter != orbDiameter ||
        oldDelegate.mode != mode ||
        oldDelegate.isDark != isDark;
  }
}

