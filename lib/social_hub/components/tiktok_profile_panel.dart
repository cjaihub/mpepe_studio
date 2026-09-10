import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../backend/tiktok_oauth_service.dart';
import '../../backend/tiktok_profile_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';

class TikTokProfilePanel extends ConsumerWidget {
  const TikTokProfilePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oauthState = ref.watch(tiktokOAuthProvider);
    final profileAsync = ref.watch(tiktokProfileProvider);

    if (oauthState.account == null) {
      return const SizedBox.shrink();
    }

    final account = oauthState.account!;

    return MpepeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, and TikTok icon
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: account.avatarUrl != null ? NetworkImage(account.avatarUrl!) : null,
                backgroundColor: AppColors.darkSurfaceHighlight,
                child: account.avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TikTok Creator',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.music_note_rounded, color: Color(0xFF00F2FE), size: 20),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Stats Row
          profileAsync.when(
            data: (state) => _buildStatsRow(state),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Text('Error loading stats: $err', style: const TextStyle(color: Colors.red)),
          ),
          
          const SizedBox(height: 24),
          Text(
            'Recent Videos',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          
          // Videos List
          profileAsync.when(
            data: (state) => _buildVideosList(state.videos),
            loading: () => const SizedBox(height: 140, child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    ).animate().fade(duration: 500.ms).slideY(begin: 0.1);
  }

  Widget _buildStatsRow(TikTokProfileState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatItem(label: 'Followers', value: state.followers),
        _StatItem(label: 'Total Likes', value: state.totalLikes),
        _StatItem(label: 'Videos', value: state.videos.length),
      ],
    );
  }

  Widget _buildVideosList(List<TikTokVideoModel> videos) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return _VideoCard(video: videos[index]);
        },
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final int value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.compact();
    
    return Column(
      children: [
        // Using AnimatedSwitcher or direct text since value updates frequently
        Text(
          formatter.format(value),
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _VideoCard extends StatelessWidget {
  final TikTokVideoModel video;

  const _VideoCard({required this.video});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.compact();

    return Container(
      width: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.darkSurfaceHighlight,
        image: DecorationImage(
          image: NetworkImage(video.thumbnailUrl),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.4),
            BlendMode.darken,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  formatter.format(video.views),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
