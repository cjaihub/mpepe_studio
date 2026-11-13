import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
    if (!s.hasAnything && !s.autoTrack) return preview;
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
                perPerson: s.effectPerPerson,
              ),
              child: const SizedBox.expand(),
            );
            // Skin smoothing: a lightly blurred copy of the preview, clipped
            // to the skin (face oval minus eyes and lips), over the camera.
            final smoothing = ctrl.activeMakeup?.smoothing ?? 0;
            final faces = frame?.faces ?? const <TrackedFace>[];
            final skin = smoothing > 0 && faces.isNotEmpty
                ? LayoutBuilder(
                    builder: (context, c) {
                      final sigma = c.maxWidth / 360 * 1.6;
                      return ClipPath(
                        clipper: _SkinClipper(faces),
                        child: Opacity(
                          opacity: (smoothing * 0.8).clamp(0.0, 1.0),
                          child: ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                            child: preview,
                          ),
                        ),
                      );
                    },
                  )
                : null;
            final mask = frame?.mask;
            final segmenting = s.backgroundMode != ArBackgroundMode.none && mask != null;
            // Outfit colour: recolour clothes on the camera image itself.
            final camera = s.outfitOn && mask != null
                ? OutfitFilter(color: s.outfitColor!, strength: s.outfitStrength, mask: mask.image, neckY: neckLine(frame), child: preview)
                : preview;

            Widget content;
            if (!segmenting) {
              content = Stack(fit: StackFit.expand, children: [camera, ?skin, overlay]);
            } else {
              final background = s.backgroundMode == ArBackgroundMode.blur
                  ? ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: s.blurSigma, sigmaY: s.blurSigma),
                      child: preview,
                    )
                  : s.backgroundVideoPath != null
                      ? LoopingBackgroundVideo(path: s.backgroundVideoPath!)
                      : s.backgroundImage != null
                          ? RawImage(image: s.backgroundImage, fit: BoxFit.cover)
                          : preview;
              Widget person = Stack(
                fit: StackFit.expand,
                children: [
                  PersonMatte(
                    mask: mask,
                    fallback: ShaderMask(
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
                      child: camera,
                    ),
                    child: camera,
                  ),
                  ?skin,
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

            if (s.autoTrack) {
              content = _SmartAutoTrackLayer(frame: frame, child: content);
            }

            if (!ctrl.handlesGestures) return content;
            return _ArGestureLayer(onGesture: ctrl.onViewfinderGesture, child: content);
          },
        );
      },
    );
  }
}

/// Smoothly centers and frames the primary human subject (face + upper body)
/// and draws a subtle tracking lock bracket when Smart Auto-Track is active.
class _SmartAutoTrackLayer extends StatefulWidget {
  final ArFrame? frame;
  final Widget child;

  const _SmartAutoTrackLayer({required this.frame, required this.child});

  @override
  State<_SmartAutoTrackLayer> createState() => _SmartAutoTrackLayerState();
}

class _SmartAutoTrackLayerState extends State<_SmartAutoTrackLayer> {
  Offset _smoothedCenter = const Offset(0.5, 0.45);
  double _smoothedScale = 1.0;

