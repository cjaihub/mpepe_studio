enum NotificationType { like, reply, follow, mention }

class OneOvaNotification {
  final String id;
  final String actorUsername;
  final String actorAvatarUrl;
  final NotificationType type;
  final String content;
  final String? targetMediaUrl;
  final List<String>? targetMediaUrls;
  final DateTime createdAt;
  final bool isRead;
  final bool hasLikeBadge;
  final bool hasStory;

  OneOvaNotification({
    required this.id,
    required this.actorUsername,
    required this.actorAvatarUrl,
    required this.type,
    required this.content,
    this.targetMediaUrl,
    this.targetMediaUrls,
    required this.createdAt,
    this.isRead = false,
    this.hasLikeBadge = false,
    this.hasStory = false,
  });

  factory OneOvaNotification.fromMap(
    Map<String, dynamic> map,
    String documentId,
  ) {
    List<String>? parsedMediaUrls;
    if (map['targetMediaUrls'] != null) {
      parsedMediaUrls = List<String>.from(map['targetMediaUrls']);
    }

    return OneOvaNotification(
      id: documentId,
      actorUsername: map['actorUsername'] ?? 'Unknown',
      actorAvatarUrl: map['actorAvatarUrl'] ?? '',
      type: _parseType(map['type']),
      content: map['content'] ?? '',
      targetMediaUrl: map['targetMediaUrl'],
      targetMediaUrls: parsedMediaUrls,
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : DateTime.now(),
      isRead: map['isRead'] ?? false,
      hasLikeBadge: map['hasLikeBadge'] ?? false,
      hasStory: map['hasStory'] ?? false,
    );
  }

  static NotificationType _parseType(String? typeStr) {
    switch (typeStr?.toUpperCase()) {
      case 'REPLY':
        return NotificationType.reply;
      case 'LIKE':
        return NotificationType.like;
      case 'FOLLOW':
        return NotificationType.follow;
      default:
        return NotificationType.mention;
    }
  }

  String get formattedTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}

