import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

/// Hardware-style surfaces for the phone controller: raised matte caps with
/// soft drop shadows, recessed wells, and glowing status LEDs. Built from
/// theme tokens so both light and dark modes read as real materials.
class Tactile {
  Tactile._();

  static Color _top(BuildContext context) => Color.lerp(
    context.surface,
    context.textPrimary,
    context.isDark ? 0.07 : 0.0,
  )!;

  static Color _bottom(BuildContext context) => Color.lerp(
    context.surfaceMid,
    AppColors.brandBlack,
    context.isDark ? 0.3 : 0.05,
  )!;

  /// A raised cap. When [pressed] the light flips and the shadow collapses,
  /// so the key visibly sinks into the deck.
  static BoxDecoration raised(
    BuildContext context, {
    double radius = AppRadius.md,
    bool pressed = false,
    bool circle = false,
    Color? borderColor,
  }) {
    final dark = context.isDark;
    final top = _top(context);
    final bottom = _bottom(context);
    return BoxDecoration(
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: pressed ? [bottom, top] : [top, bottom],
      ),
      border: Border.all(color: borderColor ?? context.border, width: 1.0),
      boxShadow: pressed
          ? [
              BoxShadow(
                color: AppColors.brandBlack.withValues(
                  alpha: dark ? 0.35 : 0.06,
                ),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ]
          : [
              BoxShadow(
                color: AppColors.brandBlack.withValues(
                  alpha: dark ? 0.55 : 0.12,
                ),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
              BoxShadow(
                color: AppColors.brandBlack.withValues(
                  alpha: dark ? 0.4 : 0.07,
                ),
                blurRadius: 3,
                offset: const Offset(0, 1.5),
              ),
            ],
    );
  }

  /// A well sunk into the surface (grooves, readouts, segmented tracks).
  static BoxDecoration recessed(
    BuildContext context, {
    double radius = AppRadius.md,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(
            context.bg,
            AppColors.brandBlack,
            context.isDark ? 0.35 : 0.04,
          )!,
          context.bg,
        ],
      ),
      border: Border.all(color: context.border, width: 1.0),
    );
  }

  /// The soft rounded tile the hardware sits on.
  static BoxDecoration tile(BuildContext context) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [context.surfaceMid, context.surface],
      ),
      border: Border.all(color: context.border, width: 1.0),
    );
  }
}

/// Status LED. Pink glow when on; a dead lens when off.
class StatusLed extends StatelessWidget {
  const StatusLed({super.key, required this.on, this.size = 6, this.color});

  final bool on;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brandPink;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c : context.border,
        boxShadow: on
            ? [
                BoxShadow(
                  color: c.withValues(alpha: 0.75),
                  blurRadius: size * 1.4,
                ),
                BoxShadow(
                  color: c.withValues(alpha: 0.35),
                  blurRadius: size * 3,
                ),
              ]
            : null,
      ),
    );
  }
}
