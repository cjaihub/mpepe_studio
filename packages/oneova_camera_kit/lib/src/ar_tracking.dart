import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Normalized 3D landmark coordinate (x, y, z in 0.0 - 1.0 or camera space).
@immutable
class Landmark3D {
  final double x;
  final double y;
  final double z;

  const Landmark3D({
    required this.x,
    required this.y,
    this.z = 0.0,
  });

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};

  factory Landmark3D.fromJson(Map<String, dynamic> json) {
    return Landmark3D(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Normalized face tracking mesh landmarks (MediaPipe canonical 468/478 points).
@immutable
class FaceMeshLandmarks {
  final List<Landmark3D> points;

  const FaceMeshLandmarks({required this.points});

  // Key landmark indices per MediaPipe Face Mesh topology
  Landmark3D? get noseTip => points.length > 1 ? points[1] : null;
  Landmark3D? get forehead => points.length > 10 ? points[10] : null;
  Landmark3D? get chin => points.length > 152 ? points[152] : null;
  Landmark3D? get leftEye => points.length > 33 ? points[33] : null;
  Landmark3D? get rightEye => points.length > 263 ? points[263] : null;
  Landmark3D? get upperLip => points.length > 13 ? points[13] : null;
  Landmark3D? get lowerLip => points.length > 14 ? points[14] : null;
  Landmark3D? get leftMouthCorner => points.length > 61 ? points[61] : null;
  Landmark3D? get rightMouthCorner => points.length > 291 ? points[291] : null;

  /// Returns mouth openness metric (0.0 closed to 1.0+ wide open).
  double get mouthOpenness {
    if (upperLip == null || lowerLip == null || noseTip == null || chin == null) return 0.0;
    final lipDist = (upperLip!.y - lowerLip!.y).abs();
    final faceHeight = (forehead != null && chin != null) ? (chin!.y - forehead!.y).abs() : 0.3;
    return (lipDist / faceHeight * 4.0).clamp(0.0, 1.0);
  }

  /// Returns smile confidence metric (0.0 to 1.0) based on mouth width vs face width.
  double get smileConfidence {
    if (leftMouthCorner == null || rightMouthCorner == null || leftEye == null || rightEye == null) return 0.0;
    final mouthWidth = (rightMouthCorner!.x - leftMouthCorner!.x).abs();
    final eyeDist = (rightEye!.x - leftEye!.x).abs();
    if (eyeDist == 0) return 0.0;
    final ratio = mouthWidth / eyeDist;
    return ((ratio - 0.75) * 2.5).clamp(0.0, 1.0);
  }
}

/// Normalized hand tracking landmarks (MediaPipe 21 points).
@immutable
class HandLandmarks {
  final bool isLeft;
  final List<Landmark3D> points;

  const HandLandmarks({required this.isLeft, required this.points});

  Landmark3D? get wrist => points.isNotEmpty ? points[0] : null;
  Landmark3D? get thumbTip => points.length > 4 ? points[4] : null;
  Landmark3D? get indexTip => points.length > 8 ? points[8] : null;
  Landmark3D? get middleTip => points.length > 12 ? points[12] : null;
  Landmark3D? get ringTip => points.length > 16 ? points[16] : null;
  Landmark3D? get pinkyTip => points.length > 20 ? points[20] : null;

  /// Detects if hand is making a peace/victory sign (index & middle up, others closed).
  bool get isPeaceSign {
    if (indexTip == null || middleTip == null || ringTip == null || pinkyTip == null || wrist == null) return false;
    final indexUp = indexTip!.y < wrist!.y - 0.15;
    final middleUp = middleTip!.y < wrist!.y - 0.15;
    final ringDown = ringTip!.y > middleTip!.y + 0.05;
    final pinkyDown = pinkyTip!.y > middleTip!.y + 0.05;
    return indexUp && middleUp && ringDown && pinkyDown;
  }

  /// Detects if hand is open palm facing camera.
  bool get isOpenPalm {
    if (indexTip == null || middleTip == null || ringTip == null || pinkyTip == null || wrist == null) return false;
    return indexTip!.y < wrist!.y - 0.10 &&
        middleTip!.y < wrist!.y - 0.10 &&
        ringTip!.y < wrist!.y - 0.10 &&
        pinkyTip!.y < wrist!.y - 0.10;
  }

  /// Detects if hand is giving a thumbs up.
  bool get isThumbsUp {
    if (thumbTip == null || indexTip == null || wrist == null) return false;
    return thumbTip!.y < wrist!.y - 0.18 && indexTip!.y > thumbTip!.y + 0.08;
  }
}

/// Full tracking frame output from camera and native vision inference.
@immutable
class TrackingFrame {
  final int timestampMs;
  final List<FaceMeshLandmarks> faces;
  final List<HandLandmarks> hands;
  final bool hasBodySegmentation;

  const TrackingFrame({
    required this.timestampMs,
    this.faces = const [],
    this.hands = const [],
    this.hasBodySegmentation = false,
  });

  bool get hasFace => faces.isNotEmpty;
  bool get hasHands => hands.isNotEmpty;

  /// Evaluates gestures and expressions for trigger conditions.
  Set<String> evaluateActiveTriggers() {
    final triggers = <String>{};

    for (final face in faces) {
      if (face.smileConfidence > 0.6) triggers.add('smile');
      if (face.mouthOpenness > 0.4) triggers.add('mouth_open');
    }

    for (final hand in hands) {
      if (hand.isPeaceSign) triggers.add('peace_sign');
      if (hand.isOpenPalm) triggers.add('open_palm');
      if (hand.isThumbsUp) triggers.add('thumbs_up');
    }

    return triggers;
  }
}
