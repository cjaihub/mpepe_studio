import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../shared/theme/app_theme.dart';
import 'wish_service.dart';
import 'wish_widgets.dart';

/// Oneova Feedback — a light pop-up sheet (never a full screen) where people
/// say what they wish Oneova had, back each other's feedback and talk about it
/// live. Opened with `context.push('/feedback')` (optional `?idea=<id>`); the
/// route is a modal sheet over whatever screen is open, and back closes it.
class FeedbackSheetPage extends Page<void> {
  const FeedbackSheetPage({super.key, this.openIdeaId});
  final String? openIdeaId;

  @override
  Route<void> createRoute(BuildContext context) {
    return ModalBottomSheetRoute<void>(
      settings: this,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedbackSheet(openIdeaId: openIdeaId),
    );
  }
}

class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, this.openIdeaId});
  final String? openIdeaId;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  late String? _openId = (widget.openIdeaId?.isNotEmpty ?? false) ? widget.openIdeaId : null;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: inset > 0 ? 0.9 : 0.62,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        snap: true,
        builder: (context, scroll) => Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: context.border)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            child: _openId == null
                ? _FeedbackList(
                    key: const ValueKey('list'),
                    scroll: scroll,
                    onOpen: (id) => setState(() => _openId = id),
                  )
                : _FeedbackDetail(
                    key: ValueKey(_openId),
                    ideaId: _openId!,
                    scroll: scroll,
                    onBack: () => setState(() => _openId = null),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

// ─── List + quick composer ──────────────────────────────────────────────────

class _FeedbackList extends StatefulWidget {
  const _FeedbackList({super.key, required this.scroll, required this.onOpen});
  final ScrollController scroll;
  final ValueChanged<String> onOpen;

  @override
  State<_FeedbackList> createState() => _FeedbackListState();
}

class _FeedbackListState extends State<_FeedbackList> {
  WishFilter _filter = WishFilter.top;
  late Stream<List<WishIdea>> _stream = WishService.instance.watchIdeas(_filter);
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _details = false;
  bool _busy = false;
  List<WishIdea> _loaded = const [];

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _setFilter(WishFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _stream = WishService.instance.watchIdeas(f);
    });
  }

  Future<void> _send() async {
    final t = _title.text.trim();
    if (t.length < 3 || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await WishService.instance.postIdea(title: t, body: _body.text);
      _title.clear();
      _body.clear();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => _details = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('Thanks! Your feedback is live.'),
        backgroundColor: AppColors.brandBlue,
        duration: Duration(seconds: 2),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send your feedback. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final similar = similarFeedback(_title.text, _loaded);
    return CustomScrollView(
      controller: widget.scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Handle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 8, 0),
              child: Row(children: [
                const Icon(Icons.rate_review_outlined, color: AppColors.brandBlue, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Feedback',
                      style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textMuted),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text('What do you wish Oneova had? The team reads every one.',
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
            ),
            _composer(context),
            if (similar.isNotEmpty) _similar(context, similar),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  for (final f in WishFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(f.label),
                        selected: f == _filter,
                        onSelected: (_) => _setFilter(f),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selectedColor: AppColors.brandBlue,
                        backgroundColor: context.surfaceMid,
                        side: BorderSide.none,
                        labelStyle: TextStyle(
                          color: f == _filter ? AppColors.brandWhite : context.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
        StreamBuilder<List<WishIdea>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return _note(context, 'Could not load feedback. Check your connection.');
            }
            if (!snap.hasData) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                ),
              );
            }
            final ideas = snap.data!;
            if (_filter == WishFilter.top || _filter == WishFilter.newest) {
              // Keep the latest list for "similar feedback" while typing.
              if (!identical(_loaded, ideas)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !identical(_loaded, ideas)) setState(() => _loaded = ideas);
                });
              }
            }
            if (ideas.isEmpty) {
              return _note(context,
                  _filter == WishFilter.mine ? 'You have not shared feedback yet.' : 'Nothing here yet — be the first.');
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList.builder(
                itemCount: ideas.length,
                itemBuilder: (context, i) => _FeedbackRow(idea: ideas[i], onTap: () => widget.onOpen(ideas[i].id)),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _note(BuildContext context, String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.textMuted, fontSize: 13.5)),
        ),
      );

  Widget _composer(BuildContext context) {
    final ok = _title.text.trim().length >= 3;
    InputDecoration dec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: context.textMuted),
          counterText: '',
          isDense: true,
          border: InputBorder.none,
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: context.textPrimary, fontSize: 14.5),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(),
              decoration: dec('I wish Oneova had…'),
            ),
          ),
          IconButton(
            tooltip: _details ? 'Hide details' : 'Add details',
            icon: Icon(_details ? Icons.notes_rounded : Icons.add_comment_outlined, color: context.textMuted, size: 20),
            onPressed: () => setState(() => _details = !_details),
          ),
          IconButton(
            onPressed: ok && !_busy ? _send : null,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                : Icon(Icons.send_rounded, color: ok ? AppColors.brandBlue : context.textMuted),
          ),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _details
              ? Padding(
                  padding: const EdgeInsets.only(right: 10, bottom: 8),
                  child: TextField(
                    controller: _body,
                    maxLength: 1500,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: context.textSecondary, fontSize: 13.5),
                    decoration: dec('Why would it help you? (optional)'),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  Widget _similar(BuildContext context, List<WishIdea> similar) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.brandPink),
          const SizedBox(width: 5),
          Text('Already asked? Back it instead',
              style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        for (final s in similar)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => widget.onOpen(s.id),
                  child: Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textPrimary, fontSize: 13.5)),
                ),
              ),
              const SizedBox(width: 8),
              _LiveReact(idea: s),
            ]),
          ),
      ]),
    );
  }
}

