import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../backend/social/models/share_models.dart';
import '../../../../backend/social/services/share_service.dart';
import '../../../../shared/theme/app_theme.dart';

enum _Tab { chats, following, followers }

/// Share a post: pick recent chats, groups, people you follow or your
/// followers (up to [ShareService.maxDirectTargets] at once), add a note,
/// or share to all your followers / everyone you follow, copy the link, or
/// hand it to another app through the system share sheet.
class ShareSheet extends ConsumerStatefulWidget {
  final String postId;
  final String authorId;

  const ShareSheet({
    super.key,
    required this.postId,
    required this.authorId,
  });

  static void show(BuildContext context, {required String postId, required String authorId}) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ShareSheet(postId: postId, authorId: authorId),
    );
  }

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  final _note = TextEditingController();
  final _search = TextEditingController();
  final Map<String, ShareTarget> _picked = {};
  _Tab _tab = _Tab.chats;
  ShareSettings? _settings;
  bool _busy = false;
  final Map<_Tab, Future<List<ShareTarget>>> _people = {};
  // Single-subscription stream: made again whenever the chats tab is shown.
  late Stream<List<ShareTarget>> _chats = _svc.recentChats(_me);

  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';
  ShareService get _svc => ref.read(shareServiceProvider);

  @override
  void initState() {
    super.initState();
    _svc.getShareSettings(widget.postId).then((s) {
      if (mounted) setState(() => _settings = s);
    }).catchError((_) {});
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brandBlue,
    ));
  }

  bool get _private => _settings?.isPrivateContent == true && widget.authorId != _me;

  void _toggle(ShareTarget t) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_picked.remove(t.id) == null) {
        if (_picked.length >= ShareService.maxDirectTargets) {
          _toast('You can pick up to ${ShareService.maxDirectTargets}. Use "Share to all" for more.');
          return;
        }
        _picked[t.id] = t;
      }
    });
  }

  Future<void> _send() async {
    if (_picked.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final n = await _svc.sendToTargets(
        postId: widget.postId,
        me: _me,
        targets: _picked.values.toList(),
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(n == 0 ? 'Could not send. Check your connection.' : 'Sent to $n ${n == 1 ? 'chat' : 'chats'}');
    } on StateError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareToAll({required bool followers}) async {
    final who = followers ? 'all your followers' : 'everyone you follow';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Share with $who?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'They’ll get a notification with this post. People who turned off shares or limited who can message them won’t get it.',
          style: TextStyle(fontSize: 12.5, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _svc.shareToAll(postId: widget.postId, followers: followers, note: _note.text);
      await _svc.recordShare(widget.postId, _me);
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(r.sent == 0 ? 'No one new to share with right now.' : 'Shared with ${r.sent} ${r.sent == 1 ? 'person' : 'people'}');
    } on FirebaseFunctionsException catch (e) {
      _toast(switch (e.code) {
        'resource-exhausted' || 'permission-denied' || 'not-found' => e.message ?? 'Could not share right now.',
        'unimplemented' => 'Share to all is coming soon.',
        _ => 'Could not share right now. Please try again.',
      });
    } catch (_) {
      _toast('Could not share right now. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink() async {
    final url = _svc.linkFor(widget.postId, _me);
    await Clipboard.setData(ClipboardData(text: url));
    await _svc.recordShare(widget.postId, _me);
    if (!mounted) return;
    Navigator.of(context).pop();
    _toast('Link copied');
  }

  Future<void> _systemShare() async {
    final url = _svc.linkFor(widget.postId, _me);
    final box = context.findRenderObject() as RenderBox?;
    final note = _note.text.trim();
    await SharePlus.instance.share(ShareParams(
      text: note.isEmpty ? 'Watch this on Oneova: $url' : '$note\n$url',
      subject: 'Watch this on Oneova',
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
    await _svc.recordShare(widget.postId, _me);
  }

  Future<List<ShareTarget>> _peopleFor(_Tab tab) =>
      _people.putIfAbsent(tab, () => _svc.people(_me, followers: tab == _Tab.followers));

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: height * 0.82),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Share',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: context.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (_private)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text('This post is private, so it can’t be shared.',
                      style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
                )
              else ...[
                _searchField(),
                _tabs(),
                Flexible(child: _targetList()),
                _noteField(),
                if (_picked.isNotEmpty) _sendButton(),
              ],
              Divider(height: 1, color: context.border),
              _quickActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _search,
          style: TextStyle(fontSize: 13, color: context.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search people and chats',
            hintStyle: TextStyle(fontSize: 13, color: context.textMuted),
            prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: context.surfaceMid,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: context.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: context.border),
            ),
          ),
        ),
      );

  Widget _tabs() {
    Widget chip(_Tab t, String label, IconData icon) {
      final on = _tab == t;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          selected: on,
          onSelected: (_) => setState(() {
            if (t == _Tab.chats && _tab != _Tab.chats) _chats = _svc.recentChats(_me);
            _tab = t;
          }),
          avatar: Icon(icon, size: 14, color: on ? Colors.white : context.textSecondary),
          label: Text(label),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : context.textPrimary,
          ),
          showCheckmark: false,
          selectedColor: AppColors.brandBlue,
          backgroundColor: context.surfaceMid,
          side: BorderSide(color: on ? AppColors.brandBlue : context.border),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(_Tab.chats, 'Recent chats', Icons.forum_outlined),
            chip(_Tab.following, 'Following', Icons.person_outline_rounded),
            chip(_Tab.followers, 'Followers', Icons.groups_2_outlined),
          ],
        ),
      ),
    );
  }

  List<ShareTarget> _filter(List<ShareTarget> list) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  Widget _targetList() {
    if (_me.isEmpty) return _empty('Sign in to share with people.');
    if (_tab == _Tab.chats) {
      return StreamBuilder<List<ShareTarget>>(
        stream: _chats,
        builder: (context, snap) {
          if (snap.hasError) return _empty('Could not load your chats.');
          if (!snap.hasData) return _loading();
          final list = _filter(snap.data!);
          return list.isEmpty ? _empty('No chats yet') : _grid(list);
        },
      );
    }
    return FutureBuilder<List<ShareTarget>>(
      future: _peopleFor(_tab),
      builder: (context, snap) {
        if (snap.hasError) return _empty('Could not load people.');
        if (!snap.hasData) return _loading();
        final list = _filter(snap.data!);
        final allLabel = _tab == _Tab.followers ? 'Share to all followers' : 'Share to everyone you follow';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snap.data!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _shareToAll(followers: _tab == _Tab.followers),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.4)),
                    minimumSize: const Size.fromHeight(38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  icon: const Icon(Icons.campaign_outlined, size: 17),
                  label: Text(allLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ),
            Flexible(
              child: list.isEmpty
                  ? _empty(_tab == _Tab.followers ? 'No followers yet' : 'You’re not following anyone yet')
                  : _grid(list),
            ),
          ],
        );
      },
    );
  }

  Widget _grid(List<ShareTarget> list) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 84,
        mainAxisExtent: 86,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final t = list[i];
        final on = _picked.containsKey(t.id);
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => _toggle(t),
          child: Column(
            children: [
              const SizedBox(height: 4),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: on ? AppColors.brandBlue : Colors.transparent, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: context.surfaceMid,
                      backgroundImage: (t.avatarUrl ?? '').startsWith('http') ? NetworkImage(t.avatarUrl!) : null,
                      child: (t.avatarUrl ?? '').startsWith('http')
                          ? null
                          : Icon(t.isGroup ? Icons.groups_rounded : Icons.person_rounded,
                              size: 20, color: context.textSecondary),
                    ),
                  ),
                  if (on)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.surface, width: 1.5),
                        ),
                        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: context.textPrimary),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _noteField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          controller: _note,
          maxLength: 140,
          style: TextStyle(fontSize: 13, color: context.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: 'Add a message (optional)',
            hintStyle: TextStyle(fontSize: 13, color: context.textMuted),
            prefixIcon: Icon(Icons.edit_outlined, size: 16, color: context.textMuted),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: context.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: context.border),
            ),
          ),
        ),
      );

  Widget _sendButton() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: FilledButton.icon(
          onPressed: _busy ? null : _send,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandBlue,
            minimumSize: const Size.fromHeight(40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
          icon: _busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 16),
          label: Text('Send to ${_picked.length}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _quickActions() {
    Widget action(IconData icon, String label, VoidCallback? onTap, {bool accent = false}) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent ? AppColors.brandBlue : context.surfaceMid,
                      shape: BoxShape.circle,
                      border: Border.all(color: accent ? AppColors.brandBlue : context.border),
                    ),
                    child: Icon(icon, size: 19, color: accent ? Colors.white : context.textPrimary),
                  ),
                  const SizedBox(height: 5),
                  Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textSecondary)),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          action(Icons.link_rounded, 'Copy link', _private ? null : _copyLink, accent: true),
          action(Icons.campaign_outlined, 'All followers',
              _private || _busy ? null : () => _shareToAll(followers: true)),
          action(Icons.ios_share_rounded, 'More apps', _private ? null : _systemShare),
        ],
      ),
    );
  }

  Widget _loading() => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(text, style: TextStyle(fontSize: 12.5, color: context.textSecondary))),
      );
}
