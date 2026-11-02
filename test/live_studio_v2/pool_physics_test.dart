import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/pool/pool_physics.dart';

void main() {
  group('Live Studio 8-Ball Pool Physics & Aim Prediction', () {
    test('accurately predicts ghost ball impact point and deflection for head-on shot', () {
      final balls = [
        const BallData(id: 0, x: 0.50, y: 0.50), // Cue ball
        const BallData(id: 1, x: 1.00, y: 0.50), // Object ball 1
      ];

      // Aim directly along X axis (angle = 0)
      final prediction = predictShotTrajectory(balls, 0.0);

      expect(prediction.hasTarget, isTrue);
      expect(prediction.targetBallId, equals(1));
      // Ghost ball should be 2 * ballRadius behind the center of target ball
      final expectedGhostX = 1.00 - (PoolConstants.ballRadius * 2.0);
      expect(prediction.ghostBallX, closeTo(expectedGhostX, 0.001));
      expect(prediction.ghostBallY, closeTo(0.50, 0.001));

      // Head-on shot deflection: target moves straight forward (angle = 0)
      expect(prediction.targetDeflectionAngle, closeTo(0.0, 0.001));
    });

    test('accurately predicts cut shot deflection at 45 degrees angle', () {
      final balls = [
        const BallData(id: 0, x: 0.50, y: 0.50),
        const BallData(id: 8, x: 1.00, y: 0.52), // Slight cut
      ];

      final angle = math.atan2(0.52 - 0.50, 1.00 - 0.50);
      final prediction = predictShotTrajectory(balls, angle);

      expect(prediction.hasTarget, isTrue);
      expect(prediction.targetBallId, equals(8));
      expect(prediction.targetDeflectionAngle, isNotNull);
      expect(prediction.cueDeflectionAngle, isNotNull);

      // Cue and object balls should separate at approximately 90 degrees tangent
      final diff = (prediction.targetDeflectionAngle! - prediction.cueDeflectionAngle!).abs();
      // Normalized angle difference modulo pi
      final modDiff = diff % math.pi;
      expect(modDiff, closeTo(math.pi / 2, 0.05));
    });

    test('predicts rail collision coordinates when no ball is in aim path', () {
      final balls = [
        const BallData(id: 0, x: 0.50, y: 0.50),
      ];

      // Aim straight towards right cushion (angle = 0)
      final prediction = predictShotTrajectory(balls, 0.0);

      expect(prediction.hasTarget, isFalse);
      expect(prediction.targetBallId, isNull);
      expect(prediction.ghostBallX, closeTo(PoolConstants.maxX, 0.001));
      expect(prediction.ghostBallY, closeTo(0.50, 0.001));
    });

    test('smoothly interpolates ball positions across simulation keyframes', () {
      final keyframes = [
        const PoolKeyframe(
          tMs: 0,
          balls: [
            PoolKeyframeBall(id: 0, x: 0.50, y: 0.50, pocketed: false),
            PoolKeyframeBall(id: 1, x: 1.00, y: 0.50, pocketed: false),
          ],
        ),
        const PoolKeyframe(
          tMs: 500,
          balls: [
            PoolKeyframeBall(id: 0, x: 0.80, y: 0.50, pocketed: false),
            PoolKeyframeBall(id: 1, x: 1.40, y: 0.50, pocketed: false),
          ],
        ),
        const PoolKeyframe(
          tMs: 1000,
          balls: [
            PoolKeyframeBall(id: 0, x: 0.90, y: 0.50, pocketed: false),
            PoolKeyframeBall(id: 1, x: 2.00, y: 0.50, pocketed: true),
          ],
        ),
      ];

      // At progress 0.25 (t = 250ms), midway between k0 and k1
      final sampled = sampleKeyframes(keyframes, 0.25, const []);
      final cue = sampled.firstWhere((b) => b.id == 0);
      final ball1 = sampled.firstWhere((b) => b.id == 1);

      expect(cue.x, closeTo(0.65, 0.01)); // Midway between 0.50 and 0.80
      expect(ball1.x, closeTo(1.20, 0.01)); // Midway between 1.00 and 1.40
      expect(ball1.pocketed, isFalse);

      // At progress 1.0 (t = 1000ms), last frame
      final finalSampled = sampleKeyframes(keyframes, 1.0, const []);
      final finalBall1 = finalSampled.firstWhere((b) => b.id == 1);
      expect(finalBall1.pocketed, isTrue);
    });
  });
}

