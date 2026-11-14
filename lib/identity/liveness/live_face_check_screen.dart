import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../shared/theme/app_theme.dart';

/// What the live check produced: a straight selfie, two turned-head frames
/// (proof of a real 3D face for the AI and the reviewer) and the actions done.
class LivenessResult {
  final File selfie;
  final File? left;
  final File? right;
  final List<String> actions;
  final int ms;
  const LivenessResult({required this.selfie, this.left, this.right, required this.actions, required this.ms});

  Map<String, Object> toMap({bool biometric = false}) => {'passed': true, 'actions': actions, 'ms': ms, 'biometric': biometric};
}

enum _Step { turnA, turnB, blink, smile, straight }

/// Live face check for identity verification: front camera, a live mesh over
/// the face, a guide that reacts to what it sees (no face, two faces, too far,
/// too close, off centre, too dark, eyes closed), then random actions (turn one
/// way, the other way, blink or smile) and a straight selfie.
///
/// It proves a live person is there; the selfie and turned frames then go to
/// the AI pre-check and a human reviewer. Pops a [LivenessResult] or null.
class LiveFaceCheckScreen extends StatefulWidget {
  const LiveFaceCheckScreen({super.key});

  static Future<LivenessResult?> open(BuildContext context) =>
      Navigator.of(context).push<LivenessResult>(MaterialPageRoute(builder: (_) => const LiveFaceCheckScreen()));

  @override
  State<LiveFaceCheckScreen> createState() => _LiveFaceCheckScreenState();
}

