import 'package:oneova/shared/widgets/smooth_load.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../backend/live/models/live_models.dart';
import '../../backend/live/services/live_service.dart';
import '../../backend/notifications/models/app_notification.dart';
import '../../backend/notifications/providers/notification_service.dart';
import '../../backend/notifications/services/follower_alert_service.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/services/play_update_service.dart';

/// Filter chips shown above the list. `null` categories means "no category
/// filter" (All / Unread).
class _Filter {
  final String id;
  final String label;
  final IconData icon;
  final Set<AppNotificationCategory>? categories;
  const _Filter(this.id, this.label, this.icon, this.categories);
}

const _filters = <_Filter>[
  _Filter('all', 'All', Icons.notifications_none_rounded, null),
  _Filter('unread', 'Unread', Icons.mark_email_unread_outlined, null),
  _Filter('live', 'Live', Icons.sensors_rounded, {AppNotificationCategory.live}),
  _Filter('posts', 'Posts', Icons.play_circle_outline_rounded, {AppNotificationCategory.newPost}),
  _Filter('follows', 'Follows', Icons.person_add_alt_1_rounded, {AppNotificationCategory.newFollower, AppNotificationCategory.followRequest}),
  _Filter('likes', 'Likes', Icons.favorite_border_rounded, {AppNotificationCategory.like, AppNotificationCategory.reaction}),
  _Filter('comments', 'Comments', Icons.chat_bubble_outline_rounded, {AppNotificationCategory.comment, AppNotificationCategory.reply}),
  _Filter('mentions', 'Mentions', Icons.alternate_email_rounded, {AppNotificationCategory.mention}),
  _Filter('messages', 'Messages', Icons.forum_outlined, {AppNotificationCategory.newMessage, AppNotificationCategory.call, AppNotificationCategory.missedCall}),
  _Filter('system', 'System', Icons.tune_rounded, {
    AppNotificationCategory.system,
    AppNotificationCategory.security,
    AppNotificationCategory.accountActivity,
    AppNotificationCategory.aiSuggestion,
    AppNotificationCategory.automation,
    AppNotificationCategory.analyticsAlert,
    AppNotificationCategory.scheduledMessage,
    AppNotificationCategory.subscription,
    AppNotificationCategory.share,
    AppNotificationCategory.repost,
  }),
  _Filter('updates', 'Updates', Icons.system_update_rounded, {
    AppNotificationCategory.appUpdate,
    AppNotificationCategory.recommendation,
    AppNotificationCategory.profileTip,
  }),
];

