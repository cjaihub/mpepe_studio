import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import 'gmail_service.dart';

// ── Connected accounts row ──────────────────────────────────────────────

/// "Gmail" row for Connected accounts: connect with Google's consent screen,
/// open the inbox, or disconnect (which also revokes access at Google).
class GmailConnectRow extends ConsumerStatefulWidget {
  const GmailConnectRow({super.key});

  @override
  ConsumerState<GmailConnectRow> createState() => _GmailConnectRowState();
}

class _GmailConnectRowState extends ConsumerState<GmailConnectRow> {
  bool _busy = false;

  Future<void> _connect() async {
    HapticFeedback.lightImpact();
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Connect your Gmail', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
            const SizedBox(height: 4),
            Text('Google will ask you to allow these. Only your account is connected; nobody else at Oneova can read it.',
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary)),
            const SizedBox(height: 12),
            for (final (t, d) in GmailService.scopeExplained)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.brandBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: ctx.textPrimary)),
                      Text(d, style: GoogleFonts.inter(fontSize: 11.5, color: ctx.textSecondary)),
                    ]),
                  ),
                ]),
              ),
            Text('You can disconnect here any time, or remove the whole Google account in Google services.',
                style: GoogleFonts.inter(fontSize: 11, color: ctx.textMuted)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Continue with Google', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (go != true) return;
    setState(() => _busy = true);
    try {
      final email = await ref.read(gmailServiceProvider).connect();
      if (mounted && email.isNotEmpty) _snack('Gmail connected: $email');
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Disconnect Gmail?', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text('Oneova stops reading and sending mail for $email. Your email itself isn\'t touched. To remove Oneova from your Google account completely, use Google services → Remove account.',
            style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Disconnect', style: TextStyle(color: AppColors.brandPink))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(gmailServiceProvider).disconnect();
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(gmailConnectionProvider).value;
    final connected = email != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (connected ? AppColors.brandBlue : context.textMuted).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(Icons.mail_rounded, size: 18, color: connected ? AppColors.brandBlue : context.textSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: connected ? () => context.push('/social_hub/gmail') : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Gmail', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                if (connected) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, size: 13, color: AppColors.brandBlue)],
              ]),
              Text(connected ? email : 'Not connected',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted)),
              const SizedBox(height: 2),
              Text(connected ? 'Read · Reply · Send · Ova · tap to open inbox' : 'Read · Reply · Send · Ova',
                  style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted)),
            ]),
          ),
        ),
        if (_busy)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else if (connected)
          TextButton(
            onPressed: () => _disconnect(email),
            child: Text('Disconnect', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary)),
          )
        else
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: _connect,
            child: Text('Connect', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
      ]),
    );
  }
}

// ── Inbox ───────────────────────────────────────────────────────────────

class GmailInboxScreen extends ConsumerStatefulWidget {
  const GmailInboxScreen({super.key});

  @override
  ConsumerState<GmailInboxScreen> createState() => _GmailInboxScreenState();
}

