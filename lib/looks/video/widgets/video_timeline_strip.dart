import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/video_color_models.dart';

/// Professional timeline strip rendering per-clip color grades, adjustment layers,
/// keyframe diamonds, and interactive scrub playhead.
class VideoTimelineStrip extends StatelessWidget {
  final List<ClipColorGrade> clips;
  final String? activeClipId;
  final List<AdjustmentLayerGrade> adjustmentLayers;
  final double playheadSeconds;
  final double totalDurationSeconds;
  final ValueChanged<String> onClipSelected;
  final ValueChanged<double> onPlayheadChanged;

  const VideoTimelineStrip({
    super.key,
    required this.clips,
    required this.activeClipId,
    this.adjustmentLayers = const [],
    required this.playheadSeconds,
    this.totalDurationSeconds = 16.0,
    required this.onClipSelected,
    required this.onPlayheadChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 1.0),
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Header / Timecode
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TIMELINE COLOR STRIP',
                style: GoogleFonts.inter(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: textMuted,
                ),
              ),
              Text(
                '${playheadSeconds.toStringAsFixed(2)}s / ${totalDurationSeconds.toStringAsFixed(1)}s',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Interactive Timeline Tracks Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                final secToPx = trackWidth / totalDurationSeconds;

                return GestureDetector(
                  onPanDown: (details) => _updatePlayheadFromDx(details.localPosition.dx, secToPx),
                  onPanUpdate: (details) => _updatePlayheadFromDx(details.localPosition.dx, secToPx),
                  child: Stack(
                    children: [
                      // Clip Tracks
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 52,
                        child: Row(
                          children: clips.map((clip) {
                            final isSelected = clip.clipId == activeClipId;
                            final clipWidth = (clip.durationSeconds * secToPx).clamp(40.0, trackWidth);

                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onClipSelected(clip.clipId);
                              },
                              child: Container(
                                width: clipWidth,
                                height: 52,
                                margin: const EdgeInsets.only(right: 2.0),
                                padding: const EdgeInsets.all(4.0),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.brandBlue.withValues(alpha: 0.25)
                                      : (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(
                                    color: isSelected ? AppColors.brandBlue : borderColor,
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.movie_outlined,
                                          size: 11,
                                          color: isSelected ? AppColors.brandBlue : textMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            clip.clipName,
                                            style: GoogleFonts.inter(
                                              fontSize: 9.5,
                                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                              color: textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.brandPink.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              clip.baseLook.name,
                                              style: GoogleFonts.inter(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.brandPink,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        if (clip.hasKeyframes) ...[
                                          const SizedBox(width: 2),
                                          const Icon(Icons.diamond_rounded, size: 10, color: Colors.amberAccent),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      // Adjustment Layer Track
                      if (adjustmentLayers.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: 16,
                          child: Stack(
                            children: adjustmentLayers.map((adj) {
                              final startPx = adj.startTimeSeconds * secToPx;
                              final widthPx = adj.durationSeconds * secToPx;
                              return Positioned(
                                left: startPx,
                                width: widthPx,
                                height: 14,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(3.0),
                                    border: Border.all(color: Colors.purpleAccent, width: 1.0),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'ADJ: ${adj.name}',
                                    style: GoogleFonts.inter(
                                      fontSize: 8.0,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      // Playhead Cursor
                      Positioned(
                        left: (playheadSeconds * secToPx).clamp(0.0, trackWidth - 2.0),
                        top: 0,
                        bottom: 0,
                        width: 2.0,
                        child: Container(
                          color: AppColors.brandPink,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.brandPink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _updatePlayheadFromDx(double dx, double secToPx) {
    if (secToPx <= 0) return;
    final targetSec = (dx / secToPx).clamp(0.0, totalDurationSeconds);
    onPlayheadChanged(targetSec);
  }
}
