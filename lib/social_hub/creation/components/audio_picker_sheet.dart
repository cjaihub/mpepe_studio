import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../backend/social/models/audio_track.dart';
import '../../../backend/social/services/audio_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AudioPickerSheet extends ConsumerStatefulWidget {
  final Function(AudioTrack) onAudioSelected;
  const AudioPickerSheet({super.key, required this.onAudioSelected});

  @override
  ConsumerState<AudioPickerSheet> createState() => _AudioPickerSheetState();
}

class _AudioPickerSheetState extends ConsumerState<AudioPickerSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: context.textMuted, size: 20),
                        const SizedBox(width: 8),
                        Text('Search sounds...', style: TextStyle(color: context.textMuted)),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: context.textPrimary),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.brandBlue,
            labelColor: context.textPrimary,
            unselectedLabelColor: context.textMuted,
            tabs: const [
              Tab(text: 'Trending'),
              Tab(text: 'Favorites'),
              Tab(text: 'Recent'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _AudioList(type: 'trending', onAudioSelected: widget.onAudioSelected),
                _AudioList(type: 'favorites', onAudioSelected: widget.onAudioSelected),
                _AudioList(type: 'recent', onAudioSelected: widget.onAudioSelected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioList extends ConsumerWidget {
  final String type;
  final Function(AudioTrack) onAudioSelected;

  const _AudioList({required this.type, required this.onAudioSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioService = ref.watch(audioServiceProvider);
    
    Future<List<AudioTrack>> future;
    if (type == 'trending') {
      future = audioService.getTrendingSounds();
    } else if (type == 'favorites') {
      future = audioService.getFavorites();
    } else {
      future = audioService.getRecentSounds();
    }

    return FutureBuilder<List<AudioTrack>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue));
        }
        final sounds = snapshot.data ?? [];
        if (sounds.isEmpty) {
          return Center(child: Text('No sounds found', style: TextStyle(color: context.textMuted)));
        }
        return ListView.builder(
          itemCount: sounds.length,
          itemBuilder: (context, index) {
            final sound = sounds[index];
            return ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note, color: context.textMuted),
              ),
              title: Text(sound.title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${sound.ownerName} • ${sound.durationMs ~/ 1000}s',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.check_circle_outline, color: AppColors.brandBlue),
                onPressed: () {
                  onAudioSelected(sound);
                  Navigator.pop(context);
                },
              ),
            );
          },
        );
      },
    );
  }
}