class _GmailInboxScreenState extends ConsumerState<GmailInboxScreen> {
  static const _filters = [('Inbox', 'in:inbox'), ('Unread', 'is:unread in:inbox'), ('Starred', 'is:starred'), ('Sent', 'in:sent')];
  final _search = TextEditingController();
  String _query = 'in:inbox';
  List<GmailMessage> _items = [];
  String? _next;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim().isEmpty ? _query : '${_search.text.trim()} $_query';
      final page = await ref.read(gmailServiceProvider).list(query: q, pageToken: more ? _next : null);
      if (!mounted) return;
      setState(() {
        _items = more ? [..._items, ...page.messages] : page.messages;
        _next = page.nextPageToken;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(gmailConnectionProvider).value;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Gmail', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
          if (email != null) Text(email, style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
        ]),
      ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: AppColors.brandBlue,
        onPressed: () => showGmailCompose(context, ref).then((sent) {
          if (sent == true) _load();
        }),
        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search mail',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
              filled: true,
              fillColor: context.surfaceMid,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final (label, q) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    selected: _query == q,
                    selectedColor: AppColors.brandBlue.withValues(alpha: 0.15),
                    side: BorderSide(color: context.border),
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() => _query = q);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: AppColors.brandBlue,
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length + 1,
                    separatorBuilder: (_, _) => Divider(height: 1, color: context.border, indent: 64),
                    itemBuilder: (context, i) {
                      if (i == _items.length) {
                        if (_loading) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                        if (_items.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(child: Text('Nothing here.', style: GoogleFonts.inter(fontSize: 13, color: context.textMuted))),
                          );
                        }
                        return _next == null
                            ? const SizedBox(height: 80)
                            : TextButton(onPressed: () => _load(more: true), child: const Text('Load more'));
                      }
                      final m = _items[i];
                      return _MailRow(
                        m: m,
                        onTap: () async {
                          await context.push('/social_hub/gmail/${m.id}');
                          _load();
                        },
                      ).animate().fadeIn(duration: 160.ms, delay: (i.clamp(0, 10) * 20).ms);
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

class _MailRow extends StatelessWidget {
  final GmailMessage m;
  final VoidCallback onTap;
  const _MailRow({required this.m, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = m.unread ? FontWeight.w700 : FontWeight.w500;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.brandBlue.withValues(alpha: 0.12),
            child: Text(m.fromName.isEmpty ? '?' : m.fromName[0].toUpperCase(),
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(m.fromName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: w, color: context.textPrimary)),
                ),
                if (m.starred) const Icon(Icons.star_rounded, size: 14, color: AppColors.brandPink),
                if (m.unread) ...[
                  const SizedBox(width: 6),
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.brandBlue, shape: BoxShape.circle)),
                ],
              ]),
              Text(m.subject.isEmpty ? '(no subject)' : m.subject, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: w, color: context.textPrimary)),
              Text(m.snippet, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mail_lock_rounded, size: 28, color: context.textMuted),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary)),
            const SizedBox(height: 10),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

// ── Message ─────────────────────────────────────────────────────────────

class GmailMessageScreen extends ConsumerStatefulWidget {
  final String id;
  const GmailMessageScreen({super.key, required this.id});

  @override
  ConsumerState<GmailMessageScreen> createState() => _GmailMessageScreenState();
}

class _GmailMessageScreenState extends ConsumerState<GmailMessageScreen> {
  GmailMessage? _m;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final svc = ref.read(gmailServiceProvider);
      final m = await svc.get(widget.id);
      if (mounted) setState(() => _m = m);
      if (m.unread) await svc.modify(widget.id, remove: ['UNREAD']);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _act(String what) async {
    final svc = ref.read(gmailServiceProvider);
    try {
      switch (what) {
        case 'star':
          await svc.modify(widget.id, add: _m!.starred ? [] : ['STARRED'], remove: _m!.starred ? ['STARRED'] : []);
          await _open();
        case 'archive':
          await svc.modify(widget.id, remove: ['INBOX']);
          if (mounted) context.pop();
        case 'trash':
          final ok = await _confirm('Move to Trash?', 'You can restore it from Trash in Gmail for 30 days.', 'Move to Trash');
          if (ok != true) return;
          await svc.trash(widget.id);
          if (mounted) context.pop();
      }
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<bool?> _confirm(String title, String body, String cta) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.surface,
          title: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
          content: Text(body, style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(cta, style: const TextStyle(color: AppColors.brandPink))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        actions: m == null
            ? null
            : [
                IconButton(
                    tooltip: 'Star',
                    icon: Icon(m.starred ? Icons.star_rounded : Icons.star_border_rounded, color: m.starred ? AppColors.brandPink : context.textSecondary),
                    onPressed: () => _act('star')),
                IconButton(tooltip: 'Archive', icon: Icon(Icons.archive_outlined, color: context.textSecondary), onPressed: () => _act('archive')),
                IconButton(tooltip: 'Trash', icon: Icon(Icons.delete_outline_rounded, color: context.textSecondary), onPressed: () => _act('trash')),
              ],
      ),
      body: _error != null
          ? _ErrorView(message: _error!, onRetry: _open)
          : m == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
                  Text(m.subject.isEmpty ? '(no subject)' : m.subject,
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: context.textPrimary)),
                  const SizedBox(height: 10),
                  Text(m.from, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                  Text('to ${m.to} · ${m.date}', style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
                  Divider(height: 24, color: context.border),
                  SelectableText((m.body ?? m.snippet).trim(),
                      style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: context.textPrimary)),
                ]),
      floatingActionButton: m == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.brandBlue,
              onPressed: () => showGmailCompose(context, ref, replyTo: m).then((sent) {
                if (sent == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent')));
                }
              }),
              icon: const Icon(Icons.reply_rounded, color: Colors.white),
              label: Text('Reply', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
    );
  }
}

