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

  MessagingRepository(
    this._firestore, {
    E2EEncryptionService? e2eeService,
    ChatAffinityExtractor? chatAffinityExtractor,
  })  : _e2eeService = e2eeService ?? E2EEncryptionService(),
        // ignore: prefer_initializing_formals
        _chatAffinityExtractor = chatAffinityExtractor;

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
      final userDoc = await _firestore.collection('users').doc(otherUserId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        final resolvedTitle = (data['displayName'] as String?)?.isNotEmpty == true
            ? data['displayName'] as String
            : ((data['fullName'] as String?)?.isNotEmpty == true
                ? data['fullName'] as String
                : ((data['username'] as String?)?.isNotEmpty == true
                    ? data['username'] as String
                    : chat.title));

        final resolvedAvatar = (data['profilePhotoUrl'] as String?) ??
            (data['photoUrl'] as String?) ??
            chat.avatarUrl;

        final isVerified = (data['isVerified'] as bool?) ?? chat.isVerified;
        final role = (data['role'] as String?)?.toUpperCase() ?? chat.roleBadge;

        // Strict Mutual Connection Resolution for 1-on-1 chats
        bool isMutual = true;
        if (currentUserId != null && currentUserId.isNotEmpty && chat.participants.length == 2) {
          try {
            final fwdDoc = await _firestore.collection('relationships').doc('${currentUserId}_$otherUserId').get();
            final revDoc = await _firestore.collection('relationships').doc('${otherUserId}_$currentUserId').get();
            final fwd = fwdDoc.exists && fwdDoc.data()?['status'] == 'accepted';
            final rev = revDoc.exists && revDoc.data()?['status'] == 'accepted';
            isMutual = fwd && rev;
          } catch (_) {
            isMutual = false;
          }
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
          creatorLevel: engagement.tier.level,
          creatorEngagementScore: engagement.totalScore,
        );
      }
    } catch (e) {
      debugPrint('Error resolving real profile for user $otherUserId: $e');
    }

    return chat;
  }

  Stream<List<ChatModel>> getUserChatsStream(String userId) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final List<ChatModel> resolvedList = [];
      for (final doc in snapshot.docs) {
        final chat = ChatModel.fromFirestore(doc);
        final resolved = await _resolveChatWithRealProfile(chat, userId);
        resolvedList.add(resolved);
      }
      return resolvedList;
    });
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

  Stream<List<MessageModel>> getChatMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => MessageModel.fromFirestore(doc)).toList());
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

    // 1. Check if chat already exists in `chats` where participants contains both
    final querySnapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .get();

    for (final doc in querySnapshot.docs) {
      final docParticipants = List<String>.from(doc.data()['participants'] ?? []);
      if (docParticipants.contains(targetUserId)) {
        return doc.id;
      }
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

      final List<Map<String, dynamic>> creators = [];

      // 1. Strictly enforce mutual follow rule: current user follows target AND target follows current user back
      for (final uid in followedUids) {
        try {
          final reverseRelDoc = await _firestore.collection('relationships').doc('${uid}_$currentUserId').get();
          final isMutual = reverseRelDoc.exists && reverseRelDoc.data()?['status'] == 'accepted';

          // As specified: "You can't see in your inbox or circle people you don't follow or don't follow back."
          if (!isMutual) continue;

          final userDoc = await _firestore.collection('users').doc(uid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final data = Map<String, dynamic>.from(userDoc.data()!);
            data['id'] = userDoc.id;
            data['uid'] = userDoc.id;
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

            creators.add(data);
          }
        } catch (e) {
          debugPrint('Error loading mutual creator $uid: $e');
        }
      }

      return creators;
    });
  }

  /// Stream of pending incoming message requests from non-mutual users
  Stream<List<ChatModel>> getMessageRequestsStream(String userId) {
    return getUserChatsStream(userId).map((chats) {
      return chats.where((c) {
        // Direct 1-on-1 chats that are NOT mutual yet
        return c.category != 'group' && c.category != 'channel' && !c.isMutual && c.participants.length == 2;
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
  }) async {
    // Check for an existing exact match
    final querySnapshot = await _firestore
        .collection('chats')
        .where('participants', arrayContains: participants.first)
        .get();

    for (final doc in querySnapshot.docs) {
      final docParticipants = List<String>.from(doc.data()['participants'] ?? []);
      if (docParticipants.length == participants.length &&
          participants.every((p) => docParticipants.contains(p))) {
        return doc.id;
      }
    }

    // Create a new chat
    final newChatId = const Uuid().v4();
    final initialUnread = {for (var p in participants) p: 0};
    
    await _firestore.collection('chats').doc(newChatId).set({
      'participants': participants,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCounts': initialUnread,
      'typingUsers': [],
      'title': ?title,
      'avatarUrl': ?avatarUrl,
      'category': ?category,
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
    final messageId = const Uuid().v4();
    final timestamp = Timestamp.now();

    // Determine recipientId if not explicitly passed. E2EE is per-recipient,
    // so it only applies to 1:1 chats; shared chats stay readable by all members.
    String? targetRecipientId = recipientId;
    bool isSharedChat = false;
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (chatDoc.exists) {
        final data = chatDoc.data() ?? {};
        final participants = List<String>.from(data['participants'] ?? []);
        const sharedCategories = {'group', 'room', 'vip_room', 'channel'};
        isSharedChat = participants.length > 2 || sharedCategories.contains(data['category']);
        if (targetRecipientId == null || targetRecipientId.isEmpty) {
          targetRecipientId = participants.firstWhere((p) => p != senderId, orElse: () => '');
        }
      }
    } catch (e) {
      debugPrint('Error resolving recipient for E2EE: $e');
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

    final message = MessageModel(
      id: messageId,
      senderId: senderId,
      text: textToSend,
      timestamp: timestamp,
      readBy: [senderId],
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
        chatRef.collection('messages').doc(messageId),
        message.toMap(),
      );

      String displayLastMessage = isEncrypted ? '🔒 Encrypted message' : text;
      if (displayLastMessage.trim().isEmpty) {
        if (mediaType == 'audio' || hasVoiceMemo) {
          displayLastMessage = '🎙️ Voice note ${voiceDuration != null ? '($voiceDuration)' : ''}';
        } else if (mediaType == 'image') {
          displayLastMessage = '📷 Photo';
        } else if (mediaType == 'video') {
          displayLastMessage = '🎥 Video';
        } else if (mediaType == 'video_note') {
          displayLastMessage = '📹 Video message ${voiceDuration != null ? '($voiceDuration)' : ''}';
        } else if (mediaType == 'gif') {
          displayLastMessage = 'GIF';
        } else if (mediaType == 'document') {
          displayLastMessage = '📄 ${fileName ?? 'Document'}';
        } else if (mediaType == 'location') {
          displayLastMessage = location?['live'] == true ? '📍 Live location' : '📍 Location';
        } else {
          displayLastMessage = 'Attachment';
        }
      }

      final updateMap = <String, dynamic>{
        'lastMessage': displayLastMessage,
        'lastMessageTime': timestamp,
        'lastMessageSenderId': senderId,
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
    return messageId;
  }
  
  Future<void> markMessagesAsRead(String chatId, String userId) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    
    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(chatRef);
      if (!doc.exists) return;
      
      final chatData = doc.data() as Map<String, dynamic>;
      final unreadCounts = Map<String, int>.from(chatData['unreadCounts'] ?? {});
      unreadCounts[userId] = 0;
      
      transaction.update(chatRef, {
        'unreadCounts': unreadCounts,
        'deliveryStatus': 'read',
      });
      
      // Also update messages that haven't been read by this user yet
      final messagesSnapshot = await chatRef.collection('messages').get();
      for (final msgDoc in messagesSnapshot.docs) {
        final data = msgDoc.data();
        if (data['senderId'] == userId) continue; // don't mark own messages as read by self
        
        final readBy = List<String>.from(data['readBy'] ?? []);
        if (!readBy.contains(userId)) {
          readBy.add(userId);
          transaction.update(msgDoc.reference, {'readBy': readBy});
        }
      }
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
        'typingUsers': FieldValue.arrayUnion([userId])
      });
    } else {
      await chatRef.update({
        'typingUsers': FieldValue.arrayRemove([userId])
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
    await msgRef.set({
      'reactions': {
        userId: emoji,
      }
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessage(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  Future<void> clearChatHistory(String chatId) async {
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
  final Map<String, int> unreadCounts;
  final List<String> typingUsers;
  final List<String> recordingUsers;
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
  final bool isMutual;
  final int creatorLevel;
  final int creatorEngagementScore;
  final String? ownerId;

  ChatModel({
    required this.id,
    required this.participants,
    required this.lastMessage,
    this.lastMessageTime,
    this.lastMessageSenderId,
    required this.unreadCounts,
    this.typingUsers = const [],
    this.recordingUsers = const [],
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
    this.isMutual = true,
    this.creatorLevel = 1,
    this.creatorEngagementScore = 0,
    this.ownerId,
  });

  factory ChatModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    Map<String, int> parsedUnread = {};
    if (data['unreadCounts'] != null && data['unreadCounts'] is Map) {
      (data['unreadCounts'] as Map).forEach((k, v) {
        if (k != null) {
          parsedUnread[k.toString()] = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        }
      });
    }

    return ChatModel(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: (data['lastMessage'] as String?) ?? '',
      lastMessageTime: data['lastMessageTime'] as Timestamp?,
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      unreadCounts: parsedUnread,
      typingUsers: List<String>.from(data['typingUsers'] ?? []),
      recordingUsers: List<String>.from(data['recordingUsers'] ?? []),
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
      isMutual: (data['isMutual'] as bool?) ?? true,
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
      'unreadCounts': unreadCounts,
      'typingUsers': typingUsers,
      'recordingUsers': recordingUsers,
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
    Map<String, int>? unreadCounts,
    List<String>? typingUsers,
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
    bool? isMutual,
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
      unreadCounts: unreadCounts ?? this.unreadCounts,
      typingUsers: typingUsers ?? this.typingUsers,
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
      isMutual: isMutual ?? this.isMutual,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'timestamp': timestamp,
      'readBy': readBy,
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
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? text,
    Timestamp? timestamp,
    List<String>? readBy,
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
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      readBy: readBy ?? this.readBy,
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
      mediaEncrypted: mediaEncrypted,
      location: location,
      forwarded: forwarded,
    );
  }
}
