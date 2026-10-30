import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../../shared/theme/app_theme.dart';

/// Insta Edits / CapCut style Exporting Indicator Panel
/// Displays a high-tech export progress indicator before proceeding to post or saving to device.
class ExportingProgressSheet extends StatefulWidget {
  final String mediaPath;
  final bool isVideo;
  final String title;
  final VoidCallback onProceedToPost;

  const ExportingProgressSheet({
    super.key,
    required this.mediaPath,
    required this.isVideo,
    this.title = 'Oneova Reel Master',
    required this.onProceedToPost,
  });

  /// Static helper to display the sheet modally with frosted glass background
  static Future<void> show({
    required BuildContext context,
    required String mediaPath,
    required bool isVideo,
    String title = 'Oneova Reel Master',
    required VoidCallback onProceedToPost,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => ExportingProgressSheet(
        mediaPath: mediaPath,
        isVideo: isVideo,
        title: title,
        onProceedToPost: onProceedToPost,
      ),
    );
  }

  @override
  State<ExportingProgressSheet> createState() => _ExportingProgressSheetState();
}

class _ExportingProgressSheetState extends State<ExportingProgressSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _progressAnim;

  double _currentProgress = 0.0;
  bool _isExportComplete = false;
  bool _isSavingToDevice = false;
  bool _savedSuccess = false;

  Timer? _tickerTimer;
  String _currentStage = 'Reading file…';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _progressAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutCubic,
    );

    _animController.addListener(() {
      setState(() {
        _currentProgress = _progressAnim.value;
        _updateStageText(_currentProgress);
      });
    });

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isExportComplete = true;
          _currentProgress = 1.0;
          _currentStage = 'Master Asset Ready!';
        });
        HapticFeedback.lightImpact();
      }
    });

    _readSpecs();
  }

  // Real facts about the file being posted (this sheet does not re-encode).
  String _format = '';
  String _resolution = '—';
  String _frameRate = '—';
  String _size = '—';
  String _specLine = '';

  Future<void> _readSpecs() async {
    final file = File(widget.mediaPath);
    final bytes = await file.exists() ? await file.length() : 0;
    var format = widget.isVideo ? 'MP4' : 'PHOTO';
    var resolution = '—', frameRate = '—', line = '';
    try {
      if (widget.isVideo) {
        final probe = await OneovaMediaEngine.probe(widget.mediaPath);
        resolution = '${probe.width}×${probe.height}';
        frameRate = probe.fps > 0 ? '${probe.fps.round()} FPS' : '—';
        line = 'Video · ${probe.duration.inSeconds}s${probe.hasAudio ? ' · with sound' : ' · no sound'}';
      } else {
        final ext = widget.mediaPath.split('.').last.toUpperCase();
        format = ext == 'JPG' ? 'JPEG' : ext;
        final buffer = await ImmutableBuffer.fromUint8List(await file.readAsBytes());
        final desc = await ImageDescriptor.encoded(buffer);
        resolution = '${desc.width}×${desc.height}';
        desc.dispose();
        buffer.dispose();
        frameRate = 'Still';
        line = '$format photo';
      }
    } catch (e) {
      debugPrint('[ExportingSheet] could not read media specs: $e');
    }
    if (!mounted) return;
    setState(() {
      _format = format;
      _resolution = resolution;
      _frameRate = frameRate;
      _size = bytes <= 0 ? '—' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      _specLine = line;
      _isExportComplete = true;
      _currentProgress = 1.0;
      _currentStage = 'Ready to post';
    });
  }

  void _updateStageText(double progress) {
    if (progress < 0.22) {
      _currentStage = 'Encoding 4K HDR 60fps Master Stream...';
    } else if (progress < 0.48) {
      _currentStage = 'Calibrating Oneova Color Grade & Audio Normalization...';
    } else if (progress < 0.74) {
      _currentStage = 'Synthesizing Fast-Trending ONPA-Flow Embeddings...';
    } else if (progress < 0.94) {
      _currentStage = 'Packaging Multi-Platform Syndication Bundle...';
    } else if (progress < 1.0) {
      _currentStage = 'Finalizing Master Asset...';
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveToDevice() async {
    HapticFeedback.selectionClick();
    setState(() => _isSavingToDevice = true);

    try {
      final file = File(widget.mediaPath);
      if (await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(widget.mediaPath)],
            text: '${widget.title} #oneova',
          ),
        );
        if (mounted) {
          setState(() {
            _savedSuccess = true;
            _isSavingToDevice = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.darkSurface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                side: BorderSide(color: AppColors.brandBlue, width: 1.0),
              ),
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Saved to device & ready to share!',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[ExportingSheet] Error saving to device: $e');
      if (mounted) {
        setState(() => _isSavingToDevice = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_currentProgress * 100).toInt();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF20D0D12),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
              BoxShadow(
                color: AppColors.brandBlue.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.brandBlue.withValues(alpha: 0.5),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.movie_creation_outlined,
                                color: AppColors.brandBlue, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'EXPORT MASTER',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _format,
                          style: GoogleFonts.inter(
                            color: AppColors.brandPink,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Animated Circular Progress Indicator
              Stack(
                alignment: Alignment.center,
                children: [
                  // Radiant Glow Backdrop
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isExportComplete
                                  ? Colors.greenAccent
                                  : AppColors.brandBlue)
                              .withValues(alpha: 0.25),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  // Background Track
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 7,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  // Progress Arc
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: _currentProgress,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isExportComplete
                            ? Colors.greenAccent
                            : AppColors.brandBlue,
                      ),
                    ),
                  ),
                  // Center Content
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isExportComplete)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.greenAccent,
                          size: 42,
                        )
                      else ...[
                        Text(
                          '$percent%',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'RENDERING',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Status Ticker
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _currentStage,
                  key: ValueKey(_currentStage),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: _isExportComplete
                        ? Colors.greenAccent
                        : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _specLine,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 24),

              // Spec Meta Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF14141A),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetaPill('RESOLUTION', _resolution),
                    Container(width: 1, height: 24, color: Colors.white12),
                    _buildMetaPill('FRAME RATE', _frameRate),
                    Container(width: 1, height: 24, color: Colors.white12),
                    _buildMetaPill('FILE SIZE', _size),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Two Core Options: Save to Device OR Proceed with Post
              Row(
                children: [
                  // Option 1: Save to Device
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSavingToDevice ? null : _saveToDevice,
                      icon: _isSavingToDevice
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            )
                          : Icon(
                              _savedSuccess
                                  ? Icons.check
                                  : Icons.save_alt_rounded,
                              size: 18,
                              color: _savedSuccess
                                  ? Colors.greenAccent
                                  : Colors.white,
                            ),
                      label: Text(
                        _savedSuccess ? 'Saved' : 'Save to Device',
                        style: GoogleFonts.inter(
                          color: _savedSuccess ? Colors.greenAccent : Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: _savedSuccess
                              ? Colors.greenAccent
                              : Colors.white24,
                          width: 1.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Option 2: Proceed with Post
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.heavyImpact();
                        Navigator.pop(context); // close export sheet
                        widget.onProceedToPost(); // navigate to post screen
                      },
                      icon: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        'Proceed to Post',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        elevation: 4,
                        shadowColor: AppColors.brandBlue.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaPill(String title, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.white38,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
