import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'smooth_load.dart';

class AnimatedLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;
  final double? strokeWidth;
  final double? value;

  const AnimatedLoadingIndicator({
    super.key,
    this.size = 48.0,
    this.color,
    this.strokeWidth,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.brandBlue;
    
    if (value != null) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          value: value,
          color: effectiveColor,
          strokeWidth: strokeWidth ?? 4.0,
          backgroundColor: effectiveColor.withValues(alpha: 0.2),
        ),
      );
    }

    final innerSize = size * 0.4;

    return Center(
      child: OneovaBlurReveal(
        delay: const Duration(milliseconds: 150), // fast loads never flash a loader
        duration: const Duration(milliseconds: 320),
        sigma: 6,
        rise: 0,
        child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing ring
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: effectiveColor.withValues(alpha: 0.5),
                  width: strokeWidth ?? 2.0,
                ),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.2, 1.2),
                  duration: 1200.ms,
                  curve: Curves.easeInOut,
                )
                .fade(
                  begin: 1.0,
                  end: 0.0,
                  duration: 1200.ms,
                  curve: Curves.easeOut,
                ),
            // Inner solid core
            Container(
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effectiveColor,
                boxShadow: [
                  BoxShadow(
                    color: effectiveColor.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            )
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.1, 1.1),
                  duration: 800.ms,
                  curve: Curves.easeInOut,
                ),
          ],
        ),
        ),
      ),
    );
  }
}
