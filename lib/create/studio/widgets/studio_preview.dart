import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_color.dart';
import '../services/studio_effects.dart';
import '../services/studio_faces.dart';
import '../services/studio_looks.dart';
import '../services/studio_playback.dart';
import '../services/studio_stabilizer.dart';
import '../services/studio_text_painter.dart';
import 'studio_text_widgets.dart';

/// The project canvas at the playhead: current clip (cropped, rotated,
/// flipped, color graded, fit/fill, zoom) and the text layers on screen.
class StudioPreview extends StatelessWidget {
  final StudioPlayback playback;
  final StudioProject project;
  final String? selectedTextId;
  final ValueChanged<String?> onSelectText;
  final void Function(StudioText text, double x, double y) onMoveText;
  final ValueChanged<StudioText> onEditText;

  /// Picture-in-picture layer selection and moves.
  final String? selectedOverlayId;
  final ValueChanged<String?>? onSelectOverlay;
  final void Function(StudioOverlay overlay, double x, double y, double scale, double rotation)? onMoveOverlay;

  /// Pinch on a layer: new size and rotation.
  final void Function(StudioText text, double size, double rotation)? onTransformText;

  /// Show every text layer regardless of time (photo projects).
  final bool showAllText;

  const StudioPreview({
    super.key,
    required this.playback,
    required this.project,
    required this.selectedTextId,
    required this.onSelectText,
    required this.onMoveText,
    required this.onEditText,
    this.onTransformText,
    this.selectedOverlayId,
    this.onSelectOverlay,
    this.onMoveOverlay,
    this.showAllText = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final aspect = project.canvasAspect;
      var w = box.maxWidth;
      var h = w / aspect;
      if (h > box.maxHeight) {
        h = box.maxHeight;
        w = h * aspect;
      }
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRect(
            child: ListenableBuilder(
              listenable: playback,
              builder: (context, _) {
                final idx = playback.activeIndex;
                final pos = playback.posMs;
                final texts = project.texts.where((t) => showAllText || (pos >= t.startMs && pos < t.endMs));
                Widget frame = Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppColors.brandBlack),
                    if (idx >= 0)
                      StudioClipView(
                        clip: project.clips[idx],
                        controller: playback.controllerFor(project.clips[idx]),
                        localMs: pos - project.clipStartMs(idx),
                      ),
                  ],
                );
                if (project.effects.isNotEmpty) {
                  frame = StudioFxFilter(effects: project.effects, posMs: showAllText ? 0 : pos, child: frame);
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelectText(null),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      frame,
                      for (final o in project.overlays)
                        if (showAllText || (pos >= o.offsetMs && pos < o.endOnTimeline))
                          _DraggableOverlay(
                            key: ValueKey('ov_${o.id}'),
                            overlay: o,
                            canvas: Size(w, h),
                            controller: playback.overlayController(o),
                            selected: o.id == selectedOverlayId,
                            onTap: () => onSelectOverlay?.call(o.id),
                            onChange: (x, y, sc, rot) => onMoveOverlay?.call(o, x, y, sc, rot),
                          ),
                      for (final t in texts)
                        _DraggableText(
                          key: ValueKey(t.id),
                          text: showAllText ? t.copyWith(anim: const StudioTextAnim()) : t,
                          canvas: Size(w, h),
                          ms: showAllText ? t.startMs : pos,
                          selected: t.id == selectedTextId,
                          onTap: () => t.id == selectedTextId ? onEditText(t) : onSelectText(t.id),
                          onMove: (x, y) => onMoveText(t, x, y),
                          onTransform: onTransformText == null ? null : (size, rot) => onTransformText!(t, size, rot),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

/// One clip framed the way the exporter frames it.
class StudioClipView extends StatelessWidget {
  final StudioClip clip;
  final VideoPlayerController? controller;

  /// Ignore crop (used under the crop editor).
  final bool uncropped;

  /// Playhead inside the clip (output ms), for face-tracked retouch.
  final int localMs;

  const StudioClipView({super.key, required this.clip, this.controller, this.uncropped = false, this.localMs = 0});

  @override
  Widget build(BuildContext context) {
    final sw = clip.sourceWidth > 0 ? clip.sourceWidth.toDouble() : 1080.0;
    final sh = clip.sourceHeight > 0 ? clip.sourceHeight.toDouble() : 1920.0;
    Widget media;
    if (clip.isImage) {
      media = Image.file(File(clip.path), fit: BoxFit.fill, gaplessPlayback: true, cacheWidth: 1440);
    } else if (controller != null && controller!.value.isInitialized) {
      media = VideoPlayer(controller!);
    } else {
      media = const ColoredBox(color: AppColors.brandBlack);
    }
    media = SizedBox(width: sw, height: sh, child: media);
    // Stabilize: same zoom and per-frame shift as the export.
    final plan = uncropped ? null : StudioStabilizer.plan(clip);
    if (plan != null) {
      final (dx, dy) = plan.at(localMs);
      media = ClipRect(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(dx * plan.zoom * sw, dy * plan.zoom * sh, 0, 1)
            ..scaleByDouble(plan.zoom, plan.zoom, 1, 1),
          child: media,
        ),
      );
    }

    final crop = uncropped ? const StudioCrop() : clip.crop;
    final cw = sw * (crop.r - crop.l);
    final ch = sh * (crop.b - crop.t);
    Widget framed = SizedBox(
      width: cw,
      height: ch,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sw,
          maxWidth: sw,
          minHeight: sh,
          maxHeight: sh,
          child: Transform.translate(offset: Offset(-crop.l * sw, -crop.t * sh), child: media),
        ),
      ),
    );
    if (clip.flipH || clip.flipV) {
      framed = Transform.scale(scaleX: clip.flipH ? -1 : 1, scaleY: clip.flipV ? -1 : 1, child: framed);
    }
    if (clip.rotation % 360 != 0) framed = RotatedBox(quarterTurns: (clip.rotation ~/ 90) % 4, child: framed);
    // Same order as the export: retouch, color matrix, then the Look engine.
    if (!clip.retouch.isIdentity && !uncropped) framed = StudioRetouchFilter(clip: clip, localMs: localMs, child: framed);
    final matrix = StudioColor.clipMatrix(clip);
    if (!StudioColor.isIdentity(matrix)) framed = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: framed);
    // Same order as the export: color matrix, then the Look engine.
    final look = StudioLooks.forClip(clip);
    if (look != null) framed = StudioLookFilter(look: look, child: framed);

    Widget fitted = SizedBox.expand(
      child: FittedBox(fit: clip.fill ? BoxFit.cover : BoxFit.contain, clipBehavior: Clip.hardEdge, child: framed),
    );
    if (clip.zoom > 1.001) fitted = ClipRect(child: Transform.scale(scale: clip.zoom, child: fitted));
    return fitted;
  }
}

class _DraggableText extends StatefulWidget {
  final StudioText text;
  final Size canvas;
  final int ms;
  final bool selected;
  final VoidCallback onTap;
  final void Function(double x, double y) onMove;
  final void Function(double size, double rotation)? onTransform;

