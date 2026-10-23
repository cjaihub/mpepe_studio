import 'package:cloud_firestore/cloud_firestore.dart';

class HashtagMetadata {
  final String tag;
  final int totalViews;
  final int totalVideos;
  final int totalCreators;
  final String? ownerId; // If it's a branded/owned hashtag
  final DateTime lastActive;

  const HashtagMetadata({
    required this.tag,
    this.totalViews = 0,
    this.totalVideos = 0,
    this.totalCreators = 0,
    this.ownerId,
    required this.lastActive,
  });

  factory HashtagMetadata.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return HashtagMetadata(
      tag: doc.id,
      totalViews: data['totalViews'] ?? 0,
      totalVideos: data['totalVideos'] ?? 0,
      totalCreators: data['totalCreators'] ?? 0,
      ownerId: data['ownerId'],
      lastActive: (data['lastActive'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class TrendingTopic {
  final String id;
  final String name;
  final String category; // 'hashtag', 'sound', 'location', 'creator'
  final int rank; // 1 = #1 trending
  final int metricDelta; // How fast it's rising

  const TrendingTopic({
    required this.id,
    required this.name,
    required this.category,
    required this.rank,
    required this.metricDelta,
  });
}
