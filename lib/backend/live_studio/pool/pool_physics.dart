import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Regulation pool dimensions (normalized 2:1 ratio)
class PoolConstants {
  static const double tableWidth = 2.0;
  static const double tableHeight = 1.0;
  static const double ballRadius = 0.028;
  static const double cornerPocketRadius = 0.060;
  static const double sidePocketRadius = 0.052;

  static const double cushionRestitution = 0.80;
  static const double ballRestitution = 0.94;
  static const double friction = 0.42;
  static const double maxCueSpeed = 11.5;
  static const double minVelocityThreshold = 0.005;

  static const double railInset = ballRadius;
  static const double minX = railInset;
  static const double maxX = tableWidth - railInset;
  static const double minY = railInset;
  static const double maxY = tableHeight - railInset;

  static const List<PocketCoord> pockets = [
    PocketCoord(0, 0.0, 0.0, false),
    PocketCoord(1, 1.0, 0.0, true),
    PocketCoord(2, 2.0, 0.0, false),
    PocketCoord(3, 2.0, 1.0, false),
    PocketCoord(4, 1.0, 1.0, true),
    PocketCoord(5, 0.0, 1.0, false),
  ];
}

@immutable
class PocketCoord {
  const PocketCoord(this.id, this.x, this.y, this.isSide);
  final int id;
  final double x;
  final double y;
  final bool isSide;

  double get radius => isSide ? PoolConstants.sidePocketRadius : PoolConstants.cornerPocketRadius;
}

@immutable
class BallData {
  const BallData({
    required this.id,
    required this.x,
    required this.y,
    this.vx = 0.0,
    this.vy = 0.0,
    this.pocketed = false,
    this.pocketId,
  });

  final int id; // 0 = Cue, 1-7 = Solids, 8 = 8-Ball, 9-15 = Stripes
  final double x;
  final double y;
  final double vx;
  final double vy;
  final bool pocketed;
  final int? pocketId;

  bool get isCue => id == 0;
  bool get isEightBall => id == 8;
  bool get isSolid => id >= 1 && id <= 7;
  bool get isStripe => id >= 9 && id <= 15;

  BallData copyWith({
    int? id,
    double? x,
    double? y,
    double? vx,
    double? vy,
    bool? pocketed,
    int? pocketId,
  }) {
    return BallData(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      pocketed: pocketed ?? this.pocketed,
      pocketId: pocketId ?? this.pocketId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'vx': vx,
        'vy': vy,
        'pocketed': pocketed,
        if (pocketId != null) 'pocketId': pocketId,
      };

  factory BallData.fromJson(Map<String, dynamic> json) {
    return BallData(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      x: json['x'] is num ? (json['x'] as num).toDouble() : 0.0,
      y: json['y'] is num ? (json['y'] as num).toDouble() : 0.0,
      vx: json['vx'] is num ? (json['vx'] as num).toDouble() : 0.0,
      vy: json['vy'] is num ? (json['vy'] as num).toDouble() : 0.0,
      pocketed: json['pocketed'] == true,
      pocketId: json['pocketId'] is num ? (json['pocketId'] as num).toInt() : null,
    );
  }
}

@immutable
class PoolKeyframeBall {
  const PoolKeyframeBall({
    required this.id,
    required this.x,
    required this.y,
    required this.pocketed,
  });

  final int id;
  final double x;
  final double y;
  final bool pocketed;

  factory PoolKeyframeBall.fromJson(Map<String, dynamic> json) {
    return PoolKeyframeBall(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      x: json['x'] is num ? (json['x'] as num).toDouble() : 0.0,
      y: json['y'] is num ? (json['y'] as num).toDouble() : 0.0,
      pocketed: json['pocketed'] == true,
    );
  }
}

@immutable
class PoolKeyframe {
  const PoolKeyframe({
    required this.tMs,
    required this.balls,
  });

  final int tMs;
  final List<PoolKeyframeBall> balls;

  factory PoolKeyframe.fromJson(Map<String, dynamic> json) {
    final ballsRaw = json['balls'] as List? ?? const [];
    return PoolKeyframe(
      tMs: json['tMs'] is num ? (json['tMs'] as num).toInt() : 0,
      balls: [
        for (final b in ballsRaw)
          if (b is Map) PoolKeyframeBall.fromJson(Map<String, dynamic>.from(b)),
      ],
    );
  }
}

@immutable
class TrajectoryPrediction {
  const TrajectoryPrediction({
    required this.ghostBallX,
    required this.ghostBallY,
    required this.targetBallId,
    required this.targetDeflectionAngle,
    required this.cueDeflectionAngle,
    required this.hasTarget,
    required this.cueRayEndX,
    required this.cueRayEndY,
  });

