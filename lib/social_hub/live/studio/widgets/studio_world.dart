import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../backend/live/services/live_stage_media_controller.dart';
import '../../../../shared/theme/obsidian_telemetry_tokens.dart';
import '../live_studio_geometry.dart';
import '../live_studio_roster.dart';

/// The 1376×768 studio "world": photo + wall-mounted video windows + center
/// stage + presentation stand, scaled as one unit so the walls always line up
/// with the photo.
class StudioWorld extends StatelessWidget {
  final StudioGeometry geometry;
  final StudioWorldPlacement placement;
  final StudioRoster roster;
  final LiveStageMediaState media;
  final String selfUid;
  final String showTitle;
  final double dimOpacity;
  final bool showWallGuests;
  final bool showStand;

  /// Null when the current user can't change the stage (non-host).
  final ValueChanged<StageMember>? onSwapToStage;

  const StudioWorld({
    super.key,
    required this.geometry,
    required this.placement,
    required this.roster,
    required this.media,
    required this.selfUid,
    required this.showTitle,
    this.dimOpacity = 0.15,
    this.showWallGuests = true,
    this.showStand = true,
    this.onSwapToStage,
  });

  @override
  Widget build(BuildContext context) {
    final img = geometry.imageSize;
    final layout = placement.layoutOf(geometry);
    final phone = !placement.isLandscape;

    return Positioned(
      left: placement.offset.dx,
      top: placement.offset.dy,
      width: img.width,
      height: img.height,
      child: Transform(
        transform: Matrix4.diagonal3Values(placement.scale, placement.scale, 1),
        child: SizedBox(
          width: img.width,
          height: img.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image.asset(
                  geometry.imageAsset,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: OTColors.obsidianBase),
                ),
              ),
              if (dimOpacity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: OTColors.obsidianBase.withValues(alpha: dimOpacity),
                    ),
                  ),
                ),
              if (showStand) _StandLayer(stand: geometry.stand),
              Positioned.fromRect(
                rect: layout.stage.rect,
                child: _CenterStage(
                  stage: layout.stage,
                  member: roster.center,
                  media: media,
                  selfUid: selfUid,
                  showTitle: showTitle,
                  compact: phone,
                ),
              ),
              if (showWallGuests)
                for (final slot in layout.slots)
                  if (roster.wall[slot.id] case final StageMember m)
                    Positioned(
                      left: 0,
                      top: 0,
                      width: slot.nativeSize.width,
                      height: slot.nativeSize.height,
                      child: Transform(
                        transform: slot.transform,
                        child: VideoWindow(
                          key: ValueKey('slot-${slot.id}-${m.uid}'),
                          member: m,
                          renderer: media.rendererFor(m.uid, selfUid),
                          hasVideo: m.isCameraOn && media.hasLiveVideo(m.uid, selfUid),
                          isActiveSpeaker: media.activeSpeakerId == m.uid,
                          isSelf: m.uid == selfUid,
                          labelSize: phone ? 15 : (slot.portrait ? 10 : 11),
                          badgeSize: phone ? 22 : (slot.portrait ? 14 : 16),
                          onTap: onSwapToStage == null ? null : () => onSwapToStage!(m),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO WINDOW (wall tile)
// ─────────────────────────────────────────────────────────────────────────────

class VideoWindow extends StatelessWidget {
  final StageMember member;
  final RTCVideoRenderer? renderer;
  final bool hasVideo;
  final bool isActiveSpeaker;
  final bool isSelf;
  final double labelSize;
  final double badgeSize;
  final VoidCallback? onTap;

  const VideoWindow({
    super.key,
    required this.member,
    required this.renderer,
    required this.hasVideo,
    required this.isActiveSpeaker,
    required this.isSelf,
    required this.labelSize,
    required this.badgeSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pad = labelSize * 0.45;
    final window = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: OTColors.surface1,
        borderRadius: BorderRadius.circular(OTRadius.base),
        border: Border.all(
          color: isActiveSpeaker ? OTColors.neonPink : OTColors.hairline16,
          width: 1,
        ),
        boxShadow: isActiveSpeaker ? OTShadows.activeSpeaker : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OTRadius.base - 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVideo && renderer != null)
              RTCVideoView(
                renderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: isSelf,
              )
            else
              StageSilhouette(avatarUrl: member.avatarUrl),
            Positioned(
              left: pad,
              bottom: pad,
              right: badgeSize + pad * 2,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: NamePill(
                  name: isSelf ? '${member.displayName} (You)' : member.displayName,
                  fontSize: labelSize,
                ),
              ),
            ),
            Positioned(
              right: pad,
              bottom: pad,
              child: MicBadge(muted: member.isMuted, size: badgeSize),
            ),
          ],
        ),
      ),
    );

