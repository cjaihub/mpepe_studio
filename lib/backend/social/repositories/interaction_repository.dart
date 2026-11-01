import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reaction.dart';

final interactionRepositoryProvider = Provider<InteractionRepository>((ref) {
  return InteractionRepository(FirebaseFirestore.instance);
});

/// Canonical repository for all user→content interactions.
///
/// Rules:
/// - Every counter mutation uses [FieldValue.increment] inside [runTransaction].
/// - Every significant interaction publishes an event to [social_events].
/// - Every interaction is recorded under the user's profile document (`users/{userId}/...`).
/// - Likes, saves, and views enforce strict one-per-user deduplication.
/// - No mock data — counts reflect real Firestore state only.
class InteractionRepository {
  final FirebaseFirestore _firestore;

  InteractionRepository(this._firestore);

  // ─────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────

  void _publishEvent(Transaction tx, String type, Map<String, dynamic> payload) {
    final eventRef = _firestore.collection('social_events').doc();
    tx.set(eventRef, {
      'type': type,
      'payload': payload,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  String _interactionId(String userId, String contentId, String type) =>
      '${type}_${userId}_$contentId';

  // ─────────────────────────────────────────────────────────────────────
  // LIKE / UNLIKE
  // ─────────────────────────────────────────────────────────────────────

  Future<void> likeContent(String userId, String contentId, {String collectionName = 'content'}) async {
    final likeId = _interactionId(userId, contentId, 'like');
    final likeRef = _firestore.collection('${collectionName}_likes').doc(likeId);
    final userLikeRef = _firestore.collection('users').doc(userId).collection('likes').doc(contentId);
    final contentRef = _firestore.collection(collectionName).doc(contentId);
    final postRef = _firestore.collection('posts').doc(contentId);

    await _firestore.runTransaction((tx) async {
      final likeDoc = await tx.get(likeRef);
      if (likeDoc.exists) return; // Enforce one like per person (idempotent)

      final userLikeDoc = await tx.get(userLikeRef);
      if (userLikeDoc.exists) return;

      final contentDoc = await tx.get(contentRef);
      final postDoc = (collectionName != 'posts') ? await tx.get(postRef) : null;

      if (!contentDoc.exists && (postDoc == null || !postDoc.exists)) {
        return;
      }

      final likeData = {
        'userId': userId,
        'contentId': contentId,
        'collectionName': collectionName,
        'createdAt': FieldValue.serverTimestamp(),
      };

      tx.set(likeRef, likeData);
      tx.set(userLikeRef, likeData);

      String? authorId;
      if (contentDoc.exists) {
        authorId = contentDoc.data()?['authorId'];
        tx.update(contentRef, {
          collectionName == 'posts' ? 'reactionCount' : 'likeCount': FieldValue.increment(1),
        });
      }

      if (postDoc != null && postDoc.exists) {
        authorId ??= postDoc.data()?['authorId'];
        tx.update(postRef, {'reactionCount': FieldValue.increment(1)});
      }

      _publishEvent(tx, '$collectionName.liked', {
        'userId': userId,
        'contentId': contentId,
        'authorId': authorId,
      });

      // Also notify author directly in real time
      if (authorId != null && authorId.isNotEmpty && authorId != userId) {
        final notifRef = _firestore.collection('notifications').doc();
        tx.set(notifRef, {
          'userId': authorId,
          'recipientId': authorId,
          'title': 'New Like',
          'message': 'Someone liked your video',
          'body': 'Someone liked your video',
          'type': 'social',
          'category': 'like',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'timestamp': FieldValue.serverTimestamp(),
          'payload': {
            'contentId': contentId,
            'userId': userId,
          },
        });
      }
    });
  }

  Future<void> unlikeContent(String userId, String contentId, {String collectionName = 'content'}) async {
    final likeId = _interactionId(userId, contentId, 'like');
    final likeRef = _firestore.collection('${collectionName}_likes').doc(likeId);
    final userLikeRef = _firestore.collection('users').doc(userId).collection('likes').doc(contentId);
    final contentRef = _firestore.collection(collectionName).doc(contentId);
    final postRef = _firestore.collection('posts').doc(contentId);

    await _firestore.runTransaction((tx) async {
      // Firestore transactions require every read before the first write.
      final likeDoc = await tx.get(likeRef);
      final userLikeDoc = await tx.get(userLikeRef);
      if (!likeDoc.exists && !userLikeDoc.exists) return; // idempotent
      final contentDoc = await tx.get(contentRef);
      final postDoc = collectionName != 'posts' ? await tx.get(postRef) : null;

      tx.delete(likeRef);
      tx.delete(userLikeRef);

      if (contentDoc.exists) {
        tx.update(contentRef, {
          collectionName == 'posts' ? 'reactionCount' : 'likeCount': FieldValue.increment(-1),
        });
      }

      if (postDoc != null && postDoc.exists) {
        tx.update(postRef, {'reactionCount': FieldValue.increment(-1)});
      }

      _publishEvent(tx, '$collectionName.unliked', {'userId': userId, 'contentId': contentId});
    });
  }

  /// Toggle like. Returns the new liked state (true = now liked).
  Future<bool> toggleLike(String userId, String contentId) async {
    final isLiked = await isContentLikedBy(userId, contentId);
    if (isLiked) {
      await unlikeContent(userId, contentId);
      return false;
    } else {
      await likeContent(userId, contentId);
      return true;
    }
  }

  Stream<bool> watchIsLiked(String userId, String contentId) {
    if (userId.isEmpty) return Stream.value(false);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('likes')
        .doc(contentId)
        .snapshots()
        .map((s) => s.exists);
  }

  Future<bool> isContentLikedBy(String userId, String contentId) async {
    if (userId.isEmpty) return false;
    final userLikeDoc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('likes')
        .doc(contentId)
        .get();
    if (userLikeDoc.exists) return true;

    final doc = await _firestore
        .collection('content_likes')
        .doc(_interactionId(userId, contentId, 'like'))
        .get();
    return doc.exists;
  }

  // ─────────────────────────────────────────────────────────────────────
  // SAVE / UNSAVE
  // ─────────────────────────────────────────────────────────────────────

  Future<void> saveContent(String userId, String contentId, {String? collectionId}) async {
    final saveId = _interactionId(userId, contentId, 'save');
    final saveRef = _firestore.collection('content_saves').doc(saveId);
    final userSaveRef = _firestore.collection('users').doc(userId).collection('saved').doc(contentId);
    final contentRef = _firestore.collection('content').doc(contentId);
    final postRef = _firestore.collection('posts').doc(contentId);

    await _firestore.runTransaction((tx) async {
      final saveDoc = await tx.get(saveRef);
      final userSaveDoc = await tx.get(userSaveRef);
      if (saveDoc.exists || userSaveDoc.exists) return; // Enforce one save per person

      final contentDoc = await tx.get(contentRef);
      final postDoc = await tx.get(postRef);
      if (!contentDoc.exists && !postDoc.exists) return;

      final saveData = {
        'userId': userId,
        'contentId': contentId,
        'collectionId': collectionId,
        'savedAt': FieldValue.serverTimestamp(),
      };

      tx.set(saveRef, saveData);
      tx.set(userSaveRef, saveData);

      if (contentDoc.exists) {
        tx.update(contentRef, {'saveCount': FieldValue.increment(1)});
      }
      if (postDoc.exists) {
        tx.update(postRef, {'saveCount': FieldValue.increment(1)});
      }

      _publishEvent(tx, 'content.saved', {'userId': userId, 'contentId': contentId});
    });
  }

  Future<void> unsaveContent(String userId, String contentId) async {
    final saveId = _interactionId(userId, contentId, 'save');
    final saveRef = _firestore.collection('content_saves').doc(saveId);
    final userSaveRef = _firestore.collection('users').doc(userId).collection('saved').doc(contentId);
    final contentRef = _firestore.collection('content').doc(contentId);
    final postRef = _firestore.collection('posts').doc(contentId);

    await _firestore.runTransaction((tx) async {
      final saveDoc = await tx.get(saveRef);
      final userSaveDoc = await tx.get(userSaveRef);
      if (!saveDoc.exists && !userSaveDoc.exists) return;
      // Firestore transactions require every read before the first write.
      final contentDoc = await tx.get(contentRef);
      final postDoc = await tx.get(postRef);

      tx.delete(saveRef);
      tx.delete(userSaveRef);

      if (contentDoc.exists) {
        tx.update(contentRef, {'saveCount': FieldValue.increment(-1)});
      }
      if (postDoc.exists) {
        tx.update(postRef, {'saveCount': FieldValue.increment(-1)});
      }

      _publishEvent(tx, 'content.unsaved', {'userId': userId, 'contentId': contentId});
    });
  }

  Stream<bool> watchIsSaved(String userId, String contentId) {
    if (userId.isEmpty) return Stream.value(false);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('saved')
        .doc(contentId)
        .snapshots()
        .map((s) => s.exists);
  }

  // ─────────────────────────────────────────────────────────────────────
  // REPOST / SHARE
  // ─────────────────────────────────────────────────────────────────────

  Future<void> repostContent(String userId, String contentId) async {
    final repostId = _interactionId(userId, contentId, 'repost');
    final repostRef = _firestore.collection('content_reposts').doc(repostId);
    final userShareRef = _firestore.collection('users').doc(userId).collection('shares').doc(contentId);
    final contentRef = _firestore.collection('content').doc(contentId);
    final postRef = _firestore.collection('posts').doc(contentId);

    await _firestore.runTransaction((tx) async {
      final repostDoc = await tx.get(repostRef);
      if (repostDoc.exists) return;

      final contentDoc = await tx.get(contentRef);
      final postDoc = await tx.get(postRef);
      if (!contentDoc.exists && !postDoc.exists) return;

      final shareData = {
        'userId': userId,
        'contentId': contentId,
        'sharedAt': FieldValue.serverTimestamp(),
      };

      tx.set(repostRef, shareData);
      tx.set(userShareRef, shareData);

      String? authorId;
      if (contentDoc.exists) {
        authorId = contentDoc.data()?['authorId'];
        tx.update(contentRef, {
          'repostCount': FieldValue.increment(1),
          'shareCount': FieldValue.increment(1),
        });
      }
      if (postDoc.exists) {
        authorId ??= postDoc.data()?['authorId'];
        tx.update(postRef, {
          'repostCount': FieldValue.increment(1),
          'shareCount': FieldValue.increment(1),
        });
      }

      _publishEvent(tx, 'content.reposted', {
        'userId': userId,
        'contentId': contentId,
        'authorId': authorId,
      });
    });
  }

  Future<void> undoRepost(String userId, String contentId) async {
    final repostId = _interactionId(userId, contentId, 'repost');
    final repostRef = _firestore.collection('content_reposts').doc(repostId);
    final userShareRef = _firestore.collection('users').doc(userId).collection('shares').doc(contentId);
    final contentRef = _firestore.collection('content').doc(contentId);
    final postRef = _firestore.collection('posts').doc(contentId);

    await _firestore.runTransaction((tx) async {
      final repostDoc = await tx.get(repostRef);
      if (!repostDoc.exists) return;
      // Firestore transactions require every read before the first write.
      final contentDoc = await tx.get(contentRef);
      final postDoc = await tx.get(postRef);

      tx.delete(repostRef);
      tx.delete(userShareRef);

      if (contentDoc.exists) {
        tx.update(contentRef, {
          'repostCount': FieldValue.increment(-1),
          'shareCount': FieldValue.increment(-1),
        });
      }
      if (postDoc.exists) {
        tx.update(postRef, {
          'repostCount': FieldValue.increment(-1),
          'shareCount': FieldValue.increment(-1),
        });
      }

      _publishEvent(tx, 'content.unreposted', {'userId': userId, 'contentId': contentId});
    });
  }

  Stream<bool> watchIsReposted(String userId, String contentId) {
    if (userId.isEmpty) return Stream.value(false);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('shares')
        .doc(contentId)
        .snapshots()
        .map((s) => s.exists);
  }

  // ─────────────────────────────────────────────────────────────────────
  // VIEW COUNT (One view per person)
  // ─────────────────────────────────────────────────────────────────────

  /// Records a view. Deduped per user per content: each person only increments count once.
  Future<void> recordView(String userId, String contentId) async {
    if (userId.isEmpty) return;
    final viewId = _interactionId(userId, contentId, 'view');
    final viewRef = _firestore.collection('content_views').doc(viewId);
    final userViewRef = _firestore.collection('users').doc(userId).collection('views').doc(contentId);
    final contentRef = _firestore.collection('content').doc(contentId);
    final postRef = _firestore.collection('posts').doc(contentId);

    await _firestore.runTransaction((tx) async {
      final viewDoc = await tx.get(viewRef);
      final userViewDoc = await tx.get(userViewRef);
      if (viewDoc.exists || userViewDoc.exists) return; // Strictly count view once per person

      final contentDoc = await tx.get(contentRef);
      final postDoc = await tx.get(postRef);
      if (!contentDoc.exists && !postDoc.exists) return;

      final viewData = {
        'userId': userId,
        'contentId': contentId,
        'viewedAt': FieldValue.serverTimestamp(),
      };

      tx.set(viewRef, viewData);
      tx.set(userViewRef, viewData);

      if (contentDoc.exists) {
        tx.update(contentRef, {'viewCount': FieldValue.increment(1)});
      }
      if (postDoc.exists) {
        tx.update(postRef, {'viewCount': FieldValue.increment(1)});
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // GENERIC EMOJI REACTIONS (posts / comments)
  // ─────────────────────────────────────────────────────────────────────

  Future<void> addReaction({
    required String targetId,
    required String targetType, // 'post' or 'comment'
    required String userId,
    required String emoji,
  }) async {
    final reactionId = '${targetId}_${userId}_$emoji';
    final reactionRef = _firestore.collection('reactions').doc(reactionId);
    final collectionName = targetType == 'post' ? 'posts' : 'comments';
    final targetRef = _firestore.collection(collectionName).doc(targetId);

    await _firestore.runTransaction((transaction) async {
      final targetDoc = await transaction.get(targetRef);
      if (!targetDoc.exists) return;

      final reactionDoc = await transaction.get(reactionRef);
      if (reactionDoc.exists) return;

      final reaction = Reaction(
        id: reactionId,
        targetId: targetId,
        targetType: targetType,
        userId: userId,
        emoji: emoji,
        createdAt: DateTime.now(),
      );

      transaction.set(reactionRef, reaction.toMap());
      transaction.update(targetRef, {'reactionCount': FieldValue.increment(1)});
    });
  }

  Future<void> removeReaction({
    required String targetId,
    required String targetType,
    required String userId,
    required String emoji,
  }) async {
    final reactionId = '${targetId}_${userId}_$emoji';
    final reactionRef = _firestore.collection('reactions').doc(reactionId);
    final collectionName = targetType == 'post' ? 'posts' : 'comments';
    final targetRef = _firestore.collection(collectionName).doc(targetId);

    await _firestore.runTransaction((transaction) async {
      final targetDoc = await transaction.get(targetRef);
      if (!targetDoc.exists) return;

      final reactionDoc = await transaction.get(reactionRef);
      if (!reactionDoc.exists) return;

      transaction.delete(reactionRef);
      transaction.update(targetRef, {'reactionCount': FieldValue.increment(-1)});
    });
  }
}
