import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/connections/linked_accounts.dart';
import '../backend/inbox/platform_inbox.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/linked_destinations_picker.dart';
import 'gmail/gmail_screens.dart';

/// Social Hub: the user's connected accounts (`/social_hub`).
///
/// Status is read from the records the real OAuth flows write
/// ([linkedAccountsProvider]); nothing here marks an account connected by
/// itself. From here the user opens the one inbox and picks the platforms
/// Post and Go Live publish to by default.
class SocialIntegrationDashboard extends ConsumerStatefulWidget {
  const SocialIntegrationDashboard({super.key});

  @override
  ConsumerState<SocialIntegrationDashboard> createState() => _SocialIntegrationDashboardState();
}

class _SocialIntegrationDashboardState extends ConsumerState<SocialIntegrationDashboard> {
  final Set<LinkedPlatform> _busy = {};

  Future<void> _connect(LinkedPlatform p) async {
    HapticFeedback.lightImpact();
    final route = LinkedAccountsController.wizardRoute(p);
    if (route != null) {
      context.push(route);
      return;
    }
    setState(() => _busy.add(p));
    try {
      final ok = await ref.read(linkedAccountsControllerProvider).connect(p);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '${p.label} connected' : '${p.label} wasn\'t connected. Access was not granted.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t connect ${p.label}: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(p));
    }
  }

  Future<void> _disconnect(LinkedAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        title: Text('Disconnect ${a.platform.label}?', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary)),
        content: Text(
          '${a.accountName.isEmpty ? 'This account' : a.accountName} will stop appearing in your inbox and as a Post / Go Live destination.',
          style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect', style: TextStyle(color: AppColors.brandPink)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(a.platform));
    try {
      await ref.read(linkedAccountsControllerProvider).disconnect(a);
    } finally {
      if (mounted) setState(() => _busy.remove(a.platform));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(linkedAccountsProvider);
    final accounts = accountsAsync.value ?? const <LinkedAccount>[];
    final unread = ref.watch(platformUnreadCountsProvider);
    final unreadTotal = unread.values.fold<int>(0, (a, b) => a + b);
    final readiness = ref.watch(connectorReadinessProvider).value;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
        title: Text('Connected accounts', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: accountsAsync.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Couldn\'t load your accounts: ${accountsAsync.error}',
                    textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Text(
                  'Link your accounts to read their messages and comments in your Oneova inbox and to publish or go live on them.',
                  style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary),
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Accounts',
                  child: Column(
                    children: [
                      for (final (i, p) in LinkedPlatform.values.indexed) ...[
                        if (i > 0) Divider(height: 1, color: context.border),
                        _PlatformRow(
                          platform: p,
                          accounts: accounts.where((a) => a.platform == p).toList(),
                          loading: accountsAsync.isLoading && accounts.isEmpty,
                          busy: _busy.contains(p),
                          readiness: readiness?[p],
                          onConnect: () => _connect(p),
                          onDisconnect: _disconnect,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const _Section(
                  title: 'Email',
                  subtitle: 'Your own Gmail, connected only to your Oneova account.',
                  child: GmailConnectRow(),
                ),
                const SizedBox(height: 18),
                _Section(
                  title: 'Inbox',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.all_inbox_rounded, color: AppColors.brandBlue),
                    title: Text('Open inbox', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                    subtitle: Text(
                      unreadTotal > 0 ? '$unreadTotal unread from linked accounts' : 'Oneova chats and every linked account in one place',
                      style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
                    onTap: () => context.push('/hub/messages'),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  title: 'Post to',
                  subtitle: 'Picked by default when you post. You can change it on each post.',
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinkedDestinationsPicker(purpose: DestinationPurpose.post),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  title: 'Go live on',
                  subtitle: 'Your Oneova live is restreamed to these. Only YouTube and Facebook offer a live API.',
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinkedDestinationsPicker(purpose: DestinationPurpose.live),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  title: 'Insights',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.insights_rounded, color: AppColors.brandBlue),
                    title: Text('Analytics', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
                    onTap: () => context.push('/social_hub/analytics'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.brandBlue)),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(subtitle!, style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted)),
          ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}

class _PlatformRow extends StatelessWidget {
  final LinkedPlatform platform;
  final List<LinkedAccount> accounts;
  final bool loading;
  final bool busy;
  /// Null while the status check runs.
  final ConnectorReadiness? readiness;
  final VoidCallback onConnect;
  final ValueChanged<LinkedAccount> onDisconnect;

  const _PlatformRow({
    this.readiness,
    required this.platform,
    required this.accounts,
    required this.loading,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final caps = [
      if (platform.publish) 'Post',
      if (platform.live) 'Live',
      if (platform.messages) 'Messages',
      if (platform.comments) 'Comments',
    ];
    final account = accounts.firstOrNull;
    final usable = account?.isUsable ?? false;
    final waiting = readiness != null && !readiness!.ready && !usable;
    final statusText = waiting ? (readiness!.note.isEmpty ? 'Waiting for setup' : readiness!.note) : switch (account?.status) {
      LinkStatus.connected => accounts.length > 1 ? '${account!.accountName} +${accounts.length - 1}' : account!.accountName,
      LinkStatus.expired => 'Sign-in expired',
      LinkStatus.needsReconnect => 'Not verified, reconnect',
      null => loading ? 'Checking…' : 'Not connected',
    };

    Widget action;
    if (busy || (readiness == null && !usable)) {
      action = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (waiting) {
      action = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 12, color: context.textMuted),
            const SizedBox(width: 4),
            Text('Coming soon', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.textSecondary)),
          ],
        ),
      );
    } else if (usable) {
      action = TextButton(
        onPressed: () => onDisconnect(account!),
        child: Text('Disconnect', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary)),
      );
    } else {
      action = FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: AppColors.brandWhite,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        onPressed: onConnect,
        child: Text(account == null ? 'Connect' : 'Reconnect', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (usable ? AppColors.brandBlue : context.textMuted).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(platform.icon, size: 18, color: usable ? AppColors.brandBlue : context.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(platform.label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    if (usable) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded, size: 13, color: AppColors.brandBlue),
                    ],
                  ],
                ),
                Text(statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11.5, color: account != null && !usable ? AppColors.brandPink : context.textMuted)),
                const SizedBox(height: 2),
                Text(caps.join(' · '), style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted)),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}
