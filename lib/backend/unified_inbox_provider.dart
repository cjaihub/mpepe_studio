import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_repository.dart';
import 'inbox/models/attachment_model.dart';
import 'inbox/models/conversation_model.dart';
import 'inbox/repositories/conversation_repository.dart';

enum SocialPlatform { youtube, tiktok, meta, instagram, system, whatsapp, facebook, messenger, telegram, email, sms, website }
enum UnifiedItemType { message, comment, notification, project, ai, device, channel }

class UnifiedItem {
  final String id;
  final SocialPlatform platform;
  final UnifiedItemType type;
  final String senderName;
  final String senderAvatarUrl;
  final String content;
  final DateTime timestamp;
  final bool isRead;
  final bool handledByAI;
  final bool isHarsh;
  final bool isMutedByAI;
  final List<Attachment> attachments;

  UnifiedItem({
    required this.id,
    required this.platform,
    required this.type,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.handledByAI = false,
    this.isHarsh = false,
    this.isMutedByAI = false,
    this.attachments = const [],
  });

  UnifiedItem copyWith({
    bool? isRead,
    bool? handledByAI,
    bool? isMutedByAI,
  }) {
    return UnifiedItem(
      id: id,
      platform: platform,
      type: type,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      content: content,
      timestamp: timestamp,
      isHarsh: isHarsh,
      isRead: isRead ?? this.isRead,
      handledByAI: handledByAI ?? this.handledByAI,
      isMutedByAI: isMutedByAI ?? this.isMutedByAI,
      attachments: attachments,
    );
  }
}

// AI Assistant Toggle Provider
final cjAiAssistantProvider = NotifierProvider<CJAiAssistantNotifier, bool>(() {
  return CJAiAssistantNotifier();
});

class CJAiAssistantNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }
  
  void toggle() {
    state = !state;
  }

  void setAssistantState(bool value) {
    state = value;
  }
}

// Unified Inbox State Provider
//
// Real-time view over the signed-in user's Firestore data:
//   - `chats`          native Oneova DMs            -> UnifiedItemType.message (platform system)
//   - `conversations`  connected external channels  -> UnifiedItemType.message
//   - `notifications`  comment/reply notifications  -> UnifiedItemType.comment, everything else -> notification
final unifiedInboxProvider = NotifierProvider<UnifiedInboxNotifier, List<UnifiedItem>>(() {
  return UnifiedInboxNotifier();
});

enum _InboxSource { chat, conversation, notification }

class UnifiedInboxNotifier extends Notifier<List<UnifiedItem>> {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String? _userId;
  List<UnifiedItem> _chatItems = const [];
  List<UnifiedItem> _conversationItems = const [];
  List<UnifiedItem> _notificationItems = const [];
  final Map<String, _InboxSource> _sources = {};
  final Set<String> _handledByAI = {};

  @override
  List<UnifiedItem> build() {
    _userId = ref.watch(authStateProvider).value?.uid;
    _chatItems = const [];
    _conversationItems = const [];
    _notificationItems = const [];
    _sources.clear();
    _handledByAI.clear();

    final uid = _userId;
    if (uid == null) return const [];

    final subscriptions = <StreamSubscription<dynamic>>[
      _firestore
          .collection('chats')
          .where('participants', arrayContains: uid)
          .orderBy('lastMessageTime', descending: true)
          .limit(50)
          .snapshots()
          .listen((snap) {
        _chatItems = snap.docs.map((d) => _fromChat(d, uid)).toList();
        _emit();
      }, onError: (Object e) => debugPrint('Unified inbox chats stream error: $e')),
      ref
          .read(conversationRepositoryProvider)
          .listenToRecentConversations(userId: uid, limit: 50)
          .listen((conversations) {
        _conversationItems = conversations.map(_fromConversation).toList();
        _emit();
      }, onError: (Object e) => debugPrint('Unified inbox conversations stream error: $e')),
      _firestore
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .listen((snap) {
        _notificationItems = snap.docs.map(_fromNotification).toList();
        _emit();
      }, onError: (Object e) => debugPrint('Unified inbox notifications stream error: $e')),
    ];
    ref.onDispose(() {
      for (final s in subscriptions) {
        s.cancel();
      }
    });

    return const [];
  }

  void _emit() {
    _sources
      ..clear()
      ..addEntries(_chatItems.map((i) => MapEntry(i.id, _InboxSource.chat)))
      ..addEntries(_conversationItems.map((i) => MapEntry(i.id, _InboxSource.conversation)))
      ..addEntries(_notificationItems.map((i) => MapEntry(i.id, _InboxSource.notification)));
    final merged = [..._chatItems, ..._conversationItems, ..._notificationItems]
        .map((i) => _handledByAI.contains(i.id) ? i.copyWith(handledByAI: true) : i)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = merged;
  }

