import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../shared/theme/app_theme.dart';

class CoverPickerSheet extends StatefulWidget {
  final String mediaPath;
  final bool isVideo;
  final int initialCoverTimeMs;
  final String? initialCustomImagePath;
  final int? recommendedTimeMs;
  final Function(int coverTimeMs, String? customImagePath) onCoverSelected;

  const CoverPickerSheet({
    super.key,
    required this.mediaPath,
    required this.isVideo,
    this.initialCoverTimeMs = 0,
    this.initialCustomImagePath,
    this.recommendedTimeMs,
    required this.onCoverSelected,
  });

  @override
  State<CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverPickerSheetState extends State<CoverPickerSheet> {
  Player? _player;
  VideoController? _videoController;
  late int _selectedTimeMs;
  String? _customImagePath;
  int _totalDurationMs = 5000;

  @override
  void initState() {
    super.initState();
    _selectedTimeMs = widget.initialCoverTimeMs;
    _customImagePath = widget.initialCustomImagePath;

    if (widget.isVideo) {
      _player = Player();
      _videoController = VideoController(_player!);
      _player!.open(Media(widget.mediaPath), play: false);
      _player!.stream.duration.listen((d) {
        if (mounted && d.inMilliseconds > 0) {
          setState(() => _totalDurationMs = d.inMilliseconds);
        }
      });
      if (_selectedTimeMs > 0) {
        _player!.seek(Duration(milliseconds: _selectedTimeMs));
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 1920,
    );
    if (picked != null && mounted) {
      setState(() {
        _customImagePath = picked.path;
      });
    }
  }

  void _seekTo(int ms) {
    setState(() {
      _selectedTimeMs = ms.clamp(0, _totalDurationMs);
      _customImagePath = null; // Clear custom image if scrubbed
    });
    _player?.seek(Duration(milliseconds: _selectedTimeMs));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            children: [
              Text(
                'Select Cover Frame',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onCoverSelected(_selectedTimeMs, _customImagePath);
                  Navigator.pop(context);
                },
                child: Text(
                  'Done',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preview Area
          Center(
            child: Container(
              width: 140,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.brandBlue, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_customImagePath != null)
                    Image.file(File(_customImagePath!), fit: BoxFit.cover)
                  else if (_videoController != null)
                    Video(controller: _videoController!, controls: NoVideoControls)
                  else
                    Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        _customImagePath != null
                            ? 'Custom Image'
                            : '${(_selectedTimeMs / 1000.0).toStringAsFixed(1)}s',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Frame Scrubber (Video Only)
          if (widget.isVideo) ...[
            Text(
              'SCRUB VIDEO TIMELINE',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: context.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.brandBlue,
                inactiveTrackColor: context.surfaceMid,
                thumbColor: AppColors.brandPink,
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _selectedTimeMs.toDouble().clamp(0.0, _totalDurationMs.toDouble()),
                min: 0.0,
                max: _totalDurationMs > 0 ? _totalDurationMs.toDouble() : 5000.0,
                onChanged: (val) => _seekTo(val.toInt()),
              ),
            ),

            // Quick Jump Suggestions
            Row(
              children: [
                if (widget.recommendedTimeMs != null) ...[
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.brandPink.withValues(alpha: 0.12),
                    side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.4)),
                    avatar: const Icon(Icons.auto_awesome, size: 12, color: AppColors.brandPink),
                    label: Text(
                      'AI Pick (${(widget.recommendedTimeMs! / 1000).toStringAsFixed(1)}s)',
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brandPink),
                    ),
                    onPressed: () => _seekTo(widget.recommendedTimeMs!),
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: context.surfaceMid,
                  side: BorderSide(color: context.border),
                  label: Text('0.0s', style: GoogleFonts.inter(fontSize: 10.5, color: context.textPrimary)),
                  onPressed: () => _seekTo(0),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: context.surfaceMid,
                  side: BorderSide(color: context.border),
                  label: Text('1.5s', style: GoogleFonts.inter(fontSize: 10.5, color: context.textPrimary)),
                  onPressed: () => _seekTo(1500),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: context.surfaceMid,
                  side: BorderSide(color: context.border),
                  label: Text('3.0s', style: GoogleFonts.inter(fontSize: 10.5, color: context.textPrimary)),
                  onPressed: () => _seekTo(3000),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Upload Custom Image Button
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(
                'Upload From Device Gallery',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: _pickFromGallery,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.textPrimary,
                side: BorderSide(color: context.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
