import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/unified_inbox_provider.dart';

class InboxSidebar extends ConsumerWidget {
  const InboxSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(unifiedInboxProvider);
    
    // Calculate real unread counts
    int totalUnread = 0;
    int whatsappUnread = 0;
    int facebookUnread = 0;
    int instagramUnread = 0;
    int emailUnread = 0;
    int systemUnread = 0;

    for (final item in inboxAsync) {
      if (!item.isRead) {
        totalUnread++;
        if (item.platform == SocialPlatform.whatsapp) whatsappUnread++;
        if (item.platform == SocialPlatform.facebook) facebookUnread++;
        if (item.platform == SocialPlatform.instagram) instagramUnread++;
        if (item.platform == SocialPlatform.email) emailUnread++;
        if (item.platform == SocialPlatform.system) systemUnread++;
      }
    }

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.darkBackground,
        border: Border(right: BorderSide(color: AppColors.outline, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Logo Area
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('MP', style: AppTypography.applicationTitle(AppColors.brandWhite)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Manifested\nPublishers',
                    style: AppTypography.bodyMedium(AppColors.brandWhite).copyWith(height: 1.2, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavItem(icon: Icons.inbox, label: 'Inbox', badge: totalUnread, isSelected: true),
                _buildNavItem(icon: Icons.contacts, label: 'Contacts'),
                _buildNavItem(icon: Icons.chat, label: 'Channels'),
                _buildNavItem(
                  icon: Icons.analytics, 
                  label: 'Analytics',
                  onTap: () => context.push('/inbox/analytics'),
                ),
                _buildNavItem(icon: Icons.auto_mode, label: 'Automation'),
                _buildNavItem(icon: Icons.calendar_today, label: 'Calendar'),
                _buildNavItem(icon: Icons.folder, label: 'Files & Documents'),
                _buildNavItem(icon: Icons.settings, label: 'Settings'),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Text('MAIN SERVICES', style: AppTypography.caption(AppColors.textMuted).copyWith(letterSpacing: 1.2)),
                ),
                _buildNavItem(icon: Icons.computer, label: 'System', badge: systemUnread),
                _buildNavItem(icon: Icons.wechat, label: 'WhatsApp', badge: whatsappUnread),
                _buildNavItem(icon: Icons.facebook, label: 'Facebook', badge: facebookUnread),
                _buildNavItem(icon: Icons.camera_alt, label: 'Instagram', badge: instagramUnread),
                _buildNavItem(icon: Icons.email, label: 'Email', badge: emailUnread),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Text('QUICK ACCESS', style: AppTypography.caption(AppColors.textMuted).copyWith(letterSpacing: 1.2)),
                ),
                _buildNavItem(icon: Icons.support_agent, label: 'MP Support', showChevron: true),
                _buildNavItem(icon: Icons.school, label: 'Courses & Students', showChevron: true),
                _buildNavItem(icon: Icons.point_of_sale, label: 'Sales & Enquiries', showChevron: true),
                _buildNavItem(icon: Icons.group, label: 'Team Chat', showChevron: true),
                _buildNavItem(icon: Icons.help, label: 'Help & Support', showChevron: true),
              ],
            ),
          ),
          
          // Bottom Premium Card
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.premiumGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Text('MP', style: AppTypography.metric(AppColors.brandWhite)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manifested Publishers', style: AppTypography.small(AppColors.brandWhite).copyWith(fontWeight: FontWeight.bold)),
                        Text('Learn - Grow - Succeed', style: AppTypography.caption(AppColors.brandWhite.withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    int badge = 0,
    bool isSelected = false,
    bool showChevron = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.darkSurfaceHighlight : Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap ?? () {},
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isSelected ? AppColors.brandBlue : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isSelected ? AppColors.brandBlue : AppColors.textSecondary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.navigation(isSelected ? AppColors.brandWhite : AppColors.textSecondary).copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge.toString(),
                      style: AppTypography.caption(AppColors.brandWhite).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                if (showChevron)
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
