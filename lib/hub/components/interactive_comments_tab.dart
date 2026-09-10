import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../backend/unified_inbox_provider.dart';
import '../../../shared/theme/app_theme.dart';
import 'comment_bubble_widget.dart';
import 'enhanced_comment_input.dart';

class InteractiveCommentsTab extends ConsumerStatefulWidget {
  const InteractiveCommentsTab({super.key});

  @override
  ConsumerState<InteractiveCommentsTab> createState() => _InteractiveCommentsTabState();
}

class _InteractiveCommentsTabState extends ConsumerState<InteractiveCommentsTab> {
  SocialPlatform? _selectedPlatform;

  final List<Map<String, dynamic>> _platforms = [
    {'name': 'All', 'platform': null, 'icon': Icons.all_inclusive, 'color': Colors.white},
    {'name': 'Meta', 'platform': SocialPlatform.meta, 'icon': FontAwesomeIcons.facebook, 'color': const Color(0xFF1877F2)},
    {'name': 'Instagram', 'platform': SocialPlatform.instagram, 'icon': FontAwesomeIcons.instagram, 'color': const Color(0xFFE1306C)},
    {'name': 'YouTube', 'platform': SocialPlatform.youtube, 'icon': FontAwesomeIcons.youtube, 'color': const Color(0xFFFF0000)},
    {'name': 'TikTok', 'platform': SocialPlatform.tiktok, 'icon': FontAwesomeIcons.tiktok, 'color': Colors.white},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: _buildCommentsList(),
        ),
        const EnhancedCommentInput(),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceHighlight.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.3))),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _platforms.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final platformData = _platforms[index];
          final isSelected = _selectedPlatform == platformData['platform'];

          return InkWell(
            onTap: () {
              setState(() {
                _selectedPlatform = platformData['platform'];
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? platformData['color']?.withValues(alpha: 0.2) : AppColors.darkSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? platformData['color'] : AppColors.outline,
                  width: isSelected ? 1.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: (platformData['color'] as Color).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Icon(
                    platformData['icon'],
                    size: 16,
                    color: isSelected ? platformData['color'] : AppColors.textSecondary,
                  ),
                  if (isSelected || platformData['name'] == 'All') ...[
                    const SizedBox(width: 8),
                    Text(
                      platformData['name'],
                      style: TextStyle(
                        color: isSelected ? platformData['color'] : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCommentsList() {
    return Consumer(
      builder: (context, ref, child) {
        final allItems = ref.watch(unifiedInboxProvider);
        var comments = allItems.where((item) => item.type == UnifiedItemType.comment).toList();

        if (_selectedPlatform != null) {
          comments = comments.where((item) => item.platform == _selectedPlatform).toList();
        }

        // Simulate AI checking on mount
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (var comment in comments) {
            if (comment.isHarsh && !comment.isMutedByAI) {
              ref.read(unifiedInboxProvider.notifier).muteCommentFromSource(comment.id);
            }
          }
        });

        comments.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (comments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(FontAwesomeIcons.commentSlash, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text(
                  'No comments found',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                ),
              ],
            ).animate().fade().scale(duration: 400.ms),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          itemCount: comments.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: CommentBubbleWidget(comment: comments[index])
                  .animate()
                  .fade()
                  .slideY(begin: 0.1, duration: 300.ms, delay: (50 * index).ms),
            );
          },
        );
      },
    );
  }
}
