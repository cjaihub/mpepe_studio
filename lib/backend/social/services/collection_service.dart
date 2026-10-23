import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/collection.dart';

final collectionServiceProvider = Provider<CollectionService>((ref) {
  return CollectionService();
});

class CollectionService {
  final Map<String, UserCollectionProgress> _progressMap = {};
  
  Future<List<MediaCollection>> getUserCollections(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      MediaCollection.mockPlaylist(),
      MediaCollection.mockPremiumSeries(),
    ];
  }

  Future<MediaCollection> getCollection(String collectionId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return MediaCollection.mockPremiumSeries(); // Just return mock for now
  }

  Future<UserCollectionProgress?> getProgress(String collectionId) async {
    return _progressMap[collectionId];
  }

  Future<void> updateProgress({
    required String collectionId,
    required String postId,
    required Duration position,
    bool markCompleted = false,
  }) async {
    final current = _progressMap[collectionId];
    
    List<String> completed = current?.completedPostIds.toList() ?? [];
    if (markCompleted && !completed.contains(postId)) {
      completed.add(postId);
    }
    
    _progressMap[collectionId] = UserCollectionProgress(
      collectionId: collectionId,
      lastWatchedPostId: postId,
      lastWatchedPosition: position,
      completedPostIds: completed,
    );
  }

  Future<void> followCollection(String collectionId) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> saveCollection(String collectionId) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
