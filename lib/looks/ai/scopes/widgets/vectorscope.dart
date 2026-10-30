import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/scope_frame_data.dart';

/// Professional Vectorscope monitor with calibrated Skin-Tone indicator line (57° I-Line)
/// and primary/secondary chroma alignment targets (R, Mg, B, Cy, G, Yl).
class Vectorscope extends StatelessWidget {
  final ScopeFrameData data;
  final double size;

  const Vectorscope({
    super.key,
    required this.data,
    this.size = 140,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF09090C),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12, width: 1.0),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _VectorscopePainter(data: data),
          ),
          Positioned(
            top: 6,
            child: Text(
              'VECTORSCOPE',
              style: GoogleFonts.firaCode(
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VectorscopePainter extends CustomPainter {
  final ScopeFrameData data;

  _VectorscopePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final radius = (size.width / 2.0) - 10.0;

    final ringPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw reference rings (50% and 75% saturation boundaries)
    canvas.drawCircle(center, radius * 0.5, ringPaint);
    canvas.drawCircle(center, radius * 0.75, ringPaint);
    canvas.drawCircle(center, radius, ringPaint);

    // Crosshairs
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), ringPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), ringPaint);

    // ── Skin Tone Reference Line (I-Line at 57°) ──
    final skinLinePaint = Paint()
      ..color = const Color(0xFFFFB300)
      ..strokeWidth = 1.0;

    const skinAngleRad = ScopeFrameData.skinToneTargetAngle * (math.pi / 180.0);
    final skinTargetEnd = Offset(
      center.dx + radius * math.cos(skinAngleRad),
      center.dy - radius * math.sin(skinAngleRad),
    );
    canvas.drawLine(center, skinTargetEnd, skinLinePaint);

    // Draw primary & secondary target boxes
    _drawTarget(canvas, center, radius * 0.75, 103, 'R', const Color(0xFFFF3B30));
    _drawTarget(canvas, center, radius * 0.75, 60, 'Mg', const Color(0xFFFF2D87));
    _drawTarget(canvas, center, radius * 0.75, 347, 'B', const Color(0xFF007AFF));
    _drawTarget(canvas, center, radius * 0.75, 283, 'Cy', const Color(0xFF00F2FE));
    _drawTarget(canvas, center, radius * 0.75, 240, 'G', const Color(0xFF34C759));
    _drawTarget(canvas, center, radius * 0.75, 167, 'Yl', const Color(0xFFFFCC00));

    // Draw Chroma Cloud from vectorscope bins
    final chromaPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.65)
      ..strokeWidth = 1.2;

    final bins = data.vectorscopeHueBins;
    for (int i = 0; i < bins.length; i++) {
      final amp = bins[i];
      if (amp <= 0.05) continue;
      final rad = (i * 10.0) * (math.pi / 180.0);
      final r = radius * amp.clamp(0.1, 0.95);
      final pt = Offset(
        center.dx + r * math.cos(rad),
        center.dy - r * math.sin(rad),
      );
      canvas.drawCircle(pt, 1.2, chromaPaint);
    }
  }

  void _drawTarget(Canvas canvas, Offset center, double dist, double deg, String label, Color color) {
    final rad = deg * (math.pi / 180.0);
    final pt = Offset(center.dx + dist * math.cos(rad), center.dy - dist * math.sin(rad));
    final boxPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRect(Rect.fromCenter(center: pt, width: 6, height: 6), boxPaint);
  }

  @override
  bool shouldRepaint(covariant _VectorscopePainter oldDelegate) => true;
}
