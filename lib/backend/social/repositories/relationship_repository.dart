import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/relationship.dart';
import '../../user_service.dart'; // To access PrivacyMode if necessary

final relationshipRepositoryProvider = Provider<RelationshipRepository>((ref) {
  return RelationshipRepository(FirebaseFirestore.instance);
});

class RelationshipRepository {
  final FirebaseFirestore _firestore;

  RelationshipRepository(this._firestore);

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
      if (!targetDoc.exists) throw Exception("Target user does not exist");
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

      final isPrivate = privacyStr == 'private' || privacyStr == 'friends';
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
      } else if (newStatus == RelationshipStatus.pending) {
        _publishEvent(tx, 'follow.requested', {
          'followerId': currentUserId,
          'followingId': targetUserId,
        });
      }
    });
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
}
