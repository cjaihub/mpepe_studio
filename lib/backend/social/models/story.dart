import 'package:cloud_firestore/cloud_firestore.dart';

enum StoryMediaType {
  photo,
  video,
  text,
  voice,
  music,
  poll,
  question,
  link,
  location,
  mention
}

enum StoryLifecycle {
  draft,
  published,
  active,
  expired,
  archived
}

enum StoryPrivacy {
  public,
  followers,
  friends,
  closeFriends,
  custom,
}

class InteractiveElement {
  final String type; // sticker, poll, question, mention, location, link
  final double x;
  final double y;
  final Map<String, dynamic> data;

  const InteractiveElement({
    required this.type,
    required this.x,
    required this.y,
    required this.data,
  });
}

class Story {
  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatarUrl;
  final StoryMediaType mediaType;
  final String mediaUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final StoryPrivacy privacy;
  final List<String>? customAudience; // user IDs if custom privacy
  final List<InteractiveElement> interactiveElements;
  final StoryLifecycle lifecycle;
  final bool isHighlight;
  
  // Stats
  final List<String> viewers;
  final List<String> likes;
  final Map<String, String> reactions; // userId -> emoji
  final int replyCount;

  Story({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.mediaType,
    required this.mediaUrl,
    required this.createdAt,
    required this.expiresAt,
    this.privacy = StoryPrivacy.public,
    this.customAudience,
    this.interactiveElements = const [],
    this.lifecycle = StoryLifecycle.draft,
    this.isHighlight = false,
    this.viewers = const [],
    this.likes = const [],
    this.reactions = const {},
    this.replyCount = 0,
  });

  bool get isExpired => lifecycle == StoryLifecycle.expired || DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'authorId': authorId,
      'authorName': authorName,
      'authorAvatarUrl': authorAvatarUrl,
      'mediaType': mediaType.name,
      'mediaUrl': mediaUrl,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'privacy': privacy.name,
      'customAudience': customAudience,
      'interactiveElements': interactiveElements.map((e) => {
        'type': e.type,
        'x': e.x,
        'y': e.y,
        'data': e.data,
      }).toList(),
      'lifecycle': lifecycle.name,
      'isHighlight': isHighlight,
      'viewers': viewers,
      'likes': likes,
      'reactions': reactions,
      'replyCount': replyCount,
    };
  }

  /// Story times are written as epoch millis; tolerate Timestamps too.
  static DateTime _storyTime(dynamic v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory Story.fromMap(Map<String, dynamic> map) {
    return Story(
      id: map['id'] ?? '',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      authorAvatarUrl: map['authorAvatarUrl'] ?? '',
      mediaType: StoryMediaType.values.firstWhere((e) => e.name == map['mediaType'], orElse: () => StoryMediaType.text),
      mediaUrl: map['mediaUrl'] ?? '',
      createdAt: _storyTime(map['createdAt']),
      expiresAt: _storyTime(map['expiresAt']),
      privacy: StoryPrivacy.values.firstWhere((e) => e.name == map['privacy'], orElse: () => StoryPrivacy.public),
      customAudience: List<String>.from(map['customAudience'] ?? []),
      interactiveElements: (map['interactiveElements'] as List<dynamic>? ?? []).map((e) {
        return InteractiveElement(
          type: e['type'],
          x: e['x'],
          y: e['y'],
          data: e['data'],
        );
      }).toList(),
      lifecycle: StoryLifecycle.values.firstWhere((e) => e.name == map['lifecycle'], orElse: () => StoryLifecycle.draft),
      isHighlight: map['isHighlight'] ?? false,
      viewers: List<String>.from(map['viewers'] ?? []),
      likes: List<String>.from(map['likes'] ?? []),
      reactions: Map<String, String>.from(map['reactions'] ?? {}),
      replyCount: map['replyCount'] ?? 0,
    );
  }

}
