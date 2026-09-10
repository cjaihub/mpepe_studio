import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import 'dart:io';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import '../services/omnichannel_upload_engine.dart';
import '../models/omnichannel_upload_task.dart';
import '../models/platform_destination.dart';
import '../models/connected_destination.dart';

class PremiumPostScreen extends ConsumerStatefulWidget {
  const PremiumPostScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PremiumPostScreen> createState() => _PremiumPostScreenState();
}

class _PremiumPostScreenState extends ConsumerState<PremiumPostScreen> {
  Future<void> _pickAndUploadFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result != null) {
      final files = result.map((f) => f.path).where((p) => p != null).map((p) => File(p!)).toList();
      if (files.isNotEmpty) {
        _showPlatformSelector(files);
      }
    }
  }

  void _showPlatformSelector(List<File> files) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _PlatformSelectorSheet(files: files);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Your Files',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.mpepeMaroon.withValues(alpha: 0.2),
              child: const Icon(Icons.person, color: AppColors.mpepeMaroon, size: 20),
            ),
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, child) {
          final tasks = ref.watch(omnichannelUploadEngineProvider);
          final activeTasks = tasks.where((t) => t.status == UploadStatus.pending || t.status == UploadStatus.uploading).toList();
          final recentTasks = tasks.where((t) => t.status == UploadStatus.completed || t.status == UploadStatus.failed).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUploadZone(),
                if (activeTasks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildUploadingSection(activeTasks),
                ],
                const SizedBox(height: 32),
                _buildRecentUploadsSection(recentTasks),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUploadZone() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48.0),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.mpepeMaroon.withValues(alpha: 0.5),
          width: 2.0,
          style: BorderStyle.solid, // In a real app, use a dashed border package like dotted_border
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.upload_rounded,
            size: 48,
            color: AppColors.mpepeMaroon,
          ).animate().slideY(begin: 0.2, end: 0, duration: 800.ms, curve: Curves.easeOutCubic),
          const SizedBox(height: 16),
          Text(
            'Upload your files here',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _pickAndUploadFiles,
            child: Text(
              'Browse',
              style: GoogleFonts.inter(
                color: AppColors.mpepeMaroon,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.mpepeMaroon,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadingSection(List<OmnichannelUploadTask> activeTasks) {
    if (activeTasks.isEmpty) return const SizedBox.shrink();

    // Use the first task's progress as an aggregate for the UI mockup
    final aggregateProgress = activeTasks.fold(0.0, (sum, task) => sum + task.progress) / activeTasks.length;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Uploading ${activeTasks.length} files',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const Icon(Icons.open_in_full_rounded, color: Colors.white54, size: 16),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: activeTasks.map((task) {
              return Container(
                margin: const EdgeInsets.only(right: 8),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.mpepeMaroon.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.mpepeMaroon.withValues(alpha: 0.5)),
                ),
                child: const Icon(Icons.image, color: AppColors.mpepeMaroon, size: 20),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: aggregateProgress > 0 ? aggregateProgress : 0.05, 
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.mpepeMaroon,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Time remaining: 23 sec.',
                style: GoogleFonts.inter(
                  color: AppColors.mpepeMaroon,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.pause_rounded, color: Colors.white54, size: 20),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.mpepeMaroon, size: 20),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildRecentUploadsSection(List<OmnichannelUploadTask> recentTasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent uploaded',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              '${recentTasks.length} items',
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: recentTasks.length,
          itemBuilder: (context, index) {
            final task = recentTasks[index];
            final fileName = task.file.path.split('/').last;
            
            // Mock size for display
            final fileSize = '2.4 MB'; 
            final isFailed = task.status == UploadStatus.failed;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isFailed 
                        ? Colors.redAccent.withValues(alpha: 0.1) 
                        : AppColors.mpepeMaroon.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isFailed ? Icons.error_outline_rounded : Icons.insert_drive_file_rounded, 
                      color: isFailed ? Colors.redAccent : AppColors.mpepeMaroon
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              fileSize,
                              style: GoogleFonts.inter(
                                color: isFailed ? Colors.redAccent : Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isFailed ? 'Failed' : 'Today',
                              style: GoogleFonts.inter(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
                    onPressed: () {
                      ref.read(omnichannelUploadEngineProvider.notifier).removeTask(task.id);
                    },
                  ),
                ],
              ).animate().fadeIn(delay: (300 + (index * 50)).ms).slideX(begin: 0.1),
            );
          },
        ),
      ],
    );
  }
}

class _PlatformSelectorSheet extends ConsumerStatefulWidget {
  final List<File> files;

  const _PlatformSelectorSheet({required this.files});

  @override
  ConsumerState<_PlatformSelectorSheet> createState() => _PlatformSelectorSheetState();
}

class _PlatformSelectorSheetState extends ConsumerState<_PlatformSelectorSheet> {
  final Set<String> _selectedPlatformIds = {};

  void _startUpload() {
    Navigator.pop(context); // Close sheet
    final engine = ref.read(omnichannelUploadEngineProvider.notifier);
    
    // Map selected IDs to mock ConnectedDestination objects for the engine
    final selectedDestinations = kAvailablePlatforms
        .where((p) => _selectedPlatformIds.contains(p.id))
        .map((p) {
          // Simplistic mock mapping for the engine
          if (p.id == 'yt') return ConnectedDestination.youtube(channelId: 'mock_yt', channelTitle: 'Mock YT', googleId: 'mock', thumbnailUrl: '');
          if (p.id == 'tt') return ConnectedDestination.tiktok(tiktokUserId: 'mock_tt', username: 'Mock TikTok');
          return ConnectedDestination.meta(pageId: 'mock_${p.id}', pageName: p.name, metaUserId: 'mock', platform: PlatformType.facebook);
        })
        .toList();

    engine.addTasks(widget.files, selectedDestinations);
    engine.startUploads();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Platforms',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Distribute ${widget.files.length} file(s) across 50+ integrations.',
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: kAvailablePlatforms.length,
              itemBuilder: (context, index) {
                final platform = kAvailablePlatforms[index];
                final isSelected = _selectedPlatformIds.contains(platform.id);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedPlatformIds.remove(platform.id);
                      } else {
                        _selectedPlatformIds.add(platform.id);
                      }
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.mpepeMaroon.withValues(alpha: 0.2) : AppColors.darkBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppColors.mpepeMaroon : Colors.white12,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          platform.icon,
                          size: 32,
                          color: isSelected ? AppColors.mpepeMaroon : Colors.white54,
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Text(
                            platform.name,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: isSelected ? Colors.white : Colors.white54,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate(target: isSelected ? 1 : 0).scaleXY(end: 1.05, duration: 200.ms),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.mpepeMaroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: Colors.white12,
            ),
            onPressed: _selectedPlatformIds.isEmpty ? null : _startUpload,
            child: Text(
              'Upload to ${_selectedPlatformIds.length} Platform(s)',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
