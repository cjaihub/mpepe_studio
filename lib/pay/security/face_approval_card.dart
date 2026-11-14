import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';

import '../../shared/theme/app_theme.dart';

/// What the real check returned.
enum FaceGateOutcome { approved, failed, notRegistered, cancelled }

enum _Phase { starting, scanning, faceFound, verifying, success, failed, notRegistered, noCamera }

/// The approval card: the user's live face with an animated mesh whose colour
/// follows the real checks as they happen (scanning → face found → device
/// biometric + hardware signature + server check → success or fail).
///
/// Security comes from [onConfirm] (the hardware key and the server), not from
/// the camera picture: the mesh is the visible part of the check. The camera
/// is released before the system prompt opens so face unlock can use it.
class FaceApprovalCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<FaceGateOutcome> Function() onConfirm;
  final VoidCallback? onRegister;
  final ValueChanged<FaceGateOutcome>? onDone;

  const FaceApprovalCard({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.onConfirm,
    this.onRegister,
    this.onDone,
  });

  @override
  State<FaceApprovalCard> createState() => _FaceApprovalCardState();
}

class _FaceApprovalCardState extends State<FaceApprovalCard> with TickerProviderStateMixin {
  CameraController? _cam;
  FaceMeshDetector? _detector;
  bool _busy = false;
  bool _mirror = true;
  _Phase _phase = _Phase.starting;
  DateTime? _faceSince;
  final ValueNotifier<_MeshFrame?> _mesh = ValueNotifier(null);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  bool get _reduceMotion => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    unawaited(_stopCamera());
    _detector?.close();
    _pulse.dispose();
    _shake.dispose();
    _mesh.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (kIsWeb || !Platform.isAndroid) {
      _set(_Phase.noCamera);
      return;
    }
    try {
      final cams = await availableCameras();
      final front = cams.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull ?? cams.firstOrNull;
      if (front == null) return _set(_Phase.noCamera);
      _mirror = front.lensDirection == CameraLensDirection.front;
      final cam = CameraController(front, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      _detector ??= FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
      _cam = cam;
      await cam.startImageStream((img) => _onFrame(img, front));
      _set(_Phase.scanning);
    } catch (e) {
      debugPrint('[FaceApprovalCard] camera: $e');
      _set(_Phase.noCamera);
    }
  }

