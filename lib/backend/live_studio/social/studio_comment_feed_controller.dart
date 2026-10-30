// LIVE STUDIO v2 — comment feed (workstream #2).
//
// Late-join history (one Firestore get of the last 50) + live `chat` events
// from the room, deduped by id and capped at StudioLimits.commentRenderCap.
// Sending is optimistic: a pending row with the server's deterministic id
// (`{uid}_{clientId}`) is shown at once, replaced by the server echo or
// confirmed from the callable result, and rolled back on failure.

import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import 'studio_social_ports.dart';

enum StudioFeedItemStatus { sent, pending }

@immutable
class StudioFeedItem {
  const StudioFeedItem(this.comment, {this.status = StudioFeedItemStatus.sent});
  final LiveStudioComment comment;
  final StudioFeedItemStatus status;

  String get id => comment.id;
  bool get isPending => status == StudioFeedItemStatus.pending;
  bool get isSystem => comment.isSystem;
}

@immutable
class StudioCommentFeedState {
  const StudioCommentFeedState({
    this.items = const [],
    this.historyLoaded = false,
    this.error,
    this.errorSeq = 0,
  });

  /// Oldest first, at most [StudioLimits.commentRenderCap].
  final List<StudioFeedItem> items;
  final bool historyLoaded;

  /// Last send/history error (user-facing), bumped [errorSeq] each time.
  final String? error;
  final int errorSeq;

  StudioCommentFeedState copyWith({
    List<StudioFeedItem>? items,
    bool? historyLoaded,
    String? error,
    int? errorSeq,
  }) =>
      StudioCommentFeedState(
        items: items ?? this.items,
        historyLoaded: historyLoaded ?? this.historyLoaded,
        error: error ?? this.error,
        errorSeq: errorSeq ?? this.errorSeq,
      );
}

/// Normalizes a draft like the server does (collapse whitespace, trim).
/// Returns null when empty or longer than [StudioLimits.commentMaxLength].
String? normalizeStudioComment(String raw) {
  final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty || t.runes.length > StudioLimits.commentMaxLength) return null;
  return t;
}

final studioCommentFeedProvider = NotifierProvider.autoDispose
    .family<StudioCommentFeedController, StudioCommentFeedState, String>(
        StudioCommentFeedController.new);

class StudioCommentFeedController extends Notifier<StudioCommentFeedState> {
  StudioCommentFeedController(this.streamId);

  final String streamId;

  static final Random _rng = Random.secure();
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  final Set<String> _deleted = <String>{};

