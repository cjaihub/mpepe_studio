import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/theme/app_theme.dart';
import '../models/scope_frame_data.dart';

/// Professional RGB Parade Scope displaying Red, Green, and Blue channel distributions side-by-side.
class RgbParadeScope extends StatelessWidget {
  final ScopeFrameData data;
  final double height;
  final double width;

  const RgbParadeScope({
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
            painter: _RgbParadePainter(data: data),
          ),
          Positioned(
            left: 4,
            top: 2,
            child: Row(
              children: [
                Text('R', style: GoogleFonts.firaCode(fontSize: 8, fontWeight: FontWeight.w800, color: const Color(0xFFFF4D4D))),
                const SizedBox(width: 24),
                Text('G', style: GoogleFonts.firaCode(fontSize: 8, fontWeight: FontWeight.w800, color: const Color(0xFF00E676))),
                const SizedBox(width: 24),
                Text('B', style: GoogleFonts.firaCode(fontSize: 8, fontWeight: FontWeight.w800, color: const Color(0xFF2979FF))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RgbParadePainter extends CustomPainter {
  final ScopeFrameData data;

  _RgbParadePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final graticulePaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.5;

    // Horizontal IRE markers
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (1.0 - (i / 4.0));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), graticulePaint);
    }

    final paneWidth = size.width / 3.0;

    // Vertical dividers between channels
    canvas.drawLine(Offset(paneWidth, 0), Offset(paneWidth, size.height), graticulePaint);
    canvas.drawLine(Offset(paneWidth * 2, 0), Offset(paneWidth * 2, size.height), graticulePaint);

    final cols = data.waveformColumns;
    if (cols.isEmpty) return;

    final subCols = cols.length ~/ 3;

    // Red Channel (Left pane)
    _drawChannel(
      canvas: canvas,
      offsetX: 0,
      width: paneWidth,
      color: const Color(0xFFFF3B30),
      dataHist: data.redHistogram,
      subCols: subCols,
    );

    // Green Channel (Center pane)
    _drawChannel(
      canvas: canvas,
      offsetX: paneWidth,
      width: paneWidth,
      color: const Color(0xFF34C759),
      dataHist: data.greenHistogram,
      subCols: subCols,
    );

    // Blue Channel (Right pane)
    _drawChannel(
      canvas: canvas,
      offsetX: paneWidth * 2,
      width: paneWidth,
      color: const Color(0xFF007AFF),
      dataHist: data.blueHistogram,
      subCols: subCols,
    );
  }

  void _drawChannel({
    required Canvas canvas,
    required double offsetX,
    required double width,
    required Color color,
    required List<double> dataHist,
    required int subCols,
  }) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    final stepX = width / dataHist.length;
    for (int i = 0; i < dataHist.length; i += 2) {
      final intensity = dataHist[i];
      if (intensity < 0.05) continue;
      final x = offsetX + i * stepX;
      final y = (1.0 - intensity) * 110;
      canvas.drawCircle(Offset(x, y), 0.7, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RgbParadePainter oldDelegate) => true;
}
