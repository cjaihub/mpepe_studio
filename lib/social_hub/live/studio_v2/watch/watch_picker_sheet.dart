// LIVE STUDIO v2 — host / co-host sheet: put YouTube or a web page on the
// shared "Watch together" layer. YouTube search runs on the server
// (lsYouTubeSearch, YouTube Data API key in Secret Manager); pasting a
// YouTube link works without the key.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/watch/studio_watch.dart';
import '../theme/live_studio_tokens.dart';
import 'watch_layer.dart' show watchUrlFromInput;

Future<void> showWatchTogetherSheet(
  BuildContext context, {
  required String streamId,
  required LiveStudioTokens tokens,
  WatchKind initial = WatchKind.youtube,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: LiveStudioAccent.clear,
    barrierColor: LiveStudioTokens.dimTint(0.45),
    builder: (_) => WatchTogetherSheet(streamId: streamId, tokens: tokens, initial: initial),
  );
}

String _errText(Object e) => e is FirebaseFunctionsException ? (e.message ?? 'Something went wrong.') : 'No connection.';

class WatchTogetherSheet extends ConsumerStatefulWidget {
  const WatchTogetherSheet({super.key, required this.streamId, required this.tokens, this.initial = WatchKind.youtube});
  final String streamId;
  final LiveStudioTokens tokens;
  final WatchKind initial;

  @override
  ConsumerState<WatchTogetherSheet> createState() => _WatchTogetherSheetState();
}

class _WatchTogetherSheetState extends ConsumerState<WatchTogetherSheet> {
  late WatchKind _kind = widget.initial;
  final _q = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool? _enabled;
  String? _error;
  String _lastQuery = '';
  List<YouTubeResult> _items = const [];
  String? _next;

