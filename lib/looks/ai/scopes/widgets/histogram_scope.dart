import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/theme/app_theme.dart';
import '../models/scope_frame_data.dart';

/// Professional RGB & Luma Histogram scope displaying tonal distribution.
class HistogramScope extends StatelessWidget {
  final ScopeFrameData data;
  final double height;
  final double width;

  const HistogramScope({
    super.key,
    required this.data,
    this.height = 100,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF09090C),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: Colors.white12, width: 1.0),
      ),
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _HistogramPainter(data: data),
          ),
          Positioned(
            left: 4,
            top: 2,
            child: Text(
              'HISTOGRAM (RGB + LUMA)',
              style: GoogleFonts.firaCode(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 2,
            child: Text(
              'CLIPPING: ${data.highlightClippingPercent.toStringAsFixed(1)}%',
              style: GoogleFonts.firaCode(
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                color: data.highlightClippingPercent > 1.0 ? AppColors.brandPink : Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final ScopeFrameData data;

  _HistogramPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final stepX = size.width / 256.0;

    // Draw Luma (gray fill)
    final lumaPath = Path()..moveTo(0, size.height);
    for (int i = 0; i < 256; i++) {
      final y = size.height * (1.0 - (data.lumaHistogram[i] * 0.85).clamp(0.0, 1.0));
      lumaPath.lineTo(i * stepX, y);
    }
    lumaPath.lineTo(size.width, size.height);
    lumaPath.close();

    final lumaPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(lumaPath, lumaPaint);

    // Draw Red curve
    _drawCurve(canvas, size, data.redHistogram, const Color(0xFFFF3B30).withValues(alpha: 0.65), stepX);
    // Draw Green curve
    _drawCurve(canvas, size, data.greenHistogram, const Color(0xFF34C759).withValues(alpha: 0.65), stepX);
    // Draw Blue curve
    _drawCurve(canvas, size, data.blueHistogram, const Color(0xFF007AFF).withValues(alpha: 0.65), stepX);
  }

  void _drawCurve(Canvas canvas, Size size, List<double> bins, Color color, double stepX) {
    final path = Path();
    for (int i = 0; i < 256; i++) {
      final x = i * stepX;
      final y = size.height * (1.0 - (bins[i] * 0.9).clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) => true;
}
