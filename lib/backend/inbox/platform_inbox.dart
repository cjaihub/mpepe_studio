import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/youtube/v3.dart' as yt;

import '../../ova_assistant/services/ova_google_access.dart';
import '../../social_hub/gmail/gmail_service.dart';
import '../../youtube_manager/services/youtube_account_store.dart';
import '../connections/linked_accounts.dart';

/// What an inbox row is.
enum InboxItemKind { message, comment, mention, email }

/// One row of a linked platform's inbox inside the single Oneova inbox
/// (`/hub/messages`). Built only from real sources:
/// - `social_messages` docs (messages / comments delivered for the account),
/// - the Gmail API (Gmail), and the YouTube Data API (YouTube comments).
class PlatformInboxItem {
  final String id;
  final LinkedPlatform platform;
  final InboxItemKind kind;
  final String senderName;
  final String senderAvatarUrl;
  final String title;
  final String preview;
  final DateTime timestamp;
  final bool isRead;

  /// Post / video / thread the item belongs to on the platform.
  final String? targetId;

  /// True for `social_messages` docs (they can be marked read in Firestore).
  final bool delivered;

  const PlatformInboxItem({
    required this.id,
    required this.platform,
    required this.kind,
    required this.senderName,
    this.senderAvatarUrl = '',
    this.title = '',
    required this.preview,
    required this.timestamp,
    this.isRead = false,
    this.targetId,
    this.delivered = false,
  });

  bool get isComment => kind == InboxItemKind.comment || kind == InboxItemKind.mention;

  static const _commentTypes = {'comment', 'video_comment', 'reply'};
  static const _mentionTypes = {'mention'};

  /// Maps a `social_messages` doc. Returns null when the doc isn't for a
  /// platform Oneova links, or carries no text.
  static PlatformInboxItem? fromSocialMessage(String id, Map<String, dynamic> data) {
    final platform = LinkedPlatform.fromId(data['platform'] as String?);
    if (platform == null) return null;
    final content = (data['content'] ?? '').toString().trim();
    if (content.isEmpty) return null;
    final type = (data['interactionType'] ?? 'message').toString().toLowerCase();
    final ts = data['timestamp'];
    return PlatformInboxItem(
      id: id,
      platform: platform,
      kind: _commentTypes.contains(type)
          ? InboxItemKind.comment
          : _mentionTypes.contains(type)
              ? InboxItemKind.mention
              : InboxItemKind.message,
      senderName: (data['senderName'] ?? '').toString().trim().isEmpty ? platform.label : data['senderName'].toString(),
      senderAvatarUrl: (data['senderAvatarUrl'] ?? '').toString(),
      preview: content,
      timestamp: ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : DateTime.fromMillisecondsSinceEpoch(0)),
      isRead: data['isRead'] == true,
      targetId: data['targetId'] as String?,
      delivered: true,
    );
  }

  /// Maps a Gmail message fetched with `format: metadata`.
  /// Maps a message returned by the server-side Gmail connection (gmailCall).
  static PlatformInboxItem fromGmail(GmailMessage m) {
    final name = m.fromName.trim();
    return PlatformInboxItem(
      id: m.id,
      platform: LinkedPlatform.gmail,
      kind: InboxItemKind.email,
      senderName: name.isEmpty ? 'Unknown sender' : name,
      title: m.subject,
      preview: m.snippet,
      timestamp: m.receivedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      isRead: !m.unread,
      targetId: m.threadId,
    );
  }

  /// Maps a YouTube comment thread's top-level comment.
  static PlatformInboxItem? fromYoutubeThread(yt.CommentThread t) {
    final c = t.snippet?.topLevelComment?.snippet;
    if (c == null) return null;
    final text = (c.textOriginal ?? c.textDisplay ?? '').trim();
    if (text.isEmpty) return null;
    return PlatformInboxItem(
      id: t.id ?? '',
      platform: LinkedPlatform.youtube,
      kind: InboxItemKind.comment,
      senderName: c.authorDisplayName ?? 'YouTube viewer',
      senderAvatarUrl: c.authorProfileImageUrl ?? '',
      preview: text,
      timestamp: c.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      isRead: true,
      targetId: t.snippet?.videoId,
    );
  }

  /// Newest first; drops duplicates by id.
  static List<PlatformInboxItem> sortNewest(Iterable<PlatformInboxItem> items) {
    final seen = <String>{};
    final list = items.where((i) => seen.add('${i.platform.id}:${i.id}')).toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }
}

