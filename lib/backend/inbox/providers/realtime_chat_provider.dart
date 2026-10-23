import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/message_repository.dart';

final recentConversationsProvider = StreamProvider<List<Conversation>>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  
  if (userId.isEmpty) {
    return Stream.value([]);
  }

  return repo.listenToRecentConversations(userId: userId, limit: 50);
});

final conversationMessagesProvider = StreamProvider.family<List<InboxMessage>, String>((ref, conversationId) {
  final repo = ref.watch(messageRepositoryProvider);
  
  if (conversationId.isEmpty) {
    return Stream.value([]);
  }

  return repo.listenToRecentMessages(conversationId: conversationId, limit: 100);
});