// ── Compose / reply ─────────────────────────────────────────────────────

/// Compose (or reply to [replyTo]). Shows the exact message again before sending.
Future<bool?> showGmailCompose(BuildContext context, WidgetRef ref, {GmailMessage? replyTo}) {
  final to = TextEditingController();
  final subject = TextEditingController(text: replyTo == null ? '' : (replyTo.subject.toLowerCase().startsWith('re:') ? replyTo.subject : 'Re: ${replyTo.subject}'));
  final body = TextEditingController();
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (ctx) {
      var sending = false;
      InputDecoration deco(String hint) => InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 13, color: ctx.textMuted),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          );
      return StatefulBuilder(builder: (ctx, setS) {
        Future<void> send() async {
          final recipient = replyTo?.from ?? to.text.trim();
          if (body.text.trim().isEmpty || (replyTo == null && !recipient.contains('@'))) return;
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (d) => AlertDialog(
              backgroundColor: d.surface,
              title: Text('Send this email?', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: d.textPrimary)),
              content: Text('To: $recipient\n\n${body.text.trim()}', maxLines: 12, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12.5, color: d.textSecondary)),
              actions: [
                TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
                  onPressed: () => Navigator.of(d).pop(true),
                  child: const Text('Send', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
          if (ok != true) return;
          setS(() => sending = true);
          try {
            final svc = ref.read(gmailServiceProvider);
            if (replyTo != null) {
              await svc.reply(replyTo.id, body.text.trim());
            } else {
              await svc.send(to: recipient, subject: subject.text.trim(), body: body.text.trim());
            }
            HapticFeedback.mediumImpact();
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          } catch (e) {
            setS(() => sending = false);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(ctx).viewInsets.bottom + 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              IconButton(icon: Icon(Icons.close_rounded, color: ctx.textSecondary), onPressed: () => Navigator.of(ctx).pop(false)),
              Expanded(
                child: Text(replyTo == null ? 'New email' : 'Reply',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
              ),
              sending
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.brandBlue), onPressed: send),
            ]),
            if (replyTo == null)
              TextField(controller: to, keyboardType: TextInputType.emailAddress, style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary), decoration: deco('To'))
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Text('To: ${replyTo.from}', style: GoogleFonts.inter(fontSize: 12.5, color: ctx.textSecondary)),
              ),
            Divider(height: 1, color: ctx.border),
            TextField(controller: subject, enabled: replyTo == null, style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary), decoration: deco('Subject')),
            Divider(height: 1, color: ctx.border),
            TextField(
              controller: body,
              autofocus: replyTo != null,
              minLines: 6,
              maxLines: 12,
              style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: ctx.textPrimary),
              decoration: deco('Message'),
            ),
          ]),
        );
      });
    },
  );
}
