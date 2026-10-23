import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../backend/photo_studio/photo_studio_models.dart';
import '../../../../shared/theme/app_theme.dart';
import '../photo_studio_screen.dart';

enum WheelTarget { shadows, midtones, highlights }

class ColorWheelsPanel extends ConsumerStatefulWidget {
  const ColorWheelsPanel({super.key});

  @override
  ConsumerState<ColorWheelsPanel> createState() => _ColorWheelsPanelState();
}

class _ColorWheelsPanelState extends ConsumerState<ColorWheelsPanel> {
  WheelTarget _currentTarget = WheelTarget.shadows;

  AdjustmentType _getAdjustmentType(WheelTarget target) {
    switch (target) {
      case WheelTarget.shadows:
        return AdjustmentType.COLOR_WHEELS_SHADOWS;
      case WheelTarget.midtones:
        return AdjustmentType.COLOR_WHEELS_MIDTONES;
      case WheelTarget.highlights:
        return AdjustmentType.COLOR_WHEELS_HIGHLIGHTS;
    }
  }

  String _getTargetName(WheelTarget target) {
    switch (target) {
      case WheelTarget.shadows:
        return 'Shadows';
      case WheelTarget.midtones:
        return 'Midtones';
      case WheelTarget.highlights:
        return 'Highlights';
    }
  }

  void _updateWheelValues({double? hue, double? saturation, double? luminance}) {
    final project = ref.read(activePhotoProjectProvider);
    if (project.currentGraph.layers.isEmpty) return;
    final layerId = project.currentGraph.layers.first.id;
    final type = _getAdjustmentType(_currentTarget);

    final existing = project.currentGraph.layers.first.adjustments
        .where((a) => a.type == type)
        .lastOrNull;

    final currentHue = (existing?.parameters['hue'] as num?)?.toDouble() ?? 0.0;
    final currentSat = (existing?.parameters['saturation'] as num?)?.toDouble() ?? 0.0;
    final currentLum = (existing?.parameters['luminance'] as num?)?.toDouble() ?? 0.0;

    ref.read(activePhotoProjectProvider.notifier).setOrReplaceAdjustment(
          layerId,
          PhotoAdjustment(
            id: DateTime.now().toIso8601String(),
            type: type,
            parameters: {
              'hue': hue ?? currentHue,
              'saturation': saturation ?? currentSat,
              'luminance': luminance ?? currentLum,
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(activePhotoProjectProvider);
    final type = _getAdjustmentType(_currentTarget);

    double hue = 0.0;
    double saturation = 0.0;
    double luminance = 0.0;

    if (project.currentGraph.layers.isNotEmpty) {
      final adj = project.currentGraph.layers.first.adjustments
          .where((a) => a.type == type)
          .lastOrNull;
      if (adj != null) {
        hue = (adj.parameters['hue'] as num?)?.toDouble() ?? 0.0;
        saturation = (adj.parameters['saturation'] as num?)?.toDouble() ?? 0.0;
        luminance = (adj.parameters['luminance'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Target Switcher Tabs
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Row(
              children: WheelTarget.values.map((target) {
                final isSelected = _currentTarget == target;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentTarget = target),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.brandBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _getTargetName(target),
                        style: GoogleFonts.inter(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Central Interactive Area (Wheel + Vertical Luminance Slider)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Interactive Color Wheel
              _InteractiveColorWheel(
                hue: hue,
                saturation: saturation,
                size: 130,
                onChanged: (newHue, newSat) {
                  _updateWheelValues(hue: newHue, saturation: newSat);
                },
              ),
              const SizedBox(width: 24),

              // Vertical Luminance Slider
              SizedBox(
                height: 130,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'LUM',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2.5,
                            activeTrackColor: AppColors.brandBlue,
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                            thumbColor: Colors.white,
                            overlayColor: AppColors.brandBlue.withValues(alpha: 0.2),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Slider(
                            value: luminance,
                            min: -1.0,
                            max: 1.0,
                            onChanged: (val) {
                              _updateWheelValues(luminance: val);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      luminance > 0 ? '+${(luminance * 100).toInt()}' : '${(luminance * 100).toInt()}',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Readout Metrics & Reset
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMetricChip('H', '${hue.toInt()}°'),
              const SizedBox(width: 8),
              _buildMetricChip('S', '${(saturation * 100).toInt()}%'),
              const SizedBox(width: 8),
              _buildMetricChip('L', luminance > 0 ? '+${(luminance * 100).toInt()}' : '${(luminance * 100).toInt()}'),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () {
                  _updateWheelValues(hue: 0.0, saturation: 0.0, luminance: 0.0);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    'Reset',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _InteractiveColorWheel extends StatelessWidget {
  final double hue;
  final double saturation;
  final double size;
  final void Function(double hue, double sat) onChanged;

  const _InteractiveColorWheel({
    required this.hue,
    required this.saturation,
    required this.size,
    required this.onChanged,
  });

  void _handlePan(Offset localPos, double radius) {
    final center = Offset(radius, radius);
    final delta = localPos - center;
    final dist = delta.distance;

    final sat = (dist / radius).clamp(0.0, 1.0);
    var angle = math.atan2(delta.dy, delta.dx) * 180 / math.pi;
    if (angle < 0) angle += 360;

    onChanged(angle, sat);
  }

  @override
  Widget build(BuildContext context) {
    final radius = size / 2;

    // Calculate thumb position from polar (hue, saturation)
    final rad = hue * math.pi / 180;
    final thumbDist = saturation * radius;
    final thumbPos = Offset(
      radius + thumbDist * math.cos(rad),
      radius + thumbDist * math.sin(rad),
    );

    return GestureDetector(
      onPanDown: (details) => _handlePan(details.localPosition, radius),
      onPanUpdate: (details) => _handlePan(details.localPosition, radius),
      onDoubleTap: () => onChanged(0.0, 0.0),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _ColorWheelGradientPainter(),
            ),
            // Thumb indicator
            Positioned(
              left: thumbPos.dx - 7,
              top: thumbPos.dy - 7,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HSVColor.fromAHSV(1.0, hue, saturation.clamp(0.0, 1.0), 1.0).toColor(),
                  border: Border.all(color: Colors.white, width: 2.0),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 4, spreadRadius: 1),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorWheelGradientPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Angular Sweep Gradient
    final sweepGradient = const SweepGradient(
      colors: [
        Color(0xFFFF0000), // Red 0°
        Color(0xFFFFFF00), // Yellow 60°
        Color(0xFF00FF00), // Green 120°
        Color(0xFF00FFFF), // Cyan 180°
        Color(0xFF0000FF), // Blue 240°
        Color(0xFFFF00FF), // Magenta 300°
        Color(0xFFFF0000), // Red 360°
      ],
    );

    final sweepPaint = Paint()
      ..shader = sweepGradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);

    // 2. Radial Desaturation Gradient (Center is neutral grey/white)
    final radialPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey.shade800,
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, radialPaint);

    // 3. Crisp hairline border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, borderPaint);

    // Subtle crosshairs
    final crossHairPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(center.dx - 8, center.dy), Offset(center.dx + 8, center.dy), crossHairPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 8), Offset(center.dx, center.dy + 8), crossHairPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