class _LiveFaceCheckScreenState extends State<LiveFaceCheckScreen> with SingleTickerProviderStateMixin {
  CameraController? _cam;
  CameraDescription? _desc;
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(enableContours: true, enableClassification: true, performanceMode: FaceDetectorMode.fast),
  );
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  bool _busy = false;
  bool _capturing = false;
  String? _error;
  String _guide = 'Starting camera…';
  bool _guideOk = false;
  List<_Step> _steps = const [];
  int _index = 0;
  DateTime? _stepStarted;
  final Stopwatch _clock = Stopwatch();
  double? _firstTurnSign;
  bool _eyesWereOpen = false;
  DateTime? _straightSince;
  File? _left, _right;
  bool _done = false;
  bool _failed = false;

  // Mesh (normalised 0–1, upright, mirrored like a mirror).
  List<List<Offset>> _contours = const [];

  static const Duration _stepTimeout = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _newSequence();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_stop());
    _detector.close();
    _pulse.dispose();
    super.dispose();
  }

  void _newSequence() {
    final r = math.Random();
    final extra = r.nextBool() ? _Step.blink : _Step.smile;
    final order = [_Step.turnA, _Step.turnB, extra]..shuffle(r);
    // Both turns stay in order (one side, then the other) for the 3D frames.
    final turnsFirst = order.indexOf(_Step.turnA) > order.indexOf(_Step.turnB);
    if (turnsFirst) {
      final a = order.indexOf(_Step.turnA), b = order.indexOf(_Step.turnB);
      order[a] = _Step.turnB;
      order[b] = _Step.turnA;
    }
    _steps = [...order, _Step.straight];
    _index = 0;
    _firstTurnSign = null;
    _eyesWereOpen = false;
    _straightSince = null;
    _left = null;
    _right = null;
    _done = false;
    _failed = false;
    _stepStarted = null;
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      final front = cams.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull ?? cams.firstOrNull;
      if (front == null) throw StateError('no camera');
      _desc = front;
      final cam = CameraController(front, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888);
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _cam = cam);
      _clock
        ..reset()
        ..start();
      await cam.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('[LiveFaceCheck] $e');
      if (mounted) setState(() => _error = 'We couldn’t open the front camera. Allow camera access and try again.');
    }
  }

  Future<void> _stop() async {
    final cam = _cam;
    _cam = null;
    if (cam == null) return;
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
    } catch (_) {}
    await cam.dispose();
  }

  InputImage? _input(CameraImage image) {
    final rotation = InputImageRotationValue.fromRawValue(_desc!.sensorOrientation);
    if (rotation == null || image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Average light from a sample of the frame (0–255).
  double _brightness(CameraImage image) {
    final b = image.planes.first.bytes;
    if (b.isEmpty) return 128;
    final step = Platform.isAndroid ? 97 : 389; // NV21: luma first; BGRA: green channel
    var sum = 0, n = 0;
    final limit = Platform.isAndroid ? image.width * image.height : b.length;
    for (var i = Platform.isAndroid ? 0 : 1; i < limit && i < b.length; i += step) {
      sum += b[i];
      n++;
    }
    return n == 0 ? 128 : sum / n;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _capturing || _done || _failed || !mounted) return;
    final input = _input(image);
    if (input == null) return;
    _busy = true;
    try {
      final faces = await _detector.processImage(input);
      if (!mounted) return;
      final rotated = _desc!.sensorOrientation == 90 || _desc!.sensorOrientation == 270;
      final w = (rotated ? image.height : image.width).toDouble();
      final h = (rotated ? image.width : image.height).toDouble();
      _evaluate(faces, w, h, _brightness(image));
    } catch (e) {
      debugPrint('[LiveFaceCheck] frame: $e');
    } finally {
      _busy = false;
    }
  }

  void _evaluate(List<Face> faces, double w, double h, double light) {
    // ── Content awareness: is the picture good enough to check? ──
    String? problem;
    if (light < 55) {
      problem = 'Find more light';
    } else if (faces.isEmpty) {
      problem = 'Put your face in the oval';
    } else if (faces.length > 1) {
      problem = 'Only you in the frame, please';
    }
    Face? f = faces.isEmpty ? null : faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
    if (problem == null && f != null) {
      final size = f.boundingBox.width / w;
      final cx = f.boundingBox.center.dx / w, cy = f.boundingBox.center.dy / h;
      if (size < 0.32) {
        problem = 'Move a little closer';
      } else if (size > 0.85) {
        problem = 'Move back a little';
      } else if ((cx - 0.5).abs() > 0.18 || (cy - 0.45).abs() > 0.22) {
        problem = 'Center your face in the oval';
      }
    }
    _contours = f == null
        ? const []
        : [
            for (final c in f.contours.values)
              if (c != null)
                [for (final p in c.points) Offset(1 - p.x / w, p.y / h)],
          ];

    final step = _steps[_index];
    _stepStarted ??= DateTime.now();
    if (DateTime.now().difference(_stepStarted!) > _stepTimeout) {
      _fail('Took too long. Let’s try again.');
      return;
    }
    if (problem != null || f == null) {
      _setGuide(problem ?? 'Put your face in the oval', ok: false);
      if (step == _Step.straight) _straightSince = null;
      return;
    }

    // ── The live actions ──
    final yaw = f.headEulerAngleY ?? 0;
    final eyes = math.min(f.leftEyeOpenProbability ?? 1, f.rightEyeOpenProbability ?? 1);
    switch (step) {
      case _Step.turnA:
        _setGuide('Slowly turn your head to one side', ok: true);
        if (yaw.abs() > 24) {
          _firstTurnSign = yaw.sign;
          unawaited(_captureTurn(first: true));
        }
      case _Step.turnB:
        _setGuide('Now turn to the other side', ok: true);
        if (yaw.abs() > 24 && yaw.sign != (_firstTurnSign ?? yaw.sign)) unawaited(_captureTurn(first: false));
      case _Step.blink:
        _setGuide('Blink slowly', ok: true);
        if (eyes > 0.6) _eyesWereOpen = true;
        if (_eyesWereOpen && eyes < 0.2) _next();
      case _Step.smile:
        _setGuide('Give a big smile', ok: true);
        if ((f.smilingProbability ?? 0) > 0.75) _next();
      case _Step.straight:
        if (yaw.abs() > 8) {
          _setGuide('Look straight at the camera', ok: true);
          _straightSince = null;
        } else if (eyes < 0.4) {
          _setGuide('Keep your eyes open', ok: false);
          _straightSince = null;
        } else {
          _setGuide('Hold still…', ok: true);
          _straightSince ??= DateTime.now();
          if (DateTime.now().difference(_straightSince!) > const Duration(milliseconds: 700)) unawaited(_finish());
        }
    }
    if (mounted) setState(() {});
  }

  void _setGuide(String g, {required bool ok}) {
    if (g == _guide && ok == _guideOk) return;
    _guide = g;
    _guideOk = ok;
    if (mounted) setState(() {});
  }

  void _next() {
    HapticFeedback.selectionClick();
    _index++;
    _stepStarted = null;
    if (mounted) setState(() {});
  }

  Future<File?> _snap() async {
    final cam = _cam;
    if (cam == null) return null;
    _capturing = true;
    try {
      await cam.stopImageStream();
      final x = await cam.takePicture();
      await cam.startImageStream(_onFrame);
      return File(x.path);
    } catch (e) {
      debugPrint('[LiveFaceCheck] snap: $e');
      return null;
    } finally {
      _capturing = false;
    }
  }

  Future<void> _captureTurn({required bool first}) async {
    final f = await _snap();
    if (!mounted) return;
    if (first) {
      _left = f;
    } else {
      _right = f;
    }
    _next();
  }

  Future<void> _finish() async {
    if (_done) return;
    _done = true;
    HapticFeedback.mediumImpact();
    _setGuide('Done', ok: true);
    final cam = _cam;
    File? selfie;
    try {
      if (cam != null && cam.value.isStreamingImages) await cam.stopImageStream();
      final x = await cam?.takePicture();
      if (x != null) selfie = File(x.path);
    } catch (e) {
      debugPrint('[LiveFaceCheck] selfie: $e');
    }
    _clock.stop();
    if (!mounted) return;
    if (selfie == null) {
      _done = false;
      _fail('We couldn’t take the photo. Try again.');
      return;
    }
    final actions = [
      for (final s in _steps)
        switch (s) {
          _Step.turnA => 'turn_one_side',
          _Step.turnB => 'turn_other_side',
          _Step.blink => 'blink',
          _Step.smile => 'smile',
          _Step.straight => 'look_straight',
        },
    ];
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (mounted) {
      Navigator.of(context).pop(LivenessResult(selfie: selfie, left: _left, right: _right, actions: actions, ms: _clock.elapsedMilliseconds));
    }
  }

  void _fail(String why) {
    HapticFeedback.heavyImpact();
    _failed = true;
    _guide = why;
    _guideOk = false;
    if (mounted) setState(() {});
  }

  Future<void> _retry() async {
    setState(_newSequence);
    _clock
      ..reset()
      ..start();
    final cam = _cam;
    if (cam != null && !cam.value.isStreamingImages) await cam.startImageStream(_onFrame);
  }

  Color get _tone => _failed ? AppColors.brandPink : (_guideOk ? AppColors.brandBlue : AppColors.brandWhite.withValues(alpha: 0.75));

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final total = _steps.length;
    return Scaffold(
      backgroundColor: AppColors.brandBlack,
      appBar: AppBar(
        backgroundColor: AppColors.brandBlack,
        foregroundColor: AppColors.brandWhite,
        toolbarHeight: 50,
        title: const Text('Live face check'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center, style: AppTypography.body(AppColors.brandWhite)),
              ),
            )
          : Column(children: [
              // Step dots
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(children: [
                  for (var i = 0; i < total; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i < _index || _done ? AppColors.brandBlue : AppColors.brandWhite.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  if (cam != null && cam.value.isInitialized)
                    ClipRect(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: cam.value.previewSize!.height,
                          height: cam.value.previewSize!.width,
                          child: CameraPreview(cam),
                        ),
                      ),
                    ),
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, _) => CustomPaint(painter: _OvalMeshPainter(_contours, _tone, _pulse.value, done: _done)),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        key: ValueKey(_guide),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlack.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: _tone.withValues(alpha: 0.6)),
                        ),
                        child: Text(_guide, textAlign: TextAlign.center, style: AppTypography.sectionTitle(AppColors.brandWhite)),
                      ),
                    ),
                  ),
                ]),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: _failed
                      ? SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
                            onPressed: _retry,
                            child: const Text('Try again'),
                          ),
                        )
                      : Text(
                          'This proves it’s really you, live. Your photos go only to Oneova’s private review.',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption(AppColors.brandWhite.withValues(alpha: 0.7)),
                        ),
                ),
              ),
            ]),
    );
  }
}

/// The face oval plus a live contour mesh in the current colour.
class _OvalMeshPainter extends CustomPainter {
  final List<List<Offset>> contours;
  final Color color;
  final double t;
  final bool done;
  _OvalMeshPainter(this.contours, this.color, this.t, {required this.done});

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.45), width: size.width * 0.72, height: size.height * 0.62);
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x99000000));
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: done ? 1 : 0.55 + 0.35 * math.sin(t * math.pi * 2).abs()),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.8);
    final dot = Paint()..color = color;
    for (final c in contours) {
      if (c.length < 2) continue;
      final path = Path()..moveTo(c.first.dx * size.width, c.first.dy * size.height);
      for (final p in c.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, line);
      for (final p in c) {
        canvas.drawCircle(Offset(p.dx * size.width, p.dy * size.height), 1.4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_OvalMeshPainter old) => true;
}
