import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/conversation_model.dart';
import '../models/inbox_query.dart';
import '../repositories/canonical_inbox_repository.dart';

// --- INBOX QUERY STATE ---
class InboxQueryNotifier extends Notifier<InboxQuery> {
  @override
  InboxQuery build() {
    return const InboxQuery(limit: 20); // Default query
  }

  void updatePlatform(String? platformId) {
    state = state.copyWith(platformId: platformId);
  }

  void updateUnread(bool? unread) {
    state = state.copyWith(unread: unread);
  }

  void updatePriority(String? priority) {
    state = state.copyWith(priority: priority);
  }

  void updateNeedsReply(bool? needsReply) {
    state = state.copyWith(needsReply: needsReply);
  }

  void updateSearch(String? search) {
    state = state.copyWith(searchQuery: search);
  }
}

final inboxQueryProvider = NotifierProvider<InboxQueryNotifier, InboxQuery>(InboxQueryNotifier.new);

// --- CANONICAL STATE ---
class CanonicalInboxState {
  final List<Conversation> conversations;
  final bool isLoading;
  final bool isFetchingMore;
  final bool hasReachedEnd;
  final String? error;
  final DocumentSnapshot? lastCursor;

  CanonicalInboxState({
    this.conversations = const [],
    this.isLoading = false,
    this.isFetchingMore = false,
    this.hasReachedEnd = false,
    this.error,
    this.lastCursor,
  });

  CanonicalInboxState copyWith({
    List<Conversation>? conversations,
    bool? isLoading,
    bool? isFetchingMore,
    bool? hasReachedEnd,
    String? error,
    DocumentSnapshot? lastCursor,
  }) {
    return CanonicalInboxState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      error: error,
      lastCursor: lastCursor ?? this.lastCursor,
    );
  }
}

class CanonicalInboxNotifier extends Notifier<CanonicalInboxState> {
  CanonicalInboxRepository get _repository => ref.read(canonicalInboxRepositoryProvider);

  @override
  CanonicalInboxState build() {
    // Listen to query changes
    ref.listen<InboxQuery>(inboxQueryProvider, (previous, next) {
      if (previous != next) {
        refresh(); // Refresh when query changes
      }
    });

    // Auto-fetch on init
    Future.microtask(() => refresh());

    return CanonicalInboxState(isLoading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        state = state.copyWith(isLoading: false, error: 'User not authenticated');
        return;
      }
      
      final query = ref.read(inboxQueryProvider);
      final results = await _repository.getConversations(query, userId);
      
      DocumentSnapshot? newCursor;
      // In a real implementation we would extract the last document snapshot from the query response, 
      // but since our repository maps to `Conversation` we need to pass back the cursor, or rely on another mechanism.
      // For now, we assume backend support or wrapper returns it.
      
      state = state.copyWith(
        conversations: results,
        isLoading: false,
        hasReachedEnd: results.length < query.limit,
        lastCursor: newCursor,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isFetchingMore || state.hasReachedEnd || state.isLoading) return;

    state = state.copyWith(isFetchingMore: true, error: null);
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      var query = ref.read(inboxQueryProvider);
      if (state.lastCursor != null) {
        query = query.copyWith(startAfter: state.lastCursor);
      }

      final results = await _repository.getConversations(query, userId);
      
      state = state.copyWith(
        conversations: [...state.conversations, ...results],
        isFetchingMore: false,
        hasReachedEnd: results.length < query.limit,
      );
    } catch (e) {
      state = state.copyWith(isFetchingMore: false, error: e.toString());
    }
  }

  /// Update a single conversation in place (called by targeted realtime listeners)
  void updateConversationLocally(Conversation updatedConversation) {
    final index = state.conversations.indexWhere((c) => c.id == updatedConversation.id);
    if (index != -1) {
      final newConversations = List<Conversation>.from(state.conversations);
      newConversations[index] = updatedConversation;
      
      // If the update involves a new message, we might need to resort it to the top.
      newConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      state = state.copyWith(conversations: newConversations);
    } else {
      // If it's a new conversation that fits our query, we could insert it at the top.
      final newConversations = [updatedConversation, ...state.conversations];
      newConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(conversations: newConversations);
    }
  }
}

final canonicalInboxNotifierProvider = NotifierProvider<CanonicalInboxNotifier, CanonicalInboxState>(CanonicalInboxNotifier.new);

// --- TARGETED REALTIME STREAM ---
// This provider is used by the Conversation row UI to listen to targeted updates, avoiding full inbox rebuilds.
final conversationStreamProvider = StreamProvider.family<Conversation?, String>((ref, conversationId) {
  final repository = ref.watch(canonicalInboxRepositoryProvider);
  return repository.watchConversation(conversationId);
});
