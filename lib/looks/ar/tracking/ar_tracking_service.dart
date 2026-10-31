import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import 'ar_tracking_models.dart';

/// What the active effects need tracked; models that are not needed are not run.
@immutable
class ArTrackingNeeds {
  final bool face;
  final bool mask;
  final bool body;

  const ArTrackingNeeds({this.face = false, this.mask = false, this.body = false});

  bool get any => face || mask || body;

  @override
  bool operator ==(Object other) =>
      other is ArTrackingNeeds && other.face == face && other.mask == mask && other.body == body;

  @override
  int get hashCode => Object.hash(face, mask, body);
}

/// On-device tracking for AR effects with ML Kit.
///
/// Android uses the 468-point face mesh (3D points give real yaw/pitch);
/// iOS, where ML Kit has no face mesh, uses face contours + Euler angles.
/// Selfie segmentation gives the person mask and pose detection the
/// shoulders. Frames that arrive while a frame is still being processed are
/// dropped, so tracking never queues up behind the camera.
class ArTrackingService {
  ArTrackingService();

  FaceMeshDetector? _mesh;
  FaceDetector? _faceDetector;
  SelfieSegmenter? _streamSegmenter;
  SelfieSegmenter? _stillSegmenter;
  PoseDetector? _pose;

  bool _busy = false;
  TrackedFace? _lastFace;
  TrackedBody? _lastBody;
  Float32List? _lastMask;

  static bool get _useMesh => Platform.isAndroid;

