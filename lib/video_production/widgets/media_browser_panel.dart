import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/projects/models/pro_project_models.dart';
import '../../backend/project_repository.dart';

class MediaBrowserPanel extends StatefulWidget {
  final StudioProject project;
  final Function(Clip) onAddClip;

  const MediaBrowserPanel({
    super.key,
    required this.project,
    required this.onAddClip,
  });

  @override
  State<MediaBrowserPanel> createState() => _MediaBrowserPanelState();
}

class _MediaBrowserPanelState extends State<MediaBrowserPanel> {
  String _activeFilter = 'All';
  final List<String> _filters = ['All', 'Video', 'Photo', 'RAW', 'Audio', 'Favorites', 'Recent'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      color: context.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Project Media',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: context.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.brandBlue),
                  onPressed: () {
                    // Logic to import actual device media
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.border),
          _buildFilters(context),
          Divider(height: 1, color: context.border),
          Expanded(
            child: _buildMediaGrid(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isActive = filter == _activeFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                filter,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isActive ? Colors.white : context.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              selected: isActive,
              selectedColor: AppColors.brandBlue,
              backgroundColor: context.bg,
              side: BorderSide(color: isActive ? AppColors.brandBlue : context.border),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _activeFilter = filter;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaGrid(BuildContext context) {
    // Mocking media items for now, but these would come from project.media
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        return _buildMediaItem(context, index);
      },
    );
  }

  Widget _buildMediaItem(BuildContext context, int index) {
    final isVideo = index % 2 == 0;
    return GestureDetector(
      onTap: () => _showMediaOptions(index, isVideo),
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                isVideo ? Icons.movie : Icons.photo,
                color: context.textSecondary,
                size: 32,
              ),
            ),
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isVideo ? '00:15' : 'RAW',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '4K HDR',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMediaOptions(int index, bool isVideo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.add_to_queue, color: context.textPrimary),
                title: Text('Add to Timeline', style: GoogleFonts.inter(color: context.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onAddClip(
                    Clip(
                      sourceMediaId: 'media_$index',
                      type: isVideo ? MediaType.video : MediaType.image,
                      startTime: 0,
                      duration: 15.0,
                      sourceStart: 0,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.layers, color: context.textPrimary),
                title: Text('Add as Overlay', style: GoogleFonts.inter(color: context.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.movie_creation, color: context.textPrimary),
                title: Text('Create Sequence from Clip', style: GoogleFonts.inter(color: context.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.psychology, color: AppColors.brandBlue),
                title: Text('Analyze with AI', style: GoogleFonts.inter(color: context.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