  Future<void> _stopCamera() async {
    final cam = _cam;
    _cam = null;
    if (cam == null) return;
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
    } catch (_) {}
    try {
      await cam.dispose();
    } catch (_) {}
  }

  void _set(_Phase p) {
    if (mounted && _phase != p) setState(() => _phase = p);
  }

  Future<void> _onFrame(CameraImage image, CameraDescription camera) async {
    if (_busy || _phase != _Phase.scanning && _phase != _Phase.faceFound) return;
    final detector = _detector;
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (detector == null || rotation == null || image.planes.length != 1) return;
    _busy = true;
    try {
      final plane = image.planes.first;
      final input = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final meshes = await detector.processImage(input);
      if (!mounted) return;
      final upright = rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());
      if (meshes.isEmpty) {
        _mesh.value = null;
        _faceSince = null;
        _set(_Phase.scanning);
        return;
      }
      _mesh.value = _MeshFrame.from(meshes.first, upright, _mirror);
      _faceSince ??= DateTime.now();
      if (_phase == _Phase.scanning) _set(_Phase.faceFound);
      // Hold still for a moment, then run the real check.
      if (DateTime.now().difference(_faceSince!) > const Duration(milliseconds: 700)) unawaited(_confirm());
    } catch (e) {
      debugPrint('[FaceApprovalCard] mesh: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _confirm() async {
    if (_phase == _Phase.verifying || _phase == _Phase.success) return;
    _set(_Phase.verifying);
    await _stopCamera();
    FaceGateOutcome out;
    try {
      out = await widget.onConfirm();
    } catch (e) {
      debugPrint('[FaceApprovalCard] confirm: $e');
      out = FaceGateOutcome.failed;
    }
    if (!mounted) return;
    switch (out) {
      case FaceGateOutcome.approved:
        _set(_Phase.success);
      case FaceGateOutcome.notRegistered:
        _set(_Phase.notRegistered);
      case FaceGateOutcome.failed:
      case FaceGateOutcome.cancelled:
        _set(_Phase.failed);
        if (!_reduceMotion) unawaited(_shake.forward(from: 0));
    }
    widget.onDone?.call(out);
  }

  Future<void> _retry() async {
    _faceSince = null;
    _mesh.value = null;
    _set(_Phase.starting);
    await _startCamera();
  }

  Color get _tone => switch (_phase) {
        _Phase.failed || _Phase.notRegistered => AppColors.brandPink,
        _ => AppColors.brandBlue,
      };

  String get _status => switch (_phase) {
        _Phase.starting => 'Starting camera…',
        _Phase.scanning => 'Look at the screen',
        _Phase.faceFound => 'Hold still',
        _Phase.verifying => 'Confirm with your fingerprint or face',
        _Phase.success => 'Verified',
        _Phase.failed => 'Not verified',
        _Phase.notRegistered => 'This phone isn’t registered yet',
        _Phase.noCamera => 'Confirm with your fingerprint or face',
      };

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final showPreview = cam != null && cam.value.isInitialized && (_phase == _Phase.scanning || _phase == _Phase.faceFound);
    return Semantics(
      liveRegion: true,
      label: '${widget.title}. $_status',
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) => Transform.translate(
          offset: Offset(math.sin(_shake.value * math.pi * 6) * 8 * (1 - _shake.value), 0),
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: context.surfaceMid),
                      if (showPreview)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: cam.value.previewSize!.height,
                            height: cam.value.previewSize!.width,
                            child: CameraPreview(cam),
                          ),
                        ),
                      // The mesh stays on screen (frozen) while the prompt and the server check run.
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: cam?.value.previewSize?.height ?? 480,
                          height: cam?.value.previewSize?.width ?? 640,
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_pulse, _mesh]),
                            builder: (context, _) => CustomPaint(
                              painter: _MeshPainter(
                                frame: _mesh.value,
                                color: _tone,
                                phase: _phase,
                                t: _reduceMotion ? 0.5 : _pulse.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_phase == _Phase.success || _phase == _Phase.failed || _phase == _Phase.notRegistered || _phase == _Phase.noCamera)
                        Center(
                          child: AnimatedScale(
                            scale: 1,
                            duration: const Duration(milliseconds: 220),
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(color: _tone.withValues(alpha: 0.92), shape: BoxShape.circle),
                              child: Icon(
                                switch (_phase) {
                                  _Phase.success => Icons.check_rounded,
                                  _Phase.noCamera => Icons.fingerprint_rounded,
                                  _Phase.notRegistered => Icons.phonelink_lock_rounded,
                                  _ => Icons.close_rounded,
                                },
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(widget.title, style: AppTypography.sectionTitle(context.textPrimary), textAlign: TextAlign.center),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                child: Text(
                  _status,
                  key: ValueKey(_phase),
                  style: AppTypography.small(_phase == _Phase.failed ? AppColors.brandPink : context.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(widget.subtitle, style: AppTypography.caption(context.textMuted), textAlign: TextAlign.center),
              ],
              if (_phase == _Phase.failed || _phase == _Phase.noCamera || _phase == _Phase.notRegistered) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    onPressed: switch (_phase) {
                      _Phase.notRegistered => widget.onRegister,
                      _Phase.noCamera => _confirm,
                      _ => _retry,
                    },
                    child: Text(switch (_phase) {
                      _Phase.notRegistered => 'Register this phone',
                      _Phase.noCamera => 'Confirm',
                      _ => 'Try again',
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Normalised (0–1) mesh points and triangle edges for one frame.
class _MeshFrame {
  final List<Offset> points;
  final List<(int, int, int)> triangles;
  const _MeshFrame(this.points, this.triangles);

  factory _MeshFrame.from(FaceMesh mesh, Size upright, bool mirror) {
    final byIndex = <int, Offset>{};
    for (final p in mesh.points) {
      final x = p.x / upright.width;
      byIndex[p.index] = Offset(mirror ? 1 - x : x, p.y / upright.height);
    }
    final maxIndex = byIndex.keys.fold<int>(0, math.max);
    final pts = List<Offset>.generate(maxIndex + 1, (i) => byIndex[i] ?? Offset.zero);
    final tris = <(int, int, int)>[
      for (final t in mesh.triangles)
        if (t.points.length == 3) (t.points[0].index, t.points[1].index, t.points[2].index),
    ];
    return _MeshFrame(pts, tris);
  }
}

class _MeshPainter extends CustomPainter {
  final _MeshFrame? frame;
  final Color color;
  final _Phase phase;
  final double t;
  _MeshPainter({required this.frame, required this.color, required this.phase, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    final settled = phase == _Phase.success || phase == _Phase.failed;
    if (f == null) {
      // No face yet: a soft scanning oval.
      final r = Rect.fromCenter(center: size.center(Offset.zero), width: size.width * 0.55, height: size.height * 0.6);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.006
        ..color = color.withValues(alpha: 0.35 + 0.35 * math.sin(t * math.pi * 2).abs());
      canvas.drawOval(r, ring);
      final sweepY = r.top + r.height * t;
      canvas.drawLine(Offset(r.left + r.width * 0.12, sweepY), Offset(r.right - r.width * 0.12, sweepY), ring..strokeWidth = size.width * 0.004);
      return;
    }
    Offset at(int i) => i < f.points.length ? Offset(f.points[i].dx * size.width, f.points[i].dy * size.height) : Offset.zero;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.0018
      ..color = color.withValues(alpha: settled ? 0.85 : 0.55);
    final path = Path();
    for (final (a, b, c) in f.triangles) {
      final pa = at(a), pb = at(b), pc = at(c);
      path
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy)
        ..lineTo(pc.dx, pc.dy)
        ..close();
    }
    if (phase == _Phase.success) {
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    }
    canvas.drawPath(path, edge);
    // A travelling highlight while verifying or scanning.
    if (!settled) {
      final dot = Paint()..color = color.withValues(alpha: 0.9);
      final n = f.points.length;
      if (n > 0) {
        final head = (t * n).floor();
        for (var k = 0; k < 24; k++) {
          final i = (head + k * (n ~/ 24)) % n;
          canvas.drawCircle(at(i), size.width * 0.004, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.frame != frame || old.color != color || old.phase != phase || old.t != t;
}
