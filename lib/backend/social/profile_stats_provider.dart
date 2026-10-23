import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live profile numbers for one user.
class ProfileStats {
  final int followers;
  final int following;
  final int posts;
  final int likes;

  const ProfileStats({
    this.followers = 0,
    this.following = 0,
    this.posts = 0,
    this.likes = 0,
  });

  ProfileStats copyWith({int? followers, int? following, int? posts, int? likes}) => ProfileStats(
        followers: followers ?? this.followers,
        following: following ?? this.following,
        posts: posts ?? this.posts,
        likes: likes ?? this.likes,
      );

  @override
  bool operator ==(Object other) =>
      other is ProfileStats &&
      other.followers == followers &&
      other.following == following &&
      other.posts == posts &&
      other.likes == likes;

  @override
  int get hashCode => Object.hash(followers, following, posts, likes);
}

/// Compact display: 999, 1.2K, 3.4M.
String formatProfileCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
  return '$n';
}

int _num(Map<String, dynamic>? d, List<String> keys) {
  if (d == null) return 0;
  for (final k in keys) {
    final v = d[k];
    if (v is num) return v.toInt();
  }
  return 0;
}

/// Real-time followers / following / posts / likes for [uid].
///
/// Sources (all live Firestore streams):
/// - `users/{uid}`: the `followers` / `following` counters that
///   RelationshipRepository bumps on follow / unfollow. Every change to the
///   doc also re-runs the count queries below.
/// - `relationships` count queries (status == accepted): the source of truth.
///   When the counters drift from the counts, the counts win on screen, and
///   the owner's own doc is corrected so every other surface heals too.
/// - `content` where authorId == uid: post count and the sum of `likeCount`
///   (owner sees all their posts, others only public ones, matching the grid).
final profileStatsProvider = StreamProvider.autoDispose.family<ProfileStats, String>((ref, uid) {
  if (uid.isEmpty) return Stream.value(const ProfileStats());
  final db = FirebaseFirestore.instance;
  final isOwner = FirebaseAuth.instance.currentUser?.uid == uid;

  final controller = StreamController<ProfileStats>();
  var stats = const ProfileStats();
  int? countedFollowers;
  int? countedFollowing;
  int docFollowers = 0;
  int docFollowing = 0;
  Timer? recount;
  var disposed = false;

  void emit() {
    if (disposed) return;
    stats = stats.copyWith(
      followers: countedFollowers ?? docFollowers,
      following: countedFollowing ?? docFollowing,
    );
    controller.add(stats);
  }

  Future<void> runCounts() async {
    try {
      final rel = db.collection('relationships');
      final results = await Future.wait([
        rel.where('followingId', isEqualTo: uid).where('status', isEqualTo: 'accepted').count().get(),
        rel.where('followerId', isEqualTo: uid).where('status', isEqualTo: 'accepted').count().get(),
      ]);
      if (disposed) return;
      countedFollowers = results[0].count;
      countedFollowing = results[1].count;
      emit();
      // Heal drifted counters on the owner's own doc (rules: owner may write).
      if (isOwner &&
          countedFollowers != null &&
          countedFollowing != null &&
          (countedFollowers != docFollowers || countedFollowing != docFollowing)) {
        await db.collection('users').doc(uid).set({
          'followers': countedFollowers,
          'following': countedFollowing,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[profileStats] count fallback to counters for $uid: $e');
    }
  }

  final userSub = db.collection('users').doc(uid).snapshots().listen((snap) {
    final d = snap.data();
    docFollowers = _num(d, const ['followers', 'followersCount', 'followerCount']);
    docFollowing = _num(d, const ['following', 'followingCount']);
    emit();
    // Debounce: a follow writes both users in one transaction.
    recount?.cancel();
    recount = Timer(const Duration(milliseconds: 400), runCounts);
  }, onError: (Object e) => debugPrint('[profileStats] user stream $uid: $e'));

  final contentSub = db
      .collection('content')
      .where('authorId', isEqualTo: uid)
      .limit(500)
      .snapshots()
      .listen((snap) {
    var posts = 0;
    var likes = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      if (!isOwner && (d['visibility'] ?? 'public') != 'public') continue;
      posts++;
      likes += _num(d, const ['likeCount', 'likesCount']);
    }
    stats = stats.copyWith(posts: posts, likes: likes);
    emit();
  }, onError: (Object e) => debugPrint('[profileStats] content stream $uid: $e'));

  ref.onDispose(() {
    disposed = true;
    recount?.cancel();
    userSub.cancel();
    contentSub.cancel();
    controller.close();
  });

  return controller.stream;
});
