import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/collection.dart';

final collectionServiceProvider = Provider<CollectionService>((ref) {
  return CollectionService();
});

class CollectionService {
  final Map<String, UserCollectionProgress> _progressMap = {};
  
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<MediaCollection>> getUserCollections(String userId) async {
    try {
      final snap = await _db.collection('collections').where('creatorId', isEqualTo: userId).get();
      return [for (final d in snap.docs) MediaCollection.fromMap(d.id, d.data())];
    } catch (_) {
      return const [];
    }
  }

  /// Null when missing or not readable (shows "Collection not found").
  Future<MediaCollection?> getCollection(String collectionId) async {
    try {
      final doc = await _db.collection('collections').doc(collectionId).get();
      final data = doc.data();
      return data == null ? null : MediaCollection.fromMap(doc.id, data);
    } catch (_) {
      return null;
    }
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
