import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/tiktok_api.dart';
import '../backend/tiktok_oauth_service.dart';
import '../shared/theme/app_theme.dart';

/// The linked TikTok account: profile + stats, the creator's TikTok videos,
/// and sending Oneova videos to TikTok (drafts or a direct post).
class TikTokAccountScreen extends ConsumerStatefulWidget {
  const TikTokAccountScreen({super.key});

  @override
  ConsumerState<TikTokAccountScreen> createState() => _TikTokAccountScreenState();
}

class _TikTokAccountScreenState extends ConsumerState<TikTokAccountScreen> {
  TikTokAccount? _account;
  String? _error;
  bool _loading = true;

  final List<TikTokVideo> _videos = [];
  int? _cursor;
  bool _hasMore = false;
  bool _loadingVideos = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String _message(Object e) => e is FirebaseFunctionsException ? (e.message ?? 'TikTok is unavailable.') : 'TikTok is unavailable. Try again.';

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(tiktokApiProvider);
    try {
      final account = await api.profile();
      final page = await api.videos();
      if (!mounted) return;
      setState(() {
        _account = account;
        _videos
          ..clear()
          ..addAll(page.videos);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _moreVideos() async {
    if (_loadingVideos || !_hasMore) return;
    setState(() => _loadingVideos = true);
    try {
      final page = await ref.read(tiktokApiProvider).videos(cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _videos.addAll(page.videos);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _loadingVideos = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Disconnect TikTok?'),
        content: const Text('Oneova will lose access to your TikTok account. You can connect again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(tiktokOAuthProvider.notifier).disconnect();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(tiktokConnectionStatusProvider).value;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.topBarBg,
        foregroundColor: context.topBarFg,
        title: const Text('TikTok'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _refresh),
          if (connection != null)
            IconButton(tooltip: 'Disconnect', icon: const Icon(Icons.link_off_rounded), onPressed: _disconnect),
        ],
      ),
      body: connection == null && !_loading
          ? _NotConnected(onConnect: () => context.push('/social_hub/tiktok_wizard'))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_loading && _account == null)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                  else if (_error != null && _account == null)
                    _ErrorCard(message: _error!, onRetry: _refresh)
                  else if (_account != null)
                    _ProfileCard(account: _account!),
                  const SizedBox(height: 24),
                  _SectionTitle('Send to TikTok', subtitle: 'Your Oneova videos'),
                  const SizedBox(height: 8),
                  const _OneovaVideos(),
                  const SizedBox(height: 24),
                  _SectionTitle('On TikTok', subtitle: _account == null ? null : '${_account!.videoCount} videos'),
                  const SizedBox(height: 8),
                  if (_videos.isEmpty && !_loading)
                    Text('No public TikTok videos yet.', style: TextStyle(color: context.textMuted))
                  else
                    for (final v in _videos) _TikTokVideoTile(video: v),
                  if (_hasMore)
                    Center(
                      child: TextButton(
                        onPressed: _loadingVideos ? null : _moreVideos,
                        child: Text(_loadingVideos ? 'Loading…' : 'Load more'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
  return '$n';
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.music_note_rounded, size: 48, color: context.brandBlue),
          const SizedBox(height: 12),
          Text('Connect TikTok', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('See your stats and videos, and send Oneova videos to TikTok.',
              textAlign: TextAlign.center, style: TextStyle(color: context.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.brandBlue),
            onPressed: onConnect,
            child: const Text('Connect'),
          ),
        ]),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.border)),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, color: context.brandPink),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: TextStyle(color: context.textPrimary))),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.account});
  final TikTokAccount account;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: context.surfaceMid,
            backgroundImage: account.avatarUrl != null ? NetworkImage(account.avatarUrl!) : null,
            child: account.avatarUrl == null ? Icon(Icons.person, color: context.textMuted) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(account.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                if (account.isVerified) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.verified_rounded, size: 16, color: context.brandBlue),
                ],
              ]),
              if (account.username != null) Text('@${account.username}', style: TextStyle(color: context.textSecondary)),
            ]),
          ),
          if (account.profileUrl != null)
            IconButton(
              tooltip: 'Open in TikTok',
              icon: Icon(Icons.open_in_new_rounded, color: context.textSecondary),
              onPressed: () => launchUrl(Uri.parse(account.profileUrl!), mode: LaunchMode.externalApplication),
            ),
        ]),
        if (account.bio != null) ...[
          const SizedBox(height: 10),
          Text(account.bio!, style: TextStyle(color: context.textSecondary)),
        ],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _Stat('Followers', account.followerCount),
          _Stat('Following', account.followingCount),
          _Stat('Likes', account.likesCount),
          _Stat('Videos', account.videoCount),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(_compact(value), style: TextStyle(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      Text(label, style: TextStyle(color: context.textMuted, fontSize: 12)),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(title, style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      if (subtitle != null) ...[
        const SizedBox(width: 8),
        Text(subtitle!, style: TextStyle(color: context.textMuted, fontSize: 13)),
      ],
    ]);
  }
}

