import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../messaging_repository.dart';
import '../../routing/oneova_share_engine.dart';
import '../models/share_models.dart';
import '../repositories/interaction_repository.dart';

final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService(
    ref.read(messagingRepositoryProvider),
    ref.read(interactionRepositoryProvider),
  );
});

/// Someone (or a chat) you can send a post to from the share sheet.
class ShareTarget {
  final String id; // uid for people, chatId for chats
  final String name;
  final String? avatarUrl;
  final bool isChat;
  final bool isGroup;

  const ShareTarget({required this.id, required this.name, this.avatarUrl, this.isChat = false, this.isGroup = false});
}

/// Result of a "share to all" run.
class BulkShareResult {
  final int sent;
  final int skipped;
  const BulkShareResult(this.sent, this.skipped);
}

/// Real sharing for posts: to chosen chats and people (as a chat message, so
/// 1:1 chats stay end-to-end encrypted), to everyone who follows you or you
/// follow (server-side, respecting each person's privacy and opt-out), the
/// link, and the system share sheet. Every share counts once per person.
class ShareService {
  ShareService(this._messaging, this._interactions);

  final MessagingRepository _messaging;
  final InteractionRepository _interactions;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Picking more than this in one go is treated as a bulk share, which goes
  /// through the server so privacy and rate limits apply.
  static const int maxDirectTargets = 20;

  Future<Map<String, dynamic>?> _post(String postId) async {
    for (final col in const ['content', 'posts']) {
      final d = (await _db.collection(col).doc(postId).get()).data();
      if (d != null) return d;
    }
    return null;
  }

  Future<ShareSettings> getShareSettings(String postId) async {
    final d = await _post(postId) ?? const <String, dynamic>{};
    final private = d['isPrivate'] == true || d['visibility'] == 'private' || d['privacy'] == 'private';
    return ShareSettings(
      postId: postId,
      allowRepost: d['allowRepost'] != false && d['allowShare'] != false,
      allowQuote: d['allowQuote'] != false,
      allowEmbed: d['allowEmbed'] != false,
      allowDownload: d['allowDownload'] != false,
      isPrivateContent: private,
    );
  }

  String linkFor(String postId, String? me) => OneovaShareEngine().generateWebShareUrl(postId, referrerId: me);

  /// Recent chats (1:1 and groups), newest first.
  Stream<List<ShareTarget>> recentChats(String me) {
    return _messaging.getUserChatsStream(me).map((chats) => [
          for (final c in chats.take(30))
            ShareTarget(
              id: c.id,
              name: (c.title ?? '').isEmpty ? 'Chat' : c.title!,
              avatarUrl: c.avatarUrl,
              isChat: true,
              isGroup: c.participants.length > 2 || const {'group', 'room', 'vip_room', 'channel'}.contains(c.category),
            ),
        ]);
  }

  /// People who follow [me] (`followers`) or whom [me] follows (`following`).
  Future<List<ShareTarget>> people(String me, {required bool followers, int limit = 60}) async {
    final snap = await _db
        .collection('relationships')
        .where(followers ? 'followingId' : 'followerId', isEqualTo: me)
        .where('status', isEqualTo: 'accepted')
        .limit(limit)
        .get();
    final ids = <String>{
      for (final d in snap.docs) (d.data()[followers ? 'followerId' : 'followingId'] ?? '') as String,
    }..removeWhere((id) => id.isEmpty || id == me);
    final out = <ShareTarget>[];
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 10) {
      final chunk = list.sublist(i, i + 10 > list.length ? list.length : i + 10);
      final users = await _db.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
      for (final u in users.docs) {
        final d = u.data();
        final name = [d['fullName'], d['displayName'], d['username']]
            .whereType<String>()
            .firstWhere((s) => s.trim().isNotEmpty, orElse: () => 'Oneova user');
        out.add(ShareTarget(
          id: u.id,
          name: name,
          avatarUrl: [d['avatarUrl'], d['photoUrl'], d['photoURL']].whereType<String>().where((s) => s.startsWith('http')).firstOrNull,
        ));
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Sends the post to the chosen chats and people. Returns how many got it.
  Future<int> sendToTargets({
    required String postId,
    required String me,
    required List<ShareTarget> targets,
    String? note,
  }) async {
    if (targets.isEmpty) return 0;
    if (targets.length > maxDirectTargets) {
      throw StateError('You can send to up to $maxDirectTargets at once. Use "Share to all" for more.');
    }
    final settings = await getShareSettings(postId);
    if (settings.isPrivateContent) throw StateError('This post is private, so it can’t be shared.');
    final link = linkFor(postId, me);
    final text = (note == null || note.trim().isEmpty) ? link : '${note.trim()}\n$link';
    var sent = 0;
    for (final t in targets) {
      try {
        final chatId = t.isChat ? t.id : await _messaging.getOrCreateDirectChat(me, t.id);
        await _messaging.sendMessage(chatId, me, text, forwarded: true);
        sent++;
      } catch (e) {
        debugPrint('[ShareService] send to ${t.id} failed: $e');
      }
    }
    if (sent > 0) await recordShare(postId, me);
    return sent;
  }

  /// Shares to everyone who follows you (or you follow) through the server.
  Future<BulkShareResult> shareToAll({
    required String postId,
    required bool followers,
    String? note,
  }) async {
    final res = await FirebaseFunctions.instance.httpsCallable('shareToAudience').call<Map<String, dynamic>>({
      'postId': postId,
      'audience': followers ? 'followers' : 'following',
      if (note != null && note.trim().isNotEmpty) 'message': note.trim(),
    });
    final sent = (res.data['sent'] as num?)?.toInt() ?? 0;
    final skipped = (res.data['skipped'] as num?)?.toInt() ?? 0;
    return BulkShareResult(sent, skipped);
  }

  /// Counts one share per person (also used for copy link / system sheet).
  Future<void> recordShare(String postId, String me) async {
    try {
      await _interactions.repostContent(me, postId);
    } catch (e) {
      debugPrint('[ShareService] record share failed: $e');
    }
  }
}
