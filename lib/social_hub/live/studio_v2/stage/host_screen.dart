import 'package:flutter/material.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../geometry/studio_geometry.dart';
import '../theme/live_studio_tokens.dart';
import 'stage_bits.dart';
import 'stage_painters.dart';
import 'stage_seat.dart';

/// The curved center screen, in world space (position it at host.rect).
///
/// Wall-layer drop shadows → clipped content (background, live video or the
/// host silhouette, bottom gradient, ON STAGE/name/role, LIVE pill) → pink
/// rim under the frame stroke → expand button.
class HostScreen extends StatelessWidget {
  const HostScreen({
    super.key,
    required this.geometry,
    required this.seat,
    required this.frameWidth,
    required this.frameColor,
    required this.title,
    required this.live,
    required this.renderScale,
    this.videoBuilder,
    this.onExpand,
  });

  final OrientationGeometry geometry;
  final StageSeat? seat;
  final int frameWidth;
  final Color frameColor;
  final String title;
  final bool live;

  /// World → UI scale, so video gets its on-screen size.
  final double renderScale;
  final StudioVideoBuilder? videoBuilder;
  final VoidCallback? onExpand;

  bool get _phone => geometry.isPhone;

  @override
  Widget build(BuildContext context) {
    final host = geometry.host;
    final size = host.rect.size;
    final s = seat;
    final isHost = s == null || s.role == StudioRole.host;
    final bg = isHost
        ? LiveStudioWorld.hostBg
        : LiveStudioWorld.guestBg(s.accent);
    final showVideo = s != null && s.camOn && videoBuilder != null;
    final ab = host.avatarBox;

    final labels = _labels(s);
    return SizedBox.fromSize(
      size: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: PathShadowPainter(host.clipPath, LiveStudioWorld.wallLayer))),
        ),
        Positioned.fill(
          child: ClipPath(
            clipper: PathClipper(host.clipPath),
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(
                painter: EllipseGradientPainter(
                  center: Offset(0.5, isHost ? 0.2 : 0.15),
                  radii: const Offset(1.2, 0.9),
                  colors: bg.colors,
                  stops: bg.stops!,
                ),
              ),
              if (showVideo)
                videoBuilder!(s.uid, size * renderScale)
              else
                Positioned(
                  left: ab.left,
                  bottom: host.avatarBottom,
                  width: ab.width,
                  height: ab.height,
                  child: const CustomPaint(painter: HostSilhouettePainter()),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _phone ? 130 : 120,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        LiveStudioTokens.dimTint(_phone ? 0.85 : 0.75),
                        LiveStudioTokens.dimTint(0),
                      ],
                    ),
                  ),
                ),
              ),
              labels,
              if (live) _livePill(host),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: HostRimPainter(
                      path: host.rimPath,
                      rimWidth: geometry.hostRim(frameWidth),
                      strokeWidth: geometry.hostStroke(frameWidth),
                      frameColor: frameColor,
                    ),
                  ),
                ),
              ),
              if (s != null && s.popped)
                InWindowOverlay(iconSize: _phone ? 30 : 26, fontSize: _phone ? 16 : 13),
              if (s != null) _expand(host, s),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _labels(StageSeat? s) {
    if (s == null) return const SizedBox.shrink();
    final p = _phone;
    final children = <Widget>[
      DecoratedBox(
        decoration: BoxDecoration(
          color: LiveStudioAccent.pink,
          borderRadius: BorderRadius.all(Radius.circular(p ? 5 : 4)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: p ? 9 : 8, vertical: 3),
          child: Text('ON STAGE',
              style: LiveStudioType.s(p ? 13 : 10, FontWeight.w600, LiveStudioWorld.textHigh,
                  height: p ? 17 : 14, letter: 0.06)),
        ),
      ),
      const SizedBox(height: 3),
      Text(s.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LiveStudioType.s(p ? 24 : 22, FontWeight.w700, LiveStudioWorld.textHigh, height: 28)),
      const SizedBox(height: 3),
      Text(
        p || title.isEmpty ? s.roleLabel : '${s.roleLabel} · $title',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: LiveStudioType.s(p ? 15 : 12, FontWeight.w400, LiveStudioWorld.textMedium, height: p ? 19 : 16),
      ),
    ];
    final col = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    final at = geometry.host.labels;
    if (at != null) {
      return Positioned(left: at.dx, top: at.dy, right: 16, child: col);
    }
    return Positioned(left: 14, right: 14, bottom: 14, child: col);
  }

  Widget _livePill(HostGeometry host) {
    final at = host.livePill;
    if (at != null) return Positioned(left: at.dx, top: at.dy, child: const LivePill());
    return const Positioned(
      right: 14,
      top: 22,
      child: LivePill(
        fontSize: 14,
        lineHeight: 18,
        dot: 8,
        gap: 7,
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      ),
    );
  }

  Widget _expand(HostGeometry host, StageSeat s) {
    final at = host.expandButton ?? const Offset(16, 22);
    final size = host.expandSize ?? 40;
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: StageExpandButton(
        size: size,
        iconSize: size >= 40 ? 22 : 17,
        radius: 8,
        label: 'Pop out ${s.name}',
        onTap: onExpand,
      ),
    );
  }
}
