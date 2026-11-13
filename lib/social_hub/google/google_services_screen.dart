import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/connections/google_services.dart';
import '../../shared/theme/app_theme.dart';

/// Google services kept with the person's Oneova account (`/social_hub/google`),
/// opened from Connected accounts. Separate from signing in to Oneova.
///
/// One card per Google account; each service can be turned on, reconnected
/// or turned off. Oneova then uses them in the background (Ova, inbox,
/// YouTube tools) and asks again only where a feature needs a service.
class GoogleServicesScreen extends ConsumerStatefulWidget {
  const GoogleServicesScreen({super.key});

  @override
  ConsumerState<GoogleServicesScreen> createState() => _GoogleServicesScreenState();
}

class _GoogleServicesScreenState extends ConsumerState<GoogleServicesScreen> {
  /// `sub/serviceId` (or `new`) while a request runs.
  final Set<String> _busy = {};

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(String key, Future<void> Function() job) async {
    setState(() => _busy.add(key));
    try {
      await job();
    } on GoogleServicesException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _report(GoogleLinkResult? r) {
    if (r == null) return;
    final on = r.linked.map((s) => s.label).join(', ');
    final off = r.skipped.map((s) => s.label).join(', ');
    _snack(off.isEmpty ? '$on on for ${r.email}' : '$on on. $off needs every permission ticked.');
  }

  /// Adds a Google account with the services picked in the sheet.
  Future<void> _addAccount() async {
    HapticFeedback.lightImpact();
    final picked = await _pickServices(context, const {});
    if (picked == null || picked.isEmpty) return;
    await _run('new', () async => _report(await GoogleServices.linkAll(picked)));
  }

  Future<void> _addServices(GoogleLinkedAccount a) async {
    final picked = await _pickServices(context, a.services.keys.toSet());
    if (picked == null || picked.isEmpty) return;
    await _run('${a.sub}/more', () async => _report(await GoogleServices.linkAll(picked, email: a.email)));
  }

  Future<void> _toggle(GoogleLinkedAccount a, GoogleService s, bool on) async {
    HapticFeedback.selectionClick();
    await _run('${a.sub}/${s.id}', () async {
      if (on) {
        _report(await GoogleServices.linkAll({s}, email: a.email));
      } else {
        await GoogleServices.unlink(a.sub, s);
      }
    });
  }

  Future<void> _remove(GoogleLinkedAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Remove ${a.email}?', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'Oneova\'s access is removed from this Google account and every service on it turns off. Nothing in your Google account is deleted.',
          style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.brandPink)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run('${a.sub}/remove', () => GoogleServices.removeAccount(a.sub));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(googleAccountsProvider);
    final accounts = async.value ?? const <GoogleLinkedAccount>[];
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/social_hub'),
        ),
        title: Text('Google services', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: async.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Couldn\'t load your Google services: ${async.error}',
                    textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary)),
              ),
            )
          : async.isLoading && accounts.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    Text(
                      'Not the same as how you sign in. Pick the Google services you use and Oneova works with them in the background. Access is kept on Oneova\'s server, never on this phone.',
                      style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    for (final a in accounts) ...[
                      _AccountCard(
                        account: a,
                        busy: _busy,
                        onToggle: (s, on) => _toggle(a, s, on),
                        onAddServices: () => _addServices(a),
                        onRemove: () => _remove(a),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _AddAccountButton(
                      first: accounts.isEmpty,
                      busy: _busy.contains('new'),
                      onTap: _addAccount,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Turning a service off stops Oneova using it. Google keeps the permission until you remove the account here or at myaccount.google.com/permissions.',
                      style: GoogleFonts.inter(fontSize: 11, height: 1.35, color: context.textMuted),
                    ),
                  ],
                ),
    );
  }
}

