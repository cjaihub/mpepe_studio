import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SocialPlatform { youtube, tiktok, meta, instagram, system }
enum UnifiedItemType { message, comment, notification }

class UnifiedItem {
  final String id;
  final SocialPlatform platform;
  final UnifiedItemType type;
  final String senderName;
  final String senderAvatarUrl;
  final String content;
  final DateTime timestamp;
  final bool isRead;
  final bool handledByAI;
  final bool isHarsh;
  final bool isMutedByAI;

  UnifiedItem({
    required this.id,
    required this.platform,
    required this.type,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.handledByAI = false,
    this.isHarsh = false,
    this.isMutedByAI = false,
  });

  UnifiedItem copyWith({
    bool? isRead,
    bool? handledByAI,
    bool? isMutedByAI,
  }) {
    return UnifiedItem(
      id: id,
      platform: platform,
      type: type,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      content: content,
      timestamp: timestamp,
      isHarsh: isHarsh,
      isRead: isRead ?? this.isRead,
      handledByAI: handledByAI ?? this.handledByAI,
      isMutedByAI: isMutedByAI ?? this.isMutedByAI,
    );
  }
}

// AI Assistant Toggle Provider
final cjAiAssistantProvider = NotifierProvider<CJAiAssistantNotifier, bool>(() {
  return CJAiAssistantNotifier();
});

class CJAiAssistantNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }
  
  void toggle() {
    state = !state;
  }

  void setAssistantState(bool value) {
    state = value;
  }
}

// Unified Inbox State Provider
final unifiedInboxProvider = NotifierProvider<UnifiedInboxNotifier, List<UnifiedItem>>(() {
  return UnifiedInboxNotifier();
});

class UnifiedInboxNotifier extends Notifier<List<UnifiedItem>> {
  @override
  List<UnifiedItem> build() {
    return _generateMockData();
  }

  void markAsRead(String id) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(isRead: true);
      }
      return item;
    }).toList();
  }

  void markAllAsRead(UnifiedItemType type) {
    state = state.map((item) {
      if (item.type == type) {
        return item.copyWith(isRead: true);
      }
      return item;
    }).toList();
  }

  // AI auto-reply simulation
  void aiAutoReply(String id, String replyContent) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(handledByAI: true, isRead: true);
      }
      return item;
    }).toList();
  }

  // AI moderation simulation
  void muteCommentFromSource(String id) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(isMutedByAI: true);
      }
      return item;
    }).toList();
  }

  static List<UnifiedItem> _generateMockData() {
    return [
      // Messages
      UnifiedItem(
        id: 'm1',
        platform: SocialPlatform.meta,
        type: UnifiedItemType.message,
        senderName: 'Alex Johnson',
        senderAvatarUrl: 'https://i.pravatar.cc/150?img=11',
        content: 'Hey, loved the new track you just dropped!',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        isRead: false,
      ),
      UnifiedItem(
        id: 'm2',
        platform: SocialPlatform.youtube,
        type: UnifiedItemType.message,
        senderName: 'Creator Collabs',
        senderAvatarUrl: 'https://i.pravatar.cc/150?img=33',
        content: 'Would you be open to a collaboration on the next beat?',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        isRead: true,
      ),
      // Comments
      UnifiedItem(
        id: 'c1',
        platform: SocialPlatform.tiktok,
        type: UnifiedItemType.comment,
        senderName: 'BeatMaker99',
        senderAvatarUrl: 'https://i.pravatar.cc/150?img=55',
        content: 'This transition is insane 🔥🔥',
        timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
        isRead: false,
      ),
      UnifiedItem(
        id: 'c2',
        platform: SocialPlatform.youtube,
        type: UnifiedItemType.comment,
        senderName: 'Music Lover',
        senderAvatarUrl: 'https://i.pravatar.cc/150?img=22',
        content: 'What VST did you use for that bassline?',
        timestamp: DateTime.now().subtract(const Duration(minutes: 45)),
        isRead: false,
      ),
      UnifiedItem(
        id: 'c3',
        platform: SocialPlatform.meta,
        type: UnifiedItemType.comment,
        senderName: 'Studio Fan',
        senderAvatarUrl: 'https://i.pravatar.cc/150?img=44',
        content: 'Awesome setup!',
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        isRead: true,
        handledByAI: true,
      ),
      UnifiedItem(
        id: 'c4',
        platform: SocialPlatform.instagram,
        type: UnifiedItemType.comment,
        senderName: 'Hater123',
        senderAvatarUrl: 'https://i.pravatar.cc/150?img=12',
        content: 'This music is absolute garbage. Worst thing I have heard.',
        timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        isRead: false,
        isHarsh: true,
        isMutedByAI: false, // The AI will automatically mute this when it mounts
      ),
      // Notifications
      UnifiedItem(
        id: 'n1',
        platform: SocialPlatform.system,
        type: UnifiedItemType.notification,
        senderName: 'System',
        senderAvatarUrl: '',
        content: 'Your scheduled upload to TikTok is complete.',
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
        isRead: false,
      ),
      UnifiedItem(
        id: 'n2',
        platform: SocialPlatform.youtube,
        type: UnifiedItemType.notification,
        senderName: 'YouTube',
        senderAvatarUrl: '',
        content: 'Your recent video hit 10k views!',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        isRead: true,
      ),
    ];
  }
}
