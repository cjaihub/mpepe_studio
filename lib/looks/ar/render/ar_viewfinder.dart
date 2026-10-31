import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/live_ar_controller.dart';
import '../tracking/ar_tracking_models.dart';
import 'ar_effect_painter.dart';

/// Wraps the camera preview with live AR: person segmentation (blur,
/// replace, "add yourself") behind tracked face/body effects.
///
/// [preview] must fill this widget exactly; tracking coordinates are
/// normalized to the same box.
class ArViewfinder extends ConsumerWidget {
  final Widget preview;

  const ArViewfinder({super.key, required this.preview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(liveArControllerProvider);
    if (!s.hasAnything) return preview;
    final ctrl = ref.read(liveArControllerProvider.notifier);

    return ValueListenableBuilder<ArFrame?>(
      valueListenable: ctrl.frame,
      builder: (context, frame, _) {
        return ValueListenableBuilder<Map<String, ArWorldPlacement>>(
          valueListenable: ctrl.world,
          builder: (context, world, _) {
            final overlay = CustomPaint(
              painter: ArEffectPainter(
                frame: frame,
                effects: s.effects,
                images: s.images,
                world: world,
              ),
              child: const SizedBox.expand(),
            );
            final mask = frame?.mask;
            final segmenting = s.backgroundMode != ArBackgroundMode.none && mask != null;

            Widget content;
            if (!segmenting) {
              content = Stack(fit: StackFit.expand, children: [preview, overlay]);
            } else {
              final background = s.backgroundMode == ArBackgroundMode.blur
                  ? ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: s.blurSigma, sigmaY: s.blurSigma),
                      child: preview,
                    )
                  : s.backgroundImage != null
                      ? RawImage(image: s.backgroundImage, fit: BoxFit.cover)
                      : preview;
              Widget person = Stack(
                fit: StackFit.expand,
                children: [
                  ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => ImageShader(
                      mask.image,
                      TileMode.clamp,
                      TileMode.clamp,
                      Matrix4.diagonal3Values(
                        rect.width / mask.width,
                        rect.height / mask.height,
                        1,
                      ).storage,
                      filterQuality: FilterQuality.medium,
                    ),
                    child: preview,
                  ),
                  overlay,
                ],
              );
              if (s.addYourself) {
                person = LayoutBuilder(
                  builder: (context, c) => Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..translateByDouble(
                        s.personOffset.dx * c.maxWidth,
                        s.personOffset.dy * c.maxHeight,
                        0,
                        1,
                      )
                      ..scaleByDouble(s.personScale, s.personScale, 1, 1),
                    child: person,
                  ),
                );
              }
              content = Stack(fit: StackFit.expand, children: [ClipRect(child: background), person]);
            }

            if (!ctrl.handlesGestures) return content;
            return _ArGestureLayer(onGesture: ctrl.onViewfinderGesture, child: content);
          },
        );
      },
    );
  }
}

/// Pan / pinch / twist in the viewfinder's own (unscaled) coordinates.
class _ArGestureLayer extends StatefulWidget {
  final void Function(Offset deltaNormalized, double scale, double rotation) onGesture;
  final Widget child;

  const _ArGestureLayer({required this.onGesture, required this.child});

  @override
  State<_ArGestureLayer> createState() => _ArGestureLayerState();
}

class _ArGestureLayerState extends State<_ArGestureLayer> {
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1;
  double _lastRotation = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (d) {
          _lastFocal = d.localFocalPoint;
          _lastScale = 1;
          _lastRotation = 0;
        },
        onScaleUpdate: (d) {
          final delta = d.localFocalPoint - _lastFocal;
          final ds = d.scale / _lastScale;
          final dr = d.rotation - _lastRotation;
          _lastFocal = d.localFocalPoint;
          _lastScale = d.scale;
          _lastRotation = d.rotation;
          widget.onGesture(Offset(delta.dx / c.maxWidth, delta.dy / c.maxHeight), ds, dr);
        },
        child: widget.child,
      ),
    );
  }
}
