import 'package:cloud_firestore/cloud_firestore.dart';
import 'mention.dart';

enum PostType { text, image, carousel, reel, short, live }

class Post {
  final String id;
  final String authorId;
  final String content;
  final PostType type;
  final List<String> attachments; // Video URLs for reels, image URLs for carousel
  final List<Mention> mentions;
  final List<String> mentionedUserIds; // Flat list for easy querying
  final String privacy;
  final bool allowComments;
  final bool allowDuet;
  final bool highQualityUploads;
  final List<String> hashtags;
  final String? location;
  final String? link;
  final String? musicId;      // Optional: linked audio track ID
  final int reactionCount;
  final int commentCount;
  final int shareCount;
  final int viewCount; // Critical for algorithmic feed and reels
  final double algorithmicScore; // Pre-calculated engagement score for ranking
  final DateTime createdAt;

  Post({
    required this.id,
    required this.authorId,
    required this.content,
    this.type = PostType.text,
    this.attachments = const [],
    this.mentions = const [],
    this.mentionedUserIds = const [],
    this.privacy = 'public',
    this.allowComments = true,
    this.allowDuet = true,
    this.highQualityUploads = false,
    this.hashtags = const [],
    this.location,
    this.link,
    this.musicId,
    this.reactionCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.viewCount = 0,
    this.algorithmicScore = 0.0,
    required this.createdAt,
  });

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Post(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      content: data['content'] ?? '',
      type: PostType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => PostType.text,
      ),
      attachments: List<String>.from(data['attachments'] ?? []),
      mentions: (data['mentions'] as List<dynamic>?)
              ?.map((e) => Mention.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      mentionedUserIds: List<String>.from(data['mentionedUserIds'] ?? []),
      privacy: data['privacy'] ?? 'public',
      allowComments: data['allowComments'] ?? true,
      allowDuet: data['allowDuet'] ?? true,
      highQualityUploads: data['highQualityUploads'] ?? false,
      hashtags: List<String>.from(data['hashtags'] ?? []),
      location: data['location'],
      link: data['link'],
      musicId: data['musicId'] as String?,
      reactionCount: data['reactionCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      shareCount: data['shareCount'] ?? 0,
      viewCount: data['viewCount'] ?? 0,
      algorithmicScore: (data['algorithmicScore'] as num?)?.toDouble() ?? 0.0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'content': content,
      'type': type.name,
      'attachments': attachments,
      'mentions': mentions.map((m) => m.toMap()).toList(),
      'mentionedUserIds': mentionedUserIds,
      'privacy': privacy,
      'allowComments': allowComments,
      'allowDuet': allowDuet,
      'highQualityUploads': highQualityUploads,
      'hashtags': hashtags,
      'location': location,
      'link': link,
      'musicId': musicId,
      'reactionCount': reactionCount,
      'commentCount': commentCount,
      'shareCount': shareCount,
      'viewCount': viewCount,
      'algorithmicScore': algorithmicScore,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
