import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../backend/live_studio/pool/pool_physics.dart';

class PoolTablePainter extends CustomPainter {
  PoolTablePainter({
    required this.balls,
    this.aimAngle,
    this.aimPower = 0.0,
    this.aimSpinX = 0.0,
    this.aimSpinY = 0.0,
    this.showAimRay = false,
    this.prediction,
    this.calledPocket,
    this.ballInHand = false,
    this.cueBallDragging = false,
    this.cueBallDragPos,
    this.pocketAnimationProgress = 0.0,
  });

  final List<BallData> balls;
  final double? aimAngle;
  final double aimPower; // 0.0 to 1.0
  final double aimSpinX;
  final double aimSpinY;
  final bool showAimRay;
  final TrajectoryPrediction? prediction;
  final int? calledPocket;
  final bool ballInHand;
  final bool cueBallDragging;
  final Offset? cueBallDragPos;
  final double pocketAnimationProgress;

  static const Color feltGreen = Color(0xFF0F5A3E);
  static const Color feltGreenHighlight = Color(0xFF157350);
  static const Color woodBorder = Color(0xFF1F110B);
  static const Color woodHighlight = Color(0xFF381F14);
  static const Color cushionColor = Color(0xFF0A442E);
  static const Color brassColor = Color(0xFFC5A059);
  static const Color diamondSight = Color(0xFFF3E5AB);

  static const Map<int, Color> ballColors = {
    1: Color(0xFFFACC15), // Yellow
    2: Color(0xFF2563EB), // Blue
    3: Color(0xFFDC2626), // Red
    4: Color(0xFF7C3AED), // Purple
    5: Color(0xFFEA580C), // Orange
    6: Color(0xFF16A34A), // Green
    7: Color(0xFF881337), // Maroon
    8: Color(0xFF111111), // 8-Ball Black
    9: Color(0xFFFACC15), // Stripe Yellow
    10: Color(0xFF2563EB), // Stripe Blue
    11: Color(0xFFDC2626), // Stripe Red
    12: Color(0xFF7C3AED), // Stripe Purple
    13: Color(0xFFEA580C), // Stripe Orange
    14: Color(0xFF16A34A), // Stripe Green
    15: Color(0xFF881337), // Stripe Maroon
  };