class _TikTokVideoTile extends StatelessWidget {
  const _TikTokVideoTile({required this.video});
  final TikTokVideo video;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 64,
          child: video.coverUrl != null
              ? Image.network(video.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: context.surfaceMid))
              : ColoredBox(color: context.surfaceMid),
        ),
      ),
      title: Text(video.title.isEmpty ? 'Untitled' : video.title,
          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.textPrimary)),
      subtitle: Text(
        '${_compact(video.views)} views · ${_compact(video.likes)} likes · ${_compact(video.comments)} comments',
        style: TextStyle(color: context.textMuted, fontSize: 12),
      ),
      onTap: video.shareUrl == null ? null : () => launchUrl(Uri.parse(video.shareUrl!), mode: LaunchMode.externalApplication),
    );
  }
}

/// The signed-in creator's recent Oneova videos, each with its TikTok status.
class _OneovaVideos extends ConsumerWidget {
  const _OneovaVideos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('content')
          .where('authorId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        final docs = snap.data!.docs.where((d) => d.data()['type'] != 'photo').take(10).toList();
        if (docs.isEmpty) {
          return Text('Post a video on Oneova to send it to TikTok.', style: TextStyle(color: context.textMuted));
        }
        return Column(children: [for (final d in docs) _OneovaVideoTile(id: d.id, data: d.data())]);
      },
    );
  }
}

class _OneovaVideoTile extends ConsumerWidget {
  const _OneovaVideoTile({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  static String? _statusLabel(String? s) => switch (s) {
        'uploading' => 'Uploading to TikTok…',
        'processing' => 'TikTok is processing',
        'in_drafts' => 'In your TikTok drafts',
        'posted' => 'Posted to TikTok',
        'public' => 'Live on TikTok',
        'failed' => 'TikTok post failed',
        'removed' => 'Removed from TikTok',
        _ => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = (data['mediaMetadata'] as Map?) ?? const {};
    final thumb = meta['thumbnailUrl'] as String?;
    final caption = (data['description'] ?? '').toString();
    final status = _statusLabel((data['tiktok'] as Map?)?['status'] as String?);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 64,
          child: thumb != null
              ? Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: context.surfaceMid))
              : ColoredBox(color: context.surfaceMid),
        ),
      ),
      title: Text(caption.isEmpty ? 'Untitled video' : caption,
          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.textPrimary)),
      subtitle: status == null ? null : Text(status, style: TextStyle(color: context.brandPink, fontSize: 12)),
      trailing: IconButton(
        tooltip: 'Send to TikTok',
        icon: Icon(Icons.send_rounded, color: context.brandBlue),
        onPressed: () => _send(context, ref),
      ),
    );
  }

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.surface,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.inbox_rounded, color: context.brandBlue),
            title: Text('Send to TikTok drafts', style: TextStyle(color: context.textPrimary)),
            subtitle: Text('Finish editing and post it in the TikTok app.', style: TextStyle(color: context.textMuted)),
            onTap: () => Navigator.pop(c, 'draft'),
          ),
          ListTile(
            leading: Icon(Icons.publish_rounded, color: context.brandBlue),
            title: Text('Post to TikTok now', style: TextStyle(color: context.textPrimary)),
            subtitle: Text('Choose who can see it, then post.', style: TextStyle(color: context.textMuted)),
            onTap: () => Navigator.pop(c, 'direct'),
          ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    final api = ref.read(tiktokApiProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (choice == 'draft') {
      messenger.showSnackBar(const SnackBar(content: Text('Sending to your TikTok drafts…')));
      try {
        await api.sendToDrafts(id);
        messenger.showSnackBar(const SnackBar(content: Text('Sent. TikTok will notify you when it’s in your drafts.')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e is FirebaseFunctionsException ? (e.message ?? 'Send failed.') : 'Send failed.')));
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      builder: (_) => TikTokDirectPostSheet(
        contentId: id,
        initialTitle: (data['description'] ?? '').toString(),
        durationMs: ((data['mediaMetadata'] as Map?)?['durationMs'] as num?)?.toInt(),
      ),
    );
  }
}

/// TikTok's required direct-post screen: the creator's account, a privacy
/// level picked by the person (no default), interaction settings, the
/// commercial-content disclosure and TikTok's consent line.
class TikTokDirectPostSheet extends ConsumerStatefulWidget {
  const TikTokDirectPostSheet({super.key, required this.contentId, this.initialTitle = '', this.durationMs});
  final String contentId;
  final String initialTitle;
  final int? durationMs;

