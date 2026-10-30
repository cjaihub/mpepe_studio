import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../geometry/studio_geometry.dart';
import '../theme/live_studio_tokens.dart';
import 'host_screen.dart';
import 'popout_controller.dart';
import 'popout_window.dart';
import 'stage_painters.dart';
import 'stage_seat.dart';
import 'stand.dart';
import 'wall_tile.dart';

/// The Live Studio stage: world layer (photo, dim, host screen, wall tiles,
/// glows) + UI-layer stage pieces (fades, stand, table frame) + the pop-out.
///
/// Fills its parent. Pure renderer: it reads [state] and [members] and
/// reports taps. A tile tap calls [onTileTap] (host/coHost → lsSetLayout swap;
/// viewers → open a pop-out, ARCHITECTURE Q3 — the caller decides). Expand
/// buttons call [onExpand]; when it is null they open the local pop-out.
class StudioStage extends ConsumerWidget {
  const StudioStage({
    super.key,
    required this.geometry,
    required this.state,
    required this.members,
    required this.orientation,
    this.isSpeaking,
    this.isMuted,
    this.videoBuilder,
    this.onTileTap,
    this.onExpand,
    this.tableContent,
    this.tableTitle = 'On the table',
    this.popoutContentBuilder,
    this.showFades = true,
    this.showPopout = true,
    this.showTable = true,
  });

  final StudioGeometry geometry;
  final StudioState state;
  final Map<String, StageMember> members;
  final StudioOrientation orientation;

  /// Speaking right now (nameplate eq bars). Default: nobody.
  final bool Function(String uid)? isSpeaking;

  /// Mic muted. Default: `!member.micOn`.
  final bool Function(String uid)? isMuted;
  final StudioVideoBuilder? videoBuilder;
  final ValueChanged<String>? onTileTap;
  final ValueChanged<PopoutTarget>? onExpand;

  /// Table content from the table workstream (frame is drawn here).
  final Widget? tableContent;
  final String tableTitle;

  /// Pop-out body. Default: live video / host silhouette + name for people,
  /// [tableContent] for the table.
  final PopoutContentBuilder? popoutContentBuilder;
  final bool showFades;
  final bool showPopout;

  /// False hides the table frame (Game Live has no table).
  final bool showTable;

  bool get _phone => orientation == StudioOrientation.phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = geometry.studio(state.settings.studioId);
    final g = studio.of(orientation);
    final settings = state.settings;
    final tokens = LiveStudioTokens.forTheme(settings.theme);
    final frameColor = studioHex(settings.frameColor);
    final popout = showPopout ? ref.watch(studioPopoutProvider) : null;
    final popped = popout?.target;

    bool speaking(String uid) => isSpeaking?.call(uid) ?? false;
    bool muted(String uid) => isMuted?.call(uid) ?? !(members[uid]?.micOn ?? true);
    StageSeat seatOf(String uid) => StageSeat.of(uid, members[uid],
        isSpeaking: speaking, isMuted: muted, popped: popped == PopoutTarget.person(uid));

    return DefaultTextStyle(
      // Reset the app font: the studio uses the system stack (SPEC §1.3).
      style: LiveStudioType.s(13, FontWeight.w400, LiveStudioWorld.textHigh),
      child: LayoutBuilder(builder: (context, box) {
        final viewport = box.biggest;
        final cam = StudioCamera.forViewport(g, studio.background.size, viewport);
        final bounds = cam.viewportInArtboard;

        void expand(PopoutTarget t) {
          if (onExpand != null) {
            onExpand!(t);
          } else {
            ref.read(studioPopoutProvider.notifier).open(t, g, bounds: bounds);
          }
        }

        final stage = state.stage;
        final center = stage.centerUid.isEmpty ? null : seatOf(stage.centerUid);
        final preset = _phone ? GuestSize.m : settings.guestSize;
        final world = Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Image.asset(
              studio.background.asset,
              fit: BoxFit.fill,
              semanticLabel: studio.background.alt,
              gaplessPlayback: true,
            ),
          ),
          Positioned.fill(child: ColoredBox(color: LiveStudioTokens.dimTint(settings.studioDim))),
          Positioned.fromRect(
            rect: g.host.rect,
            child: HostScreen(
              geometry: g,
              seat: center,
              frameWidth: settings.frameWidth,
              frameColor: frameColor,
              title: state.title,
              live: state.status == StudioStatus.live,
              renderScale: cam.scale,
              videoBuilder: videoBuilder,
              onExpand: center == null ? null : () => expand(PopoutTarget.person(center.uid)),
            ),
          ),
          if (g.host.floorGlow != null) Positioned.fromRect(rect: g.host.floorGlow!, child: const FloorGlow()),
          for (var i = 0; i < g.slotOrder.length && i < stage.wall.length; i++)
            if (g.slotAt(i, preset) case final slot?)
              Positioned.fill(
                child: WallTile(
                  key: ValueKey('wall-$i'),
                  slot: slot,
                  seat: stage.wall[i] == null ? null : seatOf(stage.wall[i]!),
                  phone: _phone,
                  glow: g.glow,
                  radius: g.tileRadius,
                  border: g.tileBorder(settings.frameWidth),
                  frameColor: frameColor,
                  focusRing: tokens.focusRing,
                  showNames: settings.showNames,
                  renderScale: cam.scale,
                  videoBuilder: videoBuilder,
                  onTap: stage.wall[i] == null || onTileTap == null ? null : () => onTileTap!(stage.wall[i]!),
                  onExpand: stage.wall[i] == null ? null : () => expand(PopoutTarget.person(stage.wall[i]!)),
                ),
              ),
        ]);

