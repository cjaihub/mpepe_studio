import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_repository.dart';
import '../../user_service.dart';

final followerAlertServiceProvider = Provider<FollowerAlertService>((ref) => FollowerAlertService());

/// Creators the signed-in user follows, with their per-creator alert switches.
final followedCreatorAlertsProvider = StreamProvider.autoDispose<List<CreatorAlertSetting>>((ref) {
  final uid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (uid == null) return Stream.value(const []);
  return ref.watch(followerAlertServiceProvider).watchFollowedCreators(uid);
});

/// Live profile card for a user shown in notification UIs.
final alertUserCardProvider = StreamProvider.autoDispose.family<AppUser?, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists && s.data() != null ? AppUser.fromMap(s.data()!, s.id) : null);
});

/// Alert switches for one creator, as seen by the signed-in follower.
final creatorAlertSettingProvider =
    StreamProvider.autoDispose.family<CreatorAlertSetting?, String>((ref, creatorId) {
  final uid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (uid == null) return Stream.value(null);
  return ref.watch(followerAlertServiceProvider).watchCreatorAlert(uid, creatorId);
});

/// Per-follow alert switches. Stored on the follower's own
/// `relationships/{followerId}_{creatorId}` doc so the creator's fan-out can
/// filter recipients with the same query it already runs.
class CreatorAlertSetting {
  final String creatorId;
  final bool posts;
  final bool live;

  const CreatorAlertSetting({required this.creatorId, this.posts = true, this.live = true});

  factory CreatorAlertSetting.fromMap(Map<String, dynamic> data) => CreatorAlertSetting(
        creatorId: data['followingId'] as String? ?? '',
        posts: data['alertPosts'] != false,
        live: data['alertLive'] != false,
      );
}

class FollowerAlertService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _batchSize = 400;

  Stream<List<CreatorAlertSetting>> watchFollowedCreators(String uid) {
    return _db
        .collection('relationships')
        .where('followerId', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .limit(300)
        .snapshots()
        .map((s) => s.docs.map((d) => CreatorAlertSetting.fromMap(d.data())).toList());
  }

  Stream<CreatorAlertSetting?> watchCreatorAlert(String uid, String creatorId) {
    return _db
        .collection('relationships')
        .doc('${uid}_$creatorId')
        .snapshots()
        .map((d) => d.exists && d.data()?['status'] == 'accepted'
            ? CreatorAlertSetting.fromMap(d.data()!)
            : null);
  }

  Future<void> setCreatorAlerts(String creatorId, {bool? posts, bool? live}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('relationships').doc('${uid}_$creatorId').update({
      'alertPosts': ?posts,
      'alertLive': ?live,
    });
  }

  /// Tell followers a creator published something new.
  Future<void> notifyFollowersNewPost({
    required String authorId,
    required String contentId,
    required String caption,
    required bool isVideo,
    String? mediaUrl,
  }) async {
    final author = await _authorCard(authorId);
    final preview = caption.trim().split('\n').first;
    await _fanOut(
      creatorId: authorId,
      wants: (d) => d['alertPosts'] != false,
      build: (uid) => {
        'userId': uid,
        'recipientId': uid,
        'actorId': authorId,
        'category': 'newPost',
        'type': 'social',
        'priority': 'normal',
        'title': '${author.name} posted a new ${isVideo ? 'reel' : 'photo'}',
        'body': preview.isEmpty ? 'Tap to watch it first.' : preview,
        'message': preview,
        'groupId': 'post_$contentId',
        'deepLink': '/hub/home?v=$contentId',
        'payload': {
          'contentId': contentId,
          'actorName': author.name,
          'avatarUrl': author.avatar,
          if (!isVideo && mediaUrl != null) 'thumbnailUrl': mediaUrl,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Tell followers a creator just went live. Tapping opens the viewer, which
  /// picks the classic or studio room.
  Future<void> notifyFollowersWentLive({
    required String hostId,
    required String streamId,
    required String title,
    String? hostName,
  }) async {
    final author = await _authorCard(hostId, fallbackName: hostName);
    await _fanOut(
      creatorId: hostId,
      wants: (d) => d['alertLive'] != false,
      build: (uid) => {
        'userId': uid,
        'recipientId': uid,
        'actorId': hostId,
        'category': 'live',
        'type': 'live',
        'priority': 'high',
        'title': '${author.name} is LIVE',
        'body': title.isEmpty ? 'Tap to join the live now.' : title,
        'message': title,
        'groupId': 'live_$streamId',
        'deepLink': '/live/viewer/$streamId',
        'payload': {
          'streamId': streamId,
          'route': '/live/viewer/$streamId',
          'actorName': author.name,
          'avatarUrl': author.avatar,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> _fanOut({
    required String creatorId,
    required bool Function(Map<String, dynamic>) wants,
    required Map<String, dynamic> Function(String uid) build,
  }) async {
    try {
      final snap = await _db
          .collection('relationships')
          .where('followingId', isEqualTo: creatorId)
          .where('status', isEqualTo: 'accepted')
          .get();
      final followerIds = snap.docs
          .where((d) => wants(d.data()) && d.data()['isMuted'] != true)
          .map((d) => d.data()['followerId'] as String?)
          .whereType<String>()
          .where((id) => id != creatorId)
          .toSet()
          .toList();
      for (var i = 0; i < followerIds.length; i += _batchSize) {
        final batch = _db.batch();
        for (final uid in followerIds.skip(i).take(_batchSize)) {
          batch.set(_db.collection('notifications').doc(), build(uid));
        }
        await batch.commit();
      }
    } catch (e) {
      // Alerts are best-effort; the post / stream itself already exists.
      debugPrint('[FollowerAlertService] fan-out failed: $e');
    }
  }

  Future<({String name, String avatar})> _authorCard(String uid, {String? fallbackName}) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final d = doc.data() ?? const {};
      final name = (d['displayName'] ?? d['fullName'] ?? d['username'] ?? d['name'] ?? fallbackName ?? 'Someone you follow') as String;
      final avatar = (d['avatarUrl'] ?? d['photoUrl'] ?? d['photoURL'] ?? '') as String;
      return (name: name, avatar: avatar);
    } catch (_) {
      return (name: fallbackName ?? 'Someone you follow', avatar: '');
    }
  }
}
