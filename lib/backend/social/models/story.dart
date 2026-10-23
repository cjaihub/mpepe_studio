import 'package:uuid/uuid.dart';

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

  factory Story.fromMap(Map<String, dynamic> map) {
    return Story(
      id: map['id'] ?? '',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      authorAvatarUrl: map['authorAvatarUrl'] ?? '',
      mediaType: StoryMediaType.values.firstWhere((e) => e.name == map['mediaType'], orElse: () => StoryMediaType.text),
      mediaUrl: map['mediaUrl'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(map['expiresAt'] ?? 0),
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

  factory Story.mock({
    required String authorName,
    bool isExpired = false,
    bool isArchived = false,
  }) {
    final now = DateTime.now();
    return Story(
      id: const Uuid().v4(),
      authorId: 'user_mock',
      authorName: authorName,
      authorAvatarUrl: 'https://i.pravatar.cc/150?u=$authorName',
      mediaType: StoryMediaType.photo,
      mediaUrl: 'https://picsum.photos/1080/1920',
      createdAt: isExpired ? now.subtract(const Duration(hours: 25)) : now.subtract(const Duration(hours: 2)),
      expiresAt: isExpired ? now.subtract(const Duration(hours: 1)) : now.add(const Duration(hours: 22)),
      privacy: StoryPrivacy.public,
      lifecycle: isArchived ? StoryLifecycle.archived : (isExpired ? StoryLifecycle.expired : StoryLifecycle.active),
      viewers: ['user1', 'user2', 'user3'],
      reactions: {'user1': '🔥', 'user2': '❤️'},
      replyCount: 1,
      interactiveElements: [
        const InteractiveElement(
          type: 'location',
          x: 0.5,
          y: 0.2,
          data: {'name': 'New York City'},
        ),
      ],
    );
  }
}