    final action = onTap == null
        ? 'On the wall'
        : 'Tap to move to the center stage';
    return Semantics(
      button: onTap != null,
      label: '${member.displayName}, ${member.roleLabel}, '
          '${member.isMuted ? 'muted' : 'mic on'}. $action',
      child: onTap == null
          ? window
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: MouseRegion(cursor: SystemMouseCursors.click, child: window),
            ),
    );
  }
}

class NamePill extends StatelessWidget {
  final String name;
  final double fontSize;
  const NamePill({super.key, required this.name, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.6, vertical: fontSize * 0.25),
      decoration: BoxDecoration(
        color: OTColors.namePill72,
        borderRadius: BorderRadius.circular(OTRadius.full),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: OTType.pill(fontSize),
      ),
    );
  }
}

class MicBadge extends StatelessWidget {
  final bool muted;
  final double size;
  const MicBadge({super.key, required this.muted, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = muted ? OTColors.liveCrimson : OTColors.telemetryCyan;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OTColors.namePill72,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Icon(
        muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        size: size * 0.62,
        color: color,
        semanticLabel: muted ? 'Muted' : 'Mic on',
      ),
    );
  }
}

/// Camera-off fallback: dark surface with avatar or silhouette.
class StageSilhouette extends StatelessWidget {
  final String avatarUrl;
  const StageSilhouette({super.key, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [OTColors.surface2, OTColors.obsidianBase],
        ),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final d = (c.biggest.shortestSide * 0.42).clamp(12.0, 160.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _SilhouettePainter()),
            if (avatarUrl.isNotEmpty)
              Align(
                alignment: const Alignment(0, -0.18),
                child: ClipOval(
                  child: Image.network(
                    avatarUrl,
                    width: d,
                    height: d,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => SizedBox(width: d, height: d),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.21;
    final cx = size.width / 2;
    final headY = size.height * 0.41;
    final paint = Paint()..color = OTColors.surface3;
    canvas.drawCircle(Offset(cx, headY), r, paint);
    final body = Rect.fromCenter(
      center: Offset(cx, size.height * 1.02),
      width: r * 4.2,
      height: r * 3.6,
    );
    canvas.drawOval(body, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// CENTER STAGE (curved LED wall)
// ─────────────────────────────────────────────────────────────────────────────

class _CenterStage extends StatelessWidget {
  final CurvedStage stage;
  final StageMember? member;
  final LiveStageMediaState media;
  final String selfUid;
  final String showTitle;
  final bool compact;

  const _CenterStage({
    required this.stage,
    required this.member,
    required this.media,
    required this.selfUid,
    required this.showTitle,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final m = member;
    final renderer = m == null ? null : media.rendererFor(m.uid, selfUid);
    final hasVideo =
        m != null && m.isCameraOn && renderer != null && media.hasLiveVideo(m.uid, selfUid);
    final speaking = m != null && media.activeSpeakerId == m.uid;

    // Native sizes (scaled down by the world scale on screen).
    final labelSize = compact ? 15.0 : 11.0;
    final nameSize = compact ? 24.0 : 30.0;
    final metaSize = compact ? 15.0 : 13.0;

    return Semantics(
      label: m == null
          ? 'Center stage, waiting for the host'
          : 'On stage: ${m.displayName}, ${m.roleLabel}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: _StageClipper(stage),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasVideo)
                    RTCVideoView(
                      renderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      mirror: m.uid == selfUid,
                    )
                  else
                    StageSilhouette(avatarUrl: m?.avatarUrl ?? ''),
                  // Legibility gradient behind the overlay text.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomLeft,
                        end: const Alignment(0.2, -0.2),
                        colors: [
                          OTColors.namePill72,
                          OTColors.obsidianBase.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  if (m != null)
                    Positioned(
                      left: compact ? 34 : 40,
                      bottom: compact ? 30 : 64,
                      right: stage.rect.width * 0.35,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: labelSize * 0.6, vertical: labelSize * 0.25),
                            decoration: BoxDecoration(
                              color: OTColors.neonPink,
                              borderRadius: BorderRadius.circular(OTRadius.sm),
                            ),
                            child: Text('ON STAGE',
                                style: OTType.pill(labelSize)
                                    .copyWith(letterSpacing: labelSize * 0.06)),
                          ),
                          SizedBox(height: labelSize * 0.5),
                          Text(
                            m.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OTType.displayName(size: nameSize),
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${m.roleLabel} · $showTitle',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OTType.bodySm().copyWith(fontSize: metaSize),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Positioned(
                    right: compact ? 26 : 30,
                    top: compact ? 18 : 22,
                    child: LivePill(fontSize: labelSize, color: OTColors.neonPink),
                  ),
                ],
              ),
            ),
          ),
          // Stroke along the same path, drawn unclipped so it is full width.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _StageStrokePainter(stage, glow: speaking),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageClipper extends CustomClipper<Path> {
  final CurvedStage stage;
  _StageClipper(this.stage);

  @override
  Path getClip(Size size) => stage.localPath();

  @override
  bool shouldReclip(covariant _StageClipper oldClipper) => oldClipper.stage != stage;
}

class _StageStrokePainter extends CustomPainter {
  final CurvedStage stage;
  final bool glow;
  _StageStrokePainter(this.stage, {required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final path = stage.localPath();
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stage.strokeWidth * 3
          ..color = OTColors.pinkGlow45
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stage.strokeWidth
        ..color = OTColors.pinkStroke55,
    );
  }

  @override
  bool shouldRepaint(covariant _StageStrokePainter old) =>
      old.glow != glow || old.stage != stage;
}

/// "● LIVE" pill with a pulsing dot.
class LivePill extends StatelessWidget {
  final double fontSize;
  final Color color;
  const LivePill({super.key, this.fontSize = 12, this.color = OTColors.liveCrimson});

  @override
  Widget build(BuildContext context) {
    final dot = fontSize * 0.55;
    return Semantics(
      label: 'Live',
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.75, vertical: fontSize * 0.32),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(OTRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dot,
              height: dot,
              decoration: const BoxDecoration(
                  color: OTColors.textHigh, shape: BoxShape.circle),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 1, end: 0.3, duration: 800.ms)
                .scaleXY(begin: 1, end: 0.8, duration: 800.ms),
            SizedBox(width: fontSize * 0.4),
            ExcludeSemantics(
              child: Text('LIVE',
                  style: OTType.pill(fontSize).copyWith(
                      fontWeight: FontWeight.w700, letterSpacing: fontSize * 0.06)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRESENTATION STAND (glowing ellipse on the stage floor)
// ─────────────────────────────────────────────────────────────────────────────

class _StandLayer extends StatelessWidget {
  final PresentationStand stand;
  const _StandLayer({required this.stand});

  @override
  Widget build(BuildContext context) {
    // Extra room around the ellipse for the glow.
    const bleed = 40.0;
    return Positioned(
      left: stand.center.dx - stand.size.width / 2 - bleed,
      top: stand.center.dy - stand.size.height / 2 - bleed,
      width: stand.size.width + bleed * 2,
      height: stand.size.height + bleed * 2,
      child: IgnorePointer(
        child: CustomPaint(painter: _StandPainter(stand.size, bleed)),
      ),
    );
  }
}

class _StandPainter extends CustomPainter {
  final Size ellipse;
  final double bleed;
  _StandPainter(this.ellipse, this.bleed);

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(bleed, bleed, ellipse.width, ellipse.height);
    final inner = Rect.fromCenter(
        center: outer.center, width: ellipse.width * 0.66, height: ellipse.height * 0.62);

    // Floor glow.
    canvas.drawOval(
      outer.inflate(10),
      Paint()
        ..color = OTColors.pinkGlow35
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    // Surface.
    canvas.drawOval(
      outer,
      Paint()
        ..shader = const RadialGradient(
          colors: [OTColors.surface2, OTColors.obsidianBase],
        ).createShader(outer),
    );
    // Pink rim.
    canvas.drawOval(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = OTColors.neonPink,
    );
    // Cyan inner ring + soft glow.
    canvas.drawOval(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = OTColors.telemetryCyan.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawOval(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = OTColors.telemetryCyan.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _StandPainter old) =>
      old.ellipse != ellipse || old.bleed != bleed;
}
