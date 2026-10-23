import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../backend/routing/oneova_share_engine.dart';
import '../../backend/social/models/audio_track.dart';
import '../../backend/social/models/content.dart';
import '../../backend/social/services/audio_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/animated_loading_indicator.dart';

final _soundDetailsProvider = FutureProvider.autoDispose.family<AudioTrack, String>(
  (ref, id) => ref.watch(audioServiceProvider).getSoundDetails(id),
);

final _soundVideosProvider = StreamProvider.autoDispose.family<List<Content>, String>(
  (ref, id) => ref.watch(audioServiceProvider).watchVideosForSound(id),
);

final _soundFavoriteProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(audioServiceProvider).watchIsFavorite(id),
);

class SoundPageScreen extends ConsumerWidget {
  final String soundId;
  const SoundPageScreen({super.key, required this.soundId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soundAsync = ref.watch(_soundDetailsProvider(soundId));

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 50,
        title: Text('Sound', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: context.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (soundAsync.hasValue)
            IconButton(
              tooltip: 'Share sound',
              icon: Icon(Icons.ios_share_rounded, color: context.textPrimary, size: 20),
              onPressed: () {
                HapticFeedback.lightImpact();
                final sound = soundAsync.value!;
                SharePlus.instance.share(ShareParams(
                  text: '${sound.title} by ${sound.ownerName} on Oneova\nhttps://${OneovaShareEngine.webDomain}/sound/${sound.id}',
                ));
              },
            ),
        ],
      ),
      body: soundAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', textAlign: TextAlign.center, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13)),
          ),
        ),
        data: (sound) => _SoundBody(sound: sound),
      ),
      floatingActionButton: soundAsync.hasValue
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brandBlue,
              onPressed: () {
                HapticFeedback.lightImpact();
                context.push('/create/camera');
              },
              icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
              label: Text('Create with camera', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _SoundBody extends ConsumerWidget {
  final AudioTrack sound;
  const _SoundBody({required this.sound});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(_soundVideosProvider(sound.id));
    final isFavorite = ref.watch(_soundFavoriteProvider(sound.id)).value ?? false;
    final videos = videosAsync.value ?? const <Content>[];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border, width: 1.0),
                    image: sound.coverImageUrl.isNotEmpty
                        ? DecorationImage(image: NetworkImage(sound.coverImageUrl), fit: BoxFit.cover)
                        : null,
                  ),
                  child: sound.coverImageUrl.isEmpty ? Icon(Icons.music_note_rounded, color: AppColors.brandPink, size: 32) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sound.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: sound.ownerId.isEmpty ? null : () => context.push('/profile/${sound.ownerId}'),
                        child: Text(sound.ownerName, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (sound.durationMs > 0) '${sound.durationMs ~/ 1000}s',
                          '${videos.length} video${videos.length == 1 ? '' : 's'}',
                        ].join(' · '),
                        style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            try {
                              await ref.read(audioServiceProvider).toggleFavorite(sound.id);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.brandPink));
                              }
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isFavorite ? AppColors.brandPink : context.border, width: 1.0),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                          ),
                          icon: Icon(isFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                              size: 16, color: isFavorite ? AppColors.brandPink : context.textPrimary),
                          label: Text(isFavorite ? 'Saved' : 'Save',
                              style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 250.ms),
        ),
        if (sound.attribution.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Text(
                  '${sound.attribution} · ${sound.licenseType.name} licence',
                  style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11.5),
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (videosAsync.isLoading)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue))))
        else if (videos.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('No videos use this sound yet.',
                  textAlign: TextAlign.center, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 88),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 9 / 16,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final video = videos[index];
                  return GestureDetector(
                    onTap: () => context.push('/hub/home?v=${video.id}'),
                    child: Container(
                      color: context.surfaceMid,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (video.mediaMetadata.thumbnailUrl != null && video.mediaMetadata.thumbnailUrl!.isNotEmpty)
                            Image.network(video.mediaMetadata.thumbnailUrl!, fit: BoxFit.cover)
                          else
                            Icon(Icons.play_circle_outline_rounded, color: context.textMuted, size: 26),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Row(
                              children: [
                                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 13),
                                const SizedBox(width: 2),
                                Text('${video.viewCount}',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: videos.length,
              ),
            ),
          ),
      ],
    );
  }
}
