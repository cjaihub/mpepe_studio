import 'package:cloud_firestore/cloud_firestore.dart';

enum AppNotificationCategory {
  newMessage,
  mention,
  reaction,
  newFollower,
  followRequest,
  comment,
  like,
  reply,
  share,
  repost,
  subscription,
  live,
  call,
  missedCall,
  aiSuggestion,
  automation,
  scheduledMessage,
  security,
  accountActivity,
  analyticsAlert,
  system,
  newPost,
}

enum AppNotificationPriority { low, normal, high, urgent }

class AppNotification {
  final String id;
  final String userId; // The recipient
  final String? actorId; // The user who triggered it (if any)
  final AppNotificationCategory category;
  final AppNotificationPriority priority;
  final String title;
  final String body;
  final String? groupId; // For grouping/deduplication (e.g. 'chat_123', 'post_456')
  final Map<String, dynamic>? payload; // JSON data for deep linking (legacy)
  final String? deepLink; // Explicit deep link path (e.g. '/chat/123')
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    this.actorId,
    required this.category,
    this.priority = AppNotificationPriority.normal,
    required this.title,
    required this.body,
    this.groupId,
    this.payload,
    this.deepLink,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppNotification(
      id: doc.id,
      userId: data['userId'] ?? '',
      actorId: data['actorId'],
      category: AppNotificationCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => AppNotificationCategory.system,
      ),
      priority: AppNotificationPriority.values.firstWhere(
        (e) => e.name == data['priority'],
        orElse: () => AppNotificationPriority.normal,
      ),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      groupId: data['groupId'],
      payload: data['payload'] as Map<String, dynamic>?,
      deepLink: data['deepLink'] as String?,
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'actorId': actorId,
      'category': category.name,
      'priority': priority.name,
      'title': title,
      'body': body,
      if (groupId != null) 'groupId': groupId,
      if (payload != null) 'payload': payload,
      if (deepLink != null) 'deepLink': deepLink,
      'isRead': isRead,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Display name of the actor, when the writer attached one.
  String? get actorName =>
      (payload?['actorName'] ?? payload?['senderName'] ?? payload?['hostName']) as String?;

  /// Avatar of the actor, when the writer attached one.
  String? get actorAvatarUrl =>
      (payload?['avatarUrl'] ?? payload?['senderAvatar'] ?? payload?['actorAvatar']) as String?;

  /// Preview image of the post / live the notification points at.
  String? get thumbnailUrl => (payload?['thumbnailUrl'] ?? payload?['mediaUrl']) as String?;

  /// Live stream this notification refers to (go-live alerts).
  String? get liveStreamId {
    final id = payload?['streamId'] as String?;
    if (id != null && id.isNotEmpty) return id;
    if (groupId != null && groupId!.startsWith('live_')) return groupId!.substring(5);
    return null;
  }

  bool get isLive => category == AppNotificationCategory.live;

  /// Where tapping the notification should take the user.
  String? get route {
    if (deepLink != null && deepLink!.isNotEmpty) return deepLink;
    final p = payload ?? const {};
    final chatId = (p['chatId'] as String?) ??
        (groupId?.startsWith('chat_') == true ? groupId!.substring(5) : null);
    if (chatId != null && chatId.isNotEmpty) return '/hub/messages/$chatId';
    final callId = p['callId'] as String?;
    if (callId != null && callId.isNotEmpty) return '/call/active?callId=$callId';
    final postId = (p['postId'] ?? p['contentId']) as String?;
    if (postId != null && postId.isNotEmpty) return '/hub/home?v=$postId';
    final r = p['route'] as String?;
    if (r != null && r.isNotEmpty) return r;
    if (actorId != null && actorId!.isNotEmpty &&
        (category == AppNotificationCategory.newFollower ||
            category == AppNotificationCategory.followRequest)) {
      return '/profile/$actorId';
    }
    return null;
  }
}
