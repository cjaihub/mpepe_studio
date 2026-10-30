import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_color.dart';
import '../services/studio_playback.dart';
import '../services/studio_text_painter.dart';

/// The project canvas at the playhead: current clip (cropped, rotated,
/// flipped, color graded, fit/fill, zoom) and the text layers on screen.
class StudioPreview extends StatelessWidget {
  final StudioPlayback playback;
  final StudioProject project;
  final String? selectedTextId;
  final ValueChanged<String?> onSelectText;
  final void Function(StudioText text, double x, double y) onMoveText;
  final ValueChanged<StudioText> onEditText;

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
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelectText(null),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: AppColors.brandBlack),
                      if (idx >= 0) StudioClipView(clip: project.clips[idx], controller: playback.controllerFor(project.clips[idx])),
                      for (final t in texts)
                        _DraggableText(
                          key: ValueKey(t.id),
                          text: t,
                          canvas: Size(w, h),
                          selected: t.id == selectedTextId,
                          onTap: () => t.id == selectedTextId ? onEditText(t) : onSelectText(t.id),
                          onMove: (x, y) => onMoveText(t, x, y),
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

  const StudioClipView({super.key, required this.clip, this.controller, this.uncropped = false});

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
    final matrix = StudioColor.clipMatrix(clip);
    if (!StudioColor.isIdentity(matrix)) framed = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: framed);

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
  final bool selected;
  final VoidCallback onTap;
  final void Function(double x, double y) onMove;

  const _DraggableText({
    super.key,
    required this.text,
    required this.canvas,
    required this.selected,
    required this.onTap,
    required this.onMove,
  });

  @override
  State<_DraggableText> createState() => _DraggableTextState();
}

class _DraggableTextState extends State<_DraggableText> {
  Offset? _drag;

  @override
  Widget build(BuildContext context) {
    final t = widget.text;
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
        onPanStart: (_) => setState(() => _drag = center),
        onPanUpdate: (d) => setState(() => _drag = (_drag ?? center) + d.delta),
        onPanEnd: (_) {
          final p = _drag!;
          setState(() => _drag = null);
          widget.onMove(
            (p.dx / c.width * 2 - 1).clamp(-1.0, 1.0),
            (p.dy / c.height * 2 - 1).clamp(-1.0, 1.0),
          );
        },
        child: StudioTextLayer(text: t, canvasWidth: c.width, selected: widget.selected),
      ),
    );
  }
}
