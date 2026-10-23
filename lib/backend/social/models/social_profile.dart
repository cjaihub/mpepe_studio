import 'package:cloud_firestore/cloud_firestore.dart';

enum PrivacyMode { public, followers, friends, private, custom }

class CreatorBadge {
  final String id;
  final String name;
  final String iconUrl;
  const CreatorBadge({required this.id, required this.name, required this.iconUrl});
}

class SocialProfile {
  final String userId;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String bio;
  final List<String> links;
  
  final bool isVerified;
  final bool isCreator;
  final bool isSubscribed; // Client-side state based on viewer
  final List<CreatorBadge> badges;
  final List<String> contentFilters; // E.g., 'Mature', 'Educational'
  
  final int followerCount;
  final int followingCount;
  final int likeCount;
  final int subscriberCount;
  
  final PrivacyMode privacyMode;

  SocialProfile({
    required this.userId,
    this.username = '',
    this.displayName = '',
    this.avatarUrl = '',
    this.bio = '',
    this.links = const [],
    this.isVerified = false,
    this.isCreator = false,
    this.isSubscribed = false,
    this.badges = const [],
    this.contentFilters = const [],
    this.followerCount = 0,
    this.followingCount = 0,
    this.likeCount = 0,
    this.subscriberCount = 0,
    this.privacyMode = PrivacyMode.public,
  });

  factory SocialProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SocialProfile(
      userId: doc.id,
      username: data['username'] ?? '',
      displayName: data['displayName'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      bio: data['bio'] ?? '',
      links: List<String>.from(data['links'] ?? []),
      isVerified: data['isVerified'] ?? false,
      isCreator: data['isCreator'] ?? false,
      contentFilters: List<String>.from(data['contentFilters'] ?? []),
      followerCount: data['followerCount'] ?? 0,
      followingCount: data['followingCount'] ?? 0,
      likeCount: data['likeCount'] ?? 0,
      subscriberCount: data['subscriberCount'] ?? 0,
      privacyMode: PrivacyMode.values.firstWhere(
        (e) => e.name == data['privacyMode'],
        orElse: () => PrivacyMode.public,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'links': links,
      'isVerified': isVerified,
      'isCreator': isCreator,
      'contentFilters': contentFilters,
      'followerCount': followerCount,
      'followingCount': followingCount,
      'likeCount': likeCount,
      'subscriberCount': subscriberCount,
      'privacyMode': privacyMode.name,
    };
  }
}
