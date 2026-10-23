import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(FirebaseFirestore.instance);
});

class MessageRepository {
  final FirebaseFirestore _firestore;

  MessageRepository(this._firestore);

  /// Get paginated messages for a conversation
  Future<List<InboxMessage>> getMessagesPaginated({
    required String conversationId,
    required int limit,
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => InboxMessage.fromFirestore(doc)).toList();
  }

  /// Listen to the most recent messages (e.g. latest 50)
  Stream<List<InboxMessage>> listenToRecentMessages({
    required String conversationId,
    int limit = 50,
  }) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => InboxMessage.fromFirestore(doc)).toList());
  }

  Future<void> sendMessage(InboxMessage message) async {
    final docRef = _firestore
        .collection('conversations')
        .doc(message.conversationId)
        .collection('messages')
        .doc(message.id);

    await docRef.set(message.toMap());

    // Update conversation latest message
    await _firestore.collection('conversations').doc(message.conversationId).update({
      'latestMessage': message.content,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> editMessage(String conversationId, String messageId, String newContent) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'content': newContent,
      'isEdited': true,
    });
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isDeleted': true,
      'content': 'This message was deleted.',
      'attachments': [],
    });
  }

  Future<void> addReaction(String conversationId, String messageId, String emoji) async {
    final docRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      
      final currentReactions = Map<String, dynamic>.from(snapshot.data()?['reactions'] ?? {});
      final currentCount = currentReactions[emoji] as int? ?? 0;
      
      currentReactions[emoji] = currentCount + 1;
      
      transaction.update(docRef, {'reactions': currentReactions});
    });
  }

  Future<void> updateMessageStatus(String conversationId, String messageId, MessageStatus status) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'status': status.name,
    });
  }
}