bool _matches(_Filter f, AppNotification n) {
  if (f.id == 'unread') return !n.isRead;
  return f.categories == null || f.categories!.contains(n.category);
}

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends ConsumerState<NotificationCenterScreen> {
  _Filter _filter = _filters.first;

  NotificationService get _service => ref.read(notificationServiceProvider);

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
  }

  Future<void> _confirmClearRead() async {
    final ok = await _confirm(
      context,
      title: 'Clear read notifications?',
      body: 'Everything you have already read will be removed. Unread alerts stay.',
      action: 'Clear',
    );
    if (ok != true) return;
    final count = await _service.clearRead();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(count == 0 ? 'Nothing to clear' : 'Cleared $count notifications')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider);
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
        title: Row(
          children: [
            Text('Notifications', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: context.topBarFg, letterSpacing: -0.3)),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text(unread > 99 ? '99+' : '$unread new',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
              ).animate().scale(duration: 200.ms, curve: Curves.easeOutBack),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            icon: Icon(Icons.done_all_rounded, color: unread > 0 ? context.topBarFg : context.topBarFg.withValues(alpha: 0.45), size: 21),
            onPressed: unread > 0
                ? () {
                    HapticFeedback.lightImpact();
                    _service.markAllAsRead();
                  }
                : null,
          ),
          IconButton(
            tooltip: 'Notification settings',
            icon: Icon(Icons.settings_outlined, color: context.topBarFg, size: 21),
            onPressed: () => context.push('/settings/notifications'),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: context.topBarFg, size: 21),
            color: context.surface,
            onSelected: (v) {
              if (v == 'clear') _confirmClearRead();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(children: [
                  Icon(Icons.cleaning_services_outlined, size: 18, color: context.textPrimary),
                  const SizedBox(width: 10),
                  Text('Clear read', style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: inbox.smoothWhen(
        loading: () => const OneovaSkeleton(),
        error: (e, _) => _EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load notifications',
          body: 'Check your connection and try again.',
          action: 'Retry',
          onAction: () => ref.invalidate(notificationInboxProvider),
        ),
        data: (all) => _buildList(all),
      ),
    );
  }

  Widget _buildList(List<AppNotification> all) {
    // Several go-live alerts for the same stream collapse into one row.
    final seenGroups = <String>{};
    final deduped = all.where((n) => n.groupId == null || seenGroups.add(n.groupId!)).toList();
    final visible = deduped.where((n) => _matches(_filter, n)).toList();
    final limit = ref.watch(notificationLimitProvider);

    final sections = <String, List<AppNotification>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final n in visible) {
      final String key;
      if (!n.isRead) {
        key = 'New';
      } else if (!n.createdAt.isBefore(today)) {
        key = 'Today';
      } else if (now.difference(n.createdAt).inDays < 7) {
        key = 'This week';
      } else {
        key = 'Earlier';
      }
      sections.putIfAbsent(key, () => []).add(n);
    }

    return RefreshIndicator(
      color: AppColors.brandBlue,
      onRefresh: () async => ref.invalidate(notificationInboxProvider),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _LiveNowStrip()),
          SliverToBoxAdapter(
            child: _FilterBar(
              selected: _filter,
              all: deduped,
              onSelected: (f) {
                HapticFeedback.selectionClick();
                setState(() => _filter = f);
              },
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: _filter.icon,
                title: _filter.id == 'all' ? "You're all caught up" : 'Nothing in ${_filter.label} yet',
                body: _filter.id == 'live'
                    ? 'When someone you follow goes live, it shows up here and rings you.'
                    : 'New activity from people you follow and your audience lands here in real time.',
                action: 'Notification settings',
                onAction: () => context.push('/settings/notifications'),
              ),
            )
          else
            for (final entry in sections.entries) ...[
              SliverToBoxAdapter(child: _SectionHeader(title: entry.key, count: entry.value.length)),
              SliverList.builder(
                itemCount: entry.value.length,
                itemBuilder: (_, i) => _NotificationTile(key: ValueKey(entry.value[i].id), notification: entry.value[i]),
              ),
            ],
          if (all.length >= limit)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => ref.read(notificationLimitProvider.notifier).increment(60),
                    icon: const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.brandBlue),
                    label: Text('Load older', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live now strip — creators you follow who are live this second
// ─────────────────────────────────────────────────────────────────────────────

class _LiveNowStrip extends ConsumerWidget {
  const _LiveNowStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = (ref.watch(followedCreatorAlertsProvider).value ?? const [])
        .map((c) => c.creatorId)
        .toSet();
    final lives = (ref.watch(activeLiveStreamsProvider).value ?? const <LiveStream>[])
        .where((s) => following.contains(s.hostId))
        .toList();
    if (lives.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const _PulseDot(),
              const SizedBox(width: 6),
              Text('Live now', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(width: 6),
              Text('${lives.length}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textMuted)),
            ],
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: lives.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final s = lives[i];
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.push('/live/viewer/${s.id}');
                },
                child: SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.premiumGradient),
                            child: CircleAvatar(
                              radius: 27,
                              backgroundColor: context.surfaceMid,
                              backgroundImage: s.hostAvatarUrl.isNotEmpty ? NetworkImage(s.hostAvatarUrl) : null,
                              child: s.hostAvatarUrl.isEmpty
                                  ? Text(s.hostDisplayName.isNotEmpty ? s.hostDisplayName[0].toUpperCase() : '?',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary))
                                  : null,
                            ),
                          ),
                          Positioned(bottom: -6, child: _LiveBadge(viewers: s.viewerCount)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.hostDisplayName.isNotEmpty ? s.hostDisplayName : 'Live',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.textPrimary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Divider(height: 1, color: context.border),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final int viewers;
  const _LiveBadge({required this.viewers});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.brandPink,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: context.bg, width: 1.5),
      ),
      child: Text(
        viewers > 0 ? 'LIVE · ${_compact(viewers)}' : 'LIVE',
        style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.8, end: 1.25, duration: 700.ms)
        .fade(begin: 0.6, end: 1);
  }
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

