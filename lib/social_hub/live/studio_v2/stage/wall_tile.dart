import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../geometry/homography.dart';
import '../geometry/studio_geometry.dart';
import '../theme/live_studio_tokens.dart';
import 'stage_bits.dart';
import 'stage_painters.dart';
import 'stage_seat.dart';

/// Tweens a column-major matrix element-wise (S/M/L preset changes).
class MatrixTween extends Tween<List<double>> {
  MatrixTween({super.begin, super.end});
  @override
  List<double> lerp(double t) => lerpMatrix(begin!, end!, t);
}

/// S/M/L change duration (transform only).
const Duration kWallPresetTween = Duration(milliseconds: 250);

/// One guest tile on the wall, in world space. Fill the world Stack with it;
/// it positions its three layers (wall glow, tile, expand button) by the
/// slot's matrix3d and animates matrix changes over [kWallPresetTween].
class WallTile extends StatelessWidget {
  const WallTile({
    super.key,
    required this.slot,
    required this.seat,
    required this.phone,
    required this.glow,
    required this.radius,
    required this.border,
    required this.frameColor,
    required this.focusRing,
    required this.showNames,
    required this.renderScale,
    this.videoBuilder,
    this.onTap,
    this.onExpand,
  });

  final SlotGeometry slot;

  /// Null = empty seat.
  final StageSeat? seat;
  final bool phone;
  final GlowSpec glow;
  final double radius;
  final double border;
  final Color frameColor;
  final Color focusRing;
  final bool showNames;

  /// World → UI scale (video render size).
  final double renderScale;
  final StudioVideoBuilder? videoBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<List<double>>(
        tween: MatrixTween(end: slot.matrix3d),
        duration: kWallPresetTween,
        curve: Curves.easeOutCubic,
        builder: (context, m, _) => _layers(m),
      ),
    );
  }

  Widget _layers(List<double> m) {
    final t = slot.tile;
    final s = seat;
    final glowM = matrixTranslateScale(
      m,
      glow.translateFactor.dx * t.width,
      glow.translateFactor.dy * t.height,
      glow.scale.dx,
      glow.scale.dy,
    );
    final projected = polygonBounds(projectTile(m, t));
    return Stack(clipBehavior: Clip.none, children: [
      if (s != null)
        Positioned(
          left: 0,
          top: 0,
          width: t.width,
          height: t.height,
          child: IgnorePointer(
            child: Transform(
              transform: Matrix4.fromList(glowM),
              child: Opacity(
                opacity: glow.opacity,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: glow.blur, sigmaY: glow.blur),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: s.accent,
                      borderRadius: BorderRadius.all(Radius.circular(glow.radius)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: 0,
        top: 0,
        width: t.width,
        height: t.height,
        child: Transform(
          transform: Matrix4.fromList(m),
          child: _TileBody(
            tile: this,
            renderSize: projected.size * renderScale,
          ),
        ),
      ),
      if (s != null)
        Positioned(
          left: 0,
          top: 0,
          width: slot.expandSize,
          height: slot.expandSize,
          child: Transform(
            transform: Matrix4.fromList(matrixTranslateScale(m, slot.expandOffset.dx, slot.expandOffset.dy)),
            child: StageExpandButton(
              size: slot.expandSize,
              iconSize: phone ? 16 : 11,
              radius: 6,
              label: 'Pop out ${s.name}',
              onTap: onExpand,
            ),
          ),
        ),
    ]);
  }
}

class _TileBody extends StatefulWidget {
  const _TileBody({required this.tile, required this.renderSize});
  final WallTile tile;
  final Size renderSize;
  @override
  State<_TileBody> createState() => _TileBodyState();
}

class _TileBodyState extends State<_TileBody> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.tile;
    final s = w.seat;
    final phone = w.phone;
    final metrics = phone
        ? NameplateMetrics.phone
        : (w.slot.portrait ? NameplateMetrics.portrait : NameplateMetrics.wide);
    final innerRadius = (w.radius - w.border).clamp(0.0, w.radius);
    final shadows = _hover && s != null
        ? LiveStudioWorld.tileHover
        : (phone ? LiveStudioWorld.tileShadowPhone : LiveStudioWorld.tileShadow);

    Widget content;
    if (s == null) {
      content = const ColoredBox(color: LiveStudioWorld.screen);
    } else {
      final bg = LiveStudioWorld.guestBg(s.accent);
      final showVideo = s.camOn && w.videoBuilder != null;
      content = Stack(fit: StackFit.expand, children: [
        CustomPaint(
          painter: EllipseGradientPainter(
            center: const Offset(0.5, 0.15),
            radii: const Offset(1.2, 0.9),
            colors: bg.colors,
            stops: bg.stops!,
          ),
        ),
        CustomPaint(
          painter: EllipseGradientPainter(
            center: const Offset(0.5, 1),
            radii: const Offset(0.8, 0.7),
            colors: [s.accent.withValues(alpha: 0x55 / 255), s.accent.withValues(alpha: 0)],
            stops: const [0, 0.7],
          ),
        ),
        if (showVideo)
          w.videoBuilder!(s.uid, widget.renderSize)
        else
          FractionallySizedBox(
            alignment: Alignment.bottomCenter,
            heightFactor: 0.86,
            widthFactor: 1,
            child: CustomPaint(painter: CartoonAvatarPainter(accent: s.accent, muted: s.muted)),
          ),
        const DecoratedBox(decoration: BoxDecoration(gradient: LiveStudioWorld.sheen)),
        if (w.showNames)
          Nameplate(name: s.name, accent: s.accent, speaking: s.speaking && !s.muted, muted: s.muted, metrics: metrics),
        if (s.popped)
          InWindowOverlay(
            iconSize: phone ? 20 : (w.slot.portrait ? 14 : 15),
            fontSize: phone ? 12 : (w.slot.portrait ? 8 : 9),
          ),
      ]);
    }

    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: LiveStudioWorld.screen,
        border: w.border > 0 ? Border.all(color: w.frameColor, width: w.border) : null,
        borderRadius: BorderRadius.all(Radius.circular(w.radius)),
        boxShadow: shadows,
      ),
      child: Padding(
        padding: EdgeInsets.all(w.border),
        child: ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(innerRadius)),
          child: content,
        ),
      ),
    );
    if (s == null) {
      return Semantics(label: 'Empty seat', child: Opacity(opacity: 0.55, child: box));
    }

    if (_focus) {
      box = Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
        box,
        Positioned(
          left: -4,
          top: -4,
          right: -4,
          bottom: -4,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: w.focusRing, width: 2),
                borderRadius: BorderRadius.all(Radius.circular(w.radius + 4)),
              ),
            ),
          ),
        ),
      ]);
    }

    return Semantics(
      button: true,
      label: 'Spotlight ${s.name}',
      onTap: w.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            w.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: w.onTap, child: box),
      ),
    );
  }
}