  const _DraggableText({
    super.key,
    required this.text,
    required this.canvas,
    required this.ms,
    required this.selected,
    required this.onTap,
    required this.onMove,
    this.onTransform,
  });

  @override
  State<_DraggableText> createState() => _DraggableTextState();
}

class _DraggableTextState extends State<_DraggableText> {
  Offset? _drag;
  double? _size;
  double? _rotation;
  double _startSize = 0;
  double _startRotation = 0;

  @override
  Widget build(BuildContext context) {
    var t = widget.text;
    if (_size != null || _rotation != null) t = t.copyWith(size: _size, rotation: _rotation);
    final c = widget.canvas;
    final size = StudioTextPainter.measure(t, c.width);
    final center = _drag ?? Offset((t.x + 1) / 2 * c.width, (t.y + 1) / 2 * c.height);
    // Same clamp as the exporter: the whole layer stays on the frame.
    final double left = (center.dx - size.width / 2).clamp(0.0, math.max(0.0, c.width - size.width)).toDouble();
    final double top = (center.dy - size.height / 2).clamp(0.0, math.max(0.0, c.height - size.height)).toDouble();
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: widget.onTap,
        onScaleStart: (_) {
          _startSize = widget.text.size;
          _startRotation = widget.text.rotation;
          setState(() => _drag = center);
        },
        onScaleUpdate: (d) => setState(() {
          _drag = (_drag ?? center) + d.focalPointDelta;
          if (d.pointerCount > 1 && widget.onTransform != null) {
            _size = (_startSize * d.scale).clamp(0.02, widget.text.isSticker ? 0.5 : 0.3);
            _rotation = _startRotation + d.rotation * 180 / math.pi;
          }
        }),
        onScaleEnd: (_) {
          final p = _drag!;
          final size = _size;
          final rotation = _rotation;
          setState(() {
            _drag = null;
            _size = null;
            _rotation = null;
          });
          widget.onMove(
            (p.dx / c.width * 2 - 1).clamp(-1.0, 1.0),
            (p.dy / c.height * 2 - 1).clamp(-1.0, 1.0),
          );
          if (size != null || rotation != null) {
            widget.onTransform?.call(size ?? widget.text.size, ((rotation ?? widget.text.rotation) * 10).roundToDouble() / 10);
          }
        },
        child: StudioAnimatedTextLayer(text: t, canvas: c, ms: widget.ms, selected: widget.selected),
      ),
    );
  }
}