  @override
  ConsumerState<TikTokDirectPostSheet> createState() => _TikTokDirectPostSheetState();
}

class _TikTokDirectPostSheetState extends ConsumerState<TikTokDirectPostSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.initialTitle);
  TikTokCreatorInfo? _info;
  String? _error;
  String? _privacy;
  bool _comments = false;
  bool _duet = false;
  bool _stitch = false;
  bool _disclose = false;
  bool _yourBrand = false;
  bool _branded = false;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    ref.read(tiktokApiProvider).creatorInfo().then((i) {
      if (mounted) setState(() => _info = i);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is FirebaseFunctionsException ? e.message : 'TikTok is unavailable.');
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String? get _blocker {
    final info = _info;
    if (info == null) return 'Loading…';
    final max = info.maxVideoPostDurationSec;
    if (max != null && widget.durationMs != null && widget.durationMs! > max * 1000) {
      return 'TikTok allows videos up to $max seconds for your account.';
    }
    if (_privacy == null) return 'Choose who can see this post.';
    if (_disclose && !_yourBrand && !_branded) return 'Choose “Your brand”, “Branded content” or both.';
    if (_branded && _privacy == 'SELF_ONLY') return 'Branded content can’t be private.';
    return null;
  }

  Future<void> _post() async {
    if (_blocker != null) return;
    setState(() => _posting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tiktokApiProvider).postDirect(
            widget.contentId,
            TikTokDirectPost(
              title: _title.text.trim(),
              privacyLevel: _privacy!,
              allowComments: _comments,
              allowDuet: _duet,
              allowStitch: _stitch,
              brandContent: _disclose && _branded,
              brandOrganic: _disclose && _yourBrand,
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Posted. It may take a few minutes to appear on your TikTok profile.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      messenger.showSnackBar(SnackBar(content: Text(e is FirebaseFunctionsException ? (e.message ?? 'Post failed.') : 'Post failed.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final blocker = _blocker;
    final consent = _disclose && _branded
        ? 'By posting, you agree to TikTok’s Branded Content Policy and Music Usage Confirmation.'
        : 'By posting, you agree to TikTok’s Music Usage Confirmation.';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Post to TikTok', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(color: context.brandPink))
            else if (info == null)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else ...[
              Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: context.surfaceMid,
                  backgroundImage: info.avatarUrl != null ? NetworkImage(info.avatarUrl!) : null,
                ),
                const SizedBox(width: 8),
                Text('Posting as ${info.nickname ?? info.username ?? 'your TikTok account'}',
                    style: TextStyle(color: context.textSecondary)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 2200,
                maxLines: 3,
                minLines: 1,
                style: TextStyle(color: context.textPrimary),
                decoration: const InputDecoration(labelText: 'Caption'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _privacy,
                hint: const Text('Who can see this post'),
                items: [
                  for (final o in info.privacyLevelOptions)
                    DropdownMenuItem(
                      value: o,
                      enabled: !(_disclose && _branded && o == 'SELF_ONLY'),
                      child: Text(TikTokCreatorInfo.label(o)),
                    ),
                ],
                onChanged: (v) => setState(() => _privacy = v),
              ),
              const SizedBox(height: 8),
              Text('Allow people to', style: TextStyle(color: context.textSecondary)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Comment'),
                value: _comments && !info.commentDisabled,
                onChanged: info.commentDisabled ? null : (v) => setState(() => _comments = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Duet'),
                value: _duet && !info.duetDisabled,
                onChanged: info.duetDisabled ? null : (v) => setState(() => _duet = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Stitch'),
                value: _stitch && !info.stitchDisabled,
                onChanged: info.stitchDisabled ? null : (v) => setState(() => _stitch = v ?? false),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disclose commercial content'),
                subtitle: const Text('This video promotes a brand, product or service.'),
                value: _disclose,
                onChanged: (v) => setState(() {
                  _disclose = v;
                  if (!v) _yourBrand = _branded = false;
                }),
              ),
              if (_disclose) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Your brand'),
                  subtitle: const Text('Labelled “Promotional content”.'),
                  value: _yourBrand,
                  onChanged: (v) => setState(() => _yourBrand = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Branded content'),
                  subtitle: const Text('Labelled “Paid partnership”.'),
                  value: _branded,
                  onChanged: (v) => setState(() {
                    _branded = v ?? false;
                    if (_branded && _privacy == 'SELF_ONLY') _privacy = null;
                  }),
                ),
              ],
              const SizedBox(height: 8),
              Text(consent, style: TextStyle(color: context.textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              if (blocker != null) Text(blocker, style: TextStyle(color: context.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: context.brandBlue),
                  onPressed: blocker != null || _posting ? null : _post,
                  child: Text(_posting ? 'Posting…' : 'Post'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
