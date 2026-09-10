import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  return MessagingRepository(FirebaseFirestore.instance);
});

final userChatsProvider = StreamProvider.family<List<ChatModel>, String>((ref, userId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getUserChats(userId);
});

final chatMessagesProvider = StreamProvider.family<List<MessageModel>, String>((ref, chatId) {
  final repository = ref.watch(messagingRepositoryProvider);
  return repository.getChatMessages(chatId);
});

class MessagingRepository {
  final FirebaseFirestore _firestore;
  MessagingRepository(this._firestore);

  Stream<List<ChatModel>> getUserChats(String userId) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => ChatModel.fromFirestore(doc)).toList());
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

  Future<ChatModel?> getChat(String chatId) async {
    final doc = await _firestore.collection('chats').doc(chatId).get();
    if (doc.exists) {
      return ChatModel.fromFirestore(doc);
    }
    return null;
  }

  Future<String> createChat(List<String> participants) async {
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
    });

    return newChatId;
  }

  Future<void> sendMessage(
    String chatId, 
    String senderId, 
    String text, {
    String? replyToMessageId,
    String? mediaUrl,
    String? mediaType,
    String? fileName,
    String? mimeType,
  }) async {
    final messageId = const Uuid().v4();
    final timestamp = Timestamp.now();
    
    final message = MessageModel(
      id: messageId,
      senderId: senderId,
      text: text,
      timestamp: timestamp,
      readBy: [],
      replyToMessageId: replyToMessageId,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      fileName: fileName,
      mimeType: mimeType,
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

      transaction.update(chatRef, {
        'lastMessage': text,
        'lastMessageTime': timestamp,
        'unreadCounts': unreadCounts,
      });
    });
  }
  
  Future<void> markMessagesAsRead(String chatId, String userId) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    
    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(chatRef);
      if (!doc.exists) return;
      
      final chatData = doc.data() as Map<String, dynamic>;
      final unreadCounts = Map<String, int>.from(chatData['unreadCounts'] ?? {});
      unreadCounts[userId] = 0;
      
      transaction.update(chatRef, {'unreadCounts': unreadCounts});
      
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

  Future<void> addReaction(String chatId, String messageId, String userId, String emoji) async {
    final msgRef = _firestore.collection('chats').doc(chatId).collection('messages').doc(messageId);
    await msgRef.set({
      'reactions': {
        userId: emoji,
      }
    }, SetOptions(merge: true));
  }
}

class ChatModel {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final Map<String, int> unreadCounts;
  final List<String> typingUsers;

  ChatModel({
    required this.id,
    required this.participants,
    required this.lastMessage,
    this.lastMessageTime,
    required this.unreadCounts,
    this.typingUsers = const [],
  });

  factory ChatModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatModel(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: data['lastMessageTime'] as Timestamp?,
      unreadCounts: Map<String, int>.from(data['unreadCounts'] ?? {}),
      typingUsers: List<String>.from(data['typingUsers'] ?? []),
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
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      timestamp: data['timestamp'] as Timestamp,
      readBy: List<String>.from(data['readBy'] ?? []),
      replyToMessageId: data['replyToMessageId'] as String?,
      reactions: data['reactions'] != null ? Map<String, String>.from(data['reactions']) : null,
      mediaUrl: data['mediaUrl'] as String?,
      mediaType: data['mediaType'] as String?,
      fileName: data['fileName'] as String?,
      mimeType: data['mimeType'] as String?,
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
    };
  }
}
