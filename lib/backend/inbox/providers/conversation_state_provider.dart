import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/message_model.dart';
import '../repositories/canonical_inbox_repository.dart';

class ConversationState {
  final List<InboxMessage> messages;
  final bool isLoading;
  final bool isFetchingOlder;
  final bool hasReachedEnd;
  final String? error;
  final DocumentSnapshot? lastCursor;
  final bool isSending;

  ConversationState({
    this.messages = const [],
    this.isLoading = false,
    this.isFetchingOlder = false,
    this.hasReachedEnd = false,
    this.error,
    this.lastCursor,
    this.isSending = false,
  });

  ConversationState copyWith({
    List<InboxMessage>? messages,
    bool? isLoading,
    bool? isFetchingOlder,
    bool? hasReachedEnd,
    String? error,
    DocumentSnapshot? lastCursor,
    bool? isSending,
    bool clearError = false,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isFetchingOlder: isFetchingOlder ?? this.isFetchingOlder,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      error: clearError ? null : (error ?? this.error),
      lastCursor: lastCursor ?? this.lastCursor,
      isSending: isSending ?? this.isSending,
    );
  }
}

class ConversationStateNotifier extends Notifier<ConversationState> {
  ConversationStateNotifier(this.conversationId);

  final String conversationId;
  StreamSubscription<List<InboxMessage>>? _realtimeSubscription;

  @override
  ConversationState build() {
    ref.onDispose(() {
      _realtimeSubscription?.cancel();
    });
    // Kick off async init after build returns
    Future.microtask(() => _init(conversationId));
    return ConversationState(isLoading: true);
  }

  Future<void> _init(String conversationId) async {
    final repository = ref.read(canonicalInboxRepositoryProvider);
    try {
      final initialMessages = await repository.getMessages(conversationId, limit: 30);

      state = state.copyWith(
        messages: initialMessages,
        isLoading: false,
        hasReachedEnd: initialMessages.length < 30,
        clearError: true,
      );

      // Start listening to real-time updates for latest messages
      _realtimeSubscription = repository
          .watchLatestMessages(conversationId, limit: 10)
          .listen((latestMessages) {
        _mergeRealtimeMessages(latestMessages);
      });
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _mergeRealtimeMessages(List<InboxMessage> latestMessages) {
    if (state.isLoading) return;

    final Map<String, InboxMessage> currentMessagesMap = {
      for (var msg in state.messages) msg.id: msg
    };

    bool changed = false;

    for (var latestMsg in latestMessages) {
      final currentMsg = currentMessagesMap[latestMsg.id];
      if (currentMsg == null) {
        currentMessagesMap[latestMsg.id] = latestMsg;
        changed = true;
      } else if (currentMsg.deliveryState != latestMsg.deliveryState ||
          currentMsg.content != latestMsg.content) {
        currentMessagesMap[latestMsg.id] = latestMsg;
        changed = true;
      }
    }

    if (changed) {
      final updatedList = currentMessagesMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      state = state.copyWith(messages: updatedList);
    }
  }

  Future<void> loadOlderMessages() async {
    if (state.isFetchingOlder || state.hasReachedEnd || state.isLoading) return;
    final repository = ref.read(canonicalInboxRepositoryProvider);

    state = state.copyWith(isFetchingOlder: true, clearError: true);

    try {
      final olderMessages = await repository.getMessages(
        conversationId,
        startAfter: state.lastCursor,
        limit: 30,
      );

      if (olderMessages.isEmpty) {
        state = state.copyWith(isFetchingOlder: false, hasReachedEnd: true);
        return;
      }

      final currentIds = state.messages.map((e) => e.id).toSet();
      final filteredOlder =
          olderMessages.where((msg) => !currentIds.contains(msg.id)).toList();

      final updatedList = [...state.messages, ...filteredOlder]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      state = state.copyWith(
        messages: updatedList,
        isFetchingOlder: false,
        hasReachedEnd: olderMessages.length < 30,
      );
    } catch (e) {
      state = state.copyWith(isFetchingOlder: false, error: e.toString());
    }
  }

  void addOptimisticMessage(InboxMessage message) {
    final updatedList = [message, ...state.messages];
    state = state.copyWith(messages: updatedList);
  }
}

final conversationStateProvider =
    NotifierProvider.family<ConversationStateNotifier, ConversationState, String>(
  ConversationStateNotifier.new,
);
