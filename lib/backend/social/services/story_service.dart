import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/story.dart';

final storyServiceProvider = Provider<StoryService>((ref) {
  return StoryService();
});

final feedStoriesStreamProvider = StreamProvider.autoDispose<List<UserStoryGroup>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return ref.watch(storyServiceProvider).watchFeedStories(currentUserId: uid);
});

class UserStoryGroup {
  final String authorId;
  final String authorName;
  final String authorAvatarUrl;
  final List<Story> stories;
  final bool hasUnviewed;

  UserStoryGroup({
    required this.authorId,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.stories,
    required this.hasUnviewed,
  });
}

class StoryService {
  final FirebaseFirestore _firestore;

  StoryService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> createStory(Story story) async {
    await _firestore.collection('stories').doc(story.id).set(story.toMap());

    // Update author profile document
    try {
      await _firestore.collection('users').doc(story.authorId).set({
        'hasActiveStory': true,
        'lastStoryAt': FieldValue.serverTimestamp(),
        'storyCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {}

    // Dispatch real-time notifications to followers to keep them in the loop
    try {
      final followersSnap = await _firestore
          .collection('relationships')
          .where('followingId', isEqualTo: story.authorId)
          .where('status', isEqualTo: 'accepted')
          .limit(25)
          .get();

      final batch = _firestore.batch();
      for (final doc in followersSnap.docs) {
        final followerId = doc.data()['followerId'] as String?;
        if (followerId != null && followerId.isNotEmpty && followerId != story.authorId) {
          final notifRef = _firestore.collection('notifications').doc();
          batch.set(notifRef, {
            'userId': followerId,
            'recipientId': followerId,
            'title': 'New Story from ${story.authorName.isNotEmpty ? story.authorName : "a creator"}',
            'message': '${story.authorName.isNotEmpty ? story.authorName : "Someone you follow"} shared a new status',
            'body': '${story.authorName.isNotEmpty ? story.authorName : "Someone you follow"} shared a new status',
            'type': 'social',
            'category': 'story',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
            'timestamp': FieldValue.serverTimestamp(),
            'payload': {
              'storyId': story.id,
              'authorId': story.authorId,
              'avatarUrl': story.authorAvatarUrl,
            },
          });
        }
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Records that [userId] viewed [storyId].
  /// Enforces that each user views a story/status count strictly ONCE.
  Future<void> recordStoryView(
    String storyId,
    String userId, {
    String? viewerName,
    String? viewerAvatar,
  }) async {
    if (userId.isEmpty || storyId.isEmpty) return;

    final storyRef = _firestore.collection('stories').doc(storyId);
    final userStoryViewRef = _firestore.collection('users').doc(userId).collection('story_views').doc(storyId);
    final viewerDetailRef = storyRef.collection('viewers').doc(userId);

    try {
      final userViewDoc = await userStoryViewRef.get();
      if (userViewDoc.exists) return; // Strictly count view once per person

      final storyDoc = await storyRef.get();
      if (!storyDoc.exists) return;

      final data = storyDoc.data() as Map<String, dynamic>;
      final viewers = List<String>.from(data['viewers'] ?? []);

      final viewRecord = {
        'storyId': storyId,
        'viewedAt': FieldValue.serverTimestamp(),
      };
      await userStoryViewRef.set(viewRecord);

      await viewerDetailRef.set({
        'userId': userId,
        'displayName': viewerName ?? 'Viewer',
        'avatarUrl': viewerAvatar ?? '',
        'viewedAt': FieldValue.serverTimestamp(),
      });

      if (!viewers.contains(userId)) {
        await storyRef.update({
          'viewers': FieldValue.arrayUnion([userId]),
          'viewCount': FieldValue.increment(1),
        });
      }
    } catch (_) {}
  }

  /// Stream of active unexpired stories grouped by author for real-time UI/UX.
  Stream<List<UserStoryGroup>> watchFeedStories({String? currentUserId}) {
    return _firestore
        .collection('stories')
        .where('lifecycle', isEqualTo: StoryLifecycle.active.name)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final stories = snapshot.docs
              .map((doc) => Story.fromMap(doc.data()))
              .where((s) => !s.isExpired && s.expiresAt.isAfter(now))
              .toList();

          // Sort stories by creation time
          stories.sort((a, b) => a.createdAt.compareTo(b.createdAt));

          final Map<String, List<Story>> byAuthor = {};
          for (final s in stories) {
            byAuthor.putIfAbsent(s.authorId, () => []).add(s);
          }

          return byAuthor.entries.map((entry) {
            final first = entry.value.first;
            final hasUnviewed = (currentUserId != null && currentUserId.isNotEmpty)
                ? entry.value.any((st) => !st.viewers.contains(currentUserId))
                : true;

            return UserStoryGroup(
              authorId: entry.key,
              authorName: first.authorName.isNotEmpty ? first.authorName : 'Creator',
              authorAvatarUrl: first.authorAvatarUrl,
              stories: entry.value,
              hasUnviewed: hasUnviewed,
            );
          }).toList();
        });
  }

  Future<List<UserStoryGroup>> getFeedStories({String? currentUserId}) async {
    final now = DateTime.now();
    final snapshot = await _firestore
        .collection('stories')
        .where('lifecycle', isEqualTo: StoryLifecycle.active.name)
        .get();

    final stories = snapshot.docs
        .map((doc) => Story.fromMap(doc.data()))
        .where((s) => !s.isExpired && s.expiresAt.isAfter(now))
        .toList();

    stories.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final Map<String, List<Story>> byAuthor = {};
    for (final s in stories) {
      byAuthor.putIfAbsent(s.authorId, () => []).add(s);
    }

    return byAuthor.entries.map((entry) {
      final first = entry.value.first;
      final hasUnviewed = (currentUserId != null && currentUserId.isNotEmpty)
          ? entry.value.any((st) => !st.viewers.contains(currentUserId))
          : true;

      return UserStoryGroup(
        authorId: entry.key,
        authorName: first.authorName.isNotEmpty ? first.authorName : 'Creator',
        authorAvatarUrl: first.authorAvatarUrl,
        stories: entry.value,
        hasUnviewed: hasUnviewed,
      );
    }).toList();
  }

  Future<void> reactToStory(String storyId, String userId, String emoji) async {
    if (userId.isEmpty || storyId.isEmpty) return;

    final storyRef = _firestore.collection('stories').doc(storyId);
    final userReactionRef = _firestore.collection('users').doc(userId).collection('story_reactions').doc(storyId);

    await _firestore.runTransaction((tx) async {
      final storyDoc = await tx.get(storyRef);
      if (!storyDoc.exists) return;

      tx.set(userReactionRef, {
        'storyId': storyId,
        'emoji': emoji,
        'reactedAt': FieldValue.serverTimestamp(),
      });

      tx.update(storyRef, {
        'reactions.$userId': emoji,
      });
    });
  }

  Future<void> replyToStory(String storyId, String userId, String message) async {
    if (storyId.isEmpty) return;
    await _firestore.collection('stories').doc(storyId).update({
      'replyCount': FieldValue.increment(1),
    });
  }

  Future<bool> toggleStoryLike(
    String storyId,
    String userId, {
    String? userName,
    String? userAvatar,
    String? storyAuthorId,
  }) async {
    if (userId.isEmpty || storyId.isEmpty) return false;

    final storyRef = _firestore.collection('stories').doc(storyId);
    final likeDetailRef = storyRef.collection('likes').doc(userId);

    final storyDoc = await storyRef.get();
    if (!storyDoc.exists) return false;

    final data = storyDoc.data() as Map<String, dynamic>;
    final likes = List<String>.from(data['likes'] ?? []);
    final isLiked = likes.contains(userId);

    if (isLiked) {
      await storyRef.update({
        'likes': FieldValue.arrayRemove([userId]),
      });
      await likeDetailRef.delete();
      return false;
    } else {
      await storyRef.update({
        'likes': FieldValue.arrayUnion([userId]),
      });
      await likeDetailRef.set({
        'userId': userId,
        'displayName': userName ?? 'User',
        'avatarUrl': userAvatar ?? '',
        'likedAt': FieldValue.serverTimestamp(),
      });

      // Notify the author if not self
      final authorId = storyAuthorId ?? data['authorId'] as String?;
      if (authorId != null && authorId.isNotEmpty && authorId != userId) {
        try {
          await _firestore.collection('notifications').add({
            'recipientId': authorId,
            'title': 'New Story Like',
            'body': '${userName ?? "Someone"} liked your status',
            'category': 'like',
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
            'payload': {
              'storyId': storyId,
              'userId': userId,
              'avatarUrl': userAvatar ?? '',
            },
          });
        } catch (_) {}
      }
      return true;
    }
  }

  Stream<List<Map<String, dynamic>>> streamStoryViewers(String storyId) {
    return _firestore
        .collection('stories')
        .doc(storyId)
        .collection('viewers')
        .orderBy('viewedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> streamStoryLikes(String storyId) {
    return _firestore
        .collection('stories')
        .doc(storyId)
        .collection('likes')
        .orderBy('likedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Future<void> deleteStory(String storyId) async {
    try {
      final storyDoc = await _firestore.collection('stories').doc(storyId).get();
      final authorId = storyDoc.data()?['authorId'] as String?;
      await _firestore.collection('stories').doc(storyId).delete();

      if (authorId != null && authorId.isNotEmpty) {
        final now = DateTime.now();
        final remainingSnap = await _firestore
            .collection('stories')
            .where('authorId', isEqualTo: authorId)
            .where('lifecycle', isEqualTo: StoryLifecycle.active.name)
            .get();
        final remainingActive = remainingSnap.docs
            .map((d) => Story.fromMap(d.data()))
            .where((s) => !s.isExpired && s.expiresAt.isAfter(now))
            .toList();

        if (remainingActive.isEmpty) {
          await _firestore.collection('users').doc(authorId).set({
            'hasActiveStory': false,
          }, SetOptions(merge: true));
        }
      }
    } catch (_) {
      await _firestore.collection('stories').doc(storyId).delete();
    }
  }
}