/// A picture-in-picture layer: drag to move, pinch to resize and rotate.
class _DraggableOverlay extends StatefulWidget {
  final StudioOverlay overlay;
  final Size canvas;
  final VideoPlayerController? controller;
  final bool selected;
  final VoidCallback onTap;
  final void Function(double x, double y, double scale, double rotation) onChange;

  const _DraggableOverlay({
    super.key,
    required this.overlay,
    required this.canvas,
    required this.controller,
    required this.selected,
    required this.onTap,
    required this.onChange,
  });

  @override
  State<_DraggableOverlay> createState() => _DraggableOverlayState();
}

class _DraggableOverlayState extends State<_DraggableOverlay> {
  Offset? _center;
  double? _scale;
  double? _rotation;
  double _startScale = 0;
  double _startRotation = 0;

  @override
  Widget build(BuildContext context) {
    final o = widget.overlay;
    final c = widget.canvas;
    final scale = _scale ?? o.scale;
    final rotation = _rotation ?? o.rotation;
    final w = scale * c.width;
    final h = w / o.aspect;
    final center = _center ?? Offset((o.x + 1) / 2 * c.width, (o.y + 1) / 2 * c.height);
    Widget media;
    if (o.isImage) {
      media = Image.file(File(o.path), fit: BoxFit.fill, cacheWidth: 1080, gaplessPlayback: true);
    } else if (widget.controller != null && widget.controller!.value.isInitialized) {
      media = VideoPlayer(widget.controller!);
    } else {
      media = const ColoredBox(color: AppColors.brandBlack);
    }
    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - h / 2,
      width: w,
      height: h,
      child: GestureDetector(
        onTap: widget.onTap,
        onScaleStart: (_) {
          _startScale = o.scale;
          _startRotation = o.rotation;
          setState(() => _center = center);
        },
        onScaleUpdate: (d) => setState(() {
          _center = (_center ?? center) + d.focalPointDelta;
          if (d.pointerCount > 1) {
            _scale = (_startScale * d.scale).clamp(0.08, 1.5);
            _rotation = _startRotation + d.rotation * 180 / math.pi;
          }
        }),
        onScaleEnd: (_) {
          final p = _center ?? center;
          final sc = _scale ?? o.scale;
          final rot = _rotation ?? o.rotation;
          setState(() {
            _center = null;
            _scale = null;
            _rotation = null;
          });
          widget.onChange(
            (p.dx / c.width * 2 - 1).clamp(-1.5, 1.5),
            (p.dy / c.height * 2 - 1).clamp(-1.5, 1.5),
            sc,
            (rot * 10).roundToDouble() / 10,
          );
        },
        child: Transform.rotate(
          angle: rotation * math.pi / 180,
          child: Opacity(
            opacity: o.opacity.clamp(0.0, 1.0),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: widget.selected ? Border.all(color: AppColors.brandWhite.withValues(alpha: 0.9), width: 1) : null,
              ),
              child: media,
            ),
          ),
        ),
      ),
    );
  }
}