  FaceMeshDetector get _meshDetector =>
      _mesh ??= FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);
  FaceDetector get _contourDetector => _faceDetector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
  PoseDetector get _poseDetector => _pose ??= PoseDetector(options: PoseDetectorOptions());

  /// Resets smoothing, e.g. after flipping the camera.
  void reset() {
    _lastFace = null;
    _lastBody = null;
    _lastMask = null;
  }

  /// Processes one streamed preview frame; returns null if the frame was
  /// dropped (still busy) or could not be read.
  Future<ArFrame?> processCameraImage(
    CameraImage image,
    CameraDescription camera,
    ArTrackingNeeds needs,
  ) async {
    if (_busy || !needs.any) return null;
    final input = _inputFromCameraImage(image, camera);
    if (input == null) return null;
    _busy = true;
    try {
      final rotation = camera.sensorOrientation;
      final upright = rotation == 90 || rotation == 270
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());
      final mirror = camera.lensDirection == CameraLensDirection.front;
      _streamSegmenter ??= SelfieSegmenter(mode: SegmenterMode.stream, enableRawSizeMask: true);
      return await _run(input, upright, mirror, needs, _streamSegmenter!, smooth: true);
    } catch (e) {
      debugPrint('AR tracking frame failed: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// Tracks a still photo (for baking effects into the saved picture).
  /// [size] is the decoded, upright size of the photo.
  Future<ArFrame> processFile(String path, Size size, ArTrackingNeeds needs) async {
    _stillSegmenter ??= SelfieSegmenter(mode: SegmenterMode.single, enableRawSizeMask: true);
    return _run(InputImage.fromFilePath(path), size, false, needs, _stillSegmenter!, smooth: false);
  }

  Future<ArFrame> _run(
    InputImage input,
    Size upright,
    bool mirror,
    ArTrackingNeeds needs,
    SelfieSegmenter segmenter, {
    required bool smooth,
  }) async {
    final results = await Future.wait<Object?>([
      needs.face
          ? (_useMesh ? _meshDetector.processImage(input) : _contourDetector.processImage(input))
          : Future<Object?>.value(null),
      needs.mask ? segmenter.processImage(input) : Future<Object?>.value(null),
      needs.body ? _poseDetector.processImage(input) : Future<Object?>.value(null),
    ]);

    final faces = <TrackedFace>[];
    final rawFaces = results[0];
    if (rawFaces is List<FaceMesh>) {
      for (final m in rawFaces.take(2)) {
        final f = _faceFromMesh(m, upright, mirror);
        if (f != null) faces.add(f);
      }
    } else if (rawFaces is List<Face>) {
      for (final f in rawFaces.take(2)) {
        final t = _faceFromContours(f, upright, mirror);
        if (t != null) faces.add(t);
      }
    }
    if (smooth && faces.isNotEmpty) {
      final prev = _lastFace;
      if (prev != null && (prev.eyesCenter - faces.first.eyesCenter).distance < prev.width) {
        faces[0] = prev.lerpTo(faces.first, 0.55);
      }
      _lastFace = faces.first;
    } else if (smooth) {
      _lastFace = null;
    }

    TrackedBody? body;
    final poses = results[2];
    if (poses is List<Pose> && poses.isNotEmpty) {
      body = _bodyFromPose(poses.first, upright, mirror);
      if (smooth && body != null) {
        final prev = _lastBody;
        if (prev != null) body = prev.lerpTo(body, 0.5);
        _lastBody = body;
      }
    }

    PersonMask? mask;
    final seg = results[1];
    if (seg is SegmentationMask) {
      mask = await _maskImage(seg, mirror, smooth);
    }

    return ArFrame(
      faces: faces,
      body: body,
      mask: mask,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  InputImage? _inputFromCameraImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
    if (Platform.isAndroid) {
      // The camera is opened with ImageFormatGroup.nv21: one packed plane.
      if (image.planes.length != 1) return null;
    } else if (format != InputImageFormat.bgra8888 || image.planes.length != 1) {
      return null;
    }
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

  // ── Face mesh (Android) ──────────────────────────────────────────────────

  TrackedFace? _faceFromMesh(FaceMesh mesh, Size size, bool mirror) {
    if (mesh.points.length < 468) return null;
    final pts = List<FaceMeshPoint?>.filled(468, null);
    for (final p in mesh.points) {
      if (p.index >= 0 && p.index < 468) pts[p.index] = p;
    }
    if (pts.any((p) => p == null)) return null;

    Offset n(FaceMeshPoint p) => _norm(p.x, p.y, size, mirror);
    double z(FaceMeshPoint p) => p.z / size.width;
    Offset mid(int a, int b) => Offset.lerp(n(pts[a]!), n(pts[b]!), 0.5)!;

    final eyeA = mid(33, 133);
    final eyeB = mid(362, 263);
    final cheekA = pts[234]!;
    final cheekB = pts[454]!;
    final leftIsA = n(cheekA).dx <= n(cheekB).dx;
    final lc = leftIsA ? cheekA : cheekB;
    final rc = leftIsA ? cheekB : cheekA;
    final le = eyeA.dx <= eyeB.dx ? eyeA : eyeB;
    final re = eyeA.dx <= eyeB.dx ? eyeB : eyeA;
    final blushA = n(pts[50]!);
    final blushB = n(pts[280]!);

    final top = pts[10]!;
    final bottom = pts[152]!;
    final yaw = math.atan2(z(rc) - z(lc), n(rc).dx - n(lc).dx);
    final pitch = math.atan2(z(bottom) - z(top), n(bottom).dy - n(top).dy);
    final roll = math.atan2(re.dy - le.dy, re.dx - le.dx);

    List<Offset> contour(FaceMeshContourType t) =>
        (mesh.contours[t] ?? const <FaceMeshPoint>[]).map(n).toList();

    final browA = contour(FaceMeshContourType.leftEyebrowTop);
    final browB = contour(FaceMeshContourType.rightEyebrowTop);
    final eyeCA = contour(FaceMeshContourType.leftEye);
    final eyeCB = contour(FaceMeshContourType.rightEye);
    bool isLeft(List<Offset> a, List<Offset> b) =>
        a.isEmpty || b.isEmpty || _meanX(a) <= _meanX(b);

    return TrackedFace(
      leftEye: le,
      rightEye: re,
      noseTip: n(pts[1]!),
      forehead: n(top),
      chin: n(bottom),
      mouth: mid(13, 14),
      upperLip: n(pts[13]!),
      lowerLip: n(pts[14]!),
      leftCheek: n(lc),
      rightCheek: n(rc),
      leftBlush: blushA.dx <= blushB.dx ? blushA : blushB,
      rightBlush: blushA.dx <= blushB.dx ? blushB : blushA,
      roll: roll,
      yaw: yaw,
      pitch: pitch,
      contours: {
        ArContour.faceOval: contour(FaceMeshContourType.faceOval),
        ArContour.leftBrow: isLeft(browA, browB) ? browA : browB,
        ArContour.rightBrow: isLeft(browA, browB) ? browB : browA,
        ArContour.leftEye: isLeft(eyeCA, eyeCB) ? eyeCA : eyeCB,
        ArContour.rightEye: isLeft(eyeCA, eyeCB) ? eyeCB : eyeCA,
        ArContour.lipsOuter: _ring(
          contour(FaceMeshContourType.upperLipTop),
          contour(FaceMeshContourType.lowerLipBottom),
        ),
        ArContour.lipsInner: _ring(
          contour(FaceMeshContourType.upperLipBottom),
          contour(FaceMeshContourType.lowerLipTop),
        ),
      },
    );
  }

  // ── Face contours (iOS) ──────────────────────────────────────────────────

  TrackedFace? _faceFromContours(Face face, Size size, bool mirror) {
    Offset? lm(FaceLandmarkType t) {
      final p = face.landmarks[t]?.position;
      return p == null ? null : _norm(p.x.toDouble(), p.y.toDouble(), size, mirror);
    }

    List<Offset> c(FaceContourType t) => (face.contours[t]?.points ?? const [])
        .map((p) => _norm(p.x.toDouble(), p.y.toDouble(), size, mirror))
        .toList();

    final eyeA = lm(FaceLandmarkType.leftEye);
    final eyeB = lm(FaceLandmarkType.rightEye);
    final nose = lm(FaceLandmarkType.noseBase);
    final oval = c(FaceContourType.face);
    if (eyeA == null || eyeB == null || nose == null || oval.length < 20) return null;

    final le = eyeA.dx <= eyeB.dx ? eyeA : eyeB;
    final re = eyeA.dx <= eyeB.dx ? eyeB : eyeA;
    final top = oval.reduce((a, b) => a.dy < b.dy ? a : b);
    final bottom = oval.reduce((a, b) => a.dy > b.dy ? a : b);
    final left = oval.reduce((a, b) => a.dx < b.dx ? a : b);
    final right = oval.reduce((a, b) => a.dx > b.dx ? a : b);
    final upper = c(FaceContourType.upperLipBottom);
    final lower = c(FaceContourType.lowerLipTop);
    final upperLip = upper.isEmpty ? nose : upper[upper.length ~/ 2];
    final lowerLip = lower.isEmpty ? upperLip : lower[lower.length ~/ 2];
    final sign = mirror ? -1.0 : 1.0;
    final browA = c(FaceContourType.leftEyebrowTop);
    final browB = c(FaceContourType.rightEyebrowTop);
    final eA = c(FaceContourType.leftEye);
    final eB = c(FaceContourType.rightEye);
    bool isLeft(List<Offset> a, List<Offset> b) =>
        a.isEmpty || b.isEmpty || _meanX(a) <= _meanX(b);

    return TrackedFace(
      leftEye: le,
      rightEye: re,
      noseTip: nose,
      forehead: top,
      chin: bottom,
      mouth: Offset.lerp(upperLip, lowerLip, 0.5)!,
      upperLip: upperLip,
      lowerLip: lowerLip,
      leftCheek: left,
      rightCheek: right,
      leftBlush: lm(FaceLandmarkType.leftCheek) ?? Offset.lerp(left, nose, 0.5)!,
      rightBlush: lm(FaceLandmarkType.rightCheek) ?? Offset.lerp(right, nose, 0.5)!,
      roll: math.atan2(re.dy - le.dy, re.dx - le.dx),
      yaw: sign * -(face.headEulerAngleY ?? 0) * math.pi / 180,
      pitch: (face.headEulerAngleX ?? 0) * math.pi / 180,
      contours: {
        ArContour.faceOval: oval,
        ArContour.leftBrow: isLeft(browA, browB) ? browA : browB,
        ArContour.rightBrow: isLeft(browA, browB) ? browB : browA,
        ArContour.leftEye: isLeft(eA, eB) ? eA : eB,
        ArContour.rightEye: isLeft(eA, eB) ? eB : eA,
        ArContour.lipsOuter: _ring(c(FaceContourType.upperLipTop), c(FaceContourType.lowerLipBottom)),
        ArContour.lipsInner: _ring(upper, lower),
      },
    );
  }

  // ── Body ────────────────────────────────────────────────────────────────

  TrackedBody? _bodyFromPose(Pose pose, Size size, bool mirror) {
    Offset? p(PoseLandmarkType t) {
      final l = pose.landmarks[t];
      if (l == null || l.likelihood < 0.5) return null;
      return _norm(l.x, l.y, size, mirror);
    }

    final a = p(PoseLandmarkType.leftShoulder);
    final b = p(PoseLandmarkType.rightShoulder);
    if (a == null || b == null) return null;
    final ha = p(PoseLandmarkType.leftHip);
    final hb = p(PoseLandmarkType.rightHip);
    final aLeft = a.dx <= b.dx;
    return TrackedBody(
      leftShoulder: aLeft ? a : b,
      rightShoulder: aLeft ? b : a,
      leftHip: aLeft ? ha : hb,
      rightHip: aLeft ? hb : ha,
    );
  }

  // ── Segmentation ─────────────────────────────────────────────────────────

  Future<PersonMask> _maskImage(SegmentationMask seg, bool mirror, bool smooth) async {
    final w = seg.width;
    final h = seg.height;
    final conf = Float32List(w * h);
    final prev = smooth ? _lastMask : null;
    final blend = prev != null && prev.length == conf.length;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final src = y * w + (mirror ? (w - 1 - x) : x);
        final dst = y * w + x;
        var v = seg.confidences[src];
        if (blend) v = prev[dst] * 0.35 + v * 0.65;
        conf[dst] = v;
        // Soft threshold so edges stay feathered but the background drops out.
        final a = ((v - 0.35) / 0.4).clamp(0.0, 1.0);
        final o = dst * 4;
        rgba[o] = 255;
        rgba[o + 1] = 255;
        rgba[o + 2] = 255;
        rgba[o + 3] = (a * a * (3 - 2 * a) * 255).round();
      }
    }
    if (smooth) _lastMask = conf;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
    return PersonMask(image: await completer.future, width: w, height: h, confidences: conf);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static Offset _norm(double x, double y, Size size, bool mirror) {
    final nx = x / size.width;
    return Offset(mirror ? 1 - nx : nx, y / size.height);
  }

  static double _meanX(List<Offset> pts) =>
      pts.fold<double>(0, (s, p) => s + p.dx) / pts.length;

  /// Joins a top and bottom lip edge into one closed ring.
  static List<Offset> _ring(List<Offset> top, List<Offset> bottom) {
    if (top.isEmpty || bottom.isEmpty) return const [];
    final tail = (top.last - bottom.first).distance < (top.last - bottom.last).distance
        ? bottom
        : bottom.reversed.toList();
    return [...top, ...tail];
  }

  Future<void> dispose() async {
    await _mesh?.close();
    await _faceDetector?.close();
    await _streamSegmenter?.close();
    await _stillSegmenter?.close();
    await _pose?.close();
  }
}
