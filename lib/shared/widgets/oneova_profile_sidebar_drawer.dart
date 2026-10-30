import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../backend/notification_service.dart';
import '../../backend/remote_connect_service.dart';
import '../../backend/social/profile_stats_provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../../auth/widgets/profile_completion_reminder_card.dart';
import '../../auth/services/secure_logout_service.dart';
import '../../auth/services/app_lifecycle_observer.dart';
import 'creation_type_modal.dart';

/// Live stream provider for current authenticated user's Firestore document.
final currentUserSidebarProfileProvider = StreamProvider.autoDispose<Map<String, dynamic>?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.data());
});

/// Live trailing hint shown on a nav row (driven by real streams, never static).
enum _RowHint { none, live, unreadAlerts, pcOnline }

class _SideLink {
  final IconData icon;
  final String label;
  final String route;
  final _RowHint hint;
  const _SideLink(this.icon, this.label, this.route, {this.hint = _RowHint.none});
}

class _SideSection {
  final String title;
  final List<_SideLink> links;
  const _SideSection(this.title, this.links);
}

/// OneOva navigation sidebar (opened from the "Me" tab).
///
/// Layout: author header (avatar, name, handle, live counts), a single row of
/// quick actions, then grouped, collapsible navigation sections as compact list
/// rows. Every row is a real route; every number comes from Firestore.
class OneovaProfileSidebarDrawer extends ConsumerStatefulWidget {
  const OneovaProfileSidebarDrawer({super.key});

  static const List<_SideSection> _sections = [
    _SideSection('CREATE', [
      _SideLink(Icons.sensors_rounded, 'Go Live', '/live/setup', hint: _RowHint.live),
      _SideLink(Icons.videocam_outlined, 'Camera', '/create/camera'),
      _SideLink(Icons.upload_rounded, 'Upload', '/upload/global'),
      _SideLink(Icons.graphic_eq_rounded, 'Audio studio', '/audio/dashboard'),
    ]),
    _SideSection('SOCIAL', [
      _SideLink(Icons.explore_outlined, 'Discover', '/hub/discover'),
      _SideLink(Icons.storefront_outlined, 'Business', '/biz_feed'),
      _SideLink(Icons.all_inbox_rounded, 'Inbox', '/hub/messages'),
      _SideLink(Icons.hub_outlined, 'Connected accounts', '/social_hub'),
    ]),
    _SideSection('GROW', [
      _SideLink(Icons.insights_rounded, 'Insights', '/social_hub/analytics'),
      _SideLink(Icons.play_circle_outline_rounded, 'Channels', '/yt/dashboard'),
      _SideLink(Icons.assistant_outlined, 'Ova assistant', '/hub/ova_assistant'),
    ]),
    _SideSection('DEVICES', [
      _SideLink(Icons.desktop_mac_outlined, 'My PC', '/connect', hint: _RowHint.pcOnline),
      _SideLink(Icons.devices_rounded, 'Linked devices', '/auth/linked_devices'),
      _SideLink(Icons.qr_code_scanner_rounded, 'Scan QR', '/qr_scanner'),
    ]),
    _SideSection('ACCOUNT', [
      _SideLink(Icons.notifications_none_rounded, 'Notifications', '/notifications', hint: _RowHint.unreadAlerts),
      _SideLink(Icons.lock_outline_rounded, 'Privacy', '/settings/privacy'),
      _SideLink(Icons.link_rounded, 'Sign-in methods', '/settings/sign-in-methods'),
    ]),
  ];

  /// Displays the slide-in sidebar from the right edge.
  static void show(BuildContext context) {
    HapticFeedback.lightImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Oneova Menu',
      barrierColor: AppColors.brandBlack.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.70 : 0.45,
      ),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, anim1, anim2) => const OneovaProfileSidebarDrawer(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  ConsumerState<OneovaProfileSidebarDrawer> createState() => _OneovaProfileSidebarDrawerState();
}

class _OneovaProfileSidebarDrawerState extends ConsumerState<OneovaProfileSidebarDrawer> {
  final Set<String> _collapsed = {};

