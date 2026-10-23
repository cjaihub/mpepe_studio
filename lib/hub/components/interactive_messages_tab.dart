import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../backend/unified_inbox_provider.dart';
import '../../../shared/theme/app_theme.dart';

class InteractiveMessagesTab extends ConsumerStatefulWidget {
  const InteractiveMessagesTab({super.key});

  @override
  ConsumerState<InteractiveMessagesTab> createState() => _InteractiveMessagesTabState();
}

class _InteractiveMessagesTabState extends ConsumerState<InteractiveMessagesTab> {
  SocialPlatform? _selectedPlatform;

  final List<Map<String, dynamic>> _platforms = [
    {'name': 'All', 'platform': null, 'icon': FontAwesomeIcons.infinity, 'color': Colors.white},
    {'name': 'Meta', 'platform': SocialPlatform.meta, 'icon': FontAwesomeIcons.facebook, 'color': const Color(0xFF0C4FA8)},
    {'name': 'Instagram', 'platform': SocialPlatform.instagram, 'icon': FontAwesomeIcons.instagram, 'color': const Color(0xFFE1306C)},
    {'name': 'YouTube', 'platform': SocialPlatform.youtube, 'icon': FontAwesomeIcons.youtube, 'color': const Color(0xFFFF0000)},
    {'name': 'TikTok', 'platform': SocialPlatform.tiktok, 'icon': FontAwesomeIcons.tiktok, 'color': Colors.white},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildWhatsappStyleHeader(),
        _buildFilterBar(),
        Expanded(
          child: _buildMessagesList(context),
        ),
      ],
    );
  }

  Widget _buildWhatsappStyleHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border(bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Chats',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Row(
            children: [
              Icon(Icons.camera_alt_outlined, color: AppColors.textSecondary, size: 22),
              const SizedBox(width: 16),
              Icon(Icons.search, color: AppColors.textSecondary, size: 24),
              const SizedBox(width: 16),
              Icon(Icons.more_vert, color: AppColors.textSecondary, size: 24),
            ],
          )
        ],
      ),
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
                  FaIcon(
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

  Widget _buildMessagesList(BuildContext context) {
    final allItems = ref.watch(unifiedInboxProvider);
    var items = allItems.where((item) => item.type == UnifiedItemType.message).toList();

    if (_selectedPlatform != null) {
      items = items.where((item) => item.platform == _selectedPlatform).toList();
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(FontAwesomeIcons.inbox, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'No messages found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ).animate().fade().scale(duration: 400.ms),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _MessageChatCard(item: items[index]).animate().fade().slideY(begin: 0.1, duration: 300.ms, delay: (50 * index).ms);
      },
    );
  }
}

class _MessageChatCard extends ConsumerWidget {
  final UnifiedItem item;

  const _MessageChatCard({required this.item});

  dynamic _getPlatformIcon() {
    switch (item.platform) {
      case SocialPlatform.youtube:
        return FontAwesomeIcons.youtube;
      case SocialPlatform.tiktok:
        return FontAwesomeIcons.tiktok;
      case SocialPlatform.meta:
        return FontAwesomeIcons.facebook;
      case SocialPlatform.instagram:
        return FontAwesomeIcons.instagram;
      case SocialPlatform.system:
      default:
        return FontAwesomeIcons.bell;
    }
  }

  Color _getPlatformColor() {
    switch (item.platform) {
      case SocialPlatform.youtube:
        return const Color(0xFFFF0000);
      case SocialPlatform.tiktok:
        return Colors.white;
      case SocialPlatform.meta:
        return const Color(0xFF0C4FA8);
      case SocialPlatform.instagram:
        return const Color(0xFFE1306C);
      case SocialPlatform.system:
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = !item.isRead;

    return Container(
      decoration: BoxDecoration(
        color: isUnread ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.2) : Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (isUnread) {
              ref.read(unifiedInboxProvider.notifier).markAsRead(item.id);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildAvatar(),
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
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatShortTime(item.timestamp),
                            style: TextStyle(
                              color: isUnread ? Theme.of(context).colorScheme.primary : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (!isUnread)
                            const Padding(
                              padding: EdgeInsets.only(right: 4.0),
                              child: Icon(Icons.done_all, size: 16, color: Colors.blue),
                            ),
                          Expanded(
                            child: Text(
                              item.content,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isUnread)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
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

  Widget _buildAvatar() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _getPlatformColor(), width: 2),
            boxShadow: [
              BoxShadow(
                color: _getPlatformColor().withValues(alpha: 0.3),
                blurRadius: 8,
              )
            ],
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundImage: item.senderAvatarUrl.isNotEmpty ? NetworkImage(item.senderAvatarUrl) : null,
            backgroundColor: AppColors.darkSurfaceHighlight,
            child: item.senderAvatarUrl.isEmpty ? Icon(Icons.person, color: AppColors.textSecondary, size: 28) : null,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.darkSurfaceHighlight, width: 1.5),
            ),
            child: FaIcon(_getPlatformIcon(), size: 12, color: _getPlatformColor()),
          ),
        ),
      ],
    );
  }

  String _formatShortTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inDays > 0) {
      if (difference.inDays == 1) return 'Yesterday';
      return '${time.day}/${time.month}/${time.year}';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
