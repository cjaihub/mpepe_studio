import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/services/secure_logout_service.dart';
import '../../backend/routing/oneova_share_engine.dart';
import '../../shared/theme/app_theme.dart';

class _MenuItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? route;
  final VoidCallback? onTap;
  final bool danger;
  const _MenuItem(this.icon, this.label, {this.subtitle, this.route, this.onTap, this.danger = false});
}

/// TikTok-style owner menu (☰ on your own profile): quick actions on top,
/// then grouped settings for profile, privacy, notifications and account.
Future<void> showOwnerProfileMenu(BuildContext context, WidgetRef ref, {required String uid}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetCtx) {
      void go(String route) {
        Navigator.of(sheetCtx).pop();
        context.push(route);
      }

      final quick = <_MenuItem>[
        _MenuItem(Icons.account_balance_wallet_rounded, 'Wallet', route: '/wallet'),
        _MenuItem(Icons.insights_rounded, 'Insights', route: '/creator/insights'),
        _MenuItem(Icons.qr_code_2_rounded, 'Share', onTap: () {
          Navigator.of(sheetCtx).pop();
          SharePlus.instance.share(ShareParams(
            text: 'Follow me on Oneova\nhttps://${OneovaShareEngine.webDomain}/profile/$uid',
          ));
        }),
        _MenuItem(Icons.monetization_on_rounded, 'Monetize', route: '/profile/monetization'),
      ];

      final groups = <String, List<_MenuItem>>{
        'Profile': [
          const _MenuItem(Icons.edit_rounded, 'Edit profile',
              subtitle: 'Photo, name, username, bio, links', route: '/settings/profile'),
          const _MenuItem(Icons.video_settings_rounded, 'Reels & content',
              subtitle: 'Downloads, remix, comments, duets', route: '/settings/reels'),
        ],
        'Privacy & safety': [
          const _MenuItem(Icons.lock_rounded, 'Privacy',
              subtitle: 'Private account, who can message or call you, blocked', route: '/settings/privacy'),
          const _MenuItem(Icons.fingerprint_rounded, 'Security & login',
              subtitle: 'Ova Guard alerts, devices, fingerprint, 2-step', route: '/profile/security'),
          const _MenuItem(Icons.devices_rounded, 'Logged-in devices', route: '/auth/linked_devices'),
        ],
        'Notifications & calls': [
          const _MenuItem(Icons.notifications_rounded, 'Notifications',
              subtitle: 'Push, pop-ups, sounds', route: '/settings/notifications'),
          const _MenuItem(Icons.call_rounded, 'Calls', subtitle: 'Ringtone, video, data use', route: '/settings/calls'),
          const _MenuItem(Icons.chat_bubble_rounded, 'Chats', route: '/settings/chat'),
        ],
        'Account': [
          const _MenuItem(Icons.manage_accounts_rounded, 'Account settings', route: '/settings/main'),
          const _MenuItem(Icons.palette_rounded, 'Appearance', subtitle: 'Light, dark, system', route: '/settings/appearance'),
          const _MenuItem(Icons.accessibility_new_rounded, 'Accessibility', route: '/settings/accessibility'),
          const _MenuItem(Icons.storage_rounded, 'Storage & data', route: '/settings/storage'),
          _MenuItem(Icons.logout_rounded, 'Log out', danger: true, onTap: () async {
            Navigator.of(sheetCtx).pop();
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: ctx.surface,
                title: Text('Log out of Oneova?',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
                content: Text('If fingerprint sign-in is on, you can sign back in with one touch.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: ctx.textSecondary)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brandPink),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Log out'),
                  ),
                ],
              ),
            );
            if (ok == true) await ref.read(secureLogoutServiceProvider).logout();
          }),
        ],
      };

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: ctx.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final q in quick)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: q.onTap ?? () => go(q.route!),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: Icon(q.icon, color: AppColors.brandBlue, size: 22),
                            ),
                            const SizedBox(height: 6),
                            Text(q.label,
                                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: ctx.textPrimary)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text(g.key.toUpperCase(),
                    style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: ctx.textMuted)),
              ),
              Container(
                decoration: BoxDecoration(
                  color: ctx.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: ctx.border, width: 1),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < g.value.length; i++) ...[
                      if (i > 0) Divider(height: 1, indent: 48, color: ctx.border),
                      ListTile(
                        dense: true,
                        leading: Icon(g.value[i].icon,
                            size: 20, color: g.value[i].danger ? AppColors.brandPink : ctx.textPrimary),
                        title: Text(g.value[i].label,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: g.value[i].danger ? AppColors.brandPink : ctx.textPrimary,
                            )),
                        subtitle: g.value[i].subtitle == null
                            ? null
                            : Text(g.value[i].subtitle!,
                                style: GoogleFonts.inter(fontSize: 11, color: ctx.textSecondary)),
                        trailing: g.value[i].danger
                            ? null
                            : Icon(Icons.chevron_right_rounded, color: ctx.textMuted, size: 20),
                        onTap: g.value[i].onTap ?? () => go(g.value[i].route!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
