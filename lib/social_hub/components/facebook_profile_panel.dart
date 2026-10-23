import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../backend/meta_profile_service.dart';
import '../../backend/social_connection_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class FacebookProfilePanel extends ConsumerWidget {
  const FacebookProfilePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsAsync = ref.watch(socialConnectionProvider);
    final profileAsync = ref.watch(metaProfileProvider);

    return connectionsAsync.when(
      data: (connections) {
        final fbConnection = connections.where((c) => c.platform.toLowerCase() == 'facebook').firstOrNull;
        
        if (fbConnection == null) {
          return const SizedBox.shrink();
        }

        return OneovaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Avatar, Name, and Facebook icon
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: null,
                    backgroundColor: context.surfaceMid,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fbConnection.accountName,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Facebook Page',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.facebook, color: AppColors.brandBlue, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Stats Row
              profileAsync.when(
                data: (state) => _buildStatsRow(state),
                loading: () => const Center(child: AnimatedLoadingIndicator()),
                error: (err, stack) => Text('Error loading stats: $err', style: const TextStyle(color: Colors.red)),
              ),
              
              const SizedBox(height: 24),
              Text(
                'Recent Posts',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              
              // Posts List
              profileAsync.when(
                data: (state) => _buildPostsList(state.posts),
                loading: () => const SizedBox(height: 140, child: Center(child: AnimatedLoadingIndicator())),
                error: (error, stackTrace) => const SizedBox.shrink(),
              ),
            ],
          ),
        ).animate().fade(duration: 500.ms).slideY(begin: 0.1);
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatsRow(MetaProfileState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatItem(label: 'Followers', value: state.followers),
        _StatItem(label: 'Total Likes', value: state.totalLikes),
        _StatItem(label: 'Posts', value: state.posts.length),
      ],
    );
  }

  Widget _buildPostsList(List<MetaPostModel> posts) {
    if (posts.isEmpty) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Text(
            'No recent posts found on this page.',
            style: GoogleFonts.outfit(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: posts.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return _PostCard(post: posts[index]);
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
        Text(
          formatter.format(value),
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  final MetaPostModel post;

  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.compact();
    final hasPicture = post.pictureUrl != null && post.pictureUrl!.isNotEmpty;

    return Container(
      width: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: context.surfaceMid,
        border: Border.all(color: context.border, width: 1.0),
        image: hasPicture ? DecorationImage(
          image: NetworkImage(post.pictureUrl!),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.6),
            BlendMode.darken,
          ),
        ) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.thumb_up_alt_rounded, color: hasPicture ? Colors.white : context.textSecondary, size: 14),
                const SizedBox(width: 4),
                Text(
                  formatter.format(post.likes),
                  style: GoogleFonts.outfit(
                    color: hasPicture ? Colors.white : context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.comment_rounded, color: hasPicture ? Colors.white : context.textSecondary, size: 14),
                const SizedBox(width: 4),
                Text(
                  formatter.format(post.comments),
                  style: GoogleFonts.outfit(
                    color: hasPicture ? Colors.white : context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Text(
              post.message.isNotEmpty ? post.message : 'Photo Post',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: hasPicture ? Colors.white : context.textPrimary,
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
