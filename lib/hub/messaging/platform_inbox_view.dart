import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../backend/connections/linked_accounts.dart';
import '../../backend/inbox/platform_inbox.dart';
import '../../shared/theme/app_theme.dart';

/// Which rows a [PlatformInboxView] shows.
enum PlatformInboxFilter { all, messages, comments }

/// One linked platform's messages and comments, inside the single inbox at
/// `/hub/messages`. Rows come from [platformInboxProvider]: delivered
/// `social_messages` docs plus, for Gmail and YouTube, the platform's API.
class PlatformInboxView extends ConsumerStatefulWidget {
  final String platformId;
  final VoidCallback onShowAll;
  final PlatformInboxFilter initialFilter;

  const PlatformInboxView({
    super.key,
    required this.platformId,
    required this.onShowAll,
    this.initialFilter = PlatformInboxFilter.all,
  });

  @override
  ConsumerState<PlatformInboxView> createState() => _PlatformInboxViewState();
}

class _PlatformInboxViewState extends ConsumerState<PlatformInboxView> {
  late PlatformInboxFilter _filter = widget.initialFilter;

  LinkedPlatform? get _platform => LinkedPlatform.fromId(widget.platformId);

  @override
  Widget build(BuildContext context) {
    final platform = _platform;
    if (platform == null) return _Message(icon: Icons.inbox_outlined, title: 'Unknown inbox', body: '', onAction: widget.onShowAll, actionLabel: 'All inboxes');

    final accounts = ref.watch(linkedAccountsProvider);
    final account = accounts.value?.where((a) => a.platform == platform).firstOrNull;

    return Column(
      children: [
        _AccountBar(platform: platform, account: account, onShowAll: widget.onShowAll),
        if (platform.messages && platform.comments) _filterBar(),
        Expanded(child: _body(platform, account, accounts.isLoading)),
      ],
    );
  }

  Widget _filterBar() {
    Widget chip(PlatformInboxFilter f, String label) {
      final on = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            setState(() => _filter = f);
          },
          labelStyle: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: on ? AppColors.brandWhite : context.textSecondary),
          selectedColor: AppColors.brandBlue,
          backgroundColor: context.surface,
          side: BorderSide(color: on ? AppColors.brandBlue : context.border),
          visualDensity: VisualDensity.compact,
          showCheckmark: false,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(children: [
        chip(PlatformInboxFilter.all, 'All'),
        chip(PlatformInboxFilter.messages, 'Messages'),
        chip(PlatformInboxFilter.comments, 'Comments'),
      ]),
    );
  }

  Widget _body(LinkedPlatform platform, LinkedAccount? account, bool loadingAccounts) {
    if (account == null) {
      if (loadingAccounts) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      return _Message(
        icon: platform.icon,
        title: '${platform.label} isn\'t connected',
        body: 'Connect your ${platform.label} account to see its ${platform.messages ? 'messages' : 'comments'} here.',
        actionLabel: 'Connect ${platform.label}',
        onAction: () => context.push('/social_hub'),
      );
    }
    if (!account.isUsable) {
      return _Message(
        icon: Icons.link_off_rounded,
        title: account.status == LinkStatus.expired ? '${platform.label} sign-in expired' : 'Reconnect ${platform.label}',
        body: 'Sign in to ${platform.label} again so Oneova can load this inbox.',
        actionLabel: 'Reconnect',
        onAction: () => context.push('/social_hub'),
      );
    }

    final itemsAsync = ref.watch(platformInboxProvider(platform.id));
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => _Message(
        icon: Icons.error_outline_rounded,
        title: 'Couldn\'t load ${platform.label}',
        body: e.toString(),
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(platformInboxProvider(platform.id)),
      ),
      data: (items) {
        final shown = items.where((i) => switch (_filter) {
              PlatformInboxFilter.all => true,
              PlatformInboxFilter.messages => !i.isComment,
              PlatformInboxFilter.comments => i.isComment,
            }).toList();
        if (shown.isEmpty) {
          final live = platform == LinkedPlatform.gmail || platform == LinkedPlatform.youtube;
          return _Message(
            icon: Icons.inbox_outlined,
            title: 'Nothing here yet',
            body: live
                ? 'New ${platform == LinkedPlatform.gmail ? 'email' : 'comments'} on ${account.accountName} appear here.'
                : '${platform.label} ${_filter == PlatformInboxFilter.comments ? 'comments' : 'messages'} appear here as soon as they are delivered to Oneova.',
          );
        }
        return RefreshIndicator(
          color: AppColors.brandBlue,
          onRefresh: () async => ref.invalidate(platformInboxProvider(platform.id)),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            itemCount: shown.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
            itemBuilder: (_, i) => _ItemTile(item: shown[i]),
          ),
        );
      },
    );
  }
}

class _AccountBar extends StatelessWidget {
  final LinkedPlatform platform;
  final LinkedAccount? account;
  final VoidCallback onShowAll;

  const _AccountBar({required this.platform, required this.account, required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final status = account?.status;
    final (label, color) = switch (status) {
      LinkStatus.connected => ('Connected', AppColors.brandBlue),
      LinkStatus.expired => ('Expired', AppColors.brandPink),
      LinkStatus.needsReconnect => ('Reconnect', AppColors.brandPink),
      null => ('Not connected', context.textMuted),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(platform.icon, size: 18, color: AppColors.brandBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(platform.label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                if ((account?.accountName ?? '').isNotEmpty)
                  Text(account!.accountName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(label.toUpperCase(),
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color)),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'All inboxes',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: context.textSecondary),
            onPressed: onShowAll,
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final PlatformInboxItem item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final unread = !item.isRead;
    final kindIcon = switch (item.kind) {
      InboxItemKind.email => Icons.mail_outline_rounded,
      InboxItemKind.comment => Icons.mode_comment_outlined,
      InboxItemKind.mention => Icons.alternate_email_rounded,
      InboxItemKind.message => Icons.chat_bubble_outline_rounded,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      dense: true,
      onTap: () => markPlatformItemRead(item),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: context.surfaceMid,
        backgroundImage: item.senderAvatarUrl.isNotEmpty ? NetworkImage(item.senderAvatarUrl) : null,
        child: item.senderAvatarUrl.isEmpty
            ? Text(item.senderName.isNotEmpty ? item.senderName[0].toUpperCase() : '?',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary))
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(item.senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: unread ? FontWeight.w800 : FontWeight.w600, color: context.textPrimary)),
          ),
          Text(timeago.format(item.timestamp, locale: 'en_short'),
              style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted)),
        ],
      ),
      subtitle: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4),
            child: Icon(kindIcon, size: 12, color: context.textMuted),
          ),
          Expanded(
            child: Text(
              item.title.isNotEmpty ? '${item.title} — ${item.preview}' : item.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: unread ? context.textPrimary : context.textSecondary),
            ),
          ),
          if (unread)
            Container(
              margin: const EdgeInsets.only(left: 6, top: 4),
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({required this.icon, required this.title, required this.body, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.brandBlue),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: AppColors.brandWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: onAction,
                child: Text(actionLabel!, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
