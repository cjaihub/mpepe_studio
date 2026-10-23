import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../models/inbox_query.dart';

final canonicalInboxRepositoryProvider = Provider<CanonicalInboxRepository>((ref) {
  return CanonicalInboxRepository(FirebaseFirestore.instance);
});

class CanonicalInboxRepository {
  final FirebaseFirestore _firestore;

  CanonicalInboxRepository(this._firestore);

  /// Paginated query for conversations based on InboxQuery
  Future<List<Conversation>> getConversations(InboxQuery query, String userId) async {
    Query fbQuery = _firestore.collection('conversations')
        .where('participants', arrayContains: userId);

    if (query.platformId != null && query.platformId != 'All') {
      fbQuery = fbQuery.where('connectorId', isEqualTo: query.platformId);
    }
    
    if (query.unread == true) {
      fbQuery = fbQuery.where('unreadCount', isGreaterThan: 0);
    }

    if (query.priority != null && query.priority != 'All') {
      fbQuery = fbQuery.where('priority', isEqualTo: query.priority);
    }
    
    if (query.needsReply == true) {
      fbQuery = fbQuery.where('needsReply', isEqualTo: true);
    }
    
    if (query.assignedTo != null) {
      fbQuery = fbQuery.where('assignment', isEqualTo: query.assignedTo);
    }

    fbQuery = fbQuery.orderBy(query.sortField ?? 'updatedAt', descending: query.descending);
    
    if (query.startAfter != null) {
      fbQuery = fbQuery.startAfterDocument(query.startAfter!);
    }
    
    fbQuery = fbQuery.limit(query.limit);

    final snapshot = await fbQuery.get();
    return snapshot.docs.map((doc) => Conversation.fromFirestore(doc)).toList();
  }

  /// Realtime targeted updates for a specific conversation
  Stream<Conversation?> watchConversation(String conversationId) {
    return _firestore.collection('conversations').doc(conversationId).snapshots()
        .map((doc) => doc.exists ? Conversation.fromFirestore(doc) : null);
  }

  /// Paginated queries for messages
  Future<List<InboxMessage>> getMessages(String conversationId, {DocumentSnapshot? startAfter, int limit = 50}) async {
    Query query = _firestore.collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true);
        
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    query = query.limit(limit);
    
    final snapshot = await query.get();
    return snapshot.docs.map((doc) => InboxMessage.fromFirestore(doc)).toList();
  }
  
  /// Realtime latest messages (e.g. listening to the top 20 only)
  Stream<List<InboxMessage>> watchLatestMessages(String conversationId, {int limit = 20}) {
    return _firestore.collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => InboxMessage.fromFirestore(doc)).toList());
  }

  /// Write a normalized message to the canonical database idempotently.
  Future<void> ingestExternalMessage(Conversation conv, InboxMessage msg) async {
    final convRef = _firestore.collection('conversations').doc(conv.id);
    final msgRef = convRef.collection('messages').doc(msg.id);
    
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(msgRef);
      if (doc.exists) {
        // Idempotency: Message already exists, do not duplicate.
        return; 
      }
      
      tx.set(msgRef, msg.toMap());
      
      // Update Conversation metadata
      tx.set(convRef, conv.toMap(), SetOptions(merge: true));
    });
  }
  
  /// Marks a conversation as read.
  Future<void> markAsRead(String conversationId, String userId) async {
    final convRef = _firestore.collection('conversations').doc(conversationId);
    await convRef.update({
      'unreadCount': 0, // In reality, we'd use a map like unreadCounts[userId] = 0
    });
  }
}
