import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/relationship.dart';

final relationshipRepositoryProvider = Provider<RelationshipRepository>((ref) {
  return RelationshipRepository(FirebaseFirestore.instance);
});

/// Live follow state for (me, them).
final followStateProvider = StreamProvider.autoDispose
    .family<FollowState, ({String me, String them})>((ref, ids) {
  return ref.watch(relationshipRepositoryProvider).watchFollowState(ids.me, ids.them);
});

class RelationshipRepository {
  final FirebaseFirestore _firestore;

  RelationshipRepository([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  void _publishEvent(Transaction tx, String type, Map<String, dynamic> payload) {
    final eventRef = _firestore.collection('social_events').doc();
    tx.set(eventRef, {
      'type': type,
      'payload': payload,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Helper to get the canonical doc ID for a relation where A acts on B
  String _relId(String a, String b) => '${a}_$b';

  Future<void> _checkTargetNotBlocking(Transaction tx, String currentUserId, String targetUserId) async {
    final reverseRelRef = _firestore.collection('relationships').doc(_relId(targetUserId, currentUserId));
    final reverseDoc = await tx.get(reverseRelRef);
    if (reverseDoc.exists) {
      final reverseRel = Relationship.fromFirestore(reverseDoc);
      if (reverseRel.status == RelationshipStatus.blocked) {
        throw Exception("Cannot perform action. Target user has blocked this user.");
      }
    }
  }

  /// Follow a user or send a follow request
  Future<void> followUser(String currentUserId, String targetUserId) async {
    if (currentUserId == targetUserId) return;

    final relRef = _firestore.collection('relationships').doc(_relId(currentUserId, targetUserId));
    final currentUserRef = _firestore.collection('users').doc(currentUserId);
    final targetUserRef = _firestore.collection('users').doc(targetUserId);

    await _firestore.runTransaction((tx) async {
      await _checkTargetNotBlocking(tx, currentUserId, targetUserId);

      final targetDoc = await tx.get(targetUserRef);
      if (!targetDoc.exists) throw Exception("This account no longer exists.");
      final meDoc = await tx.get(currentUserRef);
      final actorName = _displayName(meDoc.data());
      final targetData = targetDoc.data() as Map<String, dynamic>;
      // Read privacy from defaultPrivacyMode directly
      final privacyStr = targetData['defaultPrivacyMode'] ?? 'public';

      final relDoc = await tx.get(relRef);
      Relationship? existingRel;
      if (relDoc.exists) {
        existingRel = Relationship.fromFirestore(relDoc);
        if (existingRel.status == RelationshipStatus.accepted || existingRel.status == RelationshipStatus.pending) {
          return; // Already following or requested
        }
      }

      final isPrivate = targetData['isPrivate'] == true || privacyStr == 'private' || privacyStr == 'friends';
      final newStatus = isPrivate ? RelationshipStatus.pending : RelationshipStatus.accepted;

      if (existingRel != null) {
        tx.update(relRef, {
          'status': newStatus.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final newRel = Relationship(
          id: _relId(currentUserId, targetUserId),
          followerId: currentUserId,
          followingId: targetUserId,
          status: newStatus,
          createdAt: DateTime.now(),
        );
        tx.set(relRef, newRel.toMap());
      }

      if (newStatus == RelationshipStatus.accepted) {
        tx.update(currentUserRef, {'following': FieldValue.increment(1)});
        tx.update(targetUserRef, {'followers': FieldValue.increment(1)});
        _publishEvent(tx, 'follow.created', {
          'followerId': currentUserId,
          'followingId': targetUserId,
        });

        // Real-time notification to the followed user
        tx.set(_firestore.collection('notifications').doc(), _followNotification(
          recipientId: targetUserId,
          actorId: currentUserId,
          category: 'newFollower',
          title: 'New follower',
          body: '$actorName started following you',
        ));
      } else if (newStatus == RelationshipStatus.pending) {
        _publishEvent(tx, 'follow.requested', {
          'followerId': currentUserId,
          'followingId': targetUserId,
        });
        tx.set(_firestore.collection('notifications').doc(), _followNotification(
          recipientId: targetUserId,
          actorId: currentUserId,
          category: 'followRequest',
          title: 'Follow request',
          body: '$actorName wants to follow you',
        ));
      }
    });
  }

  /// Withdraw a pending follow request (same as unfollow for a pending rel).
  Future<void> cancelFollowRequest(String currentUserId, String targetUserId) =>
      unfollowUser(currentUserId, targetUserId);

  static String _displayName(Map<String, dynamic>? d) {
    if (d == null) return 'Someone';
    for (final k in ['fullName', 'displayName', 'username']) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return 'Someone';
  }

  Map<String, dynamic> _followNotification({
    required String recipientId,
    required String actorId,
    required String category,
    required String title,
    required String body,
  }) {
    return {
      'userId': recipientId,
      'recipientId': recipientId,
      'actorId': actorId,
      'title': title,
      'message': body,
      'body': body,
      'type': 'social',
      'category': category,
      'priority': 'normal',
      'deepLink': '/profile/$actorId',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
      'payload': {'followerId': actorId},
    };
  }

  /// Unfollow a user
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    final relRef = _firestore.collection('relationships').doc(_relId(currentUserId, targetUserId));
    final currentUserRef = _firestore.collection('users').doc(currentUserId);
    final targetUserRef = _firestore.collection('users').doc(targetUserId);

    await _firestore.runTransaction((tx) async {
      final relDoc = await tx.get(relRef);
      if (!relDoc.exists) return;
      
      final rel = Relationship.fromFirestore(relDoc);
      if (rel.status == RelationshipStatus.accepted) {
        tx.update(currentUserRef, {'following': FieldValue.increment(-1)});
        tx.update(targetUserRef, {'followers': FieldValue.increment(-1)});
      }

      if (rel.isBlocked || rel.isMuted || rel.isRestricted) {
        // Just reset the status, preserve block/mute/restrict
        tx.update(relRef, {'status': RelationshipStatus.none.name});
      } else {
        tx.delete(relRef);
      }

      _publishEvent(tx, 'follow.removed', {
        'followerId': currentUserId,
        'followingId': targetUserId,
      });
    });
  }

  /// Accept a follow request
  Future<void> acceptFollowRequest(String currentUserId, String requesterId) async {
    final relRef = _firestore.collection('relationships').doc(_relId(requesterId, currentUserId));
    final requesterRef = _firestore.collection('users').doc(requesterId);
    final currentUserRef = _firestore.collection('users').doc(currentUserId);

    await _firestore.runTransaction((tx) async {
      final relDoc = await tx.get(relRef);
      if (!relDoc.exists) return;
      
      final rel = Relationship.fromFirestore(relDoc);
      if (rel.status != RelationshipStatus.pending) return;

      tx.update(relRef, {'status': RelationshipStatus.accepted.name, 'updatedAt': FieldValue.serverTimestamp()});
      tx.update(requesterRef, {'following': FieldValue.increment(1)});
      tx.update(currentUserRef, {'followers': FieldValue.increment(1)});

      _publishEvent(tx, 'follow.accepted', {
        'followerId': requesterId,
        'followingId': currentUserId,
      });
      tx.set(_firestore.collection('notifications').doc(), _followNotification(
        recipientId: requesterId,
        actorId: currentUserId,
        category: 'newFollower',
        title: 'Request accepted',
        body: 'Your follow request was accepted',
      ));
    });
  }

  /// Decline a follow request
  Future<void> declineFollowRequest(String currentUserId, String requesterId) async {
    final relRef = _firestore.collection('relationships').doc(_relId(requesterId, currentUserId));

    await _firestore.runTransaction((tx) async {
      final relDoc = await tx.get(relRef);
      if (!relDoc.exists) return;
      
      final rel = Relationship.fromFirestore(relDoc);
      if (rel.status != RelationshipStatus.pending) return;

      if (rel.isBlocked || rel.isMuted || rel.isRestricted) {
        tx.update(relRef, {'status': RelationshipStatus.none.name});
      } else {
        tx.delete(relRef);
      }
    });
  }

  /// Remove a follower (force them to unfollow you)
  Future<void> removeFollower(String currentUserId, String followerId) async {
    final relRef = _firestore.collection('relationships').doc(_relId(followerId, currentUserId));
    final followerRef = _firestore.collection('users').doc(followerId);
    final currentUserRef = _firestore.collection('users').doc(currentUserId);

    await _firestore.runTransaction((tx) async {
      final relDoc = await tx.get(relRef);
      if (!relDoc.exists) return;
      
      final rel = Relationship.fromFirestore(relDoc);
      if (rel.status == RelationshipStatus.accepted) {
        tx.update(followerRef, {'following': FieldValue.increment(-1)});
        tx.update(currentUserRef, {'followers': FieldValue.increment(-1)});
      }

      if (rel.isBlocked || rel.isMuted || rel.isRestricted) {
        tx.update(relRef, {'status': RelationshipStatus.none.name});
      } else {
        tx.delete(relRef);
      }

      _publishEvent(tx, 'follower.removed', {
        'followerId': followerId,
        'followingId': currentUserId,
      });
    });
  }

  /// Block a user
  Future<void> blockUser(String currentUserId, String targetUserId) async {
    final relRef = _firestore.collection('relationships').doc(_relId(currentUserId, targetUserId));
    final reverseRelRef = _firestore.collection('relationships').doc(_relId(targetUserId, currentUserId));
    
    final currentUserRef = _firestore.collection('users').doc(currentUserId);
    final targetUserRef = _firestore.collection('users').doc(targetUserId);

    await _firestore.runTransaction((tx) async {
      final reverseDoc = await tx.get(reverseRelRef);
      final relDoc = await tx.get(relRef);

      // 1. Remove reverse follow if it exists
      if (reverseDoc.exists) {
        final reverseRel = Relationship.fromFirestore(reverseDoc);
        if (reverseRel.status == RelationshipStatus.accepted) {
          tx.update(targetUserRef, {'following': FieldValue.increment(-1)});
          tx.update(currentUserRef, {'followers': FieldValue.increment(-1)});
        }
        if (reverseRel.isBlocked || reverseRel.isMuted || reverseRel.isRestricted) {
          tx.update(reverseRelRef, {'status': RelationshipStatus.none.name});
        } else {
          tx.delete(reverseRelRef);
        }
      }

      // 2. Remove forward follow if it exists, apply block
      if (relDoc.exists) {
        final rel = Relationship.fromFirestore(relDoc);
        if (rel.status == RelationshipStatus.accepted) {
          tx.update(currentUserRef, {'following': FieldValue.increment(-1)});
          tx.update(targetUserRef, {'followers': FieldValue.increment(-1)});
        }
        tx.update(relRef, {
          'status': RelationshipStatus.blocked.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(relRef, {
          'followerId': currentUserId,
          'followingId': targetUserId,
          'status': RelationshipStatus.blocked.name,
          'isCloseFriend': false,
          'isFavorite': false,
          'isMuted': false,
          'isRestricted': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      _publishEvent(tx, 'user.blocked', {
        'userId': currentUserId,
        'targetId': targetUserId,
      });
    });
  }

  /// Unblock a user
  Future<void> unblockUser(String currentUserId, String targetUserId) async {
    final relRef = _firestore.collection('relationships').doc(_relId(currentUserId, targetUserId));
    await _firestore.runTransaction((tx) async {
      final relDoc = await tx.get(relRef);
      if (!relDoc.exists) return;
      final rel = Relationship.fromFirestore(relDoc);
      if (rel.status == RelationshipStatus.blocked) {
        if (rel.isMuted || rel.isRestricted) {
          tx.update(relRef, {'status': RelationshipStatus.none.name});
        } else {
          tx.delete(relRef);
        }
        
        _publishEvent(tx, 'user.unblocked', {
          'userId': currentUserId,
          'targetId': targetUserId,
        });
      }
    });
  }

  /// Toggle boolean flags
  Future<void> _toggleFlag(String currentUserId, String targetUserId, String field, bool value) async {
    final relRef = _firestore.collection('relationships').doc(_relId(currentUserId, targetUserId));
    await _firestore.runTransaction((tx) async {
      final relDoc = await tx.get(relRef);
      if (relDoc.exists) {
        tx.update(relRef, {field: value, 'updatedAt': FieldValue.serverTimestamp()});
      } else {
        tx.set(relRef, {
          'followerId': currentUserId,
          'followingId': targetUserId,
          'status': RelationshipStatus.none.name,
          'isCloseFriend': false,
          'isFavorite': false,
          'isMuted': false,
          'isRestricted': false,
          field: value,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> muteUser(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isMuted', true);
  Future<void> unmuteUser(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isMuted', false);

  Future<void> restrictUser(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isRestricted', true);
  Future<void> unrestrictUser(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isRestricted', false);

  Future<void> addCloseFriend(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isCloseFriend', true);
  Future<void> removeCloseFriend(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isCloseFriend', false);

  Future<void> addFavorite(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isFavorite', true);
  Future<void> removeFavorite(String currentUserId, String targetUserId) => _toggleFlag(currentUserId, targetUserId, 'isFavorite', false);

  /// Stream pending follow requests for a user
  Stream<List<Relationship>> watchPendingFollowRequests(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('relationships')
        .where('followingId', isEqualTo: userId)
        .where('status', isEqualTo: RelationshipStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Relationship.fromFirestore(doc)).toList());
  }

  /// Get pending follow requests count
  Stream<int> watchPendingFollowRequestsCount(String userId) {
    if (userId.isEmpty) return Stream.value(0);
    return _firestore
        .collection('relationships')
        .where('followingId', isEqualTo: userId)
        .where('status', isEqualTo: RelationshipStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Stream blocked users for a user
  Stream<List<Relationship>> watchBlockedUsers(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('relationships')
        .where('followerId', isEqualTo: userId)
        .where('status', isEqualTo: RelationshipStatus.blocked.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Relationship.fromFirestore(doc)).toList());
  }

  /// Get followers for a user
  Future<List<String>> getFollowers(String userId) async {
    final snapshot = await _firestore.collection('relationships')
        .where('followingId', isEqualTo: userId)
        .where('status', isEqualTo: RelationshipStatus.accepted.name)
        .get();
    return snapshot.docs.map((d) => d.data()['followerId'] as String).toList();
  }

  /// Get following for a user
  Future<List<String>> getFollowing(String userId) async {
    final snapshot = await _firestore.collection('relationships')
        .where('followerId', isEqualTo: userId)
        .where('status', isEqualTo: RelationshipStatus.accepted.name)
        .get();
    return snapshot.docs.map((d) => d.data()['followingId'] as String).toList();
  }

  /// Get mutual followers
  Future<List<String>> getMutualFollowers(String currentUserId, String targetUserId) async {
    final currentFollowing = await getFollowing(currentUserId);
    final targetFollowing = await getFollowing(targetUserId);
    return currentFollowing.where((id) => targetFollowing.contains(id)).toList();
  }

  /// Suggest connections (very basic: friends of friends)
  Future<List<String>> getSuggestedConnections(String userId) async {
    final following = await getFollowing(userId);
    final suggested = <String>{};
    
    for (var fId in following) {
      final subFollowing = await getFollowing(fId);
      for (var sfId in subFollowing) {
        if (sfId != userId && !following.contains(sfId)) {
          suggested.add(sfId);
        }
      }
    }
    return suggested.toList();
  }

  /// Stream whether current user is following target user
  Stream<bool> watchIsFollowing(String currentUserId, String targetUserId) {
    if (currentUserId.isEmpty || targetUserId.isEmpty || currentUserId == targetUserId) {
      return Stream.value(false);
    }
    return _firestore
        .collection('relationships')
        .doc(_relId(currentUserId, targetUserId))
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return false;
          final status = snapshot.data()?['status'] as String?;
          return status == RelationshipStatus.accepted.name;
        });
  }

  /// Check if two users mutually follow each other
  Future<bool> isMutualFollow(String userA, String userB) async {
    if (userA.isEmpty || userB.isEmpty || userA == userB) return false;
    try {
      final docA = await _firestore.collection('relationships').doc(_relId(userA, userB)).get();
      if (!docA.exists || docA.data()?['status'] != RelationshipStatus.accepted.name) {
        return false;
      }
      final docB = await _firestore.collection('relationships').doc(_relId(userB, userA)).get();
      return docB.exists && docB.data()?['status'] == RelationshipStatus.accepted.name;
    } catch (_) {
      return false;
    }
  }

  /// Stream whether two users mutually follow each other
  Stream<bool> watchIsMutual(String userA, String userB) {
    if (userA.isEmpty || userB.isEmpty || userA == userB) {
      return Stream.value(false);
    }
    return _firestore
        .collection('relationships')
        .doc(_relId(userA, userB))
        .snapshots()
        .asyncMap((snapA) async {
      if (!snapA.exists || snapA.data()?['status'] != RelationshipStatus.accepted.name) {
        return false;
      }
      final snapB = await _firestore.collection('relationships').doc(_relId(userB, userA)).get();
      return snapB.exists && snapB.data()?['status'] == RelationshipStatus.accepted.name;
    });
  }

  /// Detailed relationship status stream: none, following, followsYou, mutual
  Stream<MutualRelationshipStatus> watchRelationshipStatus(String currentUserId, String targetUserId) {
    if (currentUserId.isEmpty || targetUserId.isEmpty || currentUserId == targetUserId) {
      return Stream.value(MutualRelationshipStatus.none);
    }

    return _firestore
        .collection('relationships')
        .doc(_relId(currentUserId, targetUserId))
        .snapshots()
        .asyncMap((forwardSnap) async {
      final bool isFollowing = forwardSnap.exists &&
          forwardSnap.data()?['status'] == RelationshipStatus.accepted.name;

      final reverseSnap = await _firestore
          .collection('relationships')
          .doc(_relId(targetUserId, currentUserId))
          .get();

      final bool isFollower = reverseSnap.exists &&
          reverseSnap.data()?['status'] == RelationshipStatus.accepted.name;

      if (isFollowing && isFollower) {
        return MutualRelationshipStatus.mutual;
      } else if (isFollowing) {
        return MutualRelationshipStatus.following;
      } else if (isFollower) {
        return MutualRelationshipStatus.followsYou;
      } else {
        return MutualRelationshipStatus.none;
      }
    });
  }

  /// Live follow state between [currentUserId] and [targetUserId]; both
  /// directions are watched, so "Follow back" flips the moment they follow.
  Stream<FollowState> watchFollowState(String currentUserId, String targetUserId) {
    if (currentUserId.isEmpty || targetUserId.isEmpty) return Stream.value(FollowState.none);
    if (currentUserId == targetUserId) return Stream.value(FollowState.self);

    final forwardRef = _firestore.collection('relationships').doc(_relId(currentUserId, targetUserId));
    final reverseRef = _firestore.collection('relationships').doc(_relId(targetUserId, currentUserId));

    late StreamController<FollowState> controller;
    StreamSubscription? a;
    StreamSubscription? b;
    String? forward;
    String? reverse;
    var gotA = false;
    var gotB = false;

    void emit() {
      if (!gotA || !gotB) return;
      FollowState state;
      if (forward == RelationshipStatus.blocked.name || reverse == RelationshipStatus.blocked.name) {
        state = FollowState.blocked;
      } else {
        final iFollow = forward == RelationshipStatus.accepted.name;
        final theyFollow = reverse == RelationshipStatus.accepted.name;
        if (iFollow && theyFollow) {
          state = FollowState.mutual;
        } else if (iFollow) {
          state = FollowState.following;
        } else if (forward == RelationshipStatus.pending.name) {
          state = FollowState.requested;
        } else if (theyFollow) {
          state = FollowState.followsYou;
        } else {
          state = FollowState.none;
        }
      }
      controller.add(state);
    }

    controller = StreamController<FollowState>(
      onListen: () {
        a = forwardRef.snapshots().listen((d) {
          forward = d.data()?['status'] as String?;
          gotA = true;
          emit();
        }, onError: controller.addError);
        b = reverseRef.snapshots().listen((d) {
          reverse = d.data()?['status'] as String?;
          gotB = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
      },
    );
    return controller.stream.distinct();
  }

  /// Get list of user IDs who mutually follow [userId]
  Future<List<String>> getMutualFollowing(String userId) async {
    final following = await getFollowing(userId);
    final followers = await getFollowers(userId);
    return following.where((id) => followers.contains(id)).toList();
  }
}

/// Everything a follow button needs to know about me → them.
enum FollowState {
  /// Viewing your own profile.
  self,
  none,

  /// I asked to follow a private account; waiting for approval.
  requested,
  following,

  /// They follow me, I don't follow them.
  followsYou,
  mutual,

  /// Either side blocked the other.
  blocked,
}

enum MutualRelationshipStatus {
  none,
  following,
  followsYou,
  mutual,
}
