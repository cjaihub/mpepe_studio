import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:ui';

import '../../../backend/unified_inbox_provider.dart';
import '../../../shared/theme/app_theme.dart';

class CommentBubbleWidget extends StatelessWidget {
  final UnifiedItem comment;

  const CommentBubbleWidget({super.key, required this.comment});

  IconData _getPlatformIcon() {
    switch (comment.platform) {
      case SocialPlatform.youtube:
        return Icons.play_arrow;
      case SocialPlatform.tiktok:
        return Icons.music_note;
      case SocialPlatform.meta:
        return Icons.facebook;
      case SocialPlatform.instagram:
        return Icons.camera_alt;
      case SocialPlatform.system:
        return Icons.settings;
    }
  }

  Color _getPlatformColor() {
    switch (comment.platform) {
      case SocialPlatform.youtube:
        return Colors.red;
      case SocialPlatform.tiktok:
        return Colors.tealAccent;
      case SocialPlatform.meta:
        return Colors.blueAccent;
      case SocialPlatform.instagram:
        return Colors.pinkAccent;
      case SocialPlatform.system:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 2),
                _buildBubble(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundImage: comment.senderAvatarUrl.isNotEmpty ? NetworkImage(comment.senderAvatarUrl) : null,
          backgroundColor: AppColors.darkSurfaceHighlight,
          child: comment.senderAvatarUrl.isEmpty ? Icon(Icons.person, color: AppColors.textSecondary, size: 16) : null,
        ),
        Positioned(
          bottom: -4,
          right: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.darkBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(_getPlatformIcon(), size: 10, color: _getPlatformColor()),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          comment.senderName,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          timeago.format(comment.timestamp),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(BuildContext context) {
    Widget bubbleContent = Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Text(
        comment.content,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9),
          fontSize: 13,
          height: 1.3,
        ),
      ),
    );

    if (comment.isMutedByAI) {
      return Stack(
        children: [
          bubbleContent,
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(
                  color: AppColors.darkBackground.withValues(alpha: 0.4),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.textSecondary, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Hidden by AI',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return bubbleContent;
  }
}
