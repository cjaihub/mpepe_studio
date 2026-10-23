import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../backend/social/models/creator_analytics.dart';
import '../backend/social/services/creator_studio_service.dart';
import '../shared/theme/app_theme.dart';
import '../backend/projects/models/pro_project_models.dart';
import '../backend/project_repository.dart';
import '../backend/ai_agents/omni_command/omni_context_resolver.dart';
import '../features/omni_command/omni_command_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pro_editor_screen.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CreatorStudioScreen extends ConsumerStatefulWidget {
  const CreatorStudioScreen({super.key});

  @override
  ConsumerState<CreatorStudioScreen> createState() => _CreatorStudioScreenState();
}

class _CreatorStudioScreenState extends ConsumerState<CreatorStudioScreen> {
  int _selectedIndex = 0;
  CreatorAnalytics? _analytics;
  bool _isLoading = true;

  final List<String> _sections = [
    'Overview',
    'Projects',
    'Drafts',
    'Editor',
    'Templates',
    'Sounds',
    'Captions',
    'Thumbnails',
    'Publishing',
    'Calendar',
    'Analytics',
    'AI Copilot',
    'Revenue'
  ];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final service = ref.read(creatorStudioServiceProvider);
    final data = await service.getAnalyticsOverview('current_user');
    if (mounted) {
      setState(() {
        _analytics = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text(
          'Creator Studio',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: context.textPrimary),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: context.textPrimary),
            onPressed: () {},
          )
        ],
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 200,
            color: context.surface,
            child: ListView.builder(
              itemCount: _sections.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedIndex == index;
                return ListTile(
                  title: Text(
                    _sections[index],
                    style: GoogleFonts.inter(
                      color: isSelected ? AppColors.brandBlue : context.textPrimary,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                  selected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                );
              },
            ),
          ),
          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue))
                : _buildMainContent(),
          ),
        ],
      ),
      floatingActionButton: OmniCommandButton(
        omniContext: OmniContext(
          sessionId: buildOmniSessionId(),
          userId: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
          surface: 'creator_studio',
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_sections[_selectedIndex] == 'Overview' || _sections[_selectedIndex] == 'Analytics') {
      return _buildDashboard();
    }
    
    if (_sections[_selectedIndex] == 'Projects' || _sections[_selectedIndex] == 'Drafts') {
      return _buildProjectList();
    }
    
    return Center(
      child: Text(
        '${_sections[_selectedIndex]} Workspace',
        style: GoogleFonts.inter(color: context.textSecondary, fontSize: 24),
      ),
    );
  }

  Widget _buildProjectList() {
    final projectsAsync = ref.watch(projectsStreamProvider);

    return projectsAsync.when(
      data: (projects) {
        if (projects.isEmpty) {
          return Center(
            child: Text(
              'No projects found. Create a new one!',
              style: GoogleFonts.inter(color: context.textSecondary, fontSize: 18),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final project = projects[index];
            return Card(
              color: context.surfaceMid,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: context.border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.movie, color: context.textPrimary),
                ),
                title: Text(
                  project.title,
                  style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Updated: ${project.createdAt.toString().split('.')[0]}',
                  style: GoogleFonts.inter(color: context.textSecondary),
                ),
                trailing: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => ProEditorScreen(project: project),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                  ),
                  child: Text('Edit', style: GoogleFonts.inter(color: Colors.white)),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
    );
  }

  Widget _buildDashboard() {
    if (_analytics == null) return const SizedBox();
    
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Create New',
          style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: context.textPrimary),
        ),
        const SizedBox(height: 16),
        _buildCreateActions(context),
        const SizedBox(height: 32),
        Text(
          'Dashboard (Last 28 Days)',
          style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: context.textPrimary),
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 4,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          childAspectRatio: 1.5,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildStatCard(context, 'Views', _analytics!.views.toString()),
            _buildStatCard(context, 'Watch Time', '${_analytics!.watchTime.inHours}h'),
            _buildStatCard(context, 'Followers', _analytics!.followers.toString()),
            _buildStatCard(context, 'Likes', _analytics!.likes.toString()),
            _buildStatCard(context, 'Comments', _analytics!.comments.toString()),
            _buildStatCard(context, 'Shares', _analytics!.shares.toString()),
            _buildStatCard(context, 'Saves', _analytics!.saves.toString()),
            _buildStatCard(context, 'Profile Visits', _analytics!.profileVisits.toString()),
            _buildStatCard(context, 'Follows', _analytics!.follows.toString()),
            _buildStatCard(context, 'Revenue', '\$${_analytics!.revenue.toStringAsFixed(2)}', isHighlight: true),
          ],
        ),
      ],
    );
  }

  Widget _buildCreateActions(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildActionCard(
          context,
          icon: Icons.movie_creation,
          title: 'New Video',
          onTap: () => _launchProEditor(context, 'New Video Project', 1080, 1920),
        ),
        _buildActionCard(
          context,
          icon: Icons.photo_camera,
          title: 'New Photo',
          onTap: () => _launchProEditor(context, 'New Photo Project', 1080, 1350),
        ),
        _buildActionCard(
          context,
          icon: Icons.auto_awesome_motion,
          title: 'New Mixed',
          onTap: () => _launchProEditor(context, 'New Mixed Project', 1920, 1080),
        ),
        _buildActionCard(
          context,
          icon: Icons.psychology,
          title: 'AI Create',
          onTap: () {},
          isHighlight: true,
        ),
        _buildActionCard(
          context,
          icon: Icons.fiber_manual_record,
          title: 'Record Now',
          onTap: () {},
        ),
        _buildActionCard(
          context,
          icon: Icons.upload_file,
          title: 'Import Media',
          onTap: () {},
        ),
      ],
    );
  }

  Future<void> _launchProEditor(BuildContext context, String title, int width, int height) async {
    final project = StudioProject(
      id: '',
      title: title,
      category: 'Video',
      status: 'Draft',
      completedSteps: 0,
      createdAt: DateTime.now(),
      settings: ProjectSettings(width: width, height: height, frameRate: 30.0),
    );
    
    // Save draft to persistence
    try {
      await ref.read(projectRepositoryProvider).addProject(project);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create project: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => ProEditorScreen(project: project),
      ));
    }
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isHighlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isHighlight ? AppColors.brandBlue : context.surfaceMid,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHighlight ? AppColors.brandBlue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isHighlight ? Colors.white : context.textPrimary, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                color: isHighlight ? Colors.white : context.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, {bool isHighlight = false}) {
    return Container(
      decoration: BoxDecoration(
        color: isHighlight ? AppColors.brandBlue : context.surfaceMid,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlight ? AppColors.brandBlue : Colors.transparent,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: isHighlight ? Colors.white : context.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              color: isHighlight ? Colors.white : context.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
