import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/unified_inbox_provider.dart';
import '../providers/selected_inbox_item_provider.dart';
import '../../social_hub/components/attachment_bubble.dart';
import '../../features/omni_command/omni_command_sheet.dart';

class InboxListPanel extends ConsumerWidget {
  const InboxListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(unifiedInboxProvider);
    final selectedItem = ref.watch(selectedInboxItemProvider);

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.darkBackground,
        border: Border(right: BorderSide(color: AppColors.outline, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Text('All Inboxes', style: AppTypography.sectionTitle(AppColors.textPrimary)),
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final unreadCount = inboxAsync.where((item) => !item.isRead).length;
                    if (unreadCount == 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$unreadCount', style: AppTypography.small(AppColors.brandWhite).copyWith(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
                const Spacer(),
                const OmniCommandButton(),
              ],
            ),
          ),
          
          // Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                _buildFilterChip('All', isSelected: true),
                const SizedBox(width: 8),
                _buildFilterChip('System'),
                const SizedBox(width: 8),
                _buildFilterChip('Social'),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Conversation List
          Expanded(
            child: Builder(
              builder: (context) {
                final items = inboxAsync;
                if (items.isEmpty) {
                  return Center(
                    child: Text('No messages found.', style: AppTypography.body(AppColors.textMuted)),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildConversationItem(
                      item: item,
                      isSelected: selectedItem?.id == item.id,
                      onTap: () => ref.read(selectedInboxItemProvider.notifier).select(item),
                    );
                  },
                );
              },
            ),
          ),
          
          // Footer Stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.outline, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Showing ${inboxAsync.length} conversations', style: AppTypography.small(AppColors.textMuted)),
                const Row(
                  children: [
                    Icon(Icons.chevron_left, color: AppColors.textSecondary, size: 16),
                    SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 16),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, {bool isSelected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.brandBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: isSelected ? null : Border.all(color: AppColors.outline),
      ),
      child: Text(
        label,
        style: AppTypography.small(isSelected ? AppColors.brandWhite : AppColors.textSecondary).copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
      ),
    );
  }

  IconData _getItemIcon(UnifiedItem item) {
    switch (item.type) {
      case UnifiedItemType.project: return Icons.account_tree;
      case UnifiedItemType.ai: return Icons.auto_awesome;
      case UnifiedItemType.device: return Icons.computer;
      case UnifiedItemType.channel: return Icons.hub;
      default: break; // fallback to platform
    }
    
    switch (item.platform) {
      case SocialPlatform.facebook:
        return Icons.facebook;
      case SocialPlatform.whatsapp:
        return Icons.wechat;
      case SocialPlatform.instagram:
        return Icons.camera_alt;
      case SocialPlatform.youtube:
        return Icons.video_library;
      case SocialPlatform.email:
        return Icons.email;
      case SocialPlatform.system:
        return Icons.settings; // changed from computer
      default:
        return Icons.message;
    }
  }

  Color _getItemColor(UnifiedItem item) {
    switch (item.type) {
      case UnifiedItemType.project: return AppColors.brandBlue;
      case UnifiedItemType.ai: return AppColors.neonPurple;
      case UnifiedItemType.device: return Colors.orange;
      case UnifiedItemType.channel: return Colors.blue;
      default: break; // fallback to platform
    }
    
    switch (item.platform) {
      case SocialPlatform.whatsapp: return const Color(0xFF25D366);
      case SocialPlatform.facebook: 
      case SocialPlatform.messenger:
      case SocialPlatform.meta: return const Color(0xFF0C4FA8);
      case SocialPlatform.instagram: return const Color(0xFFE1306C);
      case SocialPlatform.youtube: return const Color(0xFFFF0000);
      case SocialPlatform.tiktok: return const Color(0xFFFF0050);
      case SocialPlatform.telegram: return const Color(0xFF0088cc);
      default: return AppColors.brandWhite;
    }
  }


  Widget _buildConversationItem({
    required UnifiedItem item,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      color: isSelected ? AppColors.darkSurfaceHighlight : Colors.transparent,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.darkSurface,
                      backgroundImage: item.senderAvatarUrl.isNotEmpty ? NetworkImage(item.senderAvatarUrl) : null,
                      child: item.senderAvatarUrl.isEmpty
                          ? Text(item.senderName.isNotEmpty ? item.senderName[0].toUpperCase() : '?', style: AppTypography.bodyMedium(AppColors.brandWhite))
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: AppColors.darkBackground, shape: BoxShape.circle),
                        child: Icon(_getItemIcon(item), size: 10, color: _getItemColor(item)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
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
                              style: AppTypography.bodyMedium(isSelected ? AppColors.brandWhite : AppColors.textSecondary).copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(item.timestamp),
                            style: AppTypography.caption(AppColors.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.content,
                              style: AppTypography.small(item.isRead ? AppColors.textMuted : AppColors.brandWhite).copyWith(fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!item.isRead)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.brandBlue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (item.attachments.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: item.attachments.map((att) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: SizedBox(
                                  width: 100, // Smaller for desktop sidebar
                                  child: AttachmentBubble(attachment: att, isMine: false),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
