import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/connections/linked_accounts.dart';
import '../../backend/inbox/platform_inbox.dart';
import '../../shared/theme/app_theme.dart';

/// Picks which inbox the single inbox (`/hub/messages`) shows: all Oneova
/// chats, or one linked platform. Lists only accounts the user really linked
/// ([linkedAccountsProvider]); unread counts come from Firestore.
class ConnectedInboxesDropdown extends ConsumerWidget {
  final String selectedPlatform;
  final ValueChanged<String> onSelectPlatform;
  final VoidCallback onClose;

  /// Unread Oneova chat messages (from `chats.unreadCounts`).
  final int totalUnreadCount;

  const ConnectedInboxesDropdown({
    super.key,
    required this.selectedPlatform,
    required this.onSelectPlatform,
    required this.onClose,
    this.totalUnreadCount = 0,
  });

  static void show(
    BuildContext context, {
    required String selectedPlatform,
    required ValueChanged<String> onSelectPlatform,
    int totalUnreadCount = 0,
  }) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        alignment: Alignment.topCenter,
        child: ConnectedInboxesDropdown(
          selectedPlatform: selectedPlatform,
          onSelectPlatform: (platform) {
            Navigator.of(ctx).pop();
            onSelectPlatform(platform);
          },
          onClose: () => Navigator.of(ctx).pop(),
          totalUnreadCount: totalUnreadCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(linkedAccountsProvider);
    final accounts = (accountsAsync.value ?? const <LinkedAccount>[]).where((a) => a.platform.hasInbox).toList();
    final unread = ref.watch(platformUnreadCountsProvider);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.border, width: 1),
        boxShadow: AppShadows.md,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'INBOXES',
            style: GoogleFonts.inter(color: context.textMuted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.9),
          ),
          const SizedBox(height: 8),
          _Row(
            icon: Icons.forum_rounded,
            title: 'All Oneova chats',
            subtitle: 'Direct messages, groups and channels',
            selected: selectedPlatform == 'all',
            badge: totalUnreadCount,
            onTap: () => onSelectPlatform('all'),
          ),
          if (accountsAsync.isLoading && accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          for (final a in accounts)
            _Row(
              icon: a.platform.icon,
              title: a.platform.label,
              subtitle: switch (a.status) {
                LinkStatus.connected => a.accountName,
                LinkStatus.expired => 'Sign-in expired',
                LinkStatus.needsReconnect => 'Reconnect to load',
              },
              selected: selectedPlatform == a.platform.id,
              badge: unread[a.platform.id] ?? 0,
              warn: !a.isUsable,
              onTap: () => onSelectPlatform(a.platform.id),
            ),
          const SizedBox(height: 6),
          Divider(height: 1, color: context.border),
          const SizedBox(height: 6),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandBlue,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: Text(
              accounts.isEmpty ? 'Connect Gmail, YouTube, Instagram…' : 'Manage connected accounts',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              onClose();
              context.push('/social_hub');
            },
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final int badge;
  final bool warn;
  final VoidCallback onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.badge,
    required this.onTap,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.brandBlue : context.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: warn ? AppColors.brandPink : context.textMuted)),
                ],
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text(badge > 99 ? '99+' : '$badge',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.brandWhite)),
              ),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded, size: 16, color: AppColors.brandBlue),
            ],
          ],
        ),
      ),
    );
  }
}
