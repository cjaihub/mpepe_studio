import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/conversation_model.dart';
import '../repositories/conversation_repository.dart';
import '../../unified_inbox_provider.dart' show SocialPlatform;
import '../../teams/team_service.dart';

class InboxState {
  final List<Conversation> conversations;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String activeFilter; // 'All', 'Unread', etc.
  final SocialPlatform? activeChannel;
  final String? userTeamId;

  InboxState({
    this.conversations = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.activeFilter = 'My Inbox',
    this.activeChannel,
    this.userTeamId,
  });

  InboxState copyWith({
    List<Conversation>? conversations,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? activeFilter,
    SocialPlatform? activeChannel,
    String? userTeamId,
    bool clearChannel = false,
  }) {
    return InboxState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      activeFilter: activeFilter ?? this.activeFilter,
      activeChannel: clearChannel ? null : (activeChannel ?? this.activeChannel),
      userTeamId: userTeamId ?? this.userTeamId,
    );
  }
}

final inboxControllerProvider = NotifierProvider<InboxController, InboxState>(() {
  return InboxController();
});

class InboxController extends Notifier<InboxState> {
  // ignore: unused_field
  late ConversationRepository _repository;
  late String _userId;
  DocumentSnapshot? _lastDoc;
  static const int _limit = 20;

  @override
  InboxState build() {
    _repository = ref.watch(conversationRepositoryProvider);
    _userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    
    if (_userId.isNotEmpty) {
      Future.microtask(() => _initializeUserTeam());
      Future.microtask(() => _loadInitial());
    }
    return InboxState();
  }

  Future<void> _initializeUserTeam() async {
    final teamService = ref.read(teamServiceProvider);
    final member = await teamService.getCurrentMemberProfile();
    if (member?.teamId != null) {
      state = state.copyWith(userTeamId: member!.teamId);
    }
  }

  Future<void> _loadInitial() async {
    state = state.copyWith(isLoading: true);
    try {
      // In a real app, we'd also subscribe to the stream for the top N.
      // For this unified architecture, we fetch paginated data first.
      // We can get the actual DocumentSnapshots by calling a slightly modified repo method, 
      // or we can change the repo to return both docs and models.
      // For simplicity, we assume we fetch models and we can use the last item's date as a cursor.
      // But Firestore `startAfterDocument` requires DocumentSnapshot. We will use `startAfter([date])` if needed.
      // Let's rewrite the repo logic inside here if we need direct snapshots.
      
      Query query = FirebaseFirestore.instance.collection('conversations')
          .where('participants', arrayContains: _userId);
      query = _applyFiltersLocally(query);
      query = query.orderBy('updatedAt', descending: true).limit(_limit);
      
      final snap = await query.get();
      final models = snap.docs.map((d) => Conversation.fromFirestore(d)).toList();
      
      if (snap.docs.isNotEmpty) {
        _lastDoc = snap.docs.last;
      }
      
      state = state.copyWith(
        conversations: models,
        isLoading: false,
        hasMore: models.length == _limit,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> fetchMore() async {
    if (state.isLoadingMore || !state.hasMore || _lastDoc == null || _userId.isEmpty) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      Query query = FirebaseFirestore.instance.collection('conversations')
          .where('participants', arrayContains: _userId);
      query = _applyFiltersLocally(query);
      query = query.orderBy('updatedAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_limit);
          
      final snap = await query.get();
      final models = snap.docs.map((d) => Conversation.fromFirestore(d)).toList();

      if (snap.docs.isNotEmpty) {
        _lastDoc = snap.docs.last;
      }

      state = state.copyWith(
        conversations: [...state.conversations, ...models],
        isLoadingMore: false,
        hasMore: models.length == _limit,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void setFilter(String filter) {
    if (state.activeFilter == filter) return;
    state = state.copyWith(activeFilter: filter);
    _lastDoc = null;
    _loadInitial();
  }

  void setChannel(SocialPlatform? channel) {
    if (state.activeChannel == channel) return;
    state = state.copyWith(activeChannel: channel, clearChannel: channel == null);
    _lastDoc = null;
    _loadInitial();
  }

  Query _applyFiltersLocally(Query query) {
    if (state.activeChannel != null) {
      query = query.where('channel', isEqualTo: state.activeChannel!.name);
    }
    if (state.activeFilter != 'Archived') {
      query = query.where('isArchived', isEqualTo: false);
    }
    switch (state.activeFilter) {
      case 'Unread':
        query = query.where('unreadCount', isGreaterThan: 0);
        break;
      case 'Priority':
        query = query.where('labels', arrayContains: 'priority');
        break;
      case 'Archived':
        query = query.where('isArchived', isEqualTo: true);
        break;
      case 'My Inbox':
      case 'Assigned to Me':
        query = query.where('assignment', isEqualTo: _userId);
        break;
      case 'Unassigned':
        query = query.where('assignment', isNull: true);
        break;
      case 'Team Inbox':
      case 'Assigned to Team':
        if (state.userTeamId != null) {
          query = query.where('assignedTeamId', isEqualTo: state.userTeamId);
        }
        break;
      case 'Mentions':
        // Assumes we store mentions in an array or we search subcollections.
        // For now, this requires a specific field 'mentionedUsers' if we want it to be a query.
        break;
    }
    return query;
  }
}
