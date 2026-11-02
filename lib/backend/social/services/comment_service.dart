import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/comment.dart';
import '../models/comment_settings.dart';

final commentServiceProvider = Provider<CommentService>((ref) {
  return CommentService();
});

class CommentAuthorizationException implements Exception {
  final String message;
  CommentAuthorizationException(this.message);

  @override
  String toString() => 'CommentAuthorizationException: $message';
}

class CommentService {
  final FirebaseFirestore _firestore;

  CommentService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final Map<String, CommentSettings> _settings = {};

  // user_id + post_id -> last comment time for slow mode tracking
  final Map<String, DateTime> _lastCommentTime = {};

  Future<CommentSettings> getSettings(String postId) async {
    // In a production app, fetch from Firestore. Using memory cache for now.
    return _settings[postId] ?? CommentSettings(postId: postId);
  }

  Future<void> updateSettings(CommentSettings settings) async {
    _settings[settings.postId] = settings;
  }

  Stream<List<Comment>> watchComments(
    String postId, {
    CommentSortType sort = CommentSortType.top,
  }) {
    late StreamController<List<Comment>> controller;
    StreamSubscription? subPosts;
    StreamSubscription? subContent;
    List<Comment> postComments = const [];
    List<Comment> contentComments = const [];

    void emitMerged() {
      if (controller.isClosed) return;
      final Map<String, Comment> map = {};
      for (final c in postComments) {
        map[c.id] = c;
      }
      for (final c in contentComments) {
        map[c.id] = c;
      }
      final merged = map.values.where((c) => !c.isModerated).toList();
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(merged);
    }

    controller = StreamController<List<Comment>>.broadcast(
      onListen: () {
        // Stream from posts/{postId}/comments
        try {
          subPosts = _firestore
              .collection('posts')
              .doc(postId)
              .collection('comments')
              .orderBy('createdAt', descending: true)
              .snapshots()
              .listen(
                (snap) {
                  postComments = snap.docs.map((doc) => Comment.fromFirestore(doc)).toList();
                  emitMerged();
                },
                onError: (e) {
                  // Silently ignore if collection doesn't exist under posts
                  debugPrint('[CommentService] posts sub notice: $e');
                },
              );
        } catch (_) {}

        // Stream from content/{postId}/comments (standard reels location)
        try {
          subContent = _firestore
              .collection('content')
              .doc(postId)
              .collection('comments')
              .orderBy('createdAt', descending: true)
              .snapshots()
              .listen(
                (snap) {
                  contentComments = snap.docs.map((doc) => Comment.fromFirestore(doc)).toList();
                  emitMerged();
                },
                onError: (e) {
                  // Silently ignore if collection doesn't exist under content
                  debugPrint('[CommentService] content sub notice: $e');
                },
              );
        } catch (_) {}
      },
      onCancel: () {
        subPosts?.cancel();
        subContent?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> addComment(
    Comment comment, {
    bool isCreator = false,
    bool isFriend = false,
    bool isFollower = false,
  }) async {
    final settings = await getSettings(comment.postId);

    // 1. Comments On/Off & Permissions
    if (settings.permission == CommentPermission.nobody && !isCreator) {
      throw CommentAuthorizationException(
        'Comments are disabled for this post.',
      );
    }
    if (settings.permission == CommentPermission.friends &&
        !isFriend &&
        !isCreator) {
      throw CommentAuthorizationException(
        'Only friends can comment on this post.',
      );
    }
    if (settings.permission == CommentPermission.followers &&
        !isFollower &&
        !isFriend &&
        !isCreator) {
      throw CommentAuthorizationException(
        'Only followers can comment on this post.',
      );
    }

    // 2. Slow Mode
    if (settings.slowModeDelay != null && !isCreator) {
      final key = '${comment.authorId}_${comment.postId}';
      final lastTime = _lastCommentTime[key];
      if (lastTime != null) {
        final nextAllowed = lastTime.add(settings.slowModeDelay!);
        if (DateTime.now().isBefore(nextAllowed)) {
          throw CommentAuthorizationException(
            'Slow mode is active. Please wait before commenting again.',
          );
        }
      }
      _lastCommentTime[key] = DateTime.now();
    }

    // 3. Blocked Words
    final lowerContent = comment.content.toLowerCase();
    for (final word in settings.blockedWords) {
      if (lowerContent.contains(word.toLowerCase())) {
        throw CommentAuthorizationException('Comment contains blocked words.');
      }
    }

    // 4. Approval/Moderation
    bool requiresModeration = settings.requireApproval;
    for (final word in settings.keywordFilters) {
      if (lowerContent.contains(word.toLowerCase())) {
        requiresModeration = true;
      }
    }

    final String commentId = comment.id.isEmpty
        ? _firestore
              .collection('posts')
              .doc(comment.postId)
              .collection('comments')
              .doc()
              .id
        : comment.id;

    final finalComment = Comment(
      id: commentId,
      postId: comment.postId,
      authorId: comment.authorId,
      content: comment.content,
      type: comment.type,
      mentions: comment.mentions,
      mentionedUserIds: comment.mentionedUserIds,
      replyToId: comment.replyToId,
      reactionCount: comment.reactionCount,
      createdAt: comment.createdAt,
      isPinned: comment.isPinned,
      hasCreatorReply: comment.hasCreatorReply,
      isModerated: requiresModeration,
      videoReplyPostId: comment.videoReplyPostId,
      likerIds: comment.likerIds,
      voiceDurationMs: comment.voiceDurationMs,
      gif: comment.gif,
    );

    // Save to Firestore with atomic batch to update post comments, content comments, user profile, and counts
    final batch = _firestore.batch();
    final postRef = _firestore.collection('posts').doc(comment.postId);
    final contentRef = _firestore.collection('content').doc(comment.postId);
    // Counters may only be bumped on parents that exist: a merge-set on a
    // missing parent is a create, which the rules reserve for its author.
    final parents = await Future.wait([postRef.get(), contentRef.get()]);
    final postExists = parents[0].exists;
    final contentExists = parents[1].exists;
    final commentRef = _firestore
        .collection('posts')
        .doc(comment.postId)
        .collection('comments')
        .doc(commentId);
    final contentCommentRef = _firestore
        .collection('content')
        .doc(comment.postId)
        .collection('comments')
        .doc(commentId);
    final userCommentRef = _firestore
        .collection('users')
        .doc(comment.authorId)
        .collection('comments')
        .doc(commentId);

    if (postExists) {
      batch.set(commentRef, finalComment.toMap());
      batch.update(postRef, {
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (contentExists) {
      batch.set(contentCommentRef, finalComment.toMap());
      batch.update(contentRef, {
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (!postExists && !contentExists) {
      batch.set(contentCommentRef, finalComment.toMap());
    }
    batch.set(userCommentRef, {
      'commentId': commentId,
      'postId': comment.postId,
      'content': comment.content,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Keep post author and parent comment author in the loop with real-time notifications
    try {
      // 1. Post author notification
      final postAuthorId = (parents[1].data()?['authorId'] ?? parents[0].data()?['authorId']) as String?;
      final preview = comment.content.length > 50
          ? '${comment.content.substring(0, 47)}...'
          : comment.content;

      if (postAuthorId != null && postAuthorId.isNotEmpty && postAuthorId != comment.authorId) {
        await _firestore.collection('notifications').add({
          'userId': postAuthorId,
          'recipientId': postAuthorId,
          'title': 'New Comment',
          'message': 'Someone commented: "$preview"',
          'body': 'Someone commented: "$preview"',
          'type': 'social',
          'category': 'comment',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'timestamp': FieldValue.serverTimestamp(),
          'deepLink': '/hub/home?v=${comment.postId}',
          'payload': {
            'postId': comment.postId,
            'commentId': commentId,
            'authorId': comment.authorId,
          },
        });
      }

      // 2. Reply to parent comment notification
      if (comment.replyToId != null && comment.replyToId!.isNotEmpty) {
        final parentCommentDoc = await _firestore
            .collection('posts')
            .doc(comment.postId)
            .collection('comments')
            .doc(comment.replyToId)
            .get();
        final parentAuthorId = parentCommentDoc.data()?['authorId'] as String?;
        if (parentAuthorId != null && parentAuthorId.isNotEmpty && parentAuthorId != comment.authorId && parentAuthorId != postAuthorId) {
          await _firestore.collection('notifications').add({
            'userId': parentAuthorId,
            'recipientId': parentAuthorId,
            'title': 'New Reply',
            'message': 'Someone replied to your comment: "$preview"',
            'body': 'Someone replied to your comment: "$preview"',
            'type': 'social',
            'category': 'reply',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
            'timestamp': FieldValue.serverTimestamp(),
            'deepLink': '/hub/home?v=${comment.postId}',
            'payload': {
              'postId': comment.postId,
              'commentId': commentId,
              'replyToId': comment.replyToId,
              'authorId': comment.authorId,
            },
          });
        }
      }
    } catch (_) {}
  }

  Future<void> reactToComment(
    String postId,
    String commentId, {
    required String userId,
    required bool isLike,
  }) async {
    final commentRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
    final contentCommentRef = _firestore
        .collection('content')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
    final userReactionRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('comment_likes')
        .doc(commentId);

    // Transaction keyed on the user's reaction doc keeps comment likes
    // one-per-user even with rapid taps or stale UI state.
    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(userReactionRef);
      if (isLike == existing.exists) return;
      // Only touch the copies that exist; a merge-set on a missing comment
      // would be a create without authorId, which the rules reject.
      final postCopy = await tx.get(commentRef);
      final contentCopy = await tx.get(contentCommentRef);
      if (!postCopy.exists && !contentCopy.exists) return;

      final delta = isLike ? 1 : -1;
      final likers = isLike ? FieldValue.arrayUnion([userId]) : FieldValue.arrayRemove([userId]);
      if (isLike) {
        tx.set(userReactionRef, {
          'commentId': commentId,
          'postId': postId,
          'likedAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.delete(userReactionRef);
      }
      final update = {'reactionCount': FieldValue.increment(delta), 'likerIds': likers};
      if (postCopy.exists) tx.update(commentRef, update);
      if (contentCopy.exists) tx.update(contentCommentRef, update);
    });
  }

  /// Deletes a comment written by [userId] (or any comment on a post they
  /// own) and keeps the counters in step, all in one transaction.
  Future<void> deleteComment({
    required String postId,
    required String commentId,
    required String userId,
  }) async {
    final commentRef = _firestore.collection('posts').doc(postId).collection('comments').doc(commentId);
    final contentCommentRef = _firestore.collection('content').doc(postId).collection('comments').doc(commentId);
    final contentRef = _firestore.collection('content').doc(postId);
    final postRef = _firestore.collection('posts').doc(postId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(commentRef);
      final altSnap = snap.exists ? snap : await tx.get(contentCommentRef);
      if (!altSnap.exists) return;
      final authorId = altSnap.data()?['authorId'] as String?;
      final content = await tx.get(contentRef);
      final post = await tx.get(postRef);
      final postOwner = (content.data()?['authorId'] ?? post.data()?['authorId']) as String?;
      if (authorId != userId && postOwner != userId) {
        throw CommentAuthorizationException('You can only delete your own comments.');
      }
      tx.delete(commentRef);
      tx.delete(contentCommentRef);
      if (authorId != null) {
        tx.delete(_firestore.collection('users').doc(authorId).collection('comments').doc(commentId));
      }
      if (content.exists) tx.update(contentRef, {'commentCount': FieldValue.increment(-1)});
      if (post.exists) tx.update(postRef, {'commentCount': FieldValue.increment(-1)});
    });
  }

  Future<void> pinComment(String postId, String commentId) async {
    final refs = [
      _firestore.collection('posts').doc(postId).collection('comments').doc(commentId),
      _firestore.collection('content').doc(postId).collection('comments').doc(commentId),
    ];
    final snaps = await Future.wait(refs.map((r) => r.get()));
    final batch = _firestore.batch();
    for (var i = 0; i < refs.length; i++) {
      if (snaps[i].exists) batch.update(refs[i], {'isPinned': true});
    }
    await batch.commit();
  }
}
