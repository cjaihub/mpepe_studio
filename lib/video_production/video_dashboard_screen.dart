import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../backend/equipment_repository.dart';
import '../backend/project_repository.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

final _videoCrewCountProvider = StreamProvider<int>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('studio_crew')
      .snapshots()
      .map((s) => s.docs.length);
});

class VideoDashboardScreen extends ConsumerWidget {
  const VideoDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsStreamProvider);
    final equipmentAsync = ref.watch(equipmentStreamProvider);
    final crewCountAsync = ref.watch(_videoCrewCountProvider);

    final videoProjects = (projectsAsync.asData?.value ?? const <StudioProject>[])
        .where((p) => p.category == 'Video')
        .toList();
    final activeCount = videoProjects
        .where((p) => p.status.toLowerCase() != 'delivered' && p.status.toLowerCase() != 'done')
        .length;
    final reviewCount = videoProjects
        .where((p) => p.status.toLowerCase() == 'review')
        .length;
    final checkedOutGear = (equipmentAsync.asData?.value ?? const <EquipmentItem>[])
        .where((e) => e.status == EquipmentStatus.checkedOut)
        .length;
    final crewCount = crewCountAsync.asData?.value ?? 0;

    return StudioBackground(
      backgroundIcons: const [Icons.videocam_outlined, Icons.movie_creation_outlined, Icons.camera_alt_outlined],
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/hub/home');
                  }
                },
                child: Row(
                  children: [
                    Icon(Icons.chevron_left, color: context.textSecondary, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Studio Home',
                      style: AppTheme.bodyStyle.copyWith(color: context.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildFriendlyHeader(context).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _StatCard(title: 'ACTIVE', value: '$activeCount').animate().fadeIn(duration: 400.ms).slideY(begin: 0.1)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'REVIEW', value: '$reviewCount').animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.1)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'GEAR OUT', value: '$checkedOutGear', valueColor: AppColors.brandBlue).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.1)),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Active projects', style: AppTheme.h2Style.copyWith(color: context.textPrimary)),
                  GestureDetector(
                    onTap: () => context.push('/video/projects'),
                    child: const Text('See all', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (projectsAsync.isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.brandBlue)))
              else if (videoProjects.isEmpty)
                OneovaCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No active video projects yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: context.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Create a project in Studio to track scripting, filming, editing, and review steps.', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                ...videoProjects.take(4).map((project) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OneovaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(project.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: context.textPrimary)),
                          if (project.toolsUsed.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(project.toolsUsed.join(' • '), style: TextStyle(color: context.textSecondary, fontSize: 12)),
                          ],
                          const SizedBox(height: 10),
                          StepProgressIndicator(totalSteps: project.totalSteps, completedSteps: project.completedSteps),
                          const SizedBox(height: 8),
                          Text(project.status, style: TextStyle(color: context.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.05),
                  );
                }),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.inventory_2_outlined,
                      title: 'Equipment',
                      meta: '$checkedOutGear checked out',
                      onTap: () => context.push('/video/equipment'),
                    ).animate().fadeIn(delay: 300.ms).scaleXY(begin: 0.95),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Tile(
                      icon: Icons.group_outlined,
                      title: 'Crew',
                      meta: '$crewCount members',
                      onTap: () => context.push('/video/team'),
                    ).animate().fadeIn(delay: 400.ms).scaleXY(begin: 0.95),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendlyHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Video Production Studio',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage your shoots, edit timelines, and coordinate your crew.',
          style: TextStyle(fontSize: 13, color: context.textSecondary),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const _StatCard({required this.title, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return OneovaCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: valueColor ?? Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String meta;
  final VoidCallback onTap;

  const _Tile({required this.icon, required this.title, required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(meta, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
