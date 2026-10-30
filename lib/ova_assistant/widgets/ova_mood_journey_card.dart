import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../memory/ova_memory_models.dart';

/// Executive visual card displaying live user emotional resonance and mood journey charts.
/// High-density iOS/Linear executive design supporting both Light and Dark themes.
class OvaMoodJourneyCard extends StatelessWidget {
  final List<OvaEmotionSnapshot> snapshots;
  final OvaEmotionSnapshot? currentEmotion;
  final VoidCallback? onRefresh;

  const OvaMoodJourneyCard({
    super.key,
    required this.snapshots,
    this.currentEmotion,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final active = currentEmotion ??
        (snapshots.isNotEmpty
            ? snapshots.last
            : OvaEmotionSnapshot(
                valence: OvaEmotionValence.creativeFlow,
                intensity: 0.88,
                primaryEmotionLabel: 'Creative Flow',
                toneGuidance: 'High velocity ideation and clear direction',
                timestamp: DateTime.now(),
              ));

    final accentColor = switch (active.valence) {
      OvaEmotionValence.excited => AppColors.brandPink,
      OvaEmotionValence.creativeFlow => AppColors.brandBlue,
      OvaEmotionValence.focused => const Color(0xFF6366F1), // Indigo
      OvaEmotionValence.frustrated => const Color(0xFFF59E0B), // Amber
      OvaEmotionValence.reflective => const Color(0xFF10B981), // Emerald
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Live Resonance Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.0),
                    ),
                    child: Icon(Icons.favorite_rounded, color: accentColor, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'EMOTIONAL RESONANCE',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(active.intensity * 100).toInt()}% • ${active.primaryEmotionLabel}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tone & Guidance Note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.brandPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.toneGuidance,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Visual Timeline Chart (Mood wave)
          Text(
            'SESSION MOOD ARC',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: CustomPaint(
              size: const Size(double.infinity, 48),
              painter: _MoodArcPainter(
                snapshots: snapshots.isNotEmpty
                    ? snapshots
                    : [
                        OvaEmotionSnapshot(
                          valence: OvaEmotionValence.reflective,
                          intensity: 0.7,
                          primaryEmotionLabel: 'Reflective',
                          toneGuidance: '',
                          timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
                        ),
                        OvaEmotionSnapshot(
                          valence: OvaEmotionValence.focused,
                          intensity: 0.8,
                          primaryEmotionLabel: 'Focused',
                          toneGuidance: '',
                          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
                        ),
                        active,
                      ],
                lineColor: accentColor,
                fillColor: accentColor.withValues(alpha: 0.12),
                gridColor: context.border,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Audience Resonance Multi-Segment Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AUDIENCE SENTIMENT PROJECTION',
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: context.textMuted,
                ),
              ),
              Text(
                '96% Positive',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(flex: 48, child: Container(color: AppColors.brandBlue)),
                  const SizedBox(width: 1),
                  Expanded(flex: 32, child: Container(color: AppColors.brandPink)),
                  const SizedBox(width: 1),
                  Expanded(flex: 20, child: Container(color: const Color(0xFF10B981))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLegend(AppColors.brandBlue, 'Inspired 48%'),
              _buildLegend(AppColors.brandPink, 'Entertained 32%'),
              _buildLegend(const Color(0xFF10B981), 'Engaged 20%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey),
        ),
      ],
    );
  }
}

class _MoodArcPainter extends CustomPainter {
  final List<OvaEmotionSnapshot> snapshots;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  _MoodArcPainter({
    required this.snapshots,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Draw reference dashed baseline
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final count = snapshots.length;
    final stepX = size.width / (count > 1 ? count - 1 : 1);

    for (int i = 0; i < count; i++) {
      final snap = snapshots[i];
      final x = i * stepX;
      // map intensity 0.0-1.0 to y
      final y = size.height - (snap.intensity * (size.height - 8)) - 4;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevSnap = snapshots[i - 1];
        final prevY = size.height - (prevSnap.intensity * (size.height - 8)) - 4;
        final controlX = (prevX + x) / 2;

        path.cubicTo(controlX, prevY, controlX, y, x, y);
        fillPath.cubicTo(controlX, prevY, controlX, y, x, y);
      }

      if (i == count - 1) {
        fillPath.lineTo(x, size.height);
        fillPath.close();
      }
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Draw current end dot
    final lastSnap = snapshots.last;
    final lastX = size.width;
    final lastY = size.height - (lastSnap.intensity * (size.height - 8)) - 4;

    canvas.drawCircle(Offset(lastX, lastY), 3.5, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _MoodArcPainter oldDelegate) => true;
}
