import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'security/e2e_encryption_service.dart';
import 'social/models/creator_engagement_level.dart';

import 'recommendation/algorithm/chat_affinity_extractor.dart';

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  final e2ee = ref.watch(e2eEncryptionServiceProvider);
  final chatAffinity = ref.watch(chatAffinityExtractorProvider);
  return MessagingRepository(
    FirebaseFirestore.instance,
    e2eeService: e2ee,
    chatAffinityExtractor: chatAffinity,
  );
});

final userChatsProvider = StreamProvider.family<List<ChatModel>, String>((ref, userId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getUserChats(userId);
});

final chatMessagesProvider = StreamProvider.family<List<MessageModel>, String>((ref, chatId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getChatMessages(chatId);
});

final chatMessagesPaginatedProvider =
    StreamProvider.family<List<MessageModel>, ({String chatId, int limit})>((ref, params) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getChatMessages(params.chatId, limit: params.limit);
});

final filteredUserChatsProvider = StreamProvider.family<List<ChatModel>, ({String userId, String? category, bool unreadOnly, bool starredOnly})>((ref, params) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getFilteredChats(
    params.userId,
    category: params.category,
    unreadOnly: params.unreadOnly,
    starredOnly: params.starredOnly,
  );
});

final starredChatsProvider = StreamProvider.family<List<ChatModel>, String>((ref, userId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getStarredChats(userId);
});

final unreadChatsProvider = StreamProvider.family<List<ChatModel>, String>((ref, userId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getUnreadChats(userId);
});

final categoryChatsProvider = StreamProvider.family<List<ChatModel>, ({String userId, String category})>((ref, params) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getChatsByCategory(params.userId, params.category);
});

final followedCreatorsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, userId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getFollowedCreatorsStream(userId);
});

final chatStreamProvider = StreamProvider.family<ChatModel?, ({String chatId, String? currentUserId})>((ref, params) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getChatStream(params.chatId, params.currentUserId);
});

final messageRequestsProvider = StreamProvider.family<List<ChatModel>, String>((ref, userId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getMessageRequestsStream(userId);
});

class MessagingRepository {
  final FirebaseFirestore _firestore;
  final E2EEncryptionService _e2eeService;
  final ChatAffinityExtractor? _chatAffinityExtractor;

  /// Short-lived caches to eliminate repeated N+1 reads on every inbox snapshot.
  final Map<String, ({Map<String, dynamic>? data, DateTime at})> _userProfileCache = {};
  final Map<String, ({bool mutual, bool blocked, DateTime at})> _pairRelationCache = {};
  final Map<String, ({bool enabled, DateTime at})> _readReceiptsCache = {};
  static const Duration _cacheTtl = Duration(seconds: 45);

  MessagingRepository(
    this._firestore, {
    E2EEncryptionService? e2eeService,
    ChatAffinityExtractor? chatAffinityExtractor,
  })  : _e2eeService = e2eeService ?? E2EEncryptionService(),
        // ignore: prefer_initializing_formals
        _chatAffinityExtractor = chatAffinityExtractor;

  void invalidateRelationCache(String a, String b) {
    _pairRelationCache.remove('${a}_$b');
    _pairRelationCache.remove('${b}_$a');
  }

  Future<Map<String, dynamic>?> _getCachedUserDoc(String uid) async {
    final now = DateTime.now();
    final cached = _userProfileCache[uid];
    if (cached != null && now.difference(cached.at) < _cacheTtl) {
      return cached.data;
    }
    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.exists ? doc.data() : null;
    _userProfileCache[uid] = (data: data, at: now);
    _accountExists[uid] = doc.exists;
    return data;
  }

  Future<({bool mutual, bool blocked})> _getPairRelation(String currentUserId, String otherUserId) async {
    final key = '${currentUserId}_$otherUserId';
    final now = DateTime.now();
    final cached = _pairRelationCache[key];
    if (cached != null && now.difference(cached.at) < _cacheTtl) {
      return (mutual: cached.mutual, blocked: cached.blocked);
    }
    try {
      final docs = await Future.wait([
        _firestore.collection('relationships').doc('${currentUserId}_$otherUserId').get(),
        _firestore.collection('relationships').doc('${otherUserId}_$currentUserId').get(),
      ]);
      final fwdData = docs[0].data();
      final revData = docs[1].data();
      final fwdStatus = fwdData != null ? fwdData['status'] : null;
      final revStatus = revData != null ? revData['status'] : null;
      final mutual = fwdStatus == 'accepted' && revStatus == 'accepted';
      final blocked = fwdStatus == 'blocked' || revStatus == 'blocked';
      _pairRelationCache[key] = (mutual: mutual, blocked: blocked, at: now);
      return (mutual: mutual, blocked: blocked);
    } catch (_) {
      return (mutual: false, blocked: false);
    }
  }

  Future<bool> isBlockedPair(String a, String b) async {
    if (a.isEmpty || b.isEmpty || a == b) return false;
    final rel = await _getPairRelation(a, b);
    return rel.blocked;
  }

  Future<bool> _shouldSendReadReceipts(String userId) async {
    final now = DateTime.now();
    final cached = _readReceiptsCache[userId];
    if (cached != null && now.difference(cached.at) < _cacheTtl) {
      return cached.enabled;
    }
    try {
      final doc = await _firestore.collection('user_settings').doc(userId).get();
      final privacy = doc.data()?['privacy'];
      final enabled = privacy is Map ? (privacy['readReceipts'] as bool? ?? true) : true;
      _readReceiptsCache[userId] = (enabled: enabled, at: now);
      return enabled;
    } catch (_) {
      return true;
    }
  }

  /// Resolves the other participant's real profile from Firestore `users/{otherUserId}`
  /// so that it always displays the exact real profile (username, displayName, photo, isVerified, role).
  Future<ChatModel> _resolveChatWithRealProfile(ChatModel chat, String? currentUserId) async {
    // Multi-member chats keep their own title/avatar.
    const sharedCategories = {'group', 'room', 'vip_room', 'channel'};
    if (sharedCategories.contains(chat.category) || chat.participants.length > 2) return chat;

    final otherUserId = chat.participants.firstWhere(
      (id) => (currentUserId != null && currentUserId.isNotEmpty) ? id != currentUserId : id.isNotEmpty,
      orElse: () => '',
    );

    if (otherUserId.isEmpty) return chat;

    try {
      final data = await _getCachedUserDoc(otherUserId);
      if (data != null) {
        final resolvedTitle = (data['displayName'] as String?)?.isNotEmpty == true
            ? data['displayName'] as String
            : ((data['fullName'] as String?)?.isNotEmpty == true
                ? data['fullName'] as String
                : ((data['username'] as String?)?.isNotEmpty == true
                    ? data['username'] as String
                    : chat.title));

        final resolvedAvatar = (data['profilePhotoUrl'] as String?) ??
            (data['photoUrl'] as String?) ??
            (data['avatarUrl'] as String?) ??
            chat.avatarUrl;

        final isVerified = (data['isVerified'] as bool?) ?? chat.isVerified;
        final role = (data['role'] as String?)?.toUpperCase() ?? chat.roleBadge;

        // Strict Mutual Connection & Block Resolution for 1-on-1 chats
        bool isMutual = true;
        bool isBlocked = false;
        if (currentUserId != null && currentUserId.isNotEmpty && chat.participants.length == 2) {
          final rel = await _getPairRelation(currentUserId, otherUserId);
          isMutual = rel.mutual;
          isBlocked = rel.blocked;
        }

        // Creator Engagement Level (Instagram-style 1-5 tier progression)
        final engagement = CreatorEngagementLevel.fromStats(
          likes: data['totalLikes'] as int? ?? 0,
          comments: data['commentsCount'] as int? ?? 0,
          followers: data['followers'] as int? ?? 0,
          creations: data['postsCount'] as int? ?? data['videoCount'] as int? ?? 0,
        );

        return chat.copyWith(
          title: resolvedTitle,
          avatarUrl: resolvedAvatar,
          isVerified: isVerified,
          roleBadge: role,
          isMutual: isMutual,
          isBlocked: isBlocked,
          creatorLevel: engagement.tier.level,
          creatorEngagementScore: engagement.totalScore,
        );
      }
    } catch (e) {
      debugPrint('Error resolving real profile for user $otherUserId: $e');
    }

    return chat;
  }

