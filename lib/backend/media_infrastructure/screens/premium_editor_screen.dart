import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/backend/media_infrastructure/services/video_project_service.dart';
import 'package:oneova/backend/media_infrastructure/models/video_project_models.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class PremiumEditorScreen extends ConsumerStatefulWidget {
  final String projectId;
  const PremiumEditorScreen({super.key, required this.projectId});

  @override
  ConsumerState<PremiumEditorScreen> createState() => _PremiumEditorScreenState();
}

class _PremiumEditorScreenState extends ConsumerState<PremiumEditorScreen> {
  final ScrollController _timelineScrollController = ScrollController();
  String _selectedTool = 'split';
  String? _selectedClipId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(videoProjectServiceProvider).loadProject(widget.projectId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectService = ref.watch(videoProjectServiceProvider);
    final project = projectService.currentProject;

    if (project == null) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(projectService),
            Flexible(
              flex: 2,
              child: _buildPreviewArea(),
            ),
            _buildToolPropertiesBar(),
            Expanded(
              flex: 3,
              child: _buildTimelineArea(project),
            ),
            _buildBottomToolDrawer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(VideoProjectService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      color: AppColors.darkSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.undo, color: AppColors.textPrimary),
                onPressed: service.canUndo ? () {
                  service.undo();
                  setState(() {});
                } : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo, color: AppColors.textPrimary),
                onPressed: service.canRedo ? () {
                  service.redo();
                  setState(() {});
                } : null,
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              // Export logic
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: AppColors.textPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              'Export',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video Player placeholder
            const Icon(Icons.play_circle_fill, size: 64, color: AppColors.textSecondary),
            Positioned(
              bottom: 16,
              child: Row(
                children: [
                  Text('00:00:15 / 00:05:00', style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildToolPropertiesBar() {
    // Contextual properties based on selected tool/clip
    return Container(
      height: 50,
      color: AppColors.darkSurfaceHighlight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        children: [
          _buildPropertyButton('Speed', Icons.speed),
          _buildPropertyButton('Volume', Icons.volume_up),
          _buildPropertyButton('Crop', Icons.crop),
          _buildPropertyButton('Filters', Icons.filter_vintage),
          _buildPropertyButton('Color', Icons.palette),
        ],
      ),
    );
  }

  Widget _buildPropertyButton(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTimelineArea(VideoProject project) {
    // Virtualized timeline rendering
    return GestureDetector(
      onScaleUpdate: (details) {
        // Handle pinch-to-zoom
      },
      child: Stack(
        children: [
          ListView.builder(
            controller: _timelineScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: 100, // Virtualized time chunks
            itemBuilder: (context, index) {
              return Container(
                width: 100, // Width per second
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppColors.darkSurfaceHighlight, width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Text('${index}s', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10)),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              );
            },
          ),
          // Tracks overlay
          Positioned.fill(
            top: 40,
            child: ListView.builder(
              itemCount: project.timeline.tracks.length,
              itemBuilder: (context, trackIndex) {
                final track = project.timeline.tracks[trackIndex];
                return _buildTrack(track);
              },
            ),
          ),
          // Playhead
          Positioned(
            left: MediaQuery.of(context).size.width / 2, // Centered playhead
            top: 0,
            bottom: 0,
            child: Container(width: 2, color: AppColors.brandBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildTrack(Track track) {
    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.darkSurface.withValues(alpha: 0.5),
      child: Stack(
        children: track.clips.map((clip) {
          return Positioned(
            left: clip.timelineStartTime.inMilliseconds / 10.0, // Scale factor
            width: clip.duration.inMilliseconds / 10.0,
            top: 10,
            bottom: 10,
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedClipId = clip.id);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: _selectedClipId == clip.id ? AppColors.brandBlue : AppColors.darkSurfaceHighlight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedClipId == clip.id ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Clip',
                  style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomToolDrawer() {
    return Container(
      height: 120,
      color: AppColors.darkSurface,
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        children: [
          _buildToolAction('AI Look', Icons.smart_toy, 'ai_look'),
          _buildToolAction('Retouch', Icons.face_retouching_natural, 'retouch'),
          _buildToolAction('Split', Icons.content_cut, 'split'),
          _buildToolAction('Text', Icons.text_fields, 'text'),
          _buildToolAction('Effects', Icons.auto_awesome, 'effects'),
          _buildToolAction('Transitions', Icons.animation, 'transitions'),
          _buildToolAction('Audio', Icons.music_note, 'audio'),
          _buildToolAction('Stickers', Icons.emoji_emotions, 'stickers'),
          _buildToolAction('Mask', Icons.format_shapes, 'mask'),
          _buildToolAction('Adjust', Icons.tune, 'adjust'),
        ],
      ),
    );
  }

  Widget _buildToolAction(String label, IconData icon, String id) {
    final isSelected = _selectedTool == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedTool = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : AppColors.textPrimary,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
