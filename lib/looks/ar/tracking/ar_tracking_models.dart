import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Face contours the makeup and eye effects draw along.
enum ArContour { faceOval, leftBrow, rightBrow, leftEye, rightEye, lipsOuter, lipsInner }

/// One tracked face in normalized viewfinder space (0..1 on both axes,
/// already mirrored for the front camera so it lines up with the preview).
///
/// `z` values share the x scale, so `atan2(dz, dx)` gives a real angle.
@immutable
class TrackedFace {
  final Offset leftEye; // screen-left eye center
  final Offset rightEye; // screen-right eye center
  final Offset noseTip;
  final Offset forehead;
  final Offset chin;
  final Offset mouth;
  final Offset upperLip;
  final Offset lowerLip;
  final Offset leftCheek;
  final Offset rightCheek;
  final Offset leftBlush;
  final Offset rightBlush;

  /// Head pose in radians: roll (in-plane), yaw (left/right), pitch (up/down).
  final double roll;
  final double yaw;
  final double pitch;

  final Map<ArContour, List<Offset>> contours;

  const TrackedFace({
    required this.leftEye,
    required this.rightEye,
    required this.noseTip,
    required this.forehead,
    required this.chin,
    required this.mouth,
    required this.upperLip,
    required this.lowerLip,
    required this.leftCheek,
    required this.rightCheek,
    required this.leftBlush,
    required this.rightBlush,
    required this.roll,
    required this.yaw,
    required this.pitch,
    this.contours = const {},
  });

  /// Face width (cheek to cheek) in normalized x units.
  double get width => (rightCheek - leftCheek).distance;

  Offset get eyesCenter => Offset.lerp(leftEye, rightEye, 0.5)!;

  /// 0 = closed, ~1 = wide open.
  double get mouthOpen {
    final h = (chin - forehead).distance;
    if (h <= 0) return 0;
    return ((lowerLip - upperLip).distance / h * 6).clamp(0.0, 1.0);
  }

  /// Exponential smoothing toward [next]; keeps overlays from jittering.
  TrackedFace lerpTo(TrackedFace next, double t) {
    Offset l(Offset a, Offset b) => Offset.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    final merged = <ArContour, List<Offset>>{};
    for (final e in next.contours.entries) {
      final prev = contours[e.key];
      if (prev != null && prev.length == e.value.length) {
        merged[e.key] = [for (var i = 0; i < prev.length; i++) l(prev[i], e.value[i])];
      } else {
        merged[e.key] = e.value;
      }
    }
    return TrackedFace(
      leftEye: l(leftEye, next.leftEye),
      rightEye: l(rightEye, next.rightEye),
      noseTip: l(noseTip, next.noseTip),
      forehead: l(forehead, next.forehead),
      chin: l(chin, next.chin),
      mouth: l(mouth, next.mouth),
      upperLip: l(upperLip, next.upperLip),
      lowerLip: l(lowerLip, next.lowerLip),
      leftCheek: l(leftCheek, next.leftCheek),
      rightCheek: l(rightCheek, next.rightCheek),
      leftBlush: l(leftBlush, next.leftBlush),
      rightBlush: l(rightBlush, next.rightBlush),
      roll: d(roll, next.roll),
      yaw: d(yaw, next.yaw),
      pitch: d(pitch, next.pitch),
      contours: merged,
    );
  }
}

/// Full/upper body and hand/wrist pose landmarks, normalized like [TrackedFace].
@immutable
class TrackedBody {
  final Offset leftShoulder;
  final Offset rightShoulder;
  final Offset? leftHip;
  final Offset? rightHip;
  final Offset? leftElbow;
  final Offset? rightElbow;
  final Offset? leftWrist;
  final Offset? rightWrist;
  final Offset? leftAnkle;
  final Offset? rightAnkle;

  const TrackedBody({
    required this.leftShoulder,
    required this.rightShoulder,
    this.leftHip,
    this.rightHip,
    this.leftElbow,
    this.rightElbow,
    this.leftWrist,
    this.rightWrist,
    this.leftAnkle,
    this.rightAnkle,
  });

  double get shoulderWidth => (rightShoulder - leftShoulder).distance;
  Offset get shouldersCenter => Offset.lerp(leftShoulder, rightShoulder, 0.5)!;
  double get roll => math.atan2(
        rightShoulder.dy - leftShoulder.dy,
        rightShoulder.dx - leftShoulder.dx,
      );

  static Offset? _lerpOpt(Offset? a, Offset? b, double t) =>
      a != null && b != null ? Offset.lerp(a, b, t) : b;

  TrackedBody lerpTo(TrackedBody next, double t) => TrackedBody(
        leftShoulder: Offset.lerp(leftShoulder, next.leftShoulder, t)!,
        rightShoulder: Offset.lerp(rightShoulder, next.rightShoulder, t)!,
        leftHip: _lerpOpt(leftHip, next.leftHip, t),
        rightHip: _lerpOpt(rightHip, next.rightHip, t),
        leftElbow: _lerpOpt(leftElbow, next.leftElbow, t),
        rightElbow: _lerpOpt(rightElbow, next.rightElbow, t),
        leftWrist: _lerpOpt(leftWrist, next.leftWrist, t),
        rightWrist: _lerpOpt(rightWrist, next.rightWrist, t),
        leftAnkle: _lerpOpt(leftAnkle, next.leftAnkle, t),
        rightAnkle: _lerpOpt(rightAnkle, next.rightAnkle, t),
      );
}

/// Person segmentation mask, already mirrored to match the preview.
/// [image] holds the person as alpha (white RGB, alpha = confidence).
class PersonMask {
  final ui.Image image;
  final int width;
  final int height;
  final Float32List confidences;

  PersonMask({
    required this.image,
    required this.width,
    required this.height,
    required this.confidences,
  });

  void dispose() => image.dispose();
}

/// Everything the renderer needs for one camera frame.
class ArFrame {
  final List<TrackedFace> faces;
  final TrackedBody? body;
  final PersonMask? mask;
  final int timestampMs;

  /// Scene brightness 0..1 (native tracker), for light-aware effects.
  final double light;

  const ArFrame({
    this.faces = const [],
    this.body,
    this.mask,
    required this.timestampMs,
    this.light = 0.5,
  });

  bool get hasFace => faces.isNotEmpty;

  /// Primary subject center in normalized preview coordinates (0..1) for Smart Auto-Tracker.
  Offset? get subjectCenter {
    if (faces.isNotEmpty) {
      final f = faces.first;
      return Offset(f.noseTip.dx, (f.eyesCenter.dy + f.mouth.dy) * 0.5);
    }
    if (body != null) {
      return body!.shouldersCenter;
    }
    return null;
  }

  /// Approximate subject width in normalized preview coordinates (0..1) for Auto-Zoom framing.
  double? get subjectWidth {
    if (faces.isNotEmpty) return faces.first.width;
    if (body != null) return body!.shoulderWidth * 0.65;
    return null;
  }
}
