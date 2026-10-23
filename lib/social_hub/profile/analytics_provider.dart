import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserAnalyticsData {
  final int followers;
  final int following;
  final int likes;

  const UserAnalyticsData({
    this.followers = 0,
    this.following = 0,
    this.likes = 0,
  });
}

final userAnalyticsProvider = FutureProvider.family<UserAnalyticsData, String>((ref, uid) async {
  final db = FirebaseFirestore.instance;
  
  // Followers count
  final followersSnap = await db.collection('relationships')
      .where('followingId', isEqualTo: uid)
      .where('status', isEqualTo: 'accepted')
      .count()
      .get();
      
  // Following count
  final followingSnap = await db.collection('relationships')
      .where('followerId', isEqualTo: uid)
      .where('status', isEqualTo: 'accepted')
      .count()
      .get();
      
  // Total likes (reactionCount across all posts)
  final postsSnap = await db.collection('posts')
      .where('authorId', isEqualTo: uid)
      .aggregate(sum('reactionCount'))
      .get();
      
  return UserAnalyticsData(
    followers: followersSnap.count ?? 0,
    following: followingSnap.count ?? 0,
    likes: postsSnap.getSum('reactionCount')?.toInt() ?? 0,
  );
});