  Stream<List<ChatModel>> getUserChatsStream(String userId, {int limit = 80}) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .limit(limit)
        .snapshots()
        .asyncMap((snapshot) async {
      final rawChats = snapshot.docs.map(ChatModel.fromFirestore).toList();
      final resolved = await Future.wait(rawChats.map((chat) async {
        if (!await _hasRealCounterpart(chat, userId)) return null;
        return _resolveChatWithRealProfile(chat, userId);
      }));
      final list = resolved.whereType<ChatModel>().toList();
      // Keep pinned chats at the top while preserving recency inside each bucket.
      list.sort((a, b) {
        final ap = a.isPinnedBy(userId) ? 1 : 0;
        final bp = b.isPinnedBy(userId) ? 1 : 0;
        if (ap != bp) return bp.compareTo(ap);
        final at = a.lastMessageTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.lastMessageTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      return list;
    });
  }

  /// Account existence cache so the inbox stream does not re-read `users`
  /// on every snapshot.
  final Map<String, bool> _accountExists = {};

  Future<bool> _accountIsReal(String uid) async {
    final cached = _accountExists[uid];
    if (cached != null) return cached;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return _accountExists[uid] = doc.exists;
    } catch (_) {
      // Network/permission hiccup: don't hide a chat we couldn't verify.
      return true;
    }
  }

  /// A thread is shown only when at least one other participant is a real
  /// account. Old placeholder threads point at ids with no `users` doc, so
  /// they drop out of Chats and Requests.
  Future<bool> _hasRealCounterpart(ChatModel chat, String userId) async {
    final others = chat.participants.where((p) => p.isNotEmpty && p != userId).toList();
    if (others.isEmpty) return false;
    for (final uid in others) {
      if (await _accountIsReal(uid)) return true;
    }
    return false;
  }

  Stream<List<ChatModel>> getUserChats(String userId) {
    return getUserChatsStream(userId);
  }