  /// Closes the sidebar, then pushes [route] so every destination has a back path.
  void _go(String route) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
    context.push(route);
  }

  /// Opens the STUDIO creation sheet (same action as the bottom-nav STUDIO button).
  void _openStudio() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
    final rootCtx = rootNavigatorKey.currentContext;
    if (rootCtx != null && rootCtx.mounted) CreationTypeModal.show(rootCtx);
  }

  String _currentPath() {
    try {
      return GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  static int _int(Map<String, dynamic>? u, List<String> keys) {
    for (final k in keys) {
      final v = u?[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(320.0, MediaQuery.of(context).size.width * 0.86);
    final currentUser = FirebaseAuth.instance.currentUser;
    final user = ref.watch(currentUserSidebarProfileProvider).value;
    final stats = ref.watch(profileStatsProvider(currentUser?.uid ?? '')).value;

    final displayName =
        (user?['displayName'] ?? user?['name'] ?? currentUser?.displayName ?? 'Oneova Member').toString();
    final rawHandle = (user?['username'] ?? user?['handle'])?.toString() ?? '';
    final handle = rawHandle.isEmpty ? '' : (rawHandle.startsWith('@') ? rawHandle : '@$rawHandle');
    final avatarUrl = (user?['photoUrl'] ?? user?['avatarUrl'] ?? currentUser?.photoURL)?.toString();
    final verified = user?['isVerified'] == true || user?['verified'] == true;

    final notifications = ref.watch(notificationProvider).value ?? const <AppNotification>[];
    final unread = notifications.where((n) => !n.isRead).length;
    final pcOnline = ref.watch(remoteConnectProvider).activeComputerId != null;
    final path = _currentPath();

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: double.infinity,
          decoration: BoxDecoration(
            color: context.bg,
            border: Border(left: BorderSide(color: context.border, width: 1.0)),
            boxShadow: context.isDark
                ? AppShadows.glow(AppColors.brandBlue, radius: 24, spread: 1)
                : AppShadows.lg,
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthorHeader(
                  name: displayName,
                  handle: handle,
                  avatarUrl: avatarUrl,
                  verified: verified,
                  posts: _compact(stats?.posts ?? _int(user, const ['postsCount', 'videoCount'])),
                  followers: _compact(stats?.followers ?? _int(user, const ['followers', 'followersCount', 'followerCount'])),
                  following: _compact(stats?.following ?? _int(user, const ['following', 'followingCount'])),
                  onOpenProfile: () => _go('/profile/me'),
                  onClose: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _buildQuickActions(context, unread),
                ),
                Divider(height: 1, thickness: 1, color: context.border),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                    children: [
                      const ProfileCompletionReminderCard(),
                      for (final section in OneovaProfileSidebarDrawer._sections)
                        _buildSection(context, section, path: path, unread: unread, pcOnline: pcOnline),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: context.border),
                _buildFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, int unread) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.add_rounded,
            label: 'Create',
            primary: true,
            onTap: _openStudio,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuickAction(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Messages',
            onTap: () => _go('/hub/messages'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuickAction(
            icon: Icons.notifications_none_rounded,
            label: 'Alerts',
            badge: unread,
            onTap: () => _go('/notifications'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuickAction(
            icon: Icons.auto_awesome_rounded,
            label: 'AI Lab',
            onTap: () => _go('/hub/ai'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _QuickAction(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => _go('/settings/main'),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    _SideSection section, {
    required String path,
    required int unread,
    required bool pcOnline,
  }) {
    final collapsed = _collapsed.contains(section.title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => collapsed ? _collapsed.remove(section.title) : _collapsed.add(section.title));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
            child: Row(
              children: [
                Text(
                  section.title,
                  style: GoogleFonts.inter(
                    color: context.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: collapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded, size: 16, color: context.textMuted),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity)
              : Column(
                  children: [
                    for (final l in section.links)
                      _NavRow(
                        link: l,
                        active: path.isNotEmpty && (path == l.route || path.startsWith('${l.route}/')),
                        trailing: _hintFor(context, l.hint, unread: unread, pcOnline: pcOnline),
                        onTap: () => _go(l.route),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget? _hintFor(BuildContext context, _RowHint hint, {required int unread, required bool pcOnline}) {
    switch (hint) {
      case _RowHint.live:
        return const _Pill(label: 'LIVE', color: AppColors.brandPink);
      case _RowHint.unreadAlerts:
        return unread > 0 ? _Pill(label: unread > 99 ? '99+' : '$unread', color: AppColors.brandPink, solid: true) : null;
      case _RowHint.pcOnline:
        return pcOnline ? const _Pill(label: 'ONLINE', color: AppColors.brandBlue) : null;
      case _RowHint.none:
        return null;
    }
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                ref.read(themeProvider.notifier).toggleTheme();
              },
              icon: Icon(
                context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 17,
                color: context.textSecondary,
              ),
              label: Text(
                context.isDark ? 'Light mode' : 'Dark mode',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary),
              ),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded, size: 17, color: AppColors.brandPink),
            label: Text(
              'Log out',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandPink),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
        ],
      ),
    );
  }

  /// Mandatory confirmation before logout.
  void _confirmLogout() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: dialogCtx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: dialogCtx.border, width: 1.0),
        ),
        title: Text(
          'Log out of Oneova?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: dialogCtx.textPrimary),
        ),
        content: Text(
          'Your session will end on this device.',
          style: GoogleFonts.inter(fontSize: 13, color: dialogCtx.textSecondary, height: 1.35),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: dialogCtx.border, width: 1.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: Text('Cancel', style: GoogleFonts.inter(color: dialogCtx.textPrimary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: AppColors.brandWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              Navigator.of(context).pop();
              await ref.read(secureLogoutServiceProvider).logout();
              final rootCtx = rootNavigatorKey.currentContext;
              if (rootCtx != null && rootCtx.mounted) {
                rootCtx.go('/auth/main_login');
              }
            },
            child: Text('Log out', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Author header: ringed avatar, name + verified mark, handle, live counts.
class _AuthorHeader extends StatelessWidget {
  final String name;
  final String handle;
  final String? avatarUrl;
  final bool verified;
  final String posts;
  final String followers;
  final String following;
  final VoidCallback onOpenProfile;
  final VoidCallback onClose;

  const _AuthorHeader({
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.verified,
    required this.posts,
    required this.followers,
    required this.following,
    required this.onOpenProfile,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: onOpenProfile,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AppColors.brandBlue, AppColors.brandPink],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: context.bg, shape: BoxShape.circle),
                            child: CircleAvatar(
                              radius: 21,
                              backgroundColor: AppColors.brandBlue,
                              backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                              child: hasAvatar
                                  ? null
                                  : Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : 'O',
                                      style: GoogleFonts.inter(
                                        color: AppColors.brandWhite,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: context.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  if (verified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified_rounded, size: 15, color: AppColors.brandBlue),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 1),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      handle.isNotEmpty ? handle : 'View profile',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: context.textSecondary,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, size: 15, color: context.textMuted),
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
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onOpenProfile,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    _stat(context, posts, 'Posts'),
                    _divider(context),
                    _stat(context, followers, 'Followers'),
                    _divider(context),
                    _stat(context, following, 'Following'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(width: 1, height: 22, color: context.border);

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(color: context.textMuted, fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// One compact quick-action button (icon over label), with optional unread badge.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final int badge;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge unread' : label,
      child: Material(
        color: primary ? AppColors.brandBlue : context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: primary ? BorderSide.none : BorderSide(color: context.border, width: 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 20, color: primary ? AppColors.brandWhite : AppColors.brandBlue),
                    if (badge > 0)
                      Positioned(
                        right: -7,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 15),
                          decoration: BoxDecoration(
                            color: AppColors.brandPink,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(color: context.surface, width: 1.0),
                          ),
                          child: Text(
                            badge > 99 ? '99+' : '$badge',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: AppColors.brandWhite,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: primary ? AppColors.brandWhite : context.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single navigation row: tinted icon, label, optional live hint, chevron.
/// The row matching the current route gets a brand-blue active state.
class _NavRow extends StatelessWidget {
  final _SideLink link;
  final bool active;
  final Widget? trailing;
  final VoidCallback onTap;

  const _NavRow({required this.link, required this.active, required this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: active ? AppColors.brandBlue.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: active ? AppColors.brandBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: active ? AppColors.brandBlue : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    link.icon,
                    size: 16,
                    color: active ? AppColors.brandWhite : AppColors.brandBlue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    link.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: active ? AppColors.brandBlue : context.textPrimary,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
                Icon(Icons.chevron_right_rounded, size: 17, color: context.textMuted),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Micro pill tag (LIVE / ONLINE / unread count).
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool solid;
  const _Pill({required this.label, required this.color, this.solid = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: solid ? null : Border.all(color: color.withValues(alpha: 0.35), width: 1.0),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: solid ? AppColors.brandWhite : color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
