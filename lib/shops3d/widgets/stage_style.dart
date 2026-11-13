import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';
import '../models/shop_models.dart';

/// Colour tokens for a shop stage. A stage can be forced dark (Midnight) or
/// light (Daylight) by the seller, so its overlays resolve from the stage's
/// own brightness instead of the app theme — always from [AppColors].
@immutable
class StageStyle {
  final bool dark;
  final Color accent;

  const StageStyle._(this.dark, this.accent);

  factory StageStyle.of(BuildContext context, StageConfig stage) => StageStyle._(
        stage.backdrop.isDark(context),
        stage.accent == StageAccent.pink ? AppColors.brandPink : AppColors.brandBlue,
      );

  Color get base => dark ? AppColors.darkBackground : AppColors.lightBackground;
  Color get fg => dark ? AppColors.textPrimary : AppColors.lightTextPrimary;
  Color get fgSecondary => dark ? AppColors.textSecondary : AppColors.lightTextSecondary;
  Color get fgMuted => dark ? AppColors.textMuted : AppColors.lightTextMuted;
  Color get glass => (dark ? AppColors.darkSurface : AppColors.lightSurface).withValues(alpha: dark ? 0.62 : 0.78);
  Color get glassStrong => (dark ? AppColors.darkSurfaceHighlight : AppColors.lightBackground).withValues(alpha: 0.9);
  Color get hairline => (dark ? AppColors.textPrimary : AppColors.lightTextPrimary).withValues(alpha: dark ? 0.12 : 0.10);
  Color get glow => accent.withValues(alpha: dark ? 0.34 : 0.16);
}

/// Frosted panel used for every floating element on the stage.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.style,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = AppRadius.lg,
    this.strong = false,
  });

  final StageStyle style;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: strong ? style.glassStrong : style.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: style.hairline, width: 1),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Stage backdrop: the base colour with a soft spotlight of the accent colour
/// above the product and a faint floor reflection.
class StageBackdropLayer extends StatelessWidget {
  const StageBackdropLayer({super.key, required this.style});
  final StageStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: style.base),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.15),
                radius: 0.85,
                colors: [style.glow, style.base.withValues(alpha: 0)],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.42,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [style.base.withValues(alpha: 0), style.accent.withValues(alpha: style.dark ? 0.10 : 0.05)],
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

/// The lit turntable the product stands on. Rings drift slowly; disabled
/// animations (accessibility setting) keep it still.
class StagePlatform extends StatefulWidget {
  const StagePlatform({super.key, required this.style, this.width = 260});
  final StageStyle style;
  final double width;

  @override
  State<StagePlatform> createState() => _StagePlatformState();
}

class _StagePlatformState extends State<StagePlatform> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.width * 0.28,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _PlatformPainter(widget.style, _c.value)),
        ),
      ),
    );
  }
}

class _PlatformPainter extends CustomPainter {
  _PlatformPainter(this.style, this.t);
  final StageStyle style;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final top = Rect.fromCenter(center: c, width: size.width * 0.86, height: size.height * 0.62);

    // Soft floor glow.
    canvas.drawOval(
      top.inflate(18),
      Paint()
        ..color = style.accent.withValues(alpha: style.dark ? 0.22 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    // Disc body.
    canvas.drawOval(top, Paint()..color = (style.dark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight));
    // Rim.
    canvas.drawOval(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = style.accent.withValues(alpha: 0.85),
    );
    // Drifting light rings.
    for (var i = 0; i < 2; i++) {
      final phase = (t + i * 0.5) % 1.0;
      final r = top.inflate(4 + phase * 22);
      canvas.drawOval(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = style.accent.withValues(alpha: (1 - phase) * 0.45),
      );
    }
    // Moving highlight on the rim.
    final a = t * 2 * math.pi;
    final p = Offset(c.dx + math.cos(a) * top.width / 2, c.dy + math.sin(a) * top.height / 2);
    canvas.drawCircle(
      p,
      3,
      Paint()
        ..color = style.accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_PlatformPainter old) => old.t != t || old.style.dark != style.dark || old.style.accent != style.accent;
}

/// Small pill badge (LIVE, 3D, discount…).
class StagePill extends StatelessWidget {
  const StagePill({super.key, required this.label, required this.color, this.icon, this.foreground = Colors.white});
  final String label;
  final Color color;
  final IconData? icon;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: foreground), const SizedBox(width: 4)],
          Text(label, style: AppTypography.micro(foreground).copyWith(fontSize: 9.5, letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

/// Network image with a quiet placeholder that matches the stage.
class StageImage extends StatelessWidget {
  const StageImage({super.key, required this.url, required this.style, this.fit = BoxFit.cover, this.cacheWidth});
  final String url;
  final StageStyle style;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final empty = ColoredBox(
      color: style.glass,
      child: Center(child: Icon(Icons.shopping_bag_outlined, color: style.fgMuted, size: 22)),
    );
    if (!url.startsWith('http')) return empty;
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) => empty,
      loadingBuilder: (c, child, p) => p == null ? child : ColoredBox(color: style.glass),
    );
  }
}