  Stream<ChatModel?> getChatStream(String chatId, [String? currentUserId]) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .snapshots()
        .asyncMap((doc) async {
      if (!doc.exists) return null;
      final chat = ChatModel.fromFirestore(doc);
      return _resolveChatWithRealProfile(chat, currentUserId);
    });
  }

  Stream<List<ChatModel>> getFilteredChats(
    String userId, {
    String? category,
    bool unreadOnly = false,
    bool starredOnly = false,
  }) {
    return getUserChats(userId).map((chats) {
      return chats.where((chat) {
        if (category != null && category.isNotEmpty && category.toLowerCase() != 'all') {
          final cat = chat.category?.toLowerCase() ?? '';
          if (cat != category.toLowerCase()) {
            return false;
          }
        }
        if (unreadOnly) {
          final unread = chat.unreadCounts[userId] ?? 0;
          if (unread <= 0) return false;
        }
        if (starredOnly && !chat.isStarred) {
          return false;
        }
        return true;
      }).toList();
    });
  }

  Stream<List<ChatModel>> getStarredChats(String userId) {
    return getFilteredChats(userId, starredOnly: true);
  }

  Stream<List<ChatModel>> getUnreadChats(String userId) {
    return getFilteredChats(userId, unreadOnly: true);
  }

  Stream<List<ChatModel>> getChatsByCategory(String userId, String category) {
    return getFilteredChats(userId, category: category);
  }

  Stream<List<MessageModel>> getChatMessages(String chatId, {int limit = 60}) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .where((m) => m.expiresAt == null || m.expiresAt!.toDate().isAfter(now))
          .toList();
    });
  }

  Future<MessageModel?> getMessage(String chatId, String messageId) async {
    final doc = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .get();
    if (!doc.exists) return null;
    return MessageModel.fromFirestore(doc);
  }

  Future<ChatModel?> getChat(String chatId, [String? currentUserId]) async {
    final doc = await _firestore.collection('chats').doc(chatId).get();
    if (doc.exists) {
      final chat = ChatModel.fromFirestore(doc);
      return _resolveChatWithRealProfile(chat, currentUserId);
    }
    return null;
  }

  /// Checks if a direct chat between [currentUserId] and [targetUserId] already exists.
  /// If so, returns its ID. Otherwise, creates a new chat document in `chats` with
  /// participants: [currentUserId, targetUserId], createdAt, unreadCounts: {currentUserId: 0, targetUserId: 0}.
  Future<String> getOrCreateDirectChat(String currentUserId, String targetUserId) async {
    if (currentUserId.isEmpty || targetUserId.isEmpty) {
      throw ArgumentError('currentUserId and targetUserId cannot be empty');
    }

    // 1. Check if a direct 1:1 chat between both users already exists.
    final querySnapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .get();

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final docParticipants = List<String>.from(data['participants'] ?? []);
      final cat = data['category'] as String?;
      if (docParticipants.length == 2 &&
          docParticipants.contains(targetUserId) &&
          cat != 'group' &&
          cat != 'room' &&
          cat != 'vip_room' &&
          cat != 'channel') {
        return doc.id;
      }
    }

    if (await isBlockedPair(currentUserId, targetUserId)) {
      throw StateError('You cannot start a conversation with a blocked user.');
    }

    // 2. Resolve target user real profile to prefill chat metadata
    String? title;
    String? avatarUrl;
    bool isVerified = false;
    String? roleBadge;
    try {
      final userDoc = await _firestore.collection('users').doc(targetUserId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        title = (data['displayName'] as String?)?.isNotEmpty == true
            ? data['displayName'] as String
            : ((data['fullName'] as String?)?.isNotEmpty == true
                ? data['fullName'] as String
                : (data['username'] as String?));
        avatarUrl = (data['profilePhotoUrl'] as String?) ?? (data['photoUrl'] as String?);
        isVerified = (data['isVerified'] as bool?) ?? false;
        roleBadge = (data['role'] as String?)?.toUpperCase();
      }
    } catch (e) {
      debugPrint('Error prefetching target profile for new direct chat: $e');
    }

    // 3. Create a new document in `chats`
    final newChatRef = _firestore.collection('chats').doc();
    await newChatRef.set({
      'participants': [currentUserId, targetUserId],
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCounts': {
        currentUserId: 0,
        targetUserId: 0,
      },
      'typingUsers': <String>[],
      'category': 'direct',
      'title': title,
      'avatarUrl': avatarUrl,
      'roleBadge': roleBadge,
      'isVerified': isVerified,
      'isOnline': false,
      'isStarred': false,
    });

    return newChatRef.id;
  }

  /// Stream of followed creators (from `relationships` where followerId == currentUserId
  /// and status == 'accepted') plus real platform creators from `users` (e.g. angel_uid, crown_uid).
  Stream<List<Map<String, dynamic>>> getFollowedCreatorsStream(String currentUserId) {
    if (currentUserId.isEmpty) {
      return _firestore.collection('users').limit(15).snapshots().map((snap) {
        return snap.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          data['uid'] = doc.id;
          data['isFollowed'] = false;
          return data;
        }).toList();
      });
    }

    return _firestore
        .collection('relationships')
        .where('followerId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .asyncMap((relSnap) async {
      final followedUids = relSnap.docs
          .map((d) => (d.data()['followingId'] as String?) ?? '')
          .where((uid) => uid.isNotEmpty && uid != currentUserId)
          .toSet();

      final resolved = await Future.wait(followedUids.map((uid) async {
        try {
          final rel = await _getPairRelation(currentUserId, uid);
          if (!rel.mutual || rel.blocked) return null;

          final userData = await _getCachedUserDoc(uid);
          if (userData == null) return null;
          final data = Map<String, dynamic>.from(userData);
          data['id'] = uid;
          data['uid'] = uid;
          data['isFollowed'] = true;
          data['isMutual'] = true;

          final engagement = CreatorEngagementLevel.fromStats(
            likes: data['totalLikes'] as int? ?? 0,
            comments: data['commentsCount'] as int? ?? 0,
            followers: data['followers'] as int? ?? 0,
            creations: data['postsCount'] as int? ?? data['videoCount'] as int? ?? 0,
          );
          data['creatorLevel'] = engagement.tier.level;
          data['creatorTierTitle'] = engagement.tier.title;
          data['creatorEngagementScore'] = engagement.totalScore;
          return data;
        } catch (e) {
          debugPrint('Error loading mutual creator $uid: $e');
          return null;
        }
      }));

      return resolved.whereType<Map<String, dynamic>>().toList();
    });
  }

  /// Stream of pending incoming message requests from non-mutual users
  Stream<List<ChatModel>> getMessageRequestsStream(String userId) {
    return getUserChatsStream(userId).map((chats) {
      return chats.where((c) {
        // Direct 1-on-1 chats that are NOT mutual/accepted yet
        return c.category != 'group' &&
            c.category != 'channel' &&
            !c.isMutual &&
            !c.isBlocked &&
            !c.acceptedRequests.contains(userId) &&
            !c.isArchivedBy(userId) &&
            c.participants.length == 2;
      }).toList();
    });
  }

  Future<String> createChat(
    List<String> participants, {
    String? title,
    String? avatarUrl,
    String? category,
    String? roleBadge,
    String? avatarOverlayIcon,
    bool isVerified = false,
    String? ownerId,
  }) async {
    final normalized = participants.where((p) => p.isNotEmpty).toSet().toList();
    final effectiveCategory = category ?? (normalized.length > 2 ? 'group' : 'direct');

    // Only deduplicate 1:1 direct chats (separate group chats can share members).
    if (effectiveCategory == 'direct' && normalized.length == 2) {
      final querySnapshot = await _firestore
          .collection('chats')
          .where('participants', arrayContains: normalized.first)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final docParticipants = List<String>.from(data['participants'] ?? []);
        final cat = data['category'] as String?;
        if (cat != 'group' &&
            cat != 'room' &&
            cat != 'vip_room' &&
            cat != 'channel' &&
            docParticipants.length == 2 &&
            normalized.every((p) => docParticipants.contains(p))) {
          return doc.id;
        }
      }
    }

    // Create a new chat
    final newChatId = const Uuid().v4();
    final initialUnread = {for (var p in normalized) p: 0};

    await _firestore.collection('chats').doc(newChatId).set({
      'participants': normalized,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageType': 'text',
      'unreadCounts': initialUnread,
      'typingUsers': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'title': ?title,
      'avatarUrl': ?avatarUrl,
      'category': effectiveCategory,
      'ownerId': ?ownerId,
      'roleBadge': ?roleBadge,
      'avatarOverlayIcon': ?avatarOverlayIcon,
      'isVerified': isVerified,
      'isOnline': false,
      'isStarred': false,
    });

    return newChatId;
  }

  // ── Rooms, VIP rooms & broadcast channels ────────────────────────────────
  // All three are ordinary `chats` docs distinguished by `category`
  // ('room' | 'vip_room' | 'channel'), so they reuse the chat thread UI.

  /// Live list of discoverable rooms. Sorted client-side to avoid needing a
  /// composite index.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchRooms({required bool vip}) {
    return _firestore
        .collection('chats')
        .where('category', isEqualTo: vip ? 'vip_room' : 'room')
        .limit(100)
        .snapshots()
        .map((snap) {
      final docs = snap.docs.toList();
      docs.sort((a, b) {
        final at = a.data()['lastMessageTime'] as Timestamp?;
        final bt = b.data()['lastMessageTime'] as Timestamp?;
        return (bt?.millisecondsSinceEpoch ?? 0).compareTo(at?.millisecondsSinceEpoch ?? 0);
      });
      return docs;
    });
  }

  Future<String> createRoom({
    required String ownerId,
    required String title,
    String description = '',
    List<String> tags = const [],
    bool isVip = false,
    String? accessNote,
  }) async {
    final ref = _firestore.collection('chats').doc();
    await ref.set({
      'participants': [ownerId],
      'ownerId': ownerId,
      'category': isVip ? 'vip_room' : 'room',
      'title': title,
      'description': description,
      'tags': tags,
      if (isVip && accessNote != null && accessNote.isNotEmpty) 'accessNote': accessNote,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCounts': {ownerId: 0},
      'typingUsers': [],
      'isVerified': false,
      'isOnline': false,
      'isStarred': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Joins an open room. Idempotent: arrayUnion never adds a user twice.
  Future<void> joinRoom(String chatId, String userId) async {
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayUnion([userId]),
      'unreadCounts.$userId': 0,
    });
  }

  /// Leaves a room the user is a member of (owners keep their room).
  Future<void> leaveRoom(String chatId, String userId) async {
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayRemove([userId]),
      'unreadCounts.$userId': FieldValue.delete(),
    });
  }

  /// Asks the owner of a VIP room for access (one request per user).
  Future<void> requestRoomAccess({
    required String chatId,
    required String userId,
    required String ownerId,
    required String roomTitle,
  }) async {
    final requestRef = _firestore.collection('chats').doc(chatId).collection('joinRequests').doc(userId);
    final notifRef = _firestore.collection('notifications').doc();
    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(requestRef);
      if (existing.exists) return;
      tx.set(requestRef, {
        'userId': userId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(notifRef, {
        'userId': ownerId,
        'recipientId': ownerId,
        'title': 'Room access request',
        'message': 'Someone asked to join "$roomTitle"',
        'body': 'Someone asked to join "$roomTitle"',
        'type': 'social',
        'category': 'room_request',
        'isRead': false,
        'deepLink': '/hub/messages/$chatId',
        'payload': {'chatId': chatId, 'requesterId': userId},
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<bool> watchHasRequestedAccess(String chatId, String userId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('joinRequests')
        .doc(userId)
        .snapshots()
        .map((d) => d.exists);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchPendingRoomRequests(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('joinRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs);
  }

  /// Host decision on a VIP room request; approving adds the user as a member
  /// and notifies them.
  Future<void> resolveRoomRequest({
    required String chatId,
    required String requesterId,
    required bool approve,
    required String roomTitle,
  }) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    final batch = _firestore.batch();
    batch.update(chatRef.collection('joinRequests').doc(requesterId), {
      'status': approve ? 'approved' : 'declined',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    if (approve) {
      batch.update(chatRef, {
        'participants': FieldValue.arrayUnion([requesterId]),
        'unreadCounts.$requesterId': 0,
      });
      batch.set(_firestore.collection('notifications').doc(), {
        'userId': requesterId,
        'recipientId': requesterId,
        'title': 'You are in',
        'message': 'Your request to join "$roomTitle" was approved',
        'body': 'Your request to join "$roomTitle" was approved',
        'type': 'social',
        'category': 'room_approved',
        'isRead': false,
        'deepLink': '/hub/messages/$chatId',
        'payload': {'chatId': chatId},
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Creates a broadcast channel: the owner posts, followers receive.
  /// Current accepted followers are added as members (up to 500).
  Future<String> createBroadcastChannel({
    required String ownerId,
    required String title,
    String description = '',
  }) async {
    final followers = await _firestore
        .collection('relationships')
        .where('followingId', isEqualTo: ownerId)
        .where('status', isEqualTo: 'accepted')
        .limit(500)
        .get();
    final members = <String>{
      ownerId,
      ...followers.docs.map((d) => d.data()['followerId'] as String? ?? '').where((id) => id.isNotEmpty),
    }.toList();

    final ref = _firestore.collection('chats').doc();
    await ref.set({
      'participants': members,
      'ownerId': ownerId,
      'category': 'channel',
      'title': title,
      'description': description,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCounts': {for (final m in members) m: 0},
      'typingUsers': [],
      'isVerified': false,
      'isOnline': false,
      'isStarred': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Returns the new message id.
  Future<String> sendMessage(
    String chatId,
    String senderId,
    String text, {
    String? messageId,
    String? recipientId,
    String? replyToMessageId,
    String? mediaUrl,
    String? mediaType,
    String? fileName,
    String? mimeType,
    int? fileSize,
    String? voiceDuration,
    List<double>? voiceWaveform,
    bool hasVoiceMemo = false,
    String? messagePrefix,
    Map<String, dynamic>? location,
    bool mediaEncrypted = false,
    bool forwarded = false,
  }) async {
    final msgId = (messageId != null && messageId.isNotEmpty) ? messageId : const Uuid().v4();
    final timestamp = Timestamp.now();

    // Determine recipientId if not explicitly passed. E2EE is per-recipient,
    // so it only applies to 1:1 chats; shared chats stay readable by all members.
    String? targetRecipientId = recipientId;
    bool isSharedChat = false;
    int disappearingSecs = 0;
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (chatDoc.exists) {
        final data = chatDoc.data() ?? {};
        final participants = List<String>.from(data['participants'] ?? []);
        const sharedCategories = {'group', 'room', 'vip_room', 'channel'};
        isSharedChat = participants.length > 2 || sharedCategories.contains(data['category']);
        disappearingSecs = (data['disappearingDuration'] as num?)?.toInt() ?? 0;
        if (targetRecipientId == null || targetRecipientId.isEmpty) {
          targetRecipientId = participants.firstWhere((p) => p != senderId, orElse: () => '');
        }
      }
    } catch (e) {
      debugPrint('Error resolving recipient for E2EE: $e');
    }

    if (!isSharedChat && targetRecipientId != null && targetRecipientId.isNotEmpty) {
      if (await isBlockedPair(senderId, targetRecipientId)) {
        throw StateError('You cannot send messages to a blocked contact.');
      }
    }

    // Check E2EE encryption
    bool isEncrypted = false;
    String textToSend = text;

    if (!isSharedChat && text.isNotEmpty && targetRecipientId != null && targetRecipientId.isNotEmpty) {
      try {
        await _e2eeService.ensureUserE2eeKeys(senderId);
        final recipientPubKey = await _e2eeService.getRecipientPublicKey(targetRecipientId);
        if (recipientPubKey != null && recipientPubKey.isNotEmpty) {
          textToSend = await _e2eeService.encryptMessage(text, recipientPubKey);
          isEncrypted = true;
        }
      } catch (e) {
        debugPrint('E2EE encryption fallback to plaintext: $e');
        isEncrypted = false;
        textToSend = text;
      }
    }

    // Feed conversational signal into the recommendation algorithm, but never
    // from end-to-end encrypted chats: topics would leak to algorithmic_state.
    if (!isEncrypted && !mediaEncrypted) {
      try {
        _chatAffinityExtractor?.processChatMessage(
          senderId: senderId,
          recipientId: targetRecipientId,
          rawText: text,
          mediaUrl: mediaUrl,
        );
      } catch (e) {
        debugPrint('Algorithmic chat signal extraction skipped: $e');
      }
    }

    final Timestamp? expiresAt = disappearingSecs > 0
        ? Timestamp.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch + disappearingSecs * 1000)
        : null;

    final message = MessageModel(
      id: msgId,
      senderId: senderId,
      text: textToSend,
      timestamp: timestamp,
      // Read receipts only track OTHER recipients, never pre-marking senderId as read.
      readBy: const [],
      deliveredTo: const [],
      replyToMessageId: replyToMessageId,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      voiceDuration: voiceDuration,
      voiceWaveform: voiceWaveform,
      isEncrypted: isEncrypted,
      mediaEncrypted: mediaEncrypted,
      location: location,
      forwarded: forwarded,
      expiresAt: expiresAt,
    );

    final chatRef = _firestore.collection('chats').doc(chatId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(chatRef);
      if (!doc.exists) return;

      final chatData = doc.data() as Map<String, dynamic>;
      final unreadCounts = Map<String, int>.from(chatData['unreadCounts'] ?? {});

      final participants = List<String>.from(chatData['participants'] ?? []);
      for (final p in participants) {
        if (p != senderId) {
          unreadCounts[p] = (unreadCounts[p] ?? 0) + 1;
        }
      }

      transaction.set(
        chatRef.collection('messages').doc(msgId),
        message.toMap(),
      );

      final String resolvedType = mediaType ?? (hasVoiceMemo ? 'audio' : 'text');
      final String displayLastMessage = _previewSnippet(
        text: text,
        isEncrypted: isEncrypted,
        mediaEncrypted: mediaEncrypted,
        mediaType: resolvedType,
        fileName: fileName,
        voiceDuration: voiceDuration,
        location: location,
      );

      final updateMap = <String, dynamic>{
        'lastMessage': displayLastMessage,
        'lastMessageTime': timestamp,
        'lastMessageSenderId': senderId,
        'lastMessageType': resolvedType,
        'unreadCounts': unreadCounts,
        'deliveryStatus': 'sent',
      };

      if (hasVoiceMemo || mediaType == 'audio') {
        updateMap['hasVoiceMemo'] = true;
        if (voiceDuration != null) {
          updateMap['voiceDuration'] = voiceDuration;
        }
      }
      if (messagePrefix != null) {
        updateMap['messagePrefix'] = messagePrefix;
      }

      transaction.update(chatRef, updateMap);
    });
    return msgId;
  }

  static String _previewSnippet({
    required String text,
    required bool isEncrypted,
    required bool mediaEncrypted,
    String? mediaType,
    String? fileName,
    String? voiceDuration,
    Map<String, dynamic>? location,
  }) {
    if (isEncrypted || mediaEncrypted) {
      return switch (mediaType) {
        'audio' => '🔒 Encrypted voice note',
        'image' => '🔒 Encrypted photo',
        'video' => '🔒 Encrypted video',
        'video_note' => '🔒 Encrypted video message',
        'location' => location?['live'] == true ? '📍 Live location' : '📍 Location',
        'document' || 'file' || 'archive' || 'code' => '🔒 Encrypted file',
        _ => '🔒 Encrypted message',
      };
    }
    if (text.trim().isNotEmpty) return text;
    return switch (mediaType) {
      'audio' => '🎙️ Voice note ${voiceDuration != null ? '($voiceDuration)' : ''}'.trim(),
      'image' => '📷 Photo',
      'video' => '🎥 Video',
      'video_note' => '📹 Video message ${voiceDuration != null ? '($voiceDuration)' : ''}'.trim(),
      'gif' => 'GIF',
      'location' => location?['live'] == true ? '📍 Live location' : '📍 Location',
      'document' || 'file' || 'archive' || 'code' => '📄 ${fileName ?? 'Document'}',
      _ => 'Attachment',
    };
  }

  Future<void> markMessagesAsRead(String chatId, String userId, {bool? sendReceipt}) async {
    if (chatId.isEmpty || userId.isEmpty || userId == 'guest') return;
    final chatRef = _firestore.collection('chats').doc(chatId);
    final allowReceipt = sendReceipt ?? await _shouldSendReadReceipts(userId);
    final nowTs = Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 2)));

    final update = <String, dynamic>{
      'unreadCounts.$userId': 0,
      'deliveredWatermarks.$userId': nowTs,
    };
    if (allowReceipt) {
      update['readWatermarks.$userId'] = nowTs;
      update['deliveryStatus'] = 'read';
    }
    await chatRef.update(update).catchError((_) {});

    if (!allowReceipt) return;
    // Bounded batch of recent unread incoming messages so individual bubbles update smoothly
    // without scanning the entire subcollection inside a transaction.
    try {
      final recent = await chatRef
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();
      final batch = _firestore.batch();
      var dirty = false;
      for (final doc in recent.docs) {
        final data = doc.data();
        if (data['senderId'] == userId) continue;
        final readBy = List<String>.from(data['readBy'] ?? []);
        final deliveredTo = List<String>.from(data['deliveredTo'] ?? []);
        final needsRead = !readBy.contains(userId);
        final needsDelivered = !deliveredTo.contains(userId);
        if (needsRead || needsDelivered) {
          batch.update(doc.reference, {
            if (needsRead) 'readBy': FieldValue.arrayUnion([userId]),
            if (needsDelivered) 'deliveredTo': FieldValue.arrayUnion([userId]),
          });
          dirty = true;
        }
      }
      if (dirty) await batch.commit();
    } catch (e) {
      debugPrint('Bounded read-receipt update skipped: $e');
    }
  }

  Future<void> markChatsDelivered(String userId, List<ChatModel> chats) async {
    if (userId.isEmpty || userId == 'guest') return;
    final batch = _firestore.batch();
    var count = 0;
    final nowTs = Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 1)));
    for (final c in chats) {
      final unread = c.unreadCounts[userId] ?? 0;
      if (unread <= 0 || c.lastMessageSenderId == userId) continue;
      final existing = c.deliveredWatermarks[userId];
      final lastMs = c.lastMessageTime?.millisecondsSinceEpoch ?? 0;
      if (existing != null && existing.millisecondsSinceEpoch >= lastMs) continue;
      batch.update(_firestore.collection('chats').doc(c.id), {
        'deliveredWatermarks.$userId': nowTs,
        if (c.deliveryStatus == 'sent') 'deliveryStatus': 'delivered',
      });
      count++;
      if (count >= 25) break;
    }
    if (count > 0) {
      await batch.commit().catchError((_) {});
    }
  }

  Future<void> markChatUnread(String chatId, String userId) async {
    if (chatId.isEmpty || userId.isEmpty) return;
    await _firestore.collection('chats').doc(chatId).update({
      'unreadCounts.$userId': 1,
    });
  }

  Future<void> markChatAsRead(String chatId, String userId) async {
    await markMessagesAsRead(chatId, userId);
  }

  Future<void> toggleChatStarred(String chatId, bool isStarred) async {
    await _firestore.collection('chats').doc(chatId).update({
      'isStarred': isStarred,
    });
  }

  Future<void> toggleMessageStarred(String chatId, String messageId, bool isStarred) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isStarred': isStarred,
    });
  }

  Future<void> setTypingStatus(String chatId, String userId, bool isTyping) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    if (isTyping) {
      await chatRef.update({
        'typingUsers': FieldValue.arrayUnion([userId]),
        'typingAt.$userId': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await chatRef.update({
        'typingUsers': FieldValue.arrayRemove([userId]),
        'typingAt.$userId': FieldValue.delete(),
      });
    }
  }

  Future<void> setRecordingStatus(String chatId, String userId, bool isRecording) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    if (isRecording) {
      await chatRef.update({
        'recordingUsers': FieldValue.arrayUnion([userId])
      });
    } else {
      await chatRef.update({
        'recordingUsers': FieldValue.arrayRemove([userId])
      });
    }
  }

  Future<void> addReaction(String chatId, String messageId, String userId, String emoji) async {
    final msgRef = _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId);
    await msgRef.update({'reactions.$userId': emoji}).catchError((_) async {
      await msgRef.set({
        'reactions': {userId: emoji},
      }, SetOptions(merge: true));
    });
  }

  Future<void> toggleReaction(
    String chatId,
    String messageId,
    String userId,
    String emoji, {
    String? currentReaction,
  }) async {
    final msgRef = _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId);
    if (currentReaction == emoji) {
      await msgRef.update({'reactions.$userId': FieldValue.delete()});
    } else {
      await msgRef.update({'reactions.$userId': emoji}).catchError((_) async {
        await msgRef.set({
          'reactions': {userId: emoji},
        }, SetOptions(merge: true));
      });
    }
  }

  Future<void> editMessage(
    String chatId,
    String messageId,
    String senderId,
    String newText, {
    String? recipientId,
  }) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    bool isSharedChat = false;
    String? targetRecipient = recipientId;
    final chatRef = _firestore.collection('chats').doc(chatId);
    final chatSnap = await chatRef.get();
    final chatData = chatSnap.data() ?? {};
    final participants = List<String>.from(chatData['participants'] ?? []);
    const sharedCategories = {'group', 'room', 'vip_room', 'channel'};
    isSharedChat = participants.length > 2 || sharedCategories.contains(chatData['category']);
    if (targetRecipient == null || targetRecipient.isEmpty) {
      targetRecipient = participants.firstWhere((p) => p != senderId, orElse: () => '');
    }

    String textToWrite = trimmed;
    bool isEncrypted = false;
    if (!isSharedChat && targetRecipient.isNotEmpty) {
      try {
        await _e2eeService.ensureUserE2eeKeys(senderId);
        final pubKey = await _e2eeService.getRecipientPublicKey(targetRecipient);
        if (pubKey != null && pubKey.isNotEmpty) {
          textToWrite = await _e2eeService.encryptMessage(trimmed, pubKey);
          isEncrypted = true;
        }
      } catch (_) {}
    }

    await chatRef.collection('messages').doc(messageId).update({
      'text': textToWrite,
      'isEncrypted': isEncrypted,
      'edited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });

    // Update inbox snippet if this was the latest message.
    try {
      final latest = await chatRef.collection('messages').orderBy('timestamp', descending: true).limit(1).get();
      if (latest.docs.isNotEmpty && latest.docs.first.id == messageId) {
        await chatRef.update({
          'lastMessage': isEncrypted ? '🔒 Encrypted message' : trimmed,
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshChatLatestSnippet(String chatId) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    try {
      final latest = await chatRef.collection('messages').orderBy('timestamp', descending: true).limit(1).get();
      if (latest.docs.isEmpty) {
        await chatRef.update({
          'lastMessage': '',
          'lastMessageType': 'text',
        });
        return;
      }
      final m = MessageModel.fromFirestore(latest.docs.first);
      final resolvedType = m.mediaType ?? 'text';
      final snippet = _previewSnippet(
        text: m.isEncrypted ? '' : m.text,
        isEncrypted: m.isEncrypted,
        mediaEncrypted: m.mediaEncrypted,
        mediaType: resolvedType,
        fileName: m.fileName,
        voiceDuration: m.voiceDuration,
        location: m.location,
      );
      await chatRef.update({
        'lastMessage': snippet,
        'lastMessageTime': m.timestamp,
        'lastMessageSenderId': m.senderId,
        'lastMessageType': resolvedType,
      });
    } catch (e) {
      debugPrint('Refresh chat snippet skipped: $e');
    }
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
    await _refreshChatLatestSnippet(chatId);
  }

  Future<void> deleteMessages(String chatId, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final batch = _firestore.batch();
    final col = _firestore.collection('chats').doc(chatId).collection('messages');
    for (final id in messageIds) {
      batch.delete(col.doc(id));
    }
    await batch.commit();
    await _refreshChatLatestSnippet(chatId);
  }

  Future<void> clearChatHistory(String chatId, {String? userId}) async {
    if (userId != null && userId.isNotEmpty) {
      await _firestore.collection('chats').doc(chatId).update({
        'unreadCounts.$userId': 0,
      }).catchError((_) {});
      return;
    }
    final messages = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();

    final batch = _firestore.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': '',
      'lastMessageType': 'text',
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setDisappearingDuration(String chatId, int durationSeconds) async {
    await _firestore.collection('chats').doc(chatId).update({
      'disappearingDuration': durationSeconds,
    });
  }

  Future<void> setChatMuted(String chatId, String userId, bool isMuted) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    if (isMuted) {
      await chatRef.update({
        'mutedUsers': FieldValue.arrayUnion([userId])
      });
    } else {
      await chatRef.update({
        'mutedUsers': FieldValue.arrayRemove([userId])
      });
    }
  }

  Future<void> setChatPinned(String chatId, String userId, bool isPinned) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    await chatRef.update({
      'pinnedUsers': isPinned ? FieldValue.arrayUnion([userId]) : FieldValue.arrayRemove([userId]),
    });
  }

  Future<void> setChatArchived(String chatId, String userId, bool isArchived) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    await chatRef.update({
      'archivedUsers': isArchived ? FieldValue.arrayUnion([userId]) : FieldValue.arrayRemove([userId]),
      if (isArchived) 'unreadCounts.$userId': 0,
    });
  }

  Future<void> togglePinMessage(
    String chatId,
    String messageId, {
    required bool currentlyPinned,
    String? previewText,
  }) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    if (currentlyPinned) {
      final doc = await chatRef.get();
      final existing = List<String>.from(doc.data()?['pinnedMessageIds'] ?? []);
      existing.remove(messageId);
      await chatRef.update({
        'pinnedMessageIds': existing,
        'pinnedMessageId': existing.isNotEmpty ? existing.last : FieldValue.delete(),
        if (existing.isEmpty) 'pinnedMessagePreview': FieldValue.delete(),
      });
    } else {
      await chatRef.update({
        'pinnedMessageIds': FieldValue.arrayUnion([messageId]),
        'pinnedMessageId': messageId,
        if (previewText != null && previewText.isNotEmpty)
          'pinnedMessagePreview': previewText.trim().length > 90
              ? '${previewText.trim().substring(0, 90)}…'
              : previewText.trim(),
      });
    }
  }

  Future<void> renameGroup(String chatId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    await _firestore.collection('chats').doc(chatId).update({'title': trimmed});
  }

  Future<void> updateGroupAvatar(String chatId, String avatarUrl) async {
    await _firestore.collection('chats').doc(chatId).update({'avatarUrl': avatarUrl});
  }

  Future<void> addGroupMembers(String chatId, List<String> memberIds) async {
    if (memberIds.isEmpty) return;
    final updates = <String, dynamic>{
      'participants': FieldValue.arrayUnion(memberIds),
    };
    for (final uid in memberIds) {
      updates['unreadCounts.$uid'] = 0;
    }
    await _firestore.collection('chats').doc(chatId).update(updates);
  }

  Future<void> removeGroupMember(String chatId, String memberId) async {
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayRemove([memberId]),
      'unreadCounts.$memberId': FieldValue.delete(),
    });
  }

  Future<void> leaveGroup(String chatId, String userId) => removeGroupMember(chatId, userId);

  Future<void> acceptMessageRequest(String chatId, String userId) async {
    await _firestore.collection('chats').doc(chatId).update({
      'acceptedRequests': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> declineMessageRequest(String chatId, String userId) async {
    await _firestore.collection('chats').doc(chatId).update({
      'archivedUsers': FieldValue.arrayUnion([userId]),
      'acceptedRequests': FieldValue.arrayRemove([userId]),
      'unreadCounts.$userId': 0,
    });
  }

  /// Deprecated: Seeded mock chats are eliminated in favor of real platform
  /// creators from Firestore `users` and genuine relationships.
  @Deprecated('Use getOrCreateDirectChat or real Firestore chat streams instead')
  Future<void> ensureDefaultOneOvaChats(String currentUserId) async {
    // No-op: Removed fake static threads (Brenda Beats, Bolo Sinai, etc.)
    return;
  }
}

class ChatModel {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final String? lastMessageSenderId;
  final String? lastMessageType;
  final Map<String, int> unreadCounts;
  final List<String> typingUsers;
  final List<String> recordingUsers;
  final Map<String, int> typingAt;
  final String? title;
  final String? avatarUrl;
  final String? category;
  final String? roleBadge;
  final String? avatarOverlayIcon;
  final bool isVerified;
  final bool isOnline;
  final String? voiceDuration;
  final bool hasVoiceMemo;
  final String? messagePrefix;
  final String? deliveryStatus;
  final bool isStarred;
  final int disappearingDuration;
  final List<String> mutedUsers;
  final List<String> pinnedUsers;
  final List<String> archivedUsers;
  final List<String> acceptedRequests;
  final String? pinnedMessageId;
  final List<String> pinnedMessageIds;
  final String? pinnedMessagePreview;
  final Map<String, Timestamp> readWatermarks;
  final Map<String, Timestamp> deliveredWatermarks;
  final bool isMutual;
  final bool isBlocked;
  final int creatorLevel;
  final int creatorEngagementScore;
  final String? ownerId;

  ChatModel({
    required this.id,
    required this.participants,
    required this.lastMessage,
    this.lastMessageTime,
    this.lastMessageSenderId,
    this.lastMessageType,
    required this.unreadCounts,
    this.typingUsers = const [],
    this.recordingUsers = const [],
    this.typingAt = const {},
    this.title,
    this.avatarUrl,
    this.category,
    this.roleBadge,
    this.avatarOverlayIcon,
    this.isVerified = false,
    this.isOnline = false,
    this.voiceDuration,
    this.hasVoiceMemo = false,
    this.messagePrefix,
    this.deliveryStatus,
    this.isStarred = false,
    this.disappearingDuration = 0,
    this.mutedUsers = const [],
    this.pinnedUsers = const [],
    this.archivedUsers = const [],
    this.acceptedRequests = const [],
    this.pinnedMessageId,
    this.pinnedMessageIds = const [],
    this.pinnedMessagePreview,
    this.readWatermarks = const {},
    this.deliveredWatermarks = const {},
    this.isMutual = true,
    this.isBlocked = false,
    this.creatorLevel = 1,
    this.creatorEngagementScore = 0,
    this.ownerId,
  });

  bool isPinnedBy(String uid) => pinnedUsers.contains(uid);
  bool isArchivedBy(String uid) => archivedUsers.contains(uid);
  bool isMutedBy(String uid) => mutedUsers.contains(uid);

  /// Filters out stale typing heartbeats older than 10s (e.g. abrupt app kill).
  List<String> activeTypingUsers(String currentUserId, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return typingUsers.where((uid) {
      if (uid == currentUserId) return false;
      final at = typingAt[uid];
      if (at == null) return true;
      return (now - at) < 10000;
    }).toList();
  }

  bool isMessageReadByOther(MessageModel m, String senderId) {
    if (m.readBy.any((id) => id != senderId)) return true;
    final msgMs = m.timestamp.millisecondsSinceEpoch;
    return readWatermarks.entries.any(
      (e) => e.key != senderId && e.value.millisecondsSinceEpoch >= msgMs,
    );
  }

  bool isMessageDeliveredToOther(MessageModel m, String senderId) {
    if (isMessageReadByOther(m, senderId)) return true;
    if (m.deliveredTo.any((id) => id != senderId)) return true;
    final msgMs = m.timestamp.millisecondsSinceEpoch;
    return deliveredWatermarks.entries.any(
      (e) => e.key != senderId && e.value.millisecondsSinceEpoch >= msgMs,
    );
  }

  static Map<String, Timestamp> _parseTsMap(dynamic raw) {
    final out = <String, Timestamp>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k != null && v is Timestamp) out[k.toString()] = v;
      });
    }
    return out;
  }

  static Map<String, int> _parseIntMap(dynamic raw) {
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k != null) {
          out[k.toString()] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        }
      });
    }
    return out;
  }

  factory ChatModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    return ChatModel(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: (data['lastMessage'] as String?) ?? '',
      lastMessageTime: data['lastMessageTime'] as Timestamp?,
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      lastMessageType: data['lastMessageType'] as String?,
      unreadCounts: _parseIntMap(data['unreadCounts']),
      typingUsers: List<String>.from(data['typingUsers'] ?? []),
      recordingUsers: List<String>.from(data['recordingUsers'] ?? []),
      typingAt: _parseIntMap(data['typingAt']),
      title: data['title'] as String?,
      avatarUrl: data['avatarUrl'] as String?,
      category: data['category'] as String?,
      roleBadge: data['roleBadge'] as String?,
      avatarOverlayIcon: data['avatarOverlayIcon'] as String?,
      isVerified: (data['isVerified'] as bool?) ?? false,
      isOnline: (data['isOnline'] as bool?) ?? false,
      voiceDuration: data['voiceDuration'] as String?,
      hasVoiceMemo: (data['hasVoiceMemo'] as bool?) ?? false,
      messagePrefix: data['messagePrefix'] as String?,
      deliveryStatus: data['deliveryStatus'] as String?,
      isStarred: (data['isStarred'] as bool?) ?? false,
      disappearingDuration: (data['disappearingDuration'] as num?)?.toInt() ?? 0,
      mutedUsers: List<String>.from(data['mutedUsers'] ?? []),
      pinnedUsers: List<String>.from(data['pinnedUsers'] ?? []),
      archivedUsers: List<String>.from(data['archivedUsers'] ?? []),
      acceptedRequests: List<String>.from(data['acceptedRequests'] ?? []),
      pinnedMessageId: data['pinnedMessageId'] as String?,
      pinnedMessageIds: List<String>.from(data['pinnedMessageIds'] ?? []),
      pinnedMessagePreview: data['pinnedMessagePreview'] as String?,
      readWatermarks: _parseTsMap(data['readWatermarks']),
      deliveredWatermarks: _parseTsMap(data['deliveredWatermarks']),
      isMutual: (data['isMutual'] as bool?) ?? true,
      isBlocked: (data['isBlocked'] as bool?) ?? false,
      creatorLevel: (data['creatorLevel'] as num?)?.toInt() ?? 1,
      creatorEngagementScore: (data['creatorEngagementScore'] as num?)?.toInt() ?? 0,
      ownerId: data['ownerId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'lastMessage': lastMessage,
      if (lastMessageTime != null) 'lastMessageTime': lastMessageTime,
      if (lastMessageSenderId != null) 'lastMessageSenderId': lastMessageSenderId,
      if (lastMessageType != null) 'lastMessageType': lastMessageType,
      'unreadCounts': unreadCounts,
      'typingUsers': typingUsers,
      'recordingUsers': recordingUsers,
      if (typingAt.isNotEmpty) 'typingAt': typingAt,
      if (title != null) 'title': title,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (category != null) 'category': category,
      if (roleBadge != null) 'roleBadge': roleBadge,
      if (avatarOverlayIcon != null) 'avatarOverlayIcon': avatarOverlayIcon,
      'isVerified': isVerified,
      'isOnline': isOnline,
      if (voiceDuration != null) 'voiceDuration': voiceDuration,
      'hasVoiceMemo': hasVoiceMemo,
      if (messagePrefix != null) 'messagePrefix': messagePrefix,
      if (deliveryStatus != null) 'deliveryStatus': deliveryStatus,
      'isStarred': isStarred,
      'disappearingDuration': disappearingDuration,
      'mutedUsers': mutedUsers,
      if (pinnedUsers.isNotEmpty) 'pinnedUsers': pinnedUsers,
      if (archivedUsers.isNotEmpty) 'archivedUsers': archivedUsers,
      if (acceptedRequests.isNotEmpty) 'acceptedRequests': acceptedRequests,
      if (pinnedMessageId != null) 'pinnedMessageId': pinnedMessageId,
      if (pinnedMessageIds.isNotEmpty) 'pinnedMessageIds': pinnedMessageIds,
      if (pinnedMessagePreview != null) 'pinnedMessagePreview': pinnedMessagePreview,
      if (readWatermarks.isNotEmpty) 'readWatermarks': readWatermarks,
      if (deliveredWatermarks.isNotEmpty) 'deliveredWatermarks': deliveredWatermarks,
      'isMutual': isMutual,
      'creatorLevel': creatorLevel,
      'creatorEngagementScore': creatorEngagementScore,
    };
  }

  ChatModel copyWith({
    String? id,
    List<String>? participants,
    String? lastMessage,
    Timestamp? lastMessageTime,
    String? lastMessageSenderId,
    String? lastMessageType,
    Map<String, int>? unreadCounts,
    List<String>? typingUsers,
    List<String>? recordingUsers,
    Map<String, int>? typingAt,
    String? title,
    String? avatarUrl,
    String? category,
    String? roleBadge,
    String? avatarOverlayIcon,
    bool? isVerified,
    bool? isOnline,
    String? voiceDuration,
    bool? hasVoiceMemo,
    String? messagePrefix,
    String? deliveryStatus,
    bool? isStarred,
    int? disappearingDuration,
    List<String>? mutedUsers,
    List<String>? pinnedUsers,
    List<String>? archivedUsers,
    List<String>? acceptedRequests,
    String? pinnedMessageId,
    List<String>? pinnedMessageIds,
    String? pinnedMessagePreview,
    Map<String, Timestamp>? readWatermarks,
    Map<String, Timestamp>? deliveredWatermarks,
    bool? isMutual,
    bool? isBlocked,
    int? creatorLevel,
    int? creatorEngagementScore,
    String? ownerId,
  }) {
    return ChatModel(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      typingUsers: typingUsers ?? this.typingUsers,
      recordingUsers: recordingUsers ?? this.recordingUsers,
      typingAt: typingAt ?? this.typingAt,
      title: title ?? this.title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      category: category ?? this.category,
      roleBadge: roleBadge ?? this.roleBadge,
      avatarOverlayIcon: avatarOverlayIcon ?? this.avatarOverlayIcon,
      isVerified: isVerified ?? this.isVerified,
      isOnline: isOnline ?? this.isOnline,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      hasVoiceMemo: hasVoiceMemo ?? this.hasVoiceMemo,
      messagePrefix: messagePrefix ?? this.messagePrefix,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      isStarred: isStarred ?? this.isStarred,
      disappearingDuration: disappearingDuration ?? this.disappearingDuration,
      mutedUsers: mutedUsers ?? this.mutedUsers,
      pinnedUsers: pinnedUsers ?? this.pinnedUsers,
      archivedUsers: archivedUsers ?? this.archivedUsers,
      acceptedRequests: acceptedRequests ?? this.acceptedRequests,
      pinnedMessageId: pinnedMessageId ?? this.pinnedMessageId,
      pinnedMessageIds: pinnedMessageIds ?? this.pinnedMessageIds,
      pinnedMessagePreview: pinnedMessagePreview ?? this.pinnedMessagePreview,
      readWatermarks: readWatermarks ?? this.readWatermarks,
      deliveredWatermarks: deliveredWatermarks ?? this.deliveredWatermarks,
      isMutual: isMutual ?? this.isMutual,
      isBlocked: isBlocked ?? this.isBlocked,
      creatorLevel: creatorLevel ?? this.creatorLevel,
      creatorEngagementScore: creatorEngagementScore ?? this.creatorEngagementScore,
      ownerId: ownerId ?? this.ownerId,
    );
  }
}