        final ui = Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: StudioStand(spec: g.stand, tokens: tokens, phone: _phone)),
          if (showTable)
            Positioned.fromRect(
              rect: g.table,
              child: TableFrame(
                radius: g.tableRadius,
                border: settings.frameWidth.toDouble(),
                frameColor: frameColor,
                phone: _phone,
                popped: popped?.isTable ?? false,
                content: tableContent,
                onExpand: () => expand(const PopoutTarget.table()),
              ),
            ),
        ]);

        return ClipRect(
          child: ColoredBox(
            color: tokens.base,
            child: Stack(fit: StackFit.expand, children: [
              _place(cam.worldMatrix, studio.background.size, world),
              if (showFades) Positioned.fill(child: StudioFades(tokens: tokens, phone: _phone, camera: cam)),
              _place(cam.artboardMatrix, g.artboard, ui),
              // The pop-out lives in viewport space (scaled like the artboard)
              // so it stays hit-testable on viewports wider/taller than it.
              if (showPopout)
                _place(
                  [cam.uiScale, 0, 0, 0, 0, cam.uiScale, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                  bounds.size,
                  StudioPopoutLayer(
                    geometry: g,
                    bounds: bounds,
                    frameWidth: settings.frameWidth.toDouble(),
                    frameColor: frameColor,
                    titleFor: (t) => t.isTable ? tableTitle : (members[t.uid]?.displayName ?? ''),
                    contentBuilder: popoutContentBuilder ?? (c, t, size) => _defaultPopout(t, size),
                  ),
                ),
            ]),
          ),
        );
      }),
    );
  }

  /// Lays out [child] at [size] and maps it through [m] (origin top-left).
  Widget _place(List<double> m, Size size, Widget child) => Positioned(
        left: 0,
        top: 0,
        width: size.width,
        height: size.height,
        child: Transform(transform: Matrix4.fromList(m), child: child),
      );

  Widget _defaultPopout(PopoutTarget t, Size size) {
    if (t.isTable) return tableContent ?? const ColoredBox(color: LiveStudioWorld.screen);
    final m = members[t.uid];
    if (m != null && m.camOn && videoBuilder != null) return videoBuilder!(t.uid!, size);
    final bg = m == null || m.role == StudioRole.host
        ? LiveStudioWorld.hostBg
        : LiveStudioWorld.guestBg(studioHex(m.accent, fallback: LiveStudioAccent.blue));
    return Stack(fit: StackFit.expand, children: [
      CustomPaint(
        painter: EllipseGradientPainter(
            center: const Offset(0.5, 0.2), radii: const Offset(1.2, 0.9), colors: bg.colors, stops: bg.stops!),
      ),
      const FractionallySizedBox(
        alignment: Alignment.bottomCenter,
        heightFactor: 0.9,
        child: CustomPaint(painter: HostSilhouettePainter()),
      ),
      Positioned(
        left: 12,
        bottom: 12,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: LiveStudioWorld.tagPill,
            borderRadius: BorderRadius.all(Radius.circular(9999)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(m?.displayName ?? '',
                style: LiveStudioType.s(13, FontWeight.w600, LiveStudioWorld.textHigh, height: 18)),
          ),
        ),
      ),
    ]);
  }
}
