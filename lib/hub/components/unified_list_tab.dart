import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../backend/unified_inbox_provider.dart';
import '../../../shared/theme/app_theme.dart';

class UnifiedListTab extends ConsumerWidget {
  final UnifiedItemType itemType;

  const UnifiedListTab({super.key, required this.itemType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allItems = ref.watch(unifiedInboxProvider);
    final items = allItems.where((item) => item.type == itemType).toList();
    // Sort by timestamp descending
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (items.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _UnifiedItemCard(item: item);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'You\'re all caught up!',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _UnifiedItemCard extends ConsumerWidget {
  final UnifiedItem item;

  const _UnifiedItemCard({required this.item});

  IconData _getPlatformIcon() {
    switch (item.platform) {
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
    switch (item.platform) {
      case SocialPlatform.youtube:
        return Colors.red;
      case SocialPlatform.tiktok:
        return Colors.tealAccent;
      case SocialPlatform.meta:
        return Colors.blueAccent;
      case SocialPlatform.instagram:
        return Colors.purpleAccent;
      case SocialPlatform.system:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = !item.isRead;

    return GestureDetector(
      onTap: () {
        if (isUnread) {
          ref.read(unifiedInboxProvider.notifier).markAsRead(item.id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUnread ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUnread ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3) : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
          boxShadow: isUnread ? [] : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  backgroundImage: item.senderAvatarUrl.isNotEmpty ? NetworkImage(item.senderAvatarUrl) : null,
                  backgroundColor: AppColors.darkSurfaceHighlight,
                  child: item.senderAvatarUrl.isEmpty ? Icon(Icons.person, color: AppColors.textSecondary) : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_getPlatformIcon(), size: 12, color: _getPlatformColor()),
                  ),
                ),
                if (isUnread)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.senderName,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeago.format(item.timestamp),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.content,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: isUnread ? 0.9 : 0.6),
                      fontSize: 14,
                    ),
                  ),
                  if (item.handledByAI) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 12, color: AppColors.neonPurple),
                        const SizedBox(width: 4),
                        Text(
                          'Replied by CJ AI Assistant',
                          style: TextStyle(
                            color: AppColors.neonPurple,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