  @override
  StudioCommentFeedState build() {
    final sub = studioSocialEvents(ref, streamId).listen(_onEvent);
    ref.onDispose(sub.cancel);
    _deleted.clear();
    Future.microtask(_loadHistory);
    return const StudioCommentFeedState();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await ref
          .read(studioCommentHistorySourceProvider)
          .latest(streamId, StudioLimits.commentHistory);
      if (!ref.mounted) return;
      final merged = <StudioFeedItem>[
        for (final c in history)
          if (!_deleted.contains(c.id)) StudioFeedItem(c),
        ...state.items,
      ];
      state = state.copyWith(items: _dedupeAndCap(merged), historyLoaded: true);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
          historyLoaded: true, error: 'Could not load recent comments.', errorSeq: state.errorSeq + 1);
    }
  }

  void _onEvent(StudioEvent e) {
    switch (e) {
      case CommentEvent(:final comment):
        _upsert(comment);
      case SystemLineEvent(:final line):
        _upsert(line);
      case CommentDeletedEvent(:final id):
        _deleted.add(id);
        if (state.items.any((i) => i.id == id)) {
          state = state.copyWith(items: state.items.where((i) => i.id != id).toList());
        }
      default:
        break;
    }
  }

  /// Adds a confirmed item, or replaces a pending one with the same id.
  void _upsert(LiveStudioComment c) {
    if (c.id.isEmpty || _deleted.contains(c.id)) return;
    final items = state.items;
    final i = items.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      if (!items[i].isPending) return; // duplicate
      final next = [...items]..[i] = StudioFeedItem(c);
      state = state.copyWith(items: next);
      return;
    }
    state = state.copyWith(items: _dedupeAndCap([...items, StudioFeedItem(c)]));
  }

  static List<StudioFeedItem> _dedupeAndCap(List<StudioFeedItem> items) {
    final seen = <String>{};
    final out = <StudioFeedItem>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    const cap = StudioLimits.commentRenderCap;
    return out.length > cap ? out.sublist(out.length - cap) : out;
  }

  static String _clientId() =>
      List.generate(16, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();

  /// Sends [raw] (optionally with a GIPHY [gif]: id, url, w, h). Returns
  /// true when the server accepted it.
  Future<bool> send(String raw, {({String id, String url, int w, int h})? gif}) async {
    final text = normalizeStudioComment(raw) ?? (gif != null ? 'GIF' : null);
    if (text == null) return false;
    final me = ref.read(studioViewerIdentityProvider);
    if (me == null) {
      _error('Sign in to comment.');
      return false;
    }
    final clientId = _clientId();
    final id = studioCommentDocId(me.uid, clientId);
    final pending = LiveStudioComment(
      id: id,
      uid: me.uid,
      name: me.name,
      avatarUrl: me.avatarUrl,
      text: text,
      ts: DateTime.now().millisecondsSinceEpoch,
      gifUrl: gif?.url,
      gifW: gif?.w ?? 0,
      gifH: gif?.h ?? 0,
    );
    state = state.copyWith(
        items: _dedupeAndCap(
            [...state.items, StudioFeedItem(pending, status: StudioFeedItemStatus.pending)]));

    try {
      final res = await ref.read(studioCallPortProvider).call(
          StudioCallables.comment, {
        'streamId': streamId,
        'text': text,
        'clientId': clientId,
        if (gif != null) 'gif': {'id': gif.id, 'url': gif.url, 'w': gif.w, 'h': gif.h},
      });
      if (!ref.mounted) return true;
      final serverId = res['id'] is String ? res['id'] as String : id;
      final i = state.items.indexWhere((x) => x.id == id);
      if (i >= 0 && state.items[i].isPending) {
        // No echo yet (or the broadcast was sampled out): confirm from the result.
        final confirmed = LiveStudioComment(
          id: serverId,
          uid: me.uid,
          name: me.name,
          avatarUrl: me.avatarUrl,
          text: res['text'] is String ? res['text'] as String : text,
          ts: res['ts'] is num ? (res['ts'] as num).toInt() : pending.ts,
          gifUrl: pending.gifUrl,
          gifW: pending.gifW,
          gifH: pending.gifH,
        );
        state = state.copyWith(items: [...state.items]..[i] = StudioFeedItem(confirmed));
      }
      return true;
    } catch (e) {
      if (!ref.mounted) return false;
      state = state.copyWith(items: state.items.where((x) => x.id != id).toList());
      _error(_messageOf(e));
      return false;
    }
  }

  void _error(String msg) {
    state = state.copyWith(error: msg, errorSeq: state.errorSeq + 1);
  }

  static String _messageOf(Object e) {
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.isNotEmpty) return m;
      if (e.code == 'resource-exhausted') return 'Slow down a little.';
    }
    return 'Your comment was not sent. Try again.';
  }

  /// Host/co-host or the author (server re-checks). Removes locally on success.
  Future<bool> delete(String commentId) async {
    try {
      await ref
          .read(studioCallPortProvider)
          .call(StudioCallables.deleteComment, {'streamId': streamId, 'commentId': commentId});
      if (!ref.mounted) return true;
      _onEvent(CommentDeletedEvent(commentId));
      return true;
    } catch (e) {
      if (ref.mounted) _error(_messageOf(e));
      return false;
    }
  }

  /// Host/co-host: mute [uid] in chat for [minutes] (0 unmutes).
  Future<bool> muteChat(String uid, int minutes) async {
    try {
      await ref
          .read(studioCallPortProvider)
          .call(StudioCallables.muteChat, {'streamId': streamId, 'uid': uid, 'minutes': minutes});
      return true;
    } catch (e) {
      if (ref.mounted) _error(_messageOf(e));
      return false;
    }
  }
}
