import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../controllers/video_color_timeline_controller.dart';
import '../models/video_color_models.dart';

/// Modal dialog for configuring hardware-accelerated local export or Cloud Run GPU render.
class VideoExportDialog extends ConsumerStatefulWidget {
  const VideoExportDialog({super.key});

  @override
  ConsumerState<VideoExportDialog> createState() => _VideoExportDialogState();
}

class _VideoExportDialogState extends ConsumerState<VideoExportDialog> {
  int _selectedWidth = 1920;
  int _selectedHeight = 1080;
  double _selectedFps = 30.0;
  int _selectedBitDepth = 8;
  bool _isHdr = false;
  String _videoCodec = 'hevc';
  bool _useCloudRender = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(videoColorTimelineControllerProvider).exportConfig;
    _selectedWidth = cfg.width;
    _selectedHeight = cfg.height;
    _selectedFps = cfg.fps;
    _selectedBitDepth = cfg.bitDepth;
    _isHdr = cfg.isHdr;
    _videoCodec = cfg.videoCodec;
    _useCloudRender = cfg.useCloudRender;
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

    final activeJob = state.activeRenderJob;
    final isRendering = activeJob != null && activeJob.isRunning;

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 540),
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
                  child: const Icon(Icons.video_settings_rounded, size: 20, color: AppColors.brandBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Video Export & Hardware Render',
                        style: GoogleFonts.inter(fontSize: 16.0, fontWeight: FontWeight.w700, color: textPrimary),
                      ),
                      Text(
                        'Native Media3 / AVFoundation / Cloud GPU',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: isRendering ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),

            // Settings Fields
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resolution Selector
                    Text('Resolution', style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600, color: textMuted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildChoiceChip('1080p FHD', _selectedHeight == 1080, () {
                          setState(() {
                            _selectedWidth = 1920;
                            _selectedHeight = 1080;
                          });
                        }),
                        _buildChoiceChip('4K UHD', _selectedHeight == 2160, () {
                          setState(() {
                            _selectedWidth = 3840;
                            _selectedHeight = 2160;
                          });
                        }),
                        _buildChoiceChip('720p HD', _selectedHeight == 720, () {
                          setState(() {
                            _selectedWidth = 1280;
                            _selectedHeight = 720;
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Frame Rate Selector
                    Text('Frame Rate', style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600, color: textMuted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildChoiceChip('24 fps (Cinema)', _selectedFps == 24.0, () => setState(() => _selectedFps = 24.0)),
                        _buildChoiceChip('30 fps', _selectedFps == 30.0, () => setState(() => _selectedFps = 30.0)),
                        _buildChoiceChip('60 fps (Smooth)', _selectedFps == 60.0, () => setState(() => _selectedFps = 60.0)),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Color Depth & HDR
                    Text('Color Fidelity & HDR', style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600, color: textMuted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildChoiceChip('8-Bit Rec.709', _selectedBitDepth == 8 && !_isHdr, () {
                          setState(() {
                            _selectedBitDepth = 8;
                            _isHdr = false;
                          });
                        }),
                        _buildChoiceChip('10-Bit HDR (HLG/PQ)', _selectedBitDepth == 10 && _isHdr, () {
                          setState(() {
                            _selectedBitDepth = 10;
                            _isHdr = true;
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Compute Target: Local vs Cloud Render
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Offload to Cloud Run GPU', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      subtitle: Text('Recommended for long 4K timelines or weak phones to keep device cool', style: GoogleFonts.inter(fontSize: 11.0, color: textMuted)),
                      value: _useCloudRender,
                      activeThumbColor: AppColors.brandBlue,
                      onChanged: (val) => setState(() => _useCloudRender = val),
                    ),
                  ],
                ),
              ),
            ),

            // Progress Section
            if (activeJob != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: activeJob.progress > 0 ? activeJob.progress : null,
                backgroundColor: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Text(
                '${activeJob.status.name.toUpperCase()} • ${(activeJob.progress * 100).toInt()}% • ETA ${activeJob.estimatedSecondsRemaining}s',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11.0, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
              ),
              const SizedBox(height: 12),
            ],

            // Action Buttons
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              icon: const Icon(Icons.file_download_rounded, size: 18),
              label: Text(
                isRendering ? 'Rendering in Progress...' : 'Start Hardware Export',
                style: GoogleFonts.inter(fontSize: 13.0, fontWeight: FontWeight.w700),
              ),
              onPressed: isRendering
                  ? null
                  : () async {
                      HapticFeedback.heavyImpact();
                      controller.updateExportConfig(
                        VideoExportConfig(
                          width: _selectedWidth,
                          height: _selectedHeight,
                          fps: _selectedFps,
                          bitDepth: _selectedBitDepth,
                          isHdr: _isHdr,
                          videoCodec: _videoCodec,
                          useCloudRender: _useCloudRender,
                        ),
                      );
                      await controller.startExport();
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceChip(String label, bool isSelected, VoidCallback onSelected) {
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 11.0, fontWeight: FontWeight.w600)),
      selected: isSelected,
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onSelected();
      },
      selectedColor: AppColors.brandBlue,
    );
  }
}