  UnifiedItem _fromChat(QueryDocumentSnapshot<Map<String, dynamic>> doc, String uid) {
    final data = doc.data();
    final unread = Map<String, dynamic>.from(data['unreadCounts'] ?? const {});
    return UnifiedItem(
      id: doc.id,
      platform: SocialPlatform.system,
      type: UnifiedItemType.message,
      senderName: (data['title'] as String?)?.isNotEmpty == true ? data['title'] as String : 'Chat',
      senderAvatarUrl: (data['avatarUrl'] as String?) ?? '',
      content: (data['lastMessage'] as String?) ?? '',
      timestamp: (data['lastMessageTime'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isRead: ((unread[uid] as num?) ?? 0) == 0,
    );
  }

  UnifiedItem _fromConversation(Conversation c) {
    final meta = c.metadata;
    return UnifiedItem(
      id: c.id,
      platform: c.channel,
      type: UnifiedItemType.message,
      senderName: (meta['title'] ?? meta['senderName'] ?? c.channel.name).toString(),
      senderAvatarUrl: (meta['avatarUrl'] ?? meta['senderAvatarUrl'] ?? '').toString(),
      content: c.latestMessage ?? '',
      timestamp: c.updatedAt,
      isRead: c.unreadCount == 0,
      isMutedByAI: c.isMuted,
    );
  }

  UnifiedItem _fromNotification(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final category = (data['category'] as String?) ?? '';
    final isComment = category == 'comment' || category == 'reply';
    SocialPlatform platform = SocialPlatform.system;
    final platformName = (data['platform'] as String?)?.toLowerCase();
    for (final p in SocialPlatform.values) {
      if (p.name == platformName) platform = p;
    }
    final flags = List<String>.from(data['flags'] ?? const []);
    return UnifiedItem(
      id: doc.id,
      platform: platform,
      type: isComment ? UnifiedItemType.comment : UnifiedItemType.notification,
      senderName: (data['senderName'] as String?) ?? (data['title'] as String?) ?? 'Oneova',
      senderAvatarUrl: (data['senderAvatarUrl'] as String?) ?? '',
      content: (data['message'] as String?) ?? (data['body'] as String?) ?? '',
      timestamp: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] == true,
      handledByAI: data['handledByAI'] == true,
      isHarsh: data['isHarsh'] == true || flags.contains('ai_spam') || flags.contains('toxic'),
      isMutedByAI: data['isMutedByAI'] == true,
    );
  }

  void _patchLocal(String id, UnifiedItem Function(UnifiedItem) update) {
    state = state.map((item) => item.id == id ? update(item) : item).toList();
  }

  Future<void> _markRemoteRead(String id) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      switch (_sources[id]) {
        case _InboxSource.chat:
          await _firestore.collection('chats').doc(id).update({'unreadCounts.$uid': 0});
        case _InboxSource.conversation:
          await ref.read(conversationRepositoryProvider).markAsRead(id);
        case _InboxSource.notification:
          await _firestore.collection('notifications').doc(id).update({'isRead': true});
        case null:
          break;
      }
    } catch (e) {
      debugPrint('Unified inbox markAsRead failed for $id: $e');
    }
  }

  void markAsRead(String id) {
    _patchLocal(id, (item) => item.copyWith(isRead: true));
    _markRemoteRead(id);
  }

  void markAllAsRead(UnifiedItemType type) {
    for (final item in state) {
      if (item.type == type && !item.isRead) {
        _markRemoteRead(item.id);
      }
    }
    state = state.map((item) => item.type == type ? item.copyWith(isRead: true) : item).toList();
  }

  /// Records that the AI assistant answered this item and marks it read.
  void aiAutoReply(String id, String replyContent) {
    _handledByAI.add(id);
    _patchLocal(id, (item) => item.copyWith(handledByAI: true, isRead: true));
    _markRemoteRead(id);
    if (_sources[id] == _InboxSource.notification) {
      _firestore.collection('notifications').doc(id).update({'handledByAI': true}).catchError(
        (Object e) => debugPrint('Unified inbox aiAutoReply failed for $id: $e'),
      );
    }
  }

  /// AI moderation: hides a harsh comment for this user (persisted on the notification).
  void muteCommentFromSource(String id) {
    _patchLocal(id, (item) => item.copyWith(isMutedByAI: true));
    if (_sources[id] == _InboxSource.notification) {
      _firestore.collection('notifications').doc(id).update({'isMutedByAI': true}).catchError(
        (Object e) => debugPrint('Unified inbox mute failed for $id: $e'),
      );
    }
  }
}
