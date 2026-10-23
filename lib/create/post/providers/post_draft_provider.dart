import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post_draft.dart';
import '../services/post_draft_repository.dart';

enum PostDraftStatus {
  idle,
  saving,
  saved,
  error,
}

class PostDraftState {
  final PostDraft? draft;
  final PostDraftStatus status;
  final DateTime? lastSavedAt;
  final String? errorMessage;

  const PostDraftState({
    this.draft,
    this.status = PostDraftStatus.idle,
    this.lastSavedAt,
    this.errorMessage,
  });

  PostDraftState copyWith({
    PostDraft? draft,
    PostDraftStatus? status,
    DateTime? lastSavedAt,
    String? errorMessage,
  }) {
    return PostDraftState(
      draft: draft ?? this.draft,
      status: status ?? this.status,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class PostDraftNotifier extends Notifier<PostDraftState> {
  Timer? _debounceTimer;

  @override
  PostDraftState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });
    return const PostDraftState();
  }

  PostDraftRepository get _repository => ref.read(postDraftRepositoryProvider);

  /// Initializes or loads an existing draft for the given mediaPath.
  Future<void> initializeForMedia({
    required String mediaPath,
    required bool isVideo,
    String? initialCaption,
  }) async {
    final existing = await _repository.findDraftForMedia(mediaPath);
    if (existing != null) {
      state = state.copyWith(
        draft: existing,
        status: PostDraftStatus.saved,
        lastSavedAt: existing.updatedAt,
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous_creator';
    final now = DateTime.now();
    final newDraft = PostDraft(
      id: 'draft_${now.millisecondsSinceEpoch}',
      userId: uid,
      mediaPath: mediaPath,
      isVideo: isVideo,
      caption: initialCaption ?? '',
      createdAt: now,
      updatedAt: now,
    );

    state = state.copyWith(
      draft: newDraft,
      status: PostDraftStatus.idle,
    );
  }

  /// Updates draft fields in state and triggers an 800ms debounced auto-save.
  void updateDraft(PostDraft updatedDraft) {
    state = state.copyWith(draft: updatedDraft);
    _scheduleDebouncedSave();
  }

  void _scheduleDebouncedSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      saveImmediately();
    });
  }

  /// Forces an immediate save to Firestore & local storage.
  Future<void> saveImmediately() async {
    final current = state.draft;
    if (current == null) return;

    state = state.copyWith(status: PostDraftStatus.saving);
    try {
      await _repository.saveDraft(current);
      state = state.copyWith(
        status: PostDraftStatus.saved,
        lastSavedAt: DateTime.now(),
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        status: PostDraftStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Cleans up draft when published or explicitly discarded.
  Future<void> discardCurrentDraft() async {
    final id = state.draft?.id;
    _debounceTimer?.cancel();
    if (id != null) {
      await _repository.deleteDraft(id);
    }
    state = const PostDraftState();
  }
}

final postDraftProvider = NotifierProvider<PostDraftNotifier, PostDraftState>(PostDraftNotifier.new);
