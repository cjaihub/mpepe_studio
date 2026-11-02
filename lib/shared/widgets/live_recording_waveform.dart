import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Scrolling live waveform drawn from real microphone levels (0..1), newest
/// on the right, like WhatsApp's recording strip. Feed it a rolling list of
/// recent levels; it repaints whenever the list changes.
class LiveRecordingWaveform extends StatelessWidget {
  final List<double> levels;
  final double height;
  final bool paused;
  final Color color;
  final Color peakColor;
  final double barWidth;
  final double gap;

  const LiveRecordingWaveform({
    super.key,
    required this.levels,
    this.height = 20,
    this.paused = false,
    this.color = AppColors.brandBlue,
    this.peakColor = AppColors.brandPink,
    this.barWidth = 2.0,
    this.gap = 1.8,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _WavePainter(
          levels: levels,
          paused: paused,
          color: color,
          peak: peakColor,
          idle: context.textMuted.withValues(alpha: 0.35),
          barWidth: barWidth,
          gap: gap,
          version: levels.length + (levels.isEmpty ? 0 : (levels.last * 1000).round()),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> levels;
  final bool paused;
  final Color color;
  final Color peak;
  final Color idle;
  final double barWidth;
  final double gap;
  final int version;

  _WavePainter({
    required this.levels,
    required this.paused,
    required this.color,
    required this.peak,
    required this.idle,
    required this.barWidth,
    required this.gap,
    required this.version,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final step = barWidth + gap;
    final slots = (size.width / step).floor();
    if (slots <= 0) return;
    final mid = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    final visible = levels.length > slots ? levels.sublist(levels.length - slots) : levels;
    final offset = slots - visible.length;

    for (var i = 0; i < slots; i++) {
      final x = size.width - (slots - i) * step + barWidth / 2;
      final li = i - offset;
      if (li < 0) {
        // Not recorded yet: faint dots so the strip reads as a timeline.
        paint.color = idle;
        canvas.drawLine(Offset(x, mid - 1), Offset(x, mid + 1), paint);
        continue;
      }
      final v = visible[li].clamp(0.0, 1.0);
      final h = math.max(2.0, v * size.height * 0.95);
      final fade = 0.45 + 0.55 * (li / math.max(1, visible.length - 1));
      final base = Color.lerp(color, peak, v > 0.7 ? (v - 0.7) / 0.3 : 0)!;
      paint.color = (paused ? idle : base).withValues(alpha: paused ? 0.6 : fade);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.version != version || old.paused != paused || old.color != color;
}

/// Converts a recorder amplitude in dBFS (about -60 quiet … 0 loud) to 0..1
/// with a gentle curve so normal speech fills the strip.
double levelFromDb(double db) {
  if (db.isNaN || db.isInfinite) return 0.05;
  final n = ((db + 55) / 55).clamp(0.0, 1.0);
  return math.pow(n, 1.6).toDouble().clamp(0.05, 1.0);
}

/// Downsamples a full recording's levels to [count] bars for the sent
/// message's waveform preview.
List<double> downsampleLevels(List<double> all, int count) {
  if (all.isEmpty) return const [];
  if (all.length <= count) return List<double>.from(all);
  final out = <double>[];
  final per = all.length / count;
  for (var i = 0; i < count; i++) {
    final start = (i * per).floor();
    final end = math.min(all.length, ((i + 1) * per).ceil());
    var peak = 0.0;
    for (var j = start; j < end; j++) {
      if (all[j] > peak) peak = all[j];
    }
    out.add(peak);
  }
  return out;
}