/// Multi-select sheet of services. [already] are shown ticked and locked.
Future<Set<GoogleService>?> _pickServices(BuildContext context, Set<GoogleService> already) {
  final picked = <GoogleService>{};
  return showModalBottomSheet<Set<GoogleService>>(
    context: context,
    backgroundColor: context.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Which Google services do you use?',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
              const SizedBox(height: 4),
              Text('Google will ask once for the ones you tick.', style: GoogleFonts.inter(fontSize: 12, color: ctx.textMuted)),
              const SizedBox(height: 8),
              for (final s in GoogleService.values)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.brandBlue,
                  value: already.contains(s) || picked.contains(s),
                  onChanged: already.contains(s)
                      ? null
                      : (v) => setSheet(() => v == true ? picked.add(s) : picked.remove(s)),
                  secondary: Icon(s.icon, color: AppColors.brandBlue, size: 20),
                  title: Text(s.label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: ctx.textPrimary)),
                  subtitle: Text(s.blurb, style: GoogleFonts.inter(fontSize: 11.5, color: ctx.textMuted)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: AppColors.brandWhite,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: picked.isEmpty ? null : () => Navigator.of(ctx).pop(picked),
                  child: Text('Continue with Google', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AccountCard extends StatelessWidget {
  final GoogleLinkedAccount account;
  final Set<String> busy;
  final void Function(GoogleService, bool) onToggle;
  final VoidCallback onAddServices;
  final VoidCallback onRemove;

  const _AccountCard({
    required this.account,
    required this.busy,
    required this.onToggle,
    required this.onAddServices,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final a = account;
    final removing = busy.contains('${a.sub}/remove') || busy.contains('${a.sub}/more');
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.brandBlue.withValues(alpha: 0.12),
                  foregroundImage: a.photoUrl.isEmpty ? null : NetworkImage(a.photoUrl),
                  child: Text(a.displayName.isEmpty ? 'G' : a.displayName[0].toUpperCase(),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      if (a.name.isNotEmpty)
                        Text(a.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted)),
                    ],
                  ),
                ),
                if (removing)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: context.textSecondary),
                    color: context.surface,
                    onSelected: (v) => v == 'add' ? onAddServices() : onRemove(),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'add', child: Text('Turn on several')),
                      const PopupMenuItem(value: 'remove', child: Text('Remove account', style: TextStyle(color: AppColors.brandPink))),
                    ],
                  ),
              ],
            ),
          ),
          for (final s in GoogleService.values) ...[
            Divider(height: 1, color: context.border),
            _ServiceRow(
              service: s,
              status: a.statusOf(s),
              busy: busy.contains('${a.sub}/${s.id}'),
              onToggle: (on) => onToggle(s, on),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final GoogleService service;
  final GoogleServiceStatus? status;
  final bool busy;
  final ValueChanged<bool> onToggle;

  const _ServiceRow({required this.service, required this.status, required this.busy, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final on = status == GoogleServiceStatus.connected;
    final broken = status == GoogleServiceStatus.needsReconnect;
    final Widget action;
    if (busy) {
      action = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (broken) {
      action = TextButton(
        onPressed: () => onToggle(true),
        child: Text('Reconnect', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandPink)),
      );
    } else {
      action = Switch.adaptive(
        value: on,
        activeTrackColor: AppColors.brandBlue,
        onChanged: onToggle,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Icon(service.icon, size: 20, color: on ? AppColors.brandBlue : context.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
                Text(
                  broken ? 'Google access was removed. Reconnect to keep using it.' : service.blurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, height: 1.3, color: broken ? AppColors.brandPink : context.textMuted),
                ),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  final bool first;
  final bool busy;
  final VoidCallback onTap;

  const _AddAccountButton({required this.first, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandBlue,
          side: BorderSide(color: context.border),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_rounded, size: 18),
        label: Text(first ? 'Connect a Google account' : 'Add another Google account',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// One row for Connected accounts: opens [GoogleServicesScreen].
class GoogleServicesRow extends ConsumerWidget {
  const GoogleServicesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(googleAccountsProvider).value ?? const <GoogleLinkedAccount>[];
    final on = {for (final a in accounts) ...a.services.keys.where(a.isOn)};
    final subtitle = accounts.isEmpty
        ? 'Gmail, YouTube, Drive, Calendar, Contacts, Tasks'
        : '${on.length} on · ${accounts.length == 1 ? accounts.first.email : '${accounts.length} accounts'}';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.apps_rounded, color: AppColors.brandBlue),
      title: Text('Google services', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted)),
      trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
      onTap: () => context.push('/social_hub/google'),
    );
  }
}
