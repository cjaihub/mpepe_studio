enum NotificationCategory {
  messages,
  comments,
  followers,
  likes,
  shares,
  calls,
  live,
  ai,
  automation,
  security,
  content,
  events,
}

enum NotificationPriority {
  low,
  defaultPriority,
  high,
  urgent, // Security events, incoming calls
}

class NotificationItem {
  final String id;
  final String userId;
  final NotificationCategory category;
  final NotificationPriority priority;
  
  final String title;
  final String body;
  final String? previewImageUrl;
  final String? deepLink;
  
  final DateTime timestamp;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.userId,
    required this.category,
    required this.priority,
    required this.title,
    required this.body,
    this.previewImageUrl,
    this.deepLink,
    required this.timestamp,
    this.isRead = false,
  });
}

class NotificationGroup {
  final String groupId;
  final NotificationCategory category;
  final List<NotificationItem> items;
  String? aiSummary; // AI can populate this to summarize

  NotificationGroup({
    required this.groupId,
    required this.category,
    required this.items,
    this.aiSummary,
  });
}

class NotificationSettings {
  final String userId;
  bool enableSound;
  bool enableVibration;
  bool showPreviews;
  
  // Quiet hours (24h format, e.g. 22 for 10 PM)
  int? quietHoursStart; 
  int? quietHoursEnd;

  NotificationSettings({
    required this.userId,
    this.enableSound = true,
    this.enableVibration = true,
    this.showPreviews = true,
    this.quietHoursStart,
    this.quietHoursEnd,
  });
  
  bool isCurrentlyQuietHour(DateTime time) {
    if (quietHoursStart == null || quietHoursEnd == null) return false;
    final hour = time.hour;
    
    if (quietHoursStart! < quietHoursEnd!) {
      return hour >= quietHoursStart! && hour < quietHoursEnd!;
    } else {
      // Overnight (e.g. 22 to 7)
      return hour >= quietHoursStart! || hour < quietHoursEnd!;
    }
  }
}
