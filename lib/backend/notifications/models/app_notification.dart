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
  appUpdate,
  recommendation,
  profileTip,
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

  /// Where tapping the notification should take the user (exact source with highlight).
  String? get route {
    final p = payload ?? const {};
    final commentId = (p['commentId'] ?? p['replyId']) as String?;
    final wantsCommentSheet = category == AppNotificationCategory.comment ||
        category == AppNotificationCategory.reply ||
        (category == AppNotificationCategory.mention && (p['postId'] != null || p['contentId'] != null)) ||
        (commentId != null && commentId.isNotEmpty);

    String buildReelRoute(String postId) {
      final params = <String, String>{
        'v': postId,
        'highlight': '1',
        if (wantsCommentSheet) 'openComments': '1',
        if (commentId != null && commentId.isNotEmpty) 'commentId': commentId,
      };
      final query = params.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return '/hub/home?$query';
    }

    if (liveStreamId != null && liveStreamId!.isNotEmpty) {
      return '/live/viewer/$liveStreamId';
    }

    final postId = (p['postId'] ?? p['contentId'] ?? p['videoId'] ?? p['reelId']) as String? ??
        (groupId?.startsWith('post_') == true ? groupId!.substring(5) : null) ??
        (groupId?.startsWith('reel_') == true ? groupId!.substring(5) : null);
    if (postId != null && postId.isNotEmpty) {
      return buildReelRoute(postId);
    }

    final chatId = (p['chatId'] ?? p['conversationId']) as String? ??
        (groupId?.startsWith('chat_') == true ? groupId!.substring(5) : null);
    if (chatId != null && chatId.isNotEmpty) return '/hub/messages/$chatId';

    final callId = p['callId'] as String?;
    if (callId != null && callId.isNotEmpty) return '/call/active?callId=$callId';

    if (deepLink != null && deepLink!.isNotEmpty) {
      final dl = deepLink!.trim();
      if (dl.startsWith('/post/') || dl.startsWith('/reel/') || dl.startsWith('/video/')) {
        final seg = dl.split('/').where((s) => s.isNotEmpty).toList();
        if (seg.length >= 2) return buildReelRoute(seg.last);
      }
      if (dl.startsWith('/chat/')) {
        final seg = dl.split('/').where((s) => s.isNotEmpty).toList();
        if (seg.length >= 2) return '/hub/messages/${seg.last}';
      }
      if (dl.startsWith('/hub/home?v=')) {
        final uri = Uri.tryParse(dl);
        final v = uri?.queryParameters['v'];
        if (v != null && v.isNotEmpty) return buildReelRoute(v);
      }
      return dl;
    }

    final r = p['route'] as String?;
    if (r != null && r.isNotEmpty) return r;

    if (actorId != null && actorId!.isNotEmpty && actorId != 'oneova_ai') {
      return '/profile/$actorId';
    }
    return null;
  }
}
