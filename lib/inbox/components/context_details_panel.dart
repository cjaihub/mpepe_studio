import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import '../providers/selected_inbox_item_provider.dart';
import '../../backend/unified_inbox_provider.dart';
import 'package:intl/intl.dart';

class ContextDetailsPanel extends ConsumerWidget {
  const ContextDetailsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedInboxItemProvider);

    if (selectedItem == null) {
      return Container(
        width: 320,
        decoration: const BoxDecoration(
          color: AppColors.darkBackground,
          border: Border(left: BorderSide(color: AppColors.outline, width: 1)),
        ),
        child: const Center(
          child: Text(
            'Select a conversation\nto view details',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.darkBackground,
        border: Border(left: BorderSide(color: AppColors.outline, width: 1)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, 'Context Details', true),
            const SizedBox(height: 24),
            _buildContactDetails(context, selectedItem),
            const SizedBox(height: 24),
            _buildConversationActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title, bool showClose) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge!.copyWith(color: AppColors.brandWhite)),
        const Spacer(),
        if (showClose)
          const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
      ],
    );
  }

  Widget _buildContactDetails(BuildContext context, UnifiedItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.darkSurfaceHighlight,
              backgroundImage: item.senderAvatarUrl.isNotEmpty ? NetworkImage(item.senderAvatarUrl) : null,
              child: item.senderAvatarUrl.isEmpty
                  ? Text(item.senderName.isNotEmpty ? item.senderName[0].toUpperCase() : '?', style: Theme.of(context).textTheme.titleLarge!.copyWith(color: AppColors.brandWhite))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.senderName, style: AppTypography.bodyMedium(AppColors.brandWhite).copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.darkSurfaceHighlight, borderRadius: BorderRadius.circular(4)),
                    child: Text(_getPlatformName(item.platform), style: AppTypography.caption(AppColors.brandWhite)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildInfoStat('Source', _getPlatformName(item.platform)),
            _buildInfoStat('Time', DateFormat('MMM d, h:mm a').format(item.timestamp)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildPlatformIcon(item.platform),
          ],
        ),
      ],
    );
  }

  String _getPlatformName(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.youtube: return 'YouTube';
      case SocialPlatform.tiktok: return 'TikTok';
      case SocialPlatform.meta: return 'Meta';
      case SocialPlatform.instagram: return 'Instagram';
      case SocialPlatform.system: return 'System';
      case SocialPlatform.whatsapp: return 'WhatsApp';
      case SocialPlatform.facebook: return 'Facebook';
      case SocialPlatform.messenger: return 'Messenger';
      case SocialPlatform.email: return 'Email';
      case SocialPlatform.telegram: return 'Telegram';
      case SocialPlatform.sms: return 'SMS';
      case SocialPlatform.website: return 'Website';
    }
  }

  Color _getPlatformColor(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.whatsapp: return const Color(0xFF25D366);
      case SocialPlatform.facebook: 
      case SocialPlatform.messenger:
      case SocialPlatform.meta: return const Color(0xFF0C4FA8);
      case SocialPlatform.instagram: return const Color(0xFFE1306C);
      case SocialPlatform.youtube: return const Color(0xFFFF0000);
      case SocialPlatform.tiktok: return const Color(0xFFFF0050); // TikTok red accent
      case SocialPlatform.telegram: return const Color(0xFF0088cc);
      case SocialPlatform.sms: return const Color(0xFF34C759);
      case SocialPlatform.website: return const Color(0xFF6366F1); // Indigo
      default: return AppColors.brandWhite;
    }
  }

  Widget _buildPlatformIcon(SocialPlatform platform) {
    IconData iconData;
    switch (platform) {
      case SocialPlatform.youtube: iconData = Icons.video_library; break;
      case SocialPlatform.tiktok: iconData = Icons.music_note; break;
      case SocialPlatform.meta: iconData = Icons.facebook; break;
      case SocialPlatform.instagram: iconData = Icons.camera_alt; break;
      case SocialPlatform.system: iconData = Icons.computer; break;
      case SocialPlatform.whatsapp: iconData = Icons.wechat; break;
      case SocialPlatform.facebook: iconData = Icons.facebook; break;
      case SocialPlatform.messenger: iconData = Icons.message; break;
      case SocialPlatform.email: iconData = Icons.email; break;
      case SocialPlatform.telegram: iconData = Icons.send; break;
      case SocialPlatform.sms: iconData = Icons.sms; break;
      case SocialPlatform.website: iconData = Icons.language; break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.outline),
      ),
      child: Icon(iconData, color: _getPlatformColor(platform), size: 16),
    );
  }

  Widget _buildInfoStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(AppColors.textMuted)),
        const SizedBox(height: 4),
        Text(value, style: AppTypography.small(AppColors.textSecondary).copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildConversationActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conversation Actions', style: AppTypography.bodyMedium(AppColors.brandWhite).copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildActionItem(Icons.edit_note, 'Add Note'),
        _buildActionItem(Icons.person_add, 'Assign to Team'),
        _buildActionItem(Icons.support, 'Create Support Ticket'),
        _buildActionItem(Icons.calendar_today, 'Add to Calendar'),
        _buildActionItem(Icons.share, 'Share Contact'),
        _buildActionItem(Icons.block, 'Block User'),
      ],
    );
  }

  Widget _buildActionItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 12),
          Text(label, style: AppTypography.navigation(AppColors.textSecondary)),
        ],
      ),
    );
  }
}
