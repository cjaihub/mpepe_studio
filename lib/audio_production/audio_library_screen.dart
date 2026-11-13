import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/project_repository.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class AudioLibraryScreen extends ConsumerWidget {
  const AudioLibraryScreen({super.key});

  Future<void> _showAddTrackDialog(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final titleController = TextEditingController();
    final artistController = TextEditingController();
    String status = 'Recording';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: ctx.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: ctx.border),
          ),
          title: Text(
            'Add Audio Track',
            style: TextStyle(
              color: ctx.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: TextStyle(color: ctx.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Track Title',
                  labelStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: ctx.surfaceMid,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: ctx.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppColors.brandBlue),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: artistController,
                style: TextStyle(color: ctx.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Artist / Producer',
                  labelStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: ctx.surfaceMid,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: ctx.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppColors.brandBlue),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                dropdownColor: ctx.surface,
                style: TextStyle(color: ctx.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Stage',
                  labelStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: ctx.surfaceMid,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: ctx.border),
                  ),
                ),
                items: const ['Recording', 'Mixing', 'Review', 'Done']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => status = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                final artist = artistController.text.trim();
                if (title.isEmpty) return;
                final fullTitle = artist.isEmpty ? title : '$title — $artist';
                await ref.read(projectRepositoryProvider).addProject(
                      StudioProject(
                        id: '',
                        category: 'Audio',
                        title: fullTitle,
                        status: status,
                        completedSteps: status == 'Done' ? 5 : (status == 'Review' ? 4 : 2),
                        toolsUsed: artist.isEmpty ? const [] : [artist],
                        createdAt: DateTime.now(),
                      ),
                    );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsStreamProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.mic_none, Icons.music_note, Icons.headphones],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Library', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.textPrimary)),
                      const SizedBox(height: 4),
                      Text('All audio under production', style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.brandBlue),
                    tooltip: 'Add Audio Track',
                    onPressed: () => _showAddTrackDialog(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: projectsAsync.when(
                  data: (allProjects) {
                    final tracks = allProjects.where((p) => p.category == 'Audio').toList();
                    if (tracks.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.library_music_outlined, size: 42, color: context.textMuted),
                            const SizedBox(height: 10),
                            Text('No audio tracks in library yet', style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandBlue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _showAddTrackDialog(context, ref),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Track'),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: tracks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final t = tracks[index];
                        final isReview = t.status.toLowerCase().contains('review');
                        return _TrackCard(
                          title: t.title,
                          time: t.toolsUsed.isNotEmpty ? t.toolsUsed.join(' • ') : 'Audio Project',
                          status: t.status,
                          statusColor: isReview ? AppColors.brandPink : AppColors.brandBlue,
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                  error: (e, _) => Center(child: Text('Error loading library: $e', style: TextStyle(color: context.textSecondary))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final String title;
  final String time;
  final String status;
  final Color statusColor;

  const _TrackCard({
    required this.title,
    required this.time,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return OneovaCard(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(time, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
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
