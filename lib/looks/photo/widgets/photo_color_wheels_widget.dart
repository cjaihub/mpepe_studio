import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../models/oneova_look.dart';

/// 3-Way Color Wheels Widget for Lift, Gamma, Gain, and Offset.
class PhotoColorWheelsWidget extends StatefulWidget {
  final LookWheels wheels;
  final ValueChanged<LookWheels> onWheelsChanged;

  const PhotoColorWheelsWidget({
    super.key,
    required this.wheels,
    required this.onWheelsChanged,
  });

  @override
  State<PhotoColorWheelsWidget> createState() => _PhotoColorWheelsWidgetState();
}

class _PhotoColorWheelsWidgetState extends State<PhotoColorWheelsWidget> {
  int _activeWheelIndex = 0; // 0 = Lift, 1 = Gamma, 2 = Gain, 3 = Offset

  static const List<String> _wheelLabels = ['Lift (Shadows)', 'Gamma (Mids)', 'Gain (Highlights)', 'Offset'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;

    final currentWheel = switch (_activeWheelIndex) {
      0 => widget.wheels.lift,
      1 => widget.wheels.gamma,
      2 => widget.wheels.gain,
      _ => widget.wheels.offset,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tab selector for wheels
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Row(
            children: List.generate(_wheelLabels.length, (index) {
              final isSelected = _activeWheelIndex == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _activeWheelIndex = index);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.brandBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(7.0),
                    ),
                    child: Text(
                      _wheelLabels[index].split(' ').first,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : textMuted,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // Wheel disc and luminance slider
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular color disc
            GestureDetector(
              onPanUpdate: (details) {
                _handleWheelPan(details.localPosition, 65.0);
              },
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                  gradient: const RadialGradient(
                    colors: [Colors.white, Color(0xFF1E293B), Colors.transparent],
                    stops: [0.0, 0.7, 1.0],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Crosshair guides
                    Container(width: 1.0, height: 130, color: borderColor.withValues(alpha: 0.5)),
                    Container(width: 130, height: 1.0, color: borderColor.withValues(alpha: 0.5)),
                    // Position puck
                    Transform.translate(
                      offset: Offset(currentWheel.r * 50.0, currentWheel.b * 50.0),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brandPink,
                          border: Border.all(color: Colors.white, width: 2.0),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandPink.withValues(alpha: 0.6),
                              blurRadius: 6.0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Luminance vertical slider
            Column(
              children: [
                Text(
                  'Luma',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 110,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                        activeTrackColor: AppColors.brandBlue,
                        inactiveTrackColor: isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0),
                        thumbColor: AppColors.brandBlue,
                      ),
                      child: Slider(
                        value: currentWheel.lum.clamp(-1.0, 1.0),
                        min: -1.0,
                        max: 1.0,
                        onChanged: (val) {
                          _updateActiveWheel(currentWheel.copyWith(lum: val));
                        },
                      ),
                    ),
                  ),
                ),
                Text(
                  '${(currentWheel.lum * 100).toInt()}%',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _handleWheelPan(Offset localPos, double radius) {
    final dx = (localPos.dx - radius) / radius;
    final dy = (localPos.dy - radius) / radius;
    final dist = math.sqrt(dx * dx + dy * dy);
    final clampedDist = dist.clamp(0.0, 1.0);
    final angle = math.atan2(dy, dx);

    final normX = math.cos(angle) * clampedDist;
    final normY = math.sin(angle) * clampedDist;

    final cur = switch (_activeWheelIndex) {
      0 => widget.wheels.lift,
      1 => widget.wheels.gamma,
      2 => widget.wheels.gain,
      _ => widget.wheels.offset,
    };

    _updateActiveWheel(cur.copyWith(r: normX, b: normY));
  }

  void _updateActiveWheel(ColorWheel updated) {
    HapticFeedback.selectionClick();
    final newWheels = switch (_activeWheelIndex) {
      0 => widget.wheels.copyWith(lift: updated),
      1 => widget.wheels.copyWith(gamma: updated),
      2 => widget.wheels.copyWith(gain: updated),
      _ => widget.wheels.copyWith(offset: updated),
    };
    widget.onWheelsChanged(newWheels);
  }
}
