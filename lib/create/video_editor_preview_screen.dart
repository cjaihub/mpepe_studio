import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../shared/design_system/app_colors.dart';
import '../backend/project_repository.dart';
import 'package:go_router/go_router.dart';

class VideoEditorPreviewScreen extends StatefulWidget {
  final StudioProject project;
  const VideoEditorPreviewScreen({super.key, required this.project});

  @override
  State<VideoEditorPreviewScreen> createState() => _VideoEditorPreviewScreenState();
}

class _VideoEditorPreviewScreenState extends State<VideoEditorPreviewScreen> {
  double _sliderValue = 0.3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // True black background for video preview
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeader(),
            Expanded(child: _buildVideoPreview()),
            _buildTimelineControls(),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 24),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video preview using the project storyboard if available
        if (widget.project.storyboardUrls.isNotEmpty)
          Image.network(widget.project.storyboardUrls.first, fit: BoxFit.contain)
        else
          Container(
            color: AppColors.darkSurfaceHighlight,
            child: const Center(child: Icon(Icons.videocam, size: 64, color: AppColors.textMuted)),
          ),
        
        // Oneova watermark
        Positioned(
          left: 16,
          bottom: 30,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text('Oneova', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              Text('@oneova', style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),

        // AI Generated badge
        Positioned(
          left: 16,
          bottom: 8,
          child: Text('AI-generated', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildTimelineControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        children: [
          // Slider
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: _sliderValue,
              onChanged: (val) => setState(() => _sliderValue = val),
            ),
          ),
          const SizedBox(height: 12),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('Crop', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                ],
              ),
              GestureDetector(
                onTap: () {
                  // Pass to export
                  context.push('/create/export', extra: widget.project);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue, // Replaced cyan with Brand Red
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Add',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 48,
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const Icon(Icons.menu, color: AppColors.textSecondary, size: 24),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.textSecondary, width: 2),
            ),
          ),
          const Icon(Icons.undo, color: AppColors.textSecondary, size: 24),
        ],
      ),
    );
  }
}