  final double ghostBallX;
  final double ghostBallY;
  final int? targetBallId;
  final double? targetDeflectionAngle;
  final double? cueDeflectionAngle;
  final bool hasTarget;
  final double cueRayEndX;
  final double cueRayEndY;
}

/// Computes the ghost ball position, aim ray intersection, and 90-degree tangent deflection lines
TrajectoryPrediction predictShotTrajectory(
  List<BallData> balls,
  double angle, {
  double? cueX,
  double? cueY,
}) {
  final cueBall = balls.firstWhere((b) => b.id == 0, orElse: () => const BallData(id: 0, x: 0.5, y: 0.5));
  final startX = cueX ?? cueBall.x;
  final startY = cueY ?? cueBall.y;

  final dirX = math.cos(angle);
  final dirY = math.sin(angle);

  double closestDist = double.infinity;
  int? targetId;
  double ghostX = startX + dirX * 2.0;
  double ghostY = startY + dirY * 2.0;

  // Check intersection with all active object balls
  for (final ball in balls) {
    if (ball.id == 0 || ball.pocketed) continue;

    // Vector from cue to object ball
    final toBallX = ball.x - startX;
    final toBallY = ball.y - startY;

    // Projection along aim ray
    final proj = toBallX * dirX + toBallY * dirY;
    if (proj <= 0) continue; // Ball is behind cue

    // Perpendicular distance squared
    final perpDistSq = (toBallX * toBallX + toBallY * toBallY) - (proj * proj);
    final collisionDiameter = PoolConstants.ballRadius * 2.0;

    if (perpDistSq < collisionDiameter * collisionDiameter) {
      final backDist = math.sqrt(collisionDiameter * collisionDiameter - perpDistSq);
      final hitDist = proj - backDist;

      if (hitDist > 0 && hitDist < closestDist) {
        closestDist = hitDist;
        targetId = ball.id;
        ghostX = startX + dirX * hitDist;
        ghostY = startY + dirY * hitDist;
      }
    }
  }

  // If no ball was hit, find intersection with table cushion rails
  if (targetId == null) {
    double minT = double.infinity;
    // Left cushion
    if (dirX < 0) {
      final t = (PoolConstants.minX - startX) / dirX;
      if (t > 0 && t < minT) minT = t;
    }
    // Right cushion
    if (dirX > 0) {
      final t = (PoolConstants.maxX - startX) / dirX;
      if (t > 0 && t < minT) minT = t;
    }
    // Top cushion
    if (dirY < 0) {
      final t = (PoolConstants.minY - startY) / dirY;
      if (t > 0 && t < minT) minT = t;
    }
    // Bottom cushion
    if (dirY > 0) {
      final t = (PoolConstants.maxY - startY) / dirY;
      if (t > 0 && t < minT) minT = t;
    }

    if (minT.isFinite) {
      ghostX = startX + dirX * minT;
      ghostY = startY + dirY * minT;
    }

    return TrajectoryPrediction(
      ghostBallX: ghostX,
      ghostBallY: ghostY,
      targetBallId: null,
      targetDeflectionAngle: null,
      cueDeflectionAngle: null,
      hasTarget: false,
      cueRayEndX: ghostX,
      cueRayEndY: ghostY,
    );
  }

  // Object ball was hit: calculate deflection angles
  final targetBall = balls.firstWhere((b) => b.id == targetId);
  final targetAngle = math.atan2(targetBall.y - ghostY, targetBall.x - ghostX);

  // Cue ball deflects at 90 degrees tangent
  final normalX = math.cos(targetAngle);
  final normalY = math.sin(targetAngle);
  final tangentX = -normalY;
  final tangentY = normalX;

  // Pick tangent direction closest to cue direction
  final dot = dirX * tangentX + dirY * tangentY;
  final cueTangentAngle = math.atan2(tangentY * (dot >= 0 ? 1 : -1), tangentX * (dot >= 0 ? 1 : -1));

  return TrajectoryPrediction(
    ghostBallX: ghostX,
    ghostBallY: ghostY,
    targetBallId: targetId,
    targetDeflectionAngle: targetAngle,
    cueDeflectionAngle: cueTangentAngle,
    hasTarget: true,
    cueRayEndX: ghostX,
    cueRayEndY: ghostY,
  );
}

/// Samples interpolated ball states from simulation keyframes at normalized progress [0.0 .. 1.0]
List<BallData> sampleKeyframes(
  List<PoolKeyframe> keyframes,
  double progress,
  List<BallData> fallbackBalls,
) {
  if (keyframes.isEmpty) return fallbackBalls;
  if (keyframes.length == 1 || progress <= 0.0) {
    return [
      for (final b in keyframes.first.balls)
        BallData(id: b.id, x: b.x, y: b.y, pocketed: b.pocketed),
    ];
  }
  if (progress >= 1.0) {
    return [
      for (final b in keyframes.last.balls)
        BallData(id: b.id, x: b.x, y: b.y, pocketed: b.pocketed),
    ];
  }

  final totalDurationMs = keyframes.last.tMs;
  final currentMs = progress * totalDurationMs;

  // Find surrounding keyframes
  int k1 = 0;
  while (k1 < keyframes.length - 1 && keyframes[k1 + 1].tMs < currentMs) {
    k1++;
  }
  final k2 = math.min(k1 + 1, keyframes.length - 1);

  final f1 = keyframes[k1];
  final f2 = keyframes[k2];

  final span = f2.tMs - f1.tMs;
  final factor = span > 0 ? ((currentMs - f1.tMs) / span).clamp(0.0, 1.0) : 0.0;

  final Map<int, PoolKeyframeBall> f2Map = {for (final b in f2.balls) b.id: b};

  return [
    for (final b1 in f1.balls) ...[
      () {
        final b2 = f2Map[b1.id] ?? b1;
        final x = b1.x + (b2.x - b1.x) * factor;
        final y = b1.y + (b2.y - b1.y) * factor;
        final pocketed = b2.pocketed || b1.pocketed;
        return BallData(id: b1.id, x: x, y: y, pocketed: pocketed);
      }(),
    ],
  ];
}