/// Word-overlap match so people back existing feedback instead of repeating it.
List<WishIdea> similarFeedback(String text, List<WishIdea> pool) {
  const stop = {
    'the', 'and', 'for', 'with', 'that', 'this', 'have', 'wish', 'oneova', 'had', 'would', 'could', 'should',
    'like', 'want', 'add', 'please', 'make', 'can', 'you', 'app', 'more', 'some', 'when', 'from', 'your',
  };
  Set<String> words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 3 && !stop.contains(w))
      .toSet();
  final q = words(text);
  if (q.isEmpty || text.trim().length < 4) return const [];
  final scored = <(WishIdea, double)>[];
  for (final i in pool) {
    final w = words('${i.title} ${i.body}');
    final hit = q.intersection(w).length;
    if (hit == 0) continue;
    final score = hit / q.length;
    if (score >= 0.5 || hit >= 2) scored.add((i, score + i.reactionCount * 0.001));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.take(3).map((e) => e.$1).toList();
}

class _LiveReact extends StatelessWidget {
  const _LiveReact({required this.idea});
  final WishIdea idea;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: WishService.instance.watchMyReaction(idea.id),
      builder: (context, s) {
        final r = s.data ?? false;
        return WishReactButton(
          reacted: r,
          count: idea.reactionCount,
          onTap: () => WishService.instance.toggleReaction(idea.id, r),
        );
      },
    );
  }
}

class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({required this.idea, required this.onTap});
  final WishIdea idea;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(idea.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3)),
              const SizedBox(height: 5),
              Row(children: [
                WishStatusChip(status: idea.status),
                const SizedBox(width: 8),
                Icon(Icons.chat_bubble_outline_rounded, size: 13, color: context.textMuted),
                const SizedBox(width: 3),
                Text('${idea.commentCount}', style: TextStyle(color: context.textMuted, fontSize: 12)),
                if (idea.adminReply.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.verified_rounded, size: 13, color: AppColors.brandBlue),
                  const SizedBox(width: 3),
                  const Text('Team replied',
                      style: TextStyle(color: AppColors.brandBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          _LiveReact(idea: idea),
        ]),
      ),
    );
  }
}

// ─── One feedback post with live comments ───────────────────────────────────

class _FeedbackDetail extends StatefulWidget {
  const _FeedbackDetail({super.key, required this.ideaId, required this.scroll, required this.onBack});
  final String ideaId;
  final ScrollController scroll;
  final VoidCallback onBack;

  @override
  State<_FeedbackDetail> createState() => _FeedbackDetailState();
}

