import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../backend/project_repository.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

final _audioArtistsCountProvider = StreamProvider<int>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('audio_artists')
      .snapshots()
      .map((s) => s.docs.length);
});

class AudioDashboardScreen extends ConsumerWidget {
  const AudioDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsStreamProvider);
    final artistsCountAsync = ref.watch(_audioArtistsCountProvider);

    final audioProjects = (projectsAsync.asData?.value ?? const <StudioProject>[])
        .where((p) => p.category == 'Audio')
        .toList();
    final activeCount = audioProjects
        .where((p) => p.status.toLowerCase() != 'done' && p.status.toLowerCase() != 'delivered')
        .length;
    final reviewCount = audioProjects
        .where((p) => p.status.toLowerCase().contains('review'))
        .length;
    final doneCount = audioProjects
        .where((p) => p.status.toLowerCase() == 'done' || p.status.toLowerCase() == 'delivered' || p.status.toLowerCase() == 'mastered')
        .length;
    final artistsCount = artistsCountAsync.asData?.value ?? 0;

    return StudioBackground(
      backgroundIcons: const [Icons.mic_none, Icons.music_note, Icons.headphones],
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
              buildFriendlyHeader(context).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _StatCard(title: 'ACTIVE', value: '$activeCount').animate().fadeIn(duration: 400.ms).slideY(begin: 0.1)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'IN REVIEW', value: '$reviewCount').animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.1)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(title: 'DONE', value: '$doneCount', valueColor: AppColors.brandBlue).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.1)),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Library',
                      meta: '${audioProjects.length} tracks',
                      onTap: () => context.push('/audio/library'),
                    ).animate().fadeIn(delay: 300.ms).scaleXY(begin: 0.95),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _Tile(
                      icon: Icons.group_outlined,
                      title: 'Artists',
                      meta: '$artistsCount registered',
                      onTap: () => context.push('/audio/artists'),
                    ).animate().fadeIn(delay: 400.ms).scaleXY(begin: 0.95),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Active productions', style: AppTheme.h2Style.copyWith(color: context.textPrimary)),
                  GestureDetector(
                    onTap: () => context.push('/audio/productions'),
                    child: const Text('See all', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (projectsAsync.isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.brandBlue)))
              else if (audioProjects.isEmpty)
                OneovaCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No active audio productions yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: context.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Open the Audio Library to add a new track or production project.', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                ...audioProjects.take(5).map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProductionCard(
                      title: p.title,
                      subtitle: p.toolsUsed.isNotEmpty ? p.toolsUsed.join(' • ') : 'Audio Studio',
                      status: p.status,
                      statusColor: p.status.toLowerCase().contains('review') ? AppColors.brandPink : AppColors.brandBlue,
                    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.05),
                  );
                }),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildFriendlyHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Audio Production Studio',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage your tracks, coordinate with artists, and master your audio.',
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

class _ProductionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;

  const _ProductionCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return OneovaCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 8),
                  Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                ],
              ),
          ),
          OneovaPill(
            text: status,
            color: statusColor,
            isGhost: true,
          ),
        ],
      ),
    );
  }
}