  StudioWatchApi get _api => ref.read(studioWatchApiProvider);

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _play(YouTubeResult v) async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await _api.playYouTube(widget.streamId, v);
      ref.read(studioWatchMinimizedProvider(widget.streamId).notifier).set(false);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPage(String input) async {
    final url = watchUrlFromInput(input);
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.openPage(widget.streamId, url);
      ref.read(studioWatchMinimizedProvider(widget.streamId).notifier).set(false);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search({bool more = false}) async {
    final q = more ? _lastQuery : _q.text.trim();
    if (q.isEmpty) return;
    final id = youTubeIdFrom(q);
    if (id != null && !more) {
      await _play(YouTubeResult(videoId: id, title: '', channel: '', thumbUrl: ''));
      return;
    }
    _focus.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await _api.search(widget.streamId, q, pageToken: more ? _next : null);
      if (!mounted) return;
      setState(() {
        _enabled = page.enabled;
        _lastQuery = q;
        _items = more ? [..._items, ...page.items] : page.items;
        _next = page.nextPageToken;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() => _kind == WatchKind.youtube ? _search() : _openPage(_q.text);

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final layer = ref.watch(studioWatchProvider(widget.streamId)).value;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final yt = _kind == WatchKind.youtube;

    Widget tab(WatchKind k, IconData icon, String label) {
      final on = _kind == k;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => setState(() {
              _kind = k;
              _error = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 38,
              decoration: BoxDecoration(
                color: on ? t.activeFill : LiveStudioAccent.clear,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? LiveStudioAccent.pink : t.ghostBorder, width: 1),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: on ? LiveStudioAccent.pink : t.textMedium),
                const SizedBox(width: 6),
                Text(label, style: LiveStudioType.s(13, FontWeight.w700, on ? t.textHigh : t.textMedium)),
              ]),
            ),
          ),
        ),
      );
    }

    final List<Widget> body;
    if (yt) {
      body = [
        if (_enabled == false)
          _Note(
            tokens: t,
            icon: Icons.key_rounded,
            title: 'Waiting for API key',
            text: 'YouTube search turns on once the YouTube Data API key is added. '
                'You can already paste any YouTube link above to watch it together.',
          ),
        for (final v in _items)
          _ResultRow(tokens: t, item: v, onTap: _busy ? null : () => _play(v)),
        if (_next != null && _items.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : () => _search(more: true),
            child: Text('More results', style: LiveStudioType.s(13, FontWeight.w700, LiveStudioAccent.blueHover)),
          ),
        if (_items.isEmpty && _enabled != false && !_busy)
          _Note(
            tokens: t,
            icon: Icons.smart_display_outlined,
            title: 'Watch YouTube together',
            text: 'Search for a video or song, or paste a link. Everyone plays it in sync on their own phone '
                'while your camera stays live.',
          ),
      ];
    } else {
      body = [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, url) in const [
            ('Google', 'https://www.google.com'),
            ('Wikipedia', 'https://www.wikipedia.org'),
            ('Maps', 'https://www.google.com/maps'),
            ('News', 'https://news.google.com'),
          ])
            ActionChip(
              label: Text(label, style: LiveStudioType.s(12.5, FontWeight.w600, t.textHigh)),
              backgroundColor: t.ghostFill,
              side: BorderSide(color: t.ghostBorder),
              onPressed: _busy ? null : () => _openPage(url),
            ),
        ]),
        const SizedBox(height: 10),
        _Note(
          tokens: t,
          icon: Icons.public_rounded,
          title: 'Browse together',
          text: 'Open a page and keep browsing on the layer: every page you open shows for your viewers. '
              'Only secure (https) public pages can be shared.',
        ),
      ];
    }

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.drawerTop, t.drawerBottom]),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: t.drawerBorder, width: 1)),
        ),
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.paddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
                width: 36, height: 4, decoration: BoxDecoration(color: t.ghostBorder, borderRadius: BorderRadius.circular(999))),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Text('Watch together', style: LiveStudioType.s(17, FontWeight.w700, t.textHigh, letter: -0.018)),
            const Spacer(),
            if (layer != null)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          await _api.stop(widget.streamId);
                        } catch (e) {
                          if (mounted) setState(() => _error = _errText(e));
                        }
                      },
                icon: const Icon(Icons.stop_circle_outlined, size: 18, color: LiveStudioAccent.pinkLight),
                label: Text('Stop', style: LiveStudioType.s(12.5, FontWeight.w700, LiveStudioAccent.pinkLight)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            tab(WatchKind.youtube, Icons.smart_display_rounded, 'YouTube'),
            const SizedBox(width: 8),
            tab(WatchKind.browser, Icons.public_rounded, 'Browser'),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _q,
            focusNode: _focus,
            textInputAction: yt ? TextInputAction.search : TextInputAction.go,
            keyboardType: yt ? TextInputType.text : TextInputType.url,
            onSubmitted: (_) => _submit(),
            style: LiveStudioType.s(14, FontWeight.w500, t.textHigh),
            cursorColor: LiveStudioAccent.pink,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: t.ghostFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: t.textMedium),
              suffixIcon: _busy
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMedium)),
                    )
                  : IconButton(
                      tooltip: yt ? 'Search' : 'Open',
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18, color: LiveStudioAccent.pink),
                      onPressed: _submit,
                    ),
              hintText: yt ? 'Search YouTube or paste a link' : 'Search or type a web address',
              hintStyle: LiveStudioType.s(14, FontWeight.w400, t.placeholder),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.ghostBorder)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.ghostBorder)),
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: LiveStudioAccent.pink)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: LiveStudioType.s(12, FontWeight.w600, LiveStudioAccent.pinkLight)),
            ),
          const SizedBox(height: 10),
          Flexible(child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: body)),
        ]),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.tokens, required this.item, required this.onTap});
  final LiveStudioTokens tokens;
  final YouTubeResult item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Semantics(
      button: true,
      label: 'Watch ${item.title} together',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 68,
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: t.ghostFill),
                  if (item.thumbUrl.isNotEmpty)
                    Image.network(item.thumbUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  if (item.live)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: LiveStudioAccent.pink, borderRadius: BorderRadius.circular(4)),
                        child: Text('LIVE', style: LiveStudioType.s(9, FontWeight.w900, LiveStudioAccent.white, letter: 0.08)),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: LiveStudioType.s(13, FontWeight.w600, t.textHigh)),
                const SizedBox(height: 3),
                Text(item.channel,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: LiveStudioType.s(11.5, FontWeight.w500, t.textMedium)),
              ]),
            ),
            Icon(Icons.play_circle_outline_rounded, size: 22, color: t.textMedium),
          ]),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.tokens, required this.icon, required this.title, required this.text});
  final LiveStudioTokens tokens;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.ghostFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.ghostBorder, width: 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: LiveStudioAccent.pink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: LiveStudioType.s(13, FontWeight.w700, tokens.textHigh)),
              const SizedBox(height: 3),
              Text(text, style: LiveStudioType.s(12, FontWeight.w500, tokens.textMedium, height: 17)),
            ]),
          ),
        ]),
      );
}