/// Live `social_messages` for the signed-in user, all platforms. Uses the
/// deployed (userId, timestamp desc) index; platform filtering is client-side.
final socialMessagesStreamProvider = StreamProvider<List<PlatformInboxItem>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('social_messages')
      .where('userId', isEqualTo: uid)
      .orderBy('timestamp', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => [for (final d in s.docs) ?PlatformInboxItem.fromSocialMessage(d.id, d.data())]);
});

/// Unread count per platform id, from the delivered `social_messages`.
final platformUnreadCountsProvider = Provider<Map<String, int>>((ref) {
  final items = ref.watch(socialMessagesStreamProvider).value ?? const [];
  final counts = <String, int>{};
  for (final i in items) {
    if (!i.isRead) counts[i.platform.id] = (counts[i.platform.id] ?? 0) + 1;
  }
  return counts;
});

/// Everything in one linked platform's inbox: delivered `social_messages`
/// plus, for Gmail and YouTube, what the platform API returns right now
/// (refreshed every [_pollEvery] while the inbox is open).
final platformInboxProvider = StreamProvider.autoDispose.family<List<PlatformInboxItem>, String>((ref, platformId) {
  final platform = LinkedPlatform.fromId(platformId);
  if (platform == null) return Stream.value(const []);

  final delivered = ref.watch(socialMessagesStreamProvider).value ?? const [];
  final own = delivered.where((i) => i.platform == platform);

  Future<List<PlatformInboxItem>> Function()? fetch;
  if (platform == LinkedPlatform.gmail) fetch = _fetchGmail;
  if (platform == LinkedPlatform.youtube) {
    fetch = () async {
      final store = await ref.read(ytAccountStoreProvider.future);
      final channelId = store.activeChannel?.id;
      return channelId == null ? const <PlatformInboxItem>[] : _fetchYoutubeComments(channelId);
    };
  }
  if (fetch == null) return Stream.value(PlatformInboxItem.sortNewest(own));

  final controller = StreamController<List<PlatformInboxItem>>();
  Future<void> load() async {
    try {
      final live = await fetch!();
      if (!controller.isClosed) controller.add(PlatformInboxItem.sortNewest([...own, ...live]));
    } catch (e, st) {
      debugPrint('[platformInbox] ${platform.id}: $e');
      if (!controller.isClosed) controller.addError(e, st);
    }
  }

  unawaited(load());
  final timer = Timer.periodic(_pollEvery, (_) => load());
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

const _pollEvery = Duration(seconds: 60);

class InboxAccessDenied implements Exception {
  final LinkedPlatform platform;
  const InboxAccessDenied(this.platform);
  @override
  String toString() => '${platform.label} access was not granted. Reconnect it in Connected accounts.';
}

/// Gmail goes through the server-side connection (`gmailCall`), which holds
/// the encrypted refresh token; the phone never needs its own Gmail grant.
Future<List<PlatformInboxItem>> _fetchGmail() async {
  try {
    final page = await GmailService().list(query: 'in:inbox', limit: 25);
    return page.messages.map(PlatformInboxItem.fromGmail).toList();
  } on GmailException catch (e) {
    if (e.notConnected) throw const InboxAccessDenied(LinkedPlatform.gmail);
    rethrow;
  }
}

Future<List<PlatformInboxItem>> _fetchYoutubeComments(String channelId) async {
  final client = await OvaGoogleAccess.client(OvaGoogleAccess.youtubeScopes, prompt: false);
  if (client == null) throw const InboxAccessDenied(LinkedPlatform.youtube);
  try {
    final res = await yt.YouTubeApi(client).commentThreads.list(
      ['snippet'],
      allThreadsRelatedToChannelId: channelId,
      maxResults: 30,
      order: 'time',
    );
    return [for (final t in res.items ?? const <yt.CommentThread>[]) ?PlatformInboxItem.fromYoutubeThread(t)];
  } finally {
    client.close();
  }
}

/// Marks a delivered `social_messages` item read (no-op for API items).
Future<void> markPlatformItemRead(PlatformInboxItem item) async {
  if (!item.delivered || item.isRead) return;
  await FirebaseFirestore.instance.collection('social_messages').doc(item.id).update({'isRead': true});
}
