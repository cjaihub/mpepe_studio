import 'package:flutter/material.dart';

import '../geometry/studio_geometry.dart';
import '../theme/live_studio_tokens.dart';
import 'stage_bits.dart';
import 'stage_painters.dart';

/// Presentation stand (UI layer, artboard px): beam, disc, inner ring.
class StudioStand extends StatelessWidget {
  const StudioStand({super.key, required this.spec, required this.tokens, required this.phone});
  final StandSpec spec;
  final LiveStudioTokens tokens;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final d = spec.disc;
    final r = spec.ring;
    return IgnorePointer(
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fromRect(
          rect: spec.beam,
          child: ClipPath(
            clipper: const BeamClipper(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [LiveStudioAccent.cyanA(0.25), LiveStudioAccent.cyanA(0)],
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: d,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.elliptical(d.width / 2, d.height / 2)),
              boxShadow: [BoxShadow(color: LiveStudioAccent.pinkA(0.35), blurRadius: phone ? 22 : 28)],
            ),
            child: ClipOval(
              child: Stack(fit: StackFit.expand, children: [
                CustomPaint(
                  painter: EllipseGradientPainter(
                    center: const Offset(0.5, 0.4),
                    radii: const Offset(0.7071, 0.8485), // ellipse farthest-corner
                    colors: [LiveStudioAccent.blueA(0.4), tokens.standDisc, tokens.standDisc],
                    stops: const [0, 0.7, 1],
                  ),
                ),
                CustomPaint(painter: EllipseInsetGlowPainter(LiveStudioAccent.cyanA(0.25), phone ? 12 : 18)),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: OvalBorder(side: BorderSide(color: LiveStudioAccent.blueA(0.75), width: 1)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: r,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: OvalBorder(side: BorderSide(color: LiveStudioAccent.cyanA(0.45), width: 1)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Phone host floor glow (world space).
class FloorGlow extends StatelessWidget {
  const FloorGlow({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: EllipseGradientPainter(
            center: const Offset(0.5, 0.5),
            radii: const Offset(0.7071, 0.7071), // ellipse farthest-corner
            colors: [LiveStudioAccent.pinkA(0.45), LiveStudioAccent.pinkA(0)],
            stops: const [0, 0.7],
          ),
        ),
      );
}

/// Theme fades over the world (viewport-wide; heights in artboard px × uiScale).
class StudioFades extends StatelessWidget {
  const StudioFades({super.key, required this.tokens, required this.phone, required this.camera});
  final LiveStudioTokens tokens;
  final bool phone;
  final StudioCamera camera;

  @override
  Widget build(BuildContext context) {
    final u = camera.uiScale;
    final b = tokens.base;
    final top = camera.uiTranslate.dy;
    return IgnorePointer(
      child: Stack(children: phone
          ? [
              Positioned(
                left: 0,
                right: 0,
                top: top,
                height: 150 * u,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [b.withValues(alpha: 0.92), b.withValues(alpha: 0.6), b.withValues(alpha: 0)],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: top + 430 * u,
                height: 180 * u,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [b.withValues(alpha: 0), b, b],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                ),
              ),
              // Below the panel the artboard base shows (the photo ends).
              Positioned(left: 0, right: 0, top: top + 610 * u, bottom: 0, child: ColoredBox(color: b)),
            ]
          : [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 140 * u,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [b.withValues(alpha: 0.7), b.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 300 * u,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [b.withValues(alpha: 0.92), b.withValues(alpha: 0.92), b.withValues(alpha: 0)],
                      stops: const [0, 0.2, 1],
                    ),
                  ),
                ),
              ),
            ]),
    );
  }
}

/// The table frame slot (UI layer). Content belongs to the table workstream
/// and comes in as [content]; this draws frame, rim, shadows and the expand
/// button.
class TableFrame extends StatelessWidget {
  const TableFrame({
    super.key,
    required this.radius,
    required this.border,
    required this.frameColor,
    required this.phone,
    required this.popped,
    this.content,
    this.onExpand,
  });
  final double radius;
  final double border;
  final Color frameColor;
  final bool phone;
  final bool popped;
  final Widget? content;
  final VoidCallback? onExpand;

  static List<BoxShadow> shadowsFor(bool phone) {
    final t = LiveStudioWorld.tableShadow;
    if (!phone) return t;
    // Phone: 0 16px 32px and 0 0 28px (same colors).
    return [
      t[0],
      BoxShadow(color: t[1].color, blurRadius: 32, offset: const Offset(0, 16)),
      BoxShadow(color: t[2].color, blurRadius: 28),
    ];
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: LiveStudioWorld.screen,
          border: border > 0 ? Border.all(color: frameColor, width: border) : null,
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          boxShadow: shadowsFor(phone),
        ),
        child: Padding(
          padding: EdgeInsets.all(border),
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular((radius - border).clamp(0.0, radius))),
            child: Stack(fit: StackFit.expand, children: [
              ?content,
              if (popped) const InWindowOverlay(iconSize: 18, fontSize: 11),
              Positioned(
                right: 6,
                top: 6,
                child: StageExpandButton(
                  size: phone ? 26 : 28,
                  iconSize: phone ? 14 : 15,
                  radius: 6,
                  label: 'Pop out the table screen',
                  onTap: onExpand,
                ),
              ),
            ]),
          ),
        ),
      );
}
