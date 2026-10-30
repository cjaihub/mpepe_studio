import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/connections/linked_accounts.dart';
import '../../backend/settings/account_settings_schema.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// Where a cross-publish choice applies.
enum DestinationPurpose {
  /// Posting a video / photo (platforms with [LinkedPlatform.publish]).
  post,

  /// Going live (platforms with [LinkedPlatform.live], restreamed by RTMP).
  live;

  String get settingKey => this == post
      ? AccountSettingsSchema.crossPostPlatforms
      : AccountSettingsSchema.liveSimulcastPlatforms;

  bool supports(LinkedPlatform p) => this == post ? p.publish : p.live;
}

/// The platform ids the account last chose for [purpose], from
/// `user_settings/{uid}.publishing`. Same value on every screen and device.
final savedDestinationsProvider = Provider.family<Set<String>, DestinationPurpose>((ref, purpose) {
  final settings = ref.watch(settingsProvider).value ?? const <String, dynamic>{};
  final section = AccountSettingsSchema.category(settings, AccountSettingsSchema.publishing);
  return AccountSettingsSchema.stringList(section, purpose.settingKey).toSet();
});

/// Saved choice narrowed to accounts that are linked and usable right now.
final activeDestinationsProvider = Provider.family<Set<String>, DestinationPurpose>((ref, purpose) {
  final saved = ref.watch(savedDestinationsProvider(purpose));
  final usable = ref.watch(usableLinkedAccountsProvider).where((a) => purpose.supports(a.platform)).map((a) => a.platform.id).toSet();
  return saved.intersection(usable);
});

Future<void> saveDestinations(WidgetRef ref, DestinationPurpose purpose, Set<String> ids) {
  return ref.read(settingsProvider.notifier).updateSetting(AccountSettingsSchema.publishing, purpose.settingKey, ids.toList()..sort());
}

/// Chips for the linked platforms that support [purpose]. Toggling a chip
/// saves the account's choice, so Post, Go Live and the connections page
/// always agree. Platforms that support [purpose] but aren't linked show a
/// "Connect" chip that opens the connections page.
class LinkedDestinationsPicker extends ConsumerWidget {
  final DestinationPurpose purpose;

  /// Light chips for use over a camera preview.
  final bool onDark;

  const LinkedDestinationsPicker({super.key, required this.purpose, this.onDark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(linkedAccountsProvider);
    final selected = ref.watch(activeDestinationsProvider(purpose));
    final accounts = (accountsAsync.value ?? const <LinkedAccount>[]).where((a) => purpose.supports(a.platform)).toList();
    final linked = accounts.map((a) => a.platform).toSet();
    final missing = LinkedPlatform.values.where((p) => purpose.supports(p) && !linked.contains(p)).toList();

    final fg = onDark ? AppColors.brandWhite : context.textPrimary;
    final muted = onDark ? AppColors.brandWhite.withValues(alpha: 0.7) : context.textMuted;
    final border = onDark ? AppColors.brandWhite.withValues(alpha: 0.25) : context.border;

    Widget chip({
      required IconData icon,
      required String label,
      required bool on,
      required VoidCallback? onTap,
      String? sub,
      bool warn = false,
    }) {
      return Material(
        color: on ? AppColors.brandBlue : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: on ? AppColors.brandBlue : (warn ? AppColors.brandPink : border)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(on ? Icons.check_circle_rounded : icon, size: 15, color: on ? AppColors.brandWhite : fg),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: on ? AppColors.brandWhite : fg)),
                    if (sub != null && sub.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 10, color: on ? AppColors.brandWhite.withValues(alpha: 0.85) : (warn ? AppColors.brandPink : muted))),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in accounts)
          chip(
            icon: a.platform.icon,
            label: a.platform.label,
            sub: a.isUsable ? a.accountName : (a.status == LinkStatus.expired ? 'Sign-in expired' : 'Reconnect'),
            warn: !a.isUsable,
            on: selected.contains(a.platform.id),
            onTap: a.isUsable
                ? () {
                    final next = {...selected};
                    next.contains(a.platform.id) ? next.remove(a.platform.id) : next.add(a.platform.id);
                    saveDestinations(ref, purpose, next);
                  }
                : () => context.push('/social_hub'),
          ),
        for (final p in missing)
          chip(
            icon: Icons.add_link_rounded,
            label: p.label,
            sub: 'Connect',
            on: false,
            onTap: () => context.push('/social_hub'),
          ),
      ],
    );
  }
}