  @override
  void didUpdateWidget(covariant _SmartAutoTrackLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final subject = widget.frame?.subjectCenter;
    final width = widget.frame?.subjectWidth;
    if (subject != null) {
      // Smooth low-pass filter so framing feels like a motorized gimbal.
      _smoothedCenter = Offset.lerp(_smoothedCenter, subject, 0.14)!;
      final desiredScale = width != null ? (0.30 / width.clamp(0.12, 0.45)).clamp(1.06, 1.26) : 1.14;
      _smoothedScale = _smoothedScale + (desiredScale - _smoothedScale) * 0.10;
    } else {
      _smoothedCenter = Offset.lerp(_smoothedCenter, const Offset(0.5, 0.45), 0.08)!;
      _smoothedScale = _smoothedScale + (1.0 - _smoothedScale) * 0.08;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = _smoothedScale;
    final maxShift = (scale - 1.0) / (2.0 * scale);
    final dxNorm = (0.5 - _smoothedCenter.dx).clamp(-maxShift, maxShift);
    final dyNorm = (0.44 - _smoothedCenter.dy).clamp(-maxShift, maxShift);
    final hasSubject = widget.frame?.subjectCenter != null;

    return LayoutBuilder(
      builder: (context, c) {
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scaleByDouble(scale, scale, 1, 1)
                  ..translateByDouble(dxNorm * c.maxWidth, dyNorm * c.maxHeight, 0, 1),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.child,
                    if (hasSubject)
                      CustomPaint(
                        painter: _SubjectBracketPainter(
                          center: _smoothedCenter,
                          span: (widget.frame?.subjectWidth ?? 0.24).clamp(0.16, 0.55),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SubjectBracketPainter extends CustomPainter {
  final Offset center;
  final double span;

  const _SubjectBracketPainter({required this.center, required this.span});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = center.dx * size.width;
    final cy = center.dy * size.height;
    final w = span * size.width * 1.35;
    final h = w * 1.18;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    final corner = math.min(w, h) * 0.18;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF0C4FA8).withValues(alpha: 0.85);

    final corners = Path()
      // Top-left
      ..moveTo(rect.left, rect.top + corner)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + corner, rect.top)
      // Top-right
      ..moveTo(rect.right - corner, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + corner)
      // Bottom-left
      ..moveTo(rect.left, rect.bottom - corner)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left + corner, rect.bottom)
      // Bottom-right
      ..moveTo(rect.right - corner, rect.bottom)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right, rect.bottom - corner);

    canvas.drawPath(corners, p);
    canvas.drawCircle(
      Offset(cx, rect.top - 6),
      3.0,
      Paint()..color = const Color(0xFFFF2D87),
    );
  }

  @override
  bool shouldRepaint(covariant _SubjectBracketPainter old) =>
      old.center != center || old.span != span;
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

/// Clips to the tracked faces' skin areas.
class _SkinClipper extends CustomClipper<Path> {
  final List<TrackedFace> faces;

  _SkinClipper(this.faces);

  @override
  Path getClip(Size size) {
    final out = Path()..fillType = PathFillType.evenOdd;
    for (final f in faces) {
      final p = ArEffectPainter.skinPath(f, size);
      if (p != null) out.addPath(p, Offset.zero);
    }
    return out;
  }

  @override
  bool shouldReclip(_SkinClipper old) => old.faces != faces;
}


/// Where clothes start (normalized y): just above the shoulders, else under
/// the chin, else a third of the way down.
double neckLine(ArFrame? frame) {
  final body = frame?.body;
  if (body != null) return math.min(body.leftShoulder.dy, body.rightShoulder.dy) - 0.03;
  final faces = frame?.faces ?? const <TrackedFace>[];
  if (faces.isNotEmpty) return faces.first.chin.dy + 0.04;
  return 0.38;
}

/// Recolours clothes over [child] with `shaders/outfit_recolor.frag`.
class OutfitFilter extends StatefulWidget {
  final Color color;
  final double strength;
  final ui.Image mask;
  final double neckY;
  final Widget child;

  const OutfitFilter({super.key, required this.color, required this.strength, required this.mask, required this.neckY, required this.child});

  @override
  State<OutfitFilter> createState() => _OutfitFilterState();
}

class _OutfitFilterState extends State<OutfitFilter> {
  static Future<ui.FragmentProgram?>? _program;
  ui.FragmentProgram? _p;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    (_program ??= ui.FragmentProgram.fromAsset('shaders/outfit_recolor.frag').then<ui.FragmentProgram?>((p) => p, onError: (Object e) {
      debugPrint('[Outfit] shader failed: $e');
      _program = null;
      return null;
    }))
        .then((p) {
      if (!mounted || p == null) return;
      setState(() {
        _p = p;
        _shader = p.fragmentShader();
      });
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sh = _shader;
    if (_p == null || sh == null) return widget.child;
    sh
      ..setFloat(2, widget.color.r)
      ..setFloat(3, widget.color.g)
      ..setFloat(4, widget.color.b)
      ..setFloat(5, widget.strength.clamp(0.0, 1.0))
      ..setFloat(6, widget.neckY.clamp(0.0, 1.0))
      ..setImageSampler(1, widget.mask);
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(sh), child: widget.child);
  }
}


/// The person cut out of [child] with an edge-aware matte
/// (`shaders/person_matte.frag`); [fallback] (plain mask) until the shader
/// is ready or where shader filters are unsupported.
class PersonMatte extends StatefulWidget {
  final PersonMask mask;
  final Widget child;
  final Widget fallback;
  const PersonMatte({super.key, required this.mask, required this.child, required this.fallback});

  @override
  State<PersonMatte> createState() => _PersonMatteState();
}

class _PersonMatteState extends State<PersonMatte> {
  static Future<ui.FragmentProgram?>? _program;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    (_program ??= ui.FragmentProgram.fromAsset('shaders/person_matte.frag').then<ui.FragmentProgram?>((p) => p, onError: (Object e) {
      debugPrint('[PersonMatte] shader failed: $e');
      _program = null;
      return null;
    }))
        .then((p) {
      if (mounted && p != null) setState(() => _shader = p.fragmentShader());
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sh = _shader;
    if (sh == null) return widget.fallback;
    sh
      ..setFloat(2, 1 / widget.mask.width)
      ..setFloat(3, 1 / widget.mask.height)
      ..setImageSampler(1, widget.mask.image);
    return ImageFiltered(imageFilter: ui.ImageFilter.shader(sh), child: widget.child);
  }
}


/// A muted, looping video filling the viewfinder (video background).
class LoopingBackgroundVideo extends StatefulWidget {
  final String path;
  const LoopingBackgroundVideo({super.key, required this.path});

  @override
  State<LoopingBackgroundVideo> createState() => _LoopingBackgroundVideoState();
}

class _LoopingBackgroundVideoState extends State<LoopingBackgroundVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(LoopingBackgroundVideo old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _open();
  }

  Future<void> _open() async {
    await _player.setVolume(0);
    await _player.setPlaylistMode(PlaylistMode.single);
    await _player.open(Media(widget.path));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Video(controller: _controller, fit: BoxFit.cover, controls: NoVideoControls, fill: Colors.black);
}