class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final Timestamp timestamp;
  final List<String> readBy;
  final List<String> deliveredTo;
  final String? replyToMessageId;
  final Map<String, String>? reactions;
  final String? mediaUrl;
  final String? mediaType;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final bool isStarred;
  final String? voiceDuration;
  final List<double>? voiceWaveform;
  final bool isEncrypted;
  final bool edited;
  final Timestamp? editedAt;
  final Timestamp? expiresAt;
  final String localStatus;

  /// The file at [mediaUrl] is AES-GCM ciphertext under the per-chat key.
  final bool mediaEncrypted;

  /// For `mediaType: 'location'`: lat, lng, accuracy, address, live,
  /// active, expiresAt, updatedAt.
  final Map<String, dynamic>? location;

  /// Sent with "Forward" from another chat.
  final bool forwarded;

  /// Ova Guard link/scam verdict, written only by the server
  /// (verdict, reasons, blockedLinks). Null when nothing was found.
  final Map<String, dynamic>? safety;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.readBy,
    this.deliveredTo = const [],
    this.replyToMessageId,
    this.reactions,
    this.mediaUrl,
    this.mediaType,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.isStarred = false,
    this.voiceDuration,
    this.voiceWaveform,
    this.isEncrypted = false,
    this.mediaEncrypted = false,
    this.location,
    this.forwarded = false,
    this.safety,
    this.edited = false,
    this.editedAt,
    this.expiresAt,
    this.localStatus = '',
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    List<double>? parsedWaveform;
    if (data['voiceWaveform'] is List) {
      parsedWaveform = (data['voiceWaveform'] as List)
          .map((v) => (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0)
          .toList();
    }

    return MessageModel(
      id: doc.id,
      senderId: (data['senderId'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      timestamp: (data['timestamp'] as Timestamp?) ?? Timestamp.now(),
      readBy: List<String>.from(data['readBy'] ?? []),
      deliveredTo: List<String>.from(data['deliveredTo'] ?? []),
      replyToMessageId: data['replyToMessageId'] as String?,
      reactions: data['reactions'] != null ? Map<String, String>.from(data['reactions'] as Map) : null,
      mediaUrl: data['mediaUrl'] as String?,
      mediaType: data['mediaType'] as String?,
      fileName: data['fileName'] as String?,
      mimeType: data['mimeType'] as String?,
      fileSize: (data['fileSize'] as num?)?.toInt(),
      isStarred: (data['isStarred'] as bool?) ?? false,
      voiceDuration: data['voiceDuration'] as String?,
      voiceWaveform: parsedWaveform,
      isEncrypted: (data['isEncrypted'] as bool?) ?? false,
      mediaEncrypted: (data['mediaEncrypted'] as bool?) ?? false,
      location: data['location'] is Map ? Map<String, dynamic>.from(data['location'] as Map) : null,
      forwarded: (data['forwarded'] as bool?) ?? false,
      safety: data['safety'] is Map ? Map<String, dynamic>.from(data['safety'] as Map) : null,
      edited: (data['edited'] as bool?) ?? false,
      editedAt: data['editedAt'] as Timestamp?,
      expiresAt: data['expiresAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'timestamp': timestamp,
      'readBy': readBy,
      'deliveredTo': deliveredTo,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (reactions != null) 'reactions': reactions,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
      if (fileName != null) 'fileName': fileName,
      if (mimeType != null) 'mimeType': mimeType,
      if (fileSize != null) 'fileSize': fileSize,
      'isStarred': isStarred,
      if (voiceDuration != null) 'voiceDuration': voiceDuration,
      if (voiceWaveform != null) 'voiceWaveform': voiceWaveform,
      'isEncrypted': isEncrypted,
      if (mediaEncrypted) 'mediaEncrypted': true,
      if (location != null) 'location': location,
      if (forwarded) 'forwarded': true,
      if (edited) 'edited': true,
      if (editedAt != null) 'editedAt': editedAt,
      if (expiresAt != null) 'expiresAt': expiresAt,
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? text,
    Timestamp? timestamp,
    List<String>? readBy,
    List<String>? deliveredTo,
    String? replyToMessageId,
    Map<String, String>? reactions,
    String? mediaUrl,
    String? mediaType,
    String? fileName,
    String? mimeType,
    int? fileSize,
    bool? isStarred,
    String? voiceDuration,
    List<double>? voiceWaveform,
    bool? isEncrypted,
    bool? mediaEncrypted,
    Map<String, dynamic>? location,
    bool? forwarded,
    Map<String, dynamic>? safety,
    bool? edited,
    Timestamp? editedAt,
    Timestamp? expiresAt,
    String? localStatus,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      readBy: readBy ?? this.readBy,
      deliveredTo: deliveredTo ?? this.deliveredTo,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      reactions: reactions ?? this.reactions,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      isStarred: isStarred ?? this.isStarred,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      voiceWaveform: voiceWaveform ?? this.voiceWaveform,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      mediaEncrypted: mediaEncrypted ?? this.mediaEncrypted,
      location: location ?? this.location,
      forwarded: forwarded ?? this.forwarded,
      safety: safety ?? this.safety,
      edited: edited ?? this.edited,
      editedAt: editedAt ?? this.editedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      localStatus: localStatus ?? this.localStatus,
    );
  }
}
