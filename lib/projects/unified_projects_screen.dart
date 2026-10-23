import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/project_repository.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/theme/app_theme.dart';

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
                      return Center(child: Text('No projects found.', style: TextStyle(color: context.textMuted, fontSize: 14)));
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
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
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
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: context.textPrimary)
        ),
        const SizedBox(height: 6),
        Text(
          'Manage all your Audio & Video productions across the studio.',
          style: TextStyle(color: context.textSecondary, fontSize: 13, letterSpacing: 0.1),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: isSelected ? Colors.transparent : context.border),
                boxShadow: isSelected ? [
                  BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))
                ] : [],
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: isSelected ? Colors.white : context.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 13,
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
    
    return OneovaCard(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isVideo ? Icons.videocam : Icons.audiotrack, 
                    color: isVideo ? AppColors.brandBlue : AppColors.brandPink, 
                    size: 18
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.title, 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: context.textPrimary),
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
                      style: TextStyle(color: context.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.status,
                      style: const TextStyle(color: AppColors.brandBlue, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (project.toolsUsed.isNotEmpty) ...[
                      Text(
                        'Tools:',
                        style: TextStyle(color: context.textMuted, fontSize: 11),
                      ),
                      Text(
                        project.toolsUsed.take(2).join(', ') + (project.toolsUsed.length > 2 ? '...' : ''),
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
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
                icon: Icon(Icons.description, size: 20, color: context.textSecondary),
                onPressed: () {
                  if (isVideo && project.storyboardUrls.isNotEmpty) {
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
        backgroundColor: context.surface,
        title: Text('${project.title} - Script', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text(project.script ?? 'No script generated yet.', style: TextStyle(color: context.textSecondary)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.brandBlue)),
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
            icon: Icon(Icons.chevron_left, color: context.textPrimary),
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.border),
            ),
            child: Text(
              'Page ${_currentPage + 1} of $totalPages',
              style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary, fontSize: 12),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: context.textPrimary),
            onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
          ),
        ],
      ),
    );
  }
}