// ─────────────────────────────────────────────────────────────────────────────
// Filters & section headers
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final _Filter selected;
  final List<AppNotification> all;
  final ValueChanged<_Filter> onSelected;
  const _FilterBar({required this.selected, required this.all, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final active = f.id == selected.id;
          final unread = f.id == 'all' ? 0 : all.where((n) => !n.isRead && _matches(f, n)).length;
          return GestureDetector(
            onTap: () => onSelected(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: active ? AppColors.brandBlue : context.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: active ? AppColors.brandBlue : context.border, width: 1.0),
              ),
              child: Row(
                children: [
                  Icon(f.icon, size: 14, color: active ? Colors.white : (f.id == 'live' ? AppColors.brandPink : context.textSecondary)),
                  const SizedBox(width: 5),
                  Text(f.label,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : context.textPrimary)),
                  if (unread > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: active ? Colors.white : AppColors.brandPink,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(unread > 99 ? '99+' : '$unread',
                          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: active ? AppColors.brandBlue : Colors.white)),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Text(title.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: title == 'New' ? AppColors.brandPink : context.textMuted)),
          const SizedBox(width: 6),
          Text('$count', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: context.textMuted)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile
// ─────────────────────────────────────────────────────────────────────────────

({IconData icon, Color color}) _categoryStyle(AppNotificationCategory c) {
  switch (c) {
    case AppNotificationCategory.live:
      return (icon: Icons.sensors_rounded, color: AppColors.brandPink);
    case AppNotificationCategory.newPost:
      return (icon: Icons.play_arrow_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.like:
    case AppNotificationCategory.reaction:
      return (icon: Icons.favorite_rounded, color: AppColors.brandPink);
    case AppNotificationCategory.comment:
    case AppNotificationCategory.reply:
      return (icon: Icons.chat_bubble_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.mention:
      return (icon: Icons.alternate_email_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.newFollower:
    case AppNotificationCategory.followRequest:
      return (icon: Icons.person_add_alt_1_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.newMessage:
      return (icon: Icons.forum_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.call:
    case AppNotificationCategory.missedCall:
      return (icon: Icons.call_rounded, color: AppColors.brandPink);
    case AppNotificationCategory.share:
    case AppNotificationCategory.repost:
      return (icon: Icons.repeat_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.security:
    case AppNotificationCategory.accountActivity:
      return (icon: Icons.shield_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.aiSuggestion:
    case AppNotificationCategory.automation:
      return (icon: Icons.auto_awesome_rounded, color: AppColors.brandPink);
    case AppNotificationCategory.appUpdate:
      return (icon: Icons.system_update_rounded, color: AppColors.brandBlue);
    case AppNotificationCategory.recommendation:
      return (icon: Icons.tune_rounded, color: AppColors.brandPink);
    case AppNotificationCategory.profileTip:
      return (icon: Icons.person_outline_rounded, color: AppColors.brandBlue);
    default:
      return (icon: Icons.notifications_rounded, color: AppColors.brandBlue);
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  const _NotificationTile({super.key, required this.notification});

  void _open(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    if (!notification.isRead) ref.read(notificationServiceProvider).markAsRead(notification.id);
    if (notification.category == AppNotificationCategory.appUpdate) {
      PlayUpdateService.instance.updateNow();
      return;
    }
    final route = notification.route;
    if (route != null) context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final service = ref.read(notificationServiceProvider);

    return Dismissible(
      key: ValueKey('dismiss_${n.id}'),
      background: _SwipeBg(
        alignment: Alignment.centerLeft,
        color: AppColors.brandBlue,
        icon: n.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
        label: n.isRead ? 'Unread' : 'Read',
      ),
      secondaryBackground: _SwipeBg(
        alignment: Alignment.centerRight,
        color: AppColors.brandPink,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.selectionClick();
          n.isRead ? service.markAsUnread(n.id) : service.markAsRead(n.id);
          return false;
        }
        final ok = await _confirm(context, title: 'Delete notification?', body: 'This alert will be removed from your inbox.', action: 'Delete');
        return ok == true;
      },
      onDismissed: (_) => service.deleteNotification(n.id),
      child: InkWell(
        onTap: () => _open(context, ref),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          color: n.isRead ? Colors.transparent : AppColors.brandBlue.withValues(alpha: context.isDark ? 0.10 : 0.05),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ActorAvatar(notification: n),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w700, color: context.textPrimary),
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12.5, height: 1.3, color: context.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      timeago.format(n.createdAt, locale: 'en_short'),
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _Trailing(notification: n, onOpen: () => _open(context, ref)),
              if (!n.isRead) ...[
                const SizedBox(width: 8),
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;
  const _SwipeBg({required this.alignment, required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

class _ActorAvatar extends ConsumerWidget {
  final AppNotification notification;
  const _ActorAvatar({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final style = _categoryStyle(n.category);
    final actor = (n.actorId != null && n.actorId!.isNotEmpty) ? ref.watch(alertUserCardProvider(n.actorId!)).value : null;
    final photo = actor?.profilePhotoUrl ?? n.actorAvatarUrl;
    final name = (actor?.fullName.isNotEmpty ?? false) ? actor!.fullName : (n.actorName ?? '');
    final hasActor = (photo != null && photo.isNotEmpty) || name.isNotEmpty;

    final Widget core = hasActor
        ? CircleAvatar(
            radius: 21,
            backgroundColor: context.surfaceMid,
            backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo == null || photo.isEmpty
                ? Text(name[0].toUpperCase(), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary))
                : null,
          )
        : Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: style.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(style.icon, color: style.color, size: 20),
          );

    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: n.isLive
                ? Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.premiumGradient),
                    child: core,
                  )
                : core,
          ),
          if (hasActor)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: style.color, shape: BoxShape.circle, border: Border.all(color: context.bg, width: 1.5)),
                child: Icon(style.icon, size: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _Trailing extends ConsumerWidget {
  final AppNotification notification;
  final VoidCallback onOpen;
  const _Trailing({required this.notification, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    if (n.isLive && n.liveStreamId != null) return _LiveJoinButton(streamId: n.liveStreamId!, onJoin: onOpen);
    if (n.category == AppNotificationCategory.newFollower && n.actorId != null && n.actorId!.isNotEmpty) {
      return _FollowBackButton(userId: n.actorId!);
    }
    final thumb = n.thumbnailUrl;
    if (thumb != null && thumb.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.network(thumb, width: 40, height: 52, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 40, height: 52)),
      );
    }
    if (n.category == AppNotificationCategory.newPost) {
      return _SmallButton(label: 'Watch', icon: Icons.play_arrow_rounded, color: AppColors.brandBlue, onTap: onOpen);
    }
    return const SizedBox.shrink();
  }
}

/// Follows the stream doc so the row flips from "Join" to "Ended" the moment
/// the host stops.
class _LiveJoinButton extends ConsumerWidget {
  final String streamId;
  final VoidCallback onJoin;
  const _LiveJoinButton({required this.streamId, required this.onJoin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(liveStreamProvider(streamId)).value;
    final ended = stream == null ||
        stream.status == LiveStreamStatus.ended ||
        stream.status == LiveStreamStatus.abandoned;
    if (ended) {
      final endedAt = stream?.endedAt;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Text('Ended', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: context.textSecondary)),
          ),
          if (endedAt != null && stream != null) ...[
            const SizedBox(height: 3),
            Text(_duration(endedAt.difference(stream.createdAt)),
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: context.textMuted)),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _SmallButton(label: 'Join', icon: Icons.sensors_rounded, color: AppColors.brandPink, onTap: onJoin)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(begin: 1, end: 1.05, duration: 800.ms),
        const SizedBox(height: 3),
        Text('${_compact(stream.viewerCount)} watching',
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: context.textMuted)),
      ],
    );
  }
}

String _duration(Duration d) {
  if (d.isNegative) return '';
  if (d.inHours > 0) return 'Lasted ${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return 'Lasted ${d.inMinutes}m';
  return 'Lasted ${d.inSeconds}s';
}

class _FollowBackButton extends ConsumerWidget {
  final String userId;
  const _FollowBackButton({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final repo = ref.read(relationshipRepositoryProvider);
    return StreamBuilder<bool>(
      stream: repo.watchIsFollowing(uid, userId),
      builder: (context, snap) {
        final following = snap.data ?? false;
        if (following) {
          return _SmallButton(label: 'Following', color: context.textSecondary, outlined: true, onTap: () => context.push('/profile/$userId'));
        }
        return _SmallButton(
          label: 'Follow back',
          color: AppColors.brandBlue,
          onTap: () {
            HapticFeedback.lightImpact();
            repo.followUser(uid, userId);
          },
        );
      },
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool outlined;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.color, required this.onTap, this.icon, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: outlined ? context.border : color, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: outlined ? color : Colors.white),
              const SizedBox(width: 4),
            ],
            Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: outlined ? color : Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;
  const _EmptyState({required this.icon, required this.title, required this.body, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, color: AppColors.brandBlue, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: context.textSecondary)),
            const SizedBox(height: 14),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                side: BorderSide(color: context.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: onAction,
              child: Text(action, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
  }
}

Future<bool?> _confirm(BuildContext context, {required String title, required String body, required String action}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
      content: Text(body, style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textSecondary))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
}
