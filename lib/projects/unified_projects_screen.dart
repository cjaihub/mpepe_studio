import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/project_repository.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/theme/app_theme.dart';
import '../video_production/storyboard_presentation_screen.dart'; // We can adapt this later if needed

class UnifiedProjectsScreen extends ConsumerStatefulWidget {
  const UnifiedProjectsScreen({super.key});

  @override
  ConsumerState<UnifiedProjectsScreen> createState() => _UnifiedProjectsScreenState();
}

class _UnifiedProjectsScreenState extends ConsumerState<UnifiedProjectsScreen> {
  String _selectedCategory = 'All'; // 'All', 'Video', 'Audio'
  int _currentPage = 0;
  static const int _itemsPerPage = 6;

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsStreamProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.folder_copy_outlined, Icons.audiotrack_outlined, Icons.movie_creation_outlined],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildFilterTabs(),
              const SizedBox(height: 24),
              Expanded(
                child: projectsAsync.when(
                  data: (allProjects) {
                    // 1. Filter by category
                    final filteredProjects = _selectedCategory == 'All' 
                        ? allProjects 
                        : allProjects.where((p) => p.category == _selectedCategory).toList();

                    // 2. Pagination Math
                    final totalItems = filteredProjects.length;
                    final totalPages = (totalItems / _itemsPerPage).ceil();
                    
                    if (totalItems == 0) {
                      return const Center(child: Text('No projects found.', style: TextStyle(color: Colors.white54, fontSize: 16)));
                    }

                    // Clamp current page just in case filtering reduced the total pages
                    if (_currentPage >= totalPages) {
                      _currentPage = (totalPages - 1).clamp(0, totalPages);
                    }

                    final startIndex = _currentPage * _itemsPerPage;
                    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
                    final paginatedProjects = filteredProjects.sublist(startIndex, endIndex);

                    return Column(
                      children: [
                        Expanded(
                          child: GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: paginatedProjects.length,
                            itemBuilder: (context, index) {
                              final p = paginatedProjects[index];
                              return _buildProjectCard(p, context);
                            },
                          ),
                        ),
                        if (totalPages > 1) 
                          _buildPaginationControls(totalPages),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.mpepeMaroon)),
                  error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Studio Projects', 
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: Theme.of(context).colorScheme.onSurface)
        ),
        const SizedBox(height: 8),
        Text(
          'Manage all your Audio & Video productions across the studio.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14, letterSpacing: 0.2),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return Row(
      children: ['All', 'Video', 'Audio'].map((category) {
        final isSelected = _selectedCategory == category;
        return Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = category;
                _currentPage = 0; // Reset pagination on filter change
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.mpepeMaroon : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? Colors.transparent : Colors.white12),
                boxShadow: isSelected ? [
                  BoxShadow(color: AppColors.mpepeMaroon.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))
                ] : [],
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildProjectCard(StudioProject project, BuildContext context) {
    final isVideo = project.category == 'Video';
    
    return MpepeCard(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isVideo ? Icons.videocam : Icons.audiotrack, 
                    color: isVideo ? Colors.blueAccent : Colors.orangeAccent, 
                    size: 18
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.title, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.status,
                      style: TextStyle(color: AppColors.mpepeMaroon, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (project.toolsUsed.isNotEmpty) ...[
                      Text(
                        'Tools:',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11),
                      ),
                      Text(
                        project.toolsUsed.take(2).join(', ') + (project.toolsUsed.length > 2 ? '...' : ''),
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    StepProgressIndicator(totalSteps: project.totalSteps, completedSteps: project.completedSteps),
                  ],
                ),
              ),
            ],
          ),
          if (project.storyboardUrls.isNotEmpty || project.script != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: IconButton(
                icon: const Icon(Icons.description, size: 20, color: Colors.white54),
                onPressed: () {
                  // View Script/Storyboard action
                  // Adapting the existing screen or creating a new dialog
                  if (isVideo && project.storyboardUrls.isNotEmpty) {
                    // Using dynamic here just as a bridge until we strictly port StoryboardPresentationScreen to use StudioProject instead of VideoProject
                    // For now, this is a placeholder behavior
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storyboard viewer launching...')));
                  } else {
                    _showScriptDialog(context, project);
                  }
                },
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: 400.ms, curve: Curves.easeOut);
  }

  void _showScriptDialog(BuildContext context, StudioProject project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkBackground,
        title: Text('${project.title} - Script', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(project.script ?? 'No script generated yet.', style: const TextStyle(color: Colors.white70)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.mpepeMaroon)),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(int totalPages) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Page ${_currentPage + 1} of $totalPages',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
          ),
        ],
      ),
    );
  }
}