  @override
  void paint(Canvas canvas, Size size) {
    // 2:1 normalized coordinates to screen pixels
    final tableW = size.width;
    final tableH = size.height;
    final scaleX = tableW / PoolConstants.tableWidth;
    final scaleY = tableH / PoolConstants.tableHeight;
    final ballPixelR = PoolConstants.ballRadius * scaleX;

    Offset toPixel(double x, double y) => Offset(x * scaleX, y * scaleY);

    // 1. Draw Wooden Rails & Frame
    final outerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-16, -16, tableW + 32, tableH + 32),
      const Radius.circular(16),
    );
    final woodPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [woodHighlight, woodBorder, woodHighlight],
      ).createShader(outerRRect.outerRect);
    canvas.drawRRect(outerRRect, woodPaint);

    // 2. Draw Felt Bed
    final feltRect = Rect.fromLTWH(0, 0, tableW, tableH);
    final feltPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: const [feltGreenHighlight, feltGreen],
      ).createShader(feltRect);
    canvas.drawRect(feltRect, feltPaint);

    // 3. Draw Cushion Strips along edges
    final cushionPaint = Paint()..color = cushionColor;
    final cushionWidth = ballPixelR * 0.75;
    // Top cushion
    canvas.drawRect(Rect.fromLTWH(0, 0, tableW, cushionWidth), cushionPaint);
    // Bottom cushion
    canvas.drawRect(Rect.fromLTWH(0, tableH - cushionWidth, tableW, cushionWidth), cushionPaint);
    // Left cushion
    canvas.drawRect(Rect.fromLTWH(0, 0, cushionWidth, tableH), cushionPaint);
    // Right cushion
    canvas.drawRect(Rect.fromLTWH(tableW - cushionWidth, 0, cushionWidth, tableH), cushionPaint);

    // 4. Inlaid Diamond Sights on Rails
    final diamondPaint = Paint()
      ..color = diamondSight
      ..style = PaintingStyle.fill;
    final sightRadius = math.max(2.5, tableH * 0.012);

    void drawDiamond(double px, double py) {
      final path = Path()
        ..moveTo(px, py - sightRadius)
        ..lineTo(px + sightRadius, py)
        ..lineTo(px, py + sightRadius)
        ..lineTo(px - sightRadius, py)
        ..close();
      canvas.drawPath(path, diamondPaint);
    }

    // Top and Bottom sights
    for (int i = 1; i <= 7; i++) {
      if (i == 4) continue; // Skip center side pocket
      final x = tableW * (i / 8);
      drawDiamond(x, -8);
      drawDiamond(x, tableH + 8);
    }
    // Left and Right sights
    for (int i = 1; i <= 3; i++) {
      if (i == 2) continue; // Skip center
      final y = tableH * (i / 4);
      drawDiamond(-8, y);
      drawDiamond(tableW + 8, y);
    }

    // 5. Draw Table Markings (Headstring line & spots)
    final markPaint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    // Headstring line at x = 0.50 (1/4 table)
    final headstringX = 0.50 * scaleX;
    canvas.drawLine(Offset(headstringX, cushionWidth), Offset(headstringX, tableH - cushionWidth), markPaint);
    // Head spot (0.50, 0.50)
    canvas.drawCircle(Offset(headstringX, tableH * 0.5), 2.5, Paint()..color = const Color(0x55FFFFFF));
    // Foot spot (1.50, 0.50)
    final footSpotX = 1.50 * scaleX;
    canvas.drawCircle(Offset(footSpotX, tableH * 0.5), 3.0, Paint()..color = const Color(0x77FFFFFF));

    // 6. Draw 6 Pockets
    for (final pocket in PoolConstants.pockets) {
      final pPos = toPixel(pocket.x, pocket.y);
      final pRadius = pocket.radius * scaleX;

      // Metallic rim / plate
      final rimPaint = Paint()
        ..color = brassColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(pPos, pRadius + 1.5, rimPaint);

      // Inner drop hole
      final holePaint = Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFF000000), Color(0xFF141416)],
        ).createShader(Rect.fromCircle(center: pPos, radius: pRadius));
      canvas.drawCircle(pPos, pRadius, holePaint);

      // Called pocket pulse highlight
      if (calledPocket == pocket.id) {
        final pulseR = pRadius + 6.0 + 3.0 * math.sin(pocketAnimationProgress * math.pi * 2);
        final glowPaint = Paint()
          ..color = const Color(0xFFFF2D87).withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        canvas.drawCircle(pPos, pulseR, glowPaint);

        // Crosshair reticle
        final reticlePaint = Paint()
          ..color = const Color(0xFFFF2D87)
          ..strokeWidth = 2.0;
        canvas.drawLine(Offset(pPos.dx - 10, pPos.dy), Offset(pPos.dx + 10, pPos.dy), reticlePaint);
        canvas.drawLine(Offset(pPos.dx, pPos.dy - 10), Offset(pPos.dx, pPos.dy + 10), reticlePaint);
      }
    }

    // 7. Aim Ray, Ghost Ball & Deflection Tangents
    if (showAimRay && aimAngle != null && prediction != null) {
      final cueBall = balls.firstWhere(
        (b) => b.id == 0,
        orElse: () => const BallData(id: 0, x: 0.5, y: 0.5),
      );
      final cuePos = cueBallDragPos ?? toPixel(cueBall.x, cueBall.y);
      final ghostPos = toPixel(prediction!.ghostBallX, prediction!.ghostBallY);

      // Dotted aim line from cue to ghost
      final aimLinePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      _drawDashedLine(canvas, cuePos, ghostPos, 5, 4, aimLinePaint);

      // Translucent Ghost Ball circle
      final ghostPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(ghostPos, ballPixelR, ghostPaint);
      canvas.drawCircle(
        ghostPos,
        ballPixelR,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Deflection lines if object ball was targeted
      if (prediction!.hasTarget && prediction!.targetDeflectionAngle != null) {
        final targetAngle = prediction!.targetDeflectionAngle!;
        final targetRayEnd = Offset(
          ghostPos.dx + math.cos(targetAngle) * (ballPixelR * 4.5),
          ghostPos.dy + math.sin(targetAngle) * (ballPixelR * 4.5),
        );
        final targetPaint = Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.9)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        _drawDashedLine(canvas, ghostPos, targetRayEnd, 4, 3, targetPaint);

        // Cue ball tangent deflection
        if (prediction!.cueDeflectionAngle != null) {
          final cueTangent = prediction!.cueDeflectionAngle!;
          final cueRayEnd = Offset(
            ghostPos.dx + math.cos(cueTangent) * (ballPixelR * 2.5),
            ghostPos.dy + math.sin(cueTangent) * (ballPixelR * 2.5),
          );
          final cueTangentPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;
          _drawDashedLine(canvas, ghostPos, cueRayEnd, 3, 3, cueTangentPaint);
        }
      }

      // 8. Cue Stick Rendering
      _drawCueStick(canvas, cuePos, aimAngle!, aimPower, ballPixelR);
    }

    // 9. Draw Balls
    for (final ball in balls) {
      if (ball.pocketed) continue;
      final ballPos = (ball.id == 0 && cueBallDragPos != null) ? cueBallDragPos! : toPixel(ball.x, ball.y);
      _drawBall(canvas, ball, ballPos, ballPixelR);
    }

    // 10. Ball-in-Hand Glow/Indicator
    if (ballInHand) {
      final cueBall = balls.firstWhere(
        (b) => b.id == 0,
        orElse: () => const BallData(id: 0, x: 0.5, y: 0.5),
      );
      final cuePos = cueBallDragPos ?? toPixel(cueBall.x, cueBall.y);
      final pulseR = ballPixelR * (1.6 + 0.2 * math.sin(pocketAnimationProgress * math.pi * 2));
      final handPaint = Paint()
        ..color = const Color(0xFF22C55E).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(cuePos, pulseR, handPaint);
    }
  }

  void _drawBall(Canvas canvas, BallData ball, Offset pos, double r) {
    // 1. Drop shadow on felt
    final shadowPaint = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(pos.translate(1.5, 2.5), r * 0.95, shadowPaint);

    if (ball.id == 0) {
      // Cue Ball (Ivory Stark White with Red Dot indicator for English)
      final cueGrad = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.85,
          colors: const [Color(0xFFFFFFFF), Color(0xFFE2E8F0), Color(0xFF94A3B8)],
        ).createShader(Rect.fromCircle(center: pos, radius: r));
      canvas.drawCircle(pos, r, cueGrad);

      // Red dot for spin
      final dotOffset = Offset(
        pos.dx + (aimSpinX * (r * 0.5)),
        pos.dy + (aimSpinY * (r * 0.5)),
      );
      canvas.drawCircle(dotOffset, math.max(1.8, r * 0.2), Paint()..color = const Color(0xFFEF4444));
      return;
    }

    final isStripe = ball.id >= 9 && ball.id <= 15;
    final primaryColor = ballColors[ball.id] ?? Colors.white;

    if (isStripe) {
      // White base
      final basePaint = Paint()..color = const Color(0xFFF1F5F9);
      canvas.drawCircle(pos, r, basePaint);

      // Colored central horizontal stripe band
      final bandPaint = Paint()..color = primaryColor;
      final stripePath = Path()
        ..addRect(Rect.fromLTWH(pos.dx - r, pos.dy - (r * 0.52), r * 2, r * 1.04));
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: pos, radius: r)));
      canvas.drawPath(stripePath, bandPaint);
      canvas.restore();
    } else {
      // Solid color
      final solidPaint = Paint()..color = primaryColor;
      canvas.drawCircle(pos, r, solidPaint);
    }

    // Number Badge (White circle with number)
    final badgeR = r * 0.44;
    canvas.drawCircle(pos, badgeR, Paint()..color = Colors.white);

    // Number text
    final numText = ball.id.toString();
    final textPainter = TextPainter(
      text: TextSpan(
        text: numText,
        style: TextStyle(
          color: Colors.black,
          fontSize: math.max(7.0, r * 0.65),
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(pos.dx - (textPainter.width / 2), pos.dy - (textPainter.height / 2)),
    );

    // 3D Specular Highlight Glass Shine
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.45),
        radius: 0.6,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: pos, radius: r));
    canvas.drawCircle(pos, r, highlightPaint);
  }

  void _drawCueStick(Canvas canvas, Offset cuePos, double angle, double power, double ballR) {
    // Cue pulls back along the line OPPOSITE to aim direction
    final oppAngle = angle + math.pi;
    final pullBackDist = ballR * 1.5 + (power * ballR * 5.0);

    final tipX = cuePos.dx + math.cos(oppAngle) * pullBackDist;
    final tipY = cuePos.dy + math.sin(oppAngle) * pullBackDist;

    final cueLength = ballR * 14.0;
    final buttX = tipX + math.cos(oppAngle) * cueLength;
    final buttY = tipY + math.sin(oppAngle) * cueLength;

    // Tapered shaft
    final shaftPaint = Paint()
      ..shader = LinearGradient(
        colors: const [
          Color(0xFFFDE68A), // Maple tip
          Color(0xFFD97706), // Mid wood
          Color(0xFF1E293B), // Leather grip butt
        ],
      ).createShader(Rect.fromPoints(Offset(tipX, tipY), Offset(buttX, buttY)))
      ..strokeWidth = math.max(3.0, ballR * 0.35)
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(tipX, tipY), Offset(buttX, buttY), shaftPaint);

    // Tip ferrule
    final ferrulePaint = Paint()
      ..color = const Color(0xFF67E8F9)
      ..strokeWidth = math.max(3.5, ballR * 0.4)
      ..strokeCap = StrokeCap.square;
    final ferruleEnd = Offset(
      tipX + math.cos(oppAngle) * (ballR * 0.3),
      tipY + math.sin(oppAngle) * (ballR * 0.3),
    );
    canvas.drawLine(Offset(tipX, tipY), ferruleEnd, ferrulePaint);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, double dashLen, double gapLen, Paint paint) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalDist = math.sqrt(dx * dx + dy * dy);
    if (totalDist <= 0) return;

    final unitX = dx / totalDist;
    final unitY = dy / totalDist;

    double currentDist = 0.0;
    while (currentDist < totalDist) {
      final segLen = math.min(dashLen, totalDist - currentDist);
      final start = Offset(p1.dx + unitX * currentDist, p1.dy + unitY * currentDist);
      final end = Offset(p1.dx + unitX * (currentDist + segLen), p1.dy + unitY * (currentDist + segLen));
      canvas.drawLine(start, end, paint);
      currentDist += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant PoolTablePainter old) {
    return old.balls != balls ||
        old.aimAngle != aimAngle ||
        old.aimPower != aimPower ||
        old.aimSpinX != aimSpinX ||
        old.aimSpinY != aimSpinY ||
        old.showAimRay != showAimRay ||
        old.prediction != prediction ||
        old.calledPocket != calledPocket ||
        old.ballInHand != ballInHand ||
        old.cueBallDragging != cueBallDragging ||
        old.cueBallDragPos != cueBallDragPos ||
        old.pocketAnimationProgress != pocketAnimationProgress;
  }
}
