import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/theme/app_theme.dart';
import '../models/scope_frame_data.dart';

/// Professional GPU Waveform Monitor rendering 0..100 IRE luma distribution.
class WaveformScope extends StatelessWidget {
  final ScopeFrameData data;
  final double height;
  final double width;

  const WaveformScope({
    super.key,
    required this.data,
    this.height = 120,
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
            painter: _WaveformPainter(data: data),
          ),
          Positioned(
            left: 4,
            top: 2,
            child: Text(
              'WAVEFORM (100 IRE)',
              style: GoogleFonts.firaCode(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
              ),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 2,
            child: Text(
              '0 IRE',
              style: GoogleFonts.firaCode(
                fontSize: 8,
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

class _WaveformPainter extends CustomPainter {
  final ScopeFrameData data;

  _WaveformPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final graticulePaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Draw horizontal IRE graticule lines (0, 25, 50, 75, 100 IRE)
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (1.0 - (i / 4.0));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), graticulePaint);
    }

    final phosphorPaint = Paint()
      ..color = const Color(0xFF00FF88).withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final clipHighPaint = Paint()
      ..color = AppColors.brandPink
      ..strokeWidth = 1.5;

    final columns = data.waveformColumns;
    if (columns.isEmpty) return;

    final colWidth = size.width / columns.length;

    for (int c = 0; c < columns.length; c++) {
      final col = columns[c];
      final x = c * colWidth + colWidth / 2.0;

      for (int r = 0; r < col.length; r++) {
        final intensity = col[r];
        if (intensity <= 0.05) continue;

        final normalizedIre = r / (col.length - 1).toDouble();
        final y = size.height * (1.0 - normalizedIre);

        // Highlight clipped points
        if (normalizedIre >= 0.95 && data.highlightClippingPercent > 1.0) {
          canvas.drawCircle(Offset(x, y), 0.8, clipHighPaint);
        } else {
          canvas.drawCircle(
            Offset(x, y),
            0.6,
            phosphorPaint..color = const Color(0xFF00FF88).withValues(alpha: (intensity * 0.7).clamp(0.1, 0.9)),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}
