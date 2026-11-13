import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/project_repository.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class AudioProductionsScreen extends ConsumerStatefulWidget {
  const AudioProductionsScreen({super.key});

  @override
  ConsumerState<AudioProductionsScreen> createState() => _AudioProductionsScreenState();
}

class _AudioProductionsScreenState extends ConsumerState<AudioProductionsScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsStreamProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.mic_none, Icons.music_note, Icons.headphones],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Productions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.textPrimary)),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Production', 'Review', 'Done'].map((label) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = label),
                        child: _SegButton(label: label, isActive: _filter == label),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: projectsAsync.when(
                  data: (all) {
                    final audio = all.where((p) => p.category == 'Audio').where((p) {
                      if (_filter == 'All') return true;
                      if (_filter == 'Done') return p.status.toLowerCase() == 'done';
                      if (_filter == 'Review') return p.status.toLowerCase().contains('review');
                      return p.status.toLowerCase() != 'done' && !p.status.toLowerCase().contains('review');
                    }).toList();

                    if (audio.isEmpty) {
                      return Center(
                        child: Text(
                          'No audio productions in this stage.',
                          style: TextStyle(color: context.textSecondary, fontSize: 13),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: audio.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final p = audio[index];
                        final isReview = p.status.toLowerCase().contains('review');
                        return _ProductionCard(
                          title: p.title,
                          subtitle: p.toolsUsed.isNotEmpty ? p.toolsUsed.join(' • ') : 'Audio Studio',
                          status: p.status,
                          statusColor: isReview ? AppColors.brandPink : AppColors.brandBlue,
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                  error: (e, _) => Center(child: Text('Error: $e', style: TextStyle(color: context.textSecondary))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool isActive;

  const _SegButton({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
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
