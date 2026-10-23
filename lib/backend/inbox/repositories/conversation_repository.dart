import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation_model.dart';
import '../../unified_inbox_provider.dart' show SocialPlatform;

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(FirebaseFirestore.instance);
});

class ConversationRepository {
  final FirebaseFirestore _firestore;
  
  ConversationRepository(this._firestore);

  /// Fetches a paginated list of conversations for a user.
  /// Applies filters (e.g., 'unread', 'priority', 'archived') and channel filters.
  Future<List<Conversation>> getConversationsPaginated({
    required String userId,
    required int limit,
    DocumentSnapshot? startAfter,
    String filter = 'All',
    SocialPlatform? channel,
  }) async {
    Query query = _firestore.collection('conversations')
        .where('participants', arrayContains: userId);

    query = _applyFilters(query, filter, channel);
    
    // Default sorting by most recently updated
    query = query.orderBy('updatedAt', descending: true);
    
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    
    query = query.limit(limit);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => Conversation.fromFirestore(doc)).toList();
  }

  /// Listens to real-time changes for the most recent active conversations.
  /// We only listen to a small limit (e.g., top 20) to prevent excessive read charges.
  Stream<List<Conversation>> listenToRecentConversations({
    required String userId,
    int limit = 20,
    String filter = 'All',
    SocialPlatform? channel,
  }) {
    Query query = _firestore.collection('conversations')
        .where('participants', arrayContains: userId);

    query = _applyFilters(query, filter, channel);
    
    query = query.orderBy('updatedAt', descending: true).limit(limit);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Conversation.fromFirestore(doc)).toList();
    });
  }

  Query _applyFilters(Query query, String filter, SocialPlatform? channel) {
    if (channel != null) {
      query = query.where('channel', isEqualTo: channel.name);
    }

    // Default filters
    if (filter != 'Archived') {
      query = query.where('isArchived', isEqualTo: false);
    }

    switch (filter) {
      case 'Unread':
        query = query.where('unreadCount', isGreaterThan: 0);
        break;
      case 'Priority':
        query = query.where('labels', arrayContains: 'priority');
        break;
      case 'Assigned to me':
        // Requires composite index if we had a known user ID, but this is a complex filter.
        // Assuming we add a specific label or field for assignment that is simple.
        break;
      case 'Mentions':
        query = query.where('labels', arrayContains: 'mention');
        break;
      case 'AI assisted':
        query = query.where('aiAccessPolicy', isEqualTo: 'full'); // simplified
        break;
      case 'Scheduled':
        query = query.where('labels', arrayContains: 'scheduled');
        break;
      case 'Archived':
        query = query.where('isArchived', isEqualTo: true);
        break;
      case 'All':
      default:
        break;
    }

    return query;
  }

  Future<void> updateTypingState(String conversationId, String? typingUserId) async {
    await _firestore.collection('conversations').doc(conversationId).update({
      'typingState': typingUserId,
    });
  }

  Future<void> updatePresence(String conversationId, String userId, String status) async {
    await _firestore.collection('conversations').doc(conversationId).set({
      'presence': {userId: status},
    }, SetOptions(merge: true));
  }

  Future<void> markAsRead(String conversationId) async {
    await _firestore.collection('conversations').doc(conversationId).update({
      'unreadCount': 0,
    });
  }
}
