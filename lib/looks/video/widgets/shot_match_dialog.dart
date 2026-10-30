import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../controllers/video_color_timeline_controller.dart';
import '../models/video_color_models.dart';

/// Modal dialog for performing AI color shot matching across timeline clips.
class ShotMatchDialog extends ConsumerStatefulWidget {
  const ShotMatchDialog({super.key});

  @override
  ConsumerState<ShotMatchDialog> createState() => _ShotMatchDialogState();
}

class _ShotMatchDialogState extends ConsumerState<ShotMatchDialog> {
  late String _selectedRefClipId;
  late String _selectedTargetClipId;
  ShotMatchResult? _result;

  @override
  void initState() {
    super.initState();
    final clips = ref.read(videoColorTimelineControllerProvider).clips;
    _selectedRefClipId = clips.isNotEmpty ? clips.first.clipId : '';
    _selectedTargetClipId = clips.length > 1 ? clips[1].clipId : (clips.isNotEmpty ? clips.first.clipId : '');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoColorTimelineControllerProvider);
    final controller = ref.read(videoColorTimelineControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: const Icon(Icons.compare_arrows_rounded, size: 20, color: AppColors.brandBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Shot Matcher',
                        style: GoogleFonts.inter(fontSize: 16.0, fontWeight: FontWeight.w700, color: textPrimary),
                      ),
                      Text(
                        'Harmonize color, exposure & skin tones across cuts',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),

            // Selectors for Reference and Target Clip
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reference Clip', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: textMuted)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedRefClipId,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                        ),
                        items: state.clips.map((c) {
                          return DropdownMenuItem(
                            value: c.clipId,
                            child: Text(c.clipName, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedRefClipId = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Target Clip', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: textMuted)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedTargetClipId,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                        ),
                        items: state.clips.map((c) {
                          return DropdownMenuItem(
                            value: c.clipId,
                            child: Text(c.clipName, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedTargetClipId = val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Computed Match Details Card
            Expanded(
              child: _result == null
                  ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: borderColor, width: 1.0),
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 36, color: AppColors.brandPink),
                          const SizedBox(height: 8),
                          Text('Ready to Calculate Match', style: GoogleFonts.inter(fontSize: 13.0, fontWeight: FontWeight.w600, color: textPrimary)),
                          const SizedBox(height: 4),
                          Text('Tap "Analyze & Match" to compute mathematical alignment', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11.5, color: textMuted)),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 1.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Alignment Telemetry',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandBlue,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${(_result!.confidenceScore * 100).toInt()}% Match',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          _buildDeltaRow('Exposure Offset', '${_result!.exposureOffset > 0 ? "+" : ""}${_result!.exposureOffset.toStringAsFixed(2)} EV', textPrimary, textMuted),
                          _buildDeltaRow('Temperature Shift', '${_result!.temperatureDelta > 0 ? "+" : ""}${_result!.temperatureDelta.toStringAsFixed(1)}K', textPrimary, textMuted),
                          _buildDeltaRow('Tint Shift', '${_result!.tintDelta > 0 ? "+" : ""}${_result!.tintDelta.toStringAsFixed(1)}', textPrimary, textMuted),
                          _buildDeltaRow('Saturation Scale', '${(_result!.saturationRatio * 100).toInt()}%', textPrimary, textMuted),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: borderColor, width: 1.0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                    icon: const Icon(Icons.analytics_outlined, size: 18),
                    label: Text('Analyze & Match', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      final match = controller.matchShots(
                        referenceClipId: _selectedRefClipId,
                        targetClipId: _selectedTargetClipId,
                      );
                      setState(() => _result = match);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Apply Match', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    onPressed: _result != null
                        ? () {
                            HapticFeedback.heavyImpact();
                            controller.applyShotMatchResult();
                            Navigator.of(context).pop();
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeltaRow(String label, String value, Color primary, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: muted)),
          Text(value, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: primary)),
        ],
      ),
    );
  }
}