class _FeedbackDetailState extends State<_FeedbackDetail> {
  final _svc = WishService.instance;
  late final Stream<WishIdea?> _idea = _svc.watchIdea(widget.ideaId);
  late final Stream<List<WishComment>> _comments = _svc.watchComments(widget.ideaId);
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _svc.addComment(widget.ideaId, text);
      _input.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not post your comment. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(WishIdea idea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: context.surface,
        title: Text('Delete this feedback?', style: TextStyle(color: context.textPrimary)),
        content: Text('It will be removed with its comments.', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.brandPink)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.deleteIdea(idea.id);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WishIdea?>(
      stream: _idea,
      builder: (context, snap) {
        final idea = snap.data;
        return Column(children: [
          const _Handle(),
          Row(children: [
            IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: widget.onBack),
            Expanded(
              child: Text('Feedback',
                  style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (idea != null && idea.authorId == _svc.uid)
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline_rounded, color: context.textMuted),
                onPressed: () => _delete(idea),
              ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: context.textMuted),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
          Expanded(
            child: idea == null
                ? ListView(controller: widget.scroll, children: [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: snap.connectionState == ConnectionState.waiting
                            ? const CircularProgressIndicator(color: AppColors.brandBlue)
                            : Text('This feedback is no longer available.',
                                style: TextStyle(color: context.textSecondary)),
                      ),
                    ),
                  ])
                : StreamBuilder<List<WishComment>>(
                    stream: _comments,
                    builder: (context, cs) {
                      final comments = cs.data ?? const <WishComment>[];
                      return ListView(
                        controller: widget.scroll,
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                        children: [
                          _Body(idea: idea),
                          const SizedBox(height: 18),
                          Row(children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(comments.isEmpty ? 'Live comments' : 'Live comments · ${comments.length}',
                                style: TextStyle(
                                    color: context.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 6),
                          if (comments.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text('Add how this would help you.',
                                  style: TextStyle(color: context.textMuted, fontSize: 13)),
                            ),
                          for (final c in comments)
                            _CommentTile(
                              comment: c,
                              canDelete: c.authorId == _svc.uid,
                              onDelete: () => _svc.deleteComment(idea.id, c.id),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          if (idea != null) _CommentBar(controller: _input, sending: _sending, onSend: _send),
        ]);
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.idea});
  final WishIdea idea;

  @override
  Widget build(BuildContext context) {
    final cat = wishCategoryLabel(idea.category);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        WishAvatar(url: idea.authorPhoto, name: idea.authorName, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(idea.authorName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
        if (idea.createdAt != null)
          Text(timeago.format(idea.createdAt!), style: TextStyle(color: context.textMuted, fontSize: 11.5)),
      ]),
      const SizedBox(height: 10),
      Text(idea.title,
          style: TextStyle(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w800, height: 1.3)),
      if (idea.body.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(idea.body, style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.45)),
      ],
      const SizedBox(height: 10),
      Row(children: [
        WishStatusChip(status: idea.status),
        if (cat.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(cat, style: TextStyle(color: context.textMuted, fontSize: 12)),
        ],
        const Spacer(),
        _LiveReact(idea: idea),
      ]),
      const SizedBox(height: 12),
      _StatusJourney(status: idea.status),
      if (idea.adminReply.isNotEmpty) ...[
        const SizedBox(height: 12),
        WishTeamReply(text: idea.adminReply),
      ],
    ]);
  }
}

/// Open → Planned → Building → Shipped, with the current step lit.
class _StatusJourney extends StatelessWidget {
  const _StatusJourney({required this.status});
  final String status;
  static const _steps = ['open', 'planned', 'building', 'shipped'];

  @override
  Widget build(BuildContext context) {
    if (status == 'declined') {
      return Text('The team reviewed this; it is not on the plan for now.',
          style: TextStyle(color: context.textMuted, fontSize: 12.5));
    }
    final at = _steps.indexOf(status).clamp(0, _steps.length - 1);
    final lit = _steps[at] == 'shipped' ? AppColors.brandPink : AppColors.brandBlue;
    return Row(children: [
      for (var i = 0; i < _steps.length; i++) ...[
        Expanded(
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 3,
              decoration: BoxDecoration(color: i <= at ? lit : context.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 4),
            Text(WishStatusChip.labelOf(_steps[i]),
                style: TextStyle(
                  color: i == at ? context.textPrimary : context.textMuted,
                  fontSize: 10.5,
                  fontWeight: i == at ? FontWeight.w700 : FontWeight.w500,
                )),
          ]),
        ),
        if (i < _steps.length - 1) const SizedBox(width: 4),
      ],
    ]);
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.canDelete, required this.onDelete});
  final WishComment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (comment.isOfficial) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: WishTeamReply(text: comment.text));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        WishAvatar(url: comment.authorPhoto, name: comment.authorName, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(comment.authorName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              if (comment.createdAt != null) ...[
                const SizedBox(width: 6),
                Text(timeago.format(comment.createdAt!), style: TextStyle(color: context.textMuted, fontSize: 11)),
              ],
            ]),
            const SizedBox(height: 2),
            Text(comment.text, style: TextStyle(color: context.textSecondary, fontSize: 13.5, height: 1.35)),
          ]),
        ),
        if (canDelete)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
            onPressed: onDelete,
          ),
      ]),
    );
  }
}

class _CommentBar extends StatelessWidget {
  const _CommentBar({required this.controller, required this.sending, required this.onSend});
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.border))),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: context.textPrimary, fontSize: 14),
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Add a comment…',
                hintStyle: TextStyle(color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
          ),
          IconButton(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                : const Icon(Icons.send_rounded, color: AppColors.brandBlue),
          ),
        ]),
      ),
    );
  }
}

/// Opens Feedback as a pop-up over the current screen.
void openFeedback(BuildContext context, {String? ideaId}) =>
    context.push(ideaId == null ? '/feedback' : '/feedback?idea=$ideaId');
