import 'package:oneova/backend/notifications/models/notification_models.dart';

class NotificationEngine {
  final Map<String, List<NotificationItem>> _userInbox = {};
  final Map<String, NotificationSettings> _settings = {};

  NotificationSettings getSettings(String userId) {
    return _settings.putIfAbsent(userId, () => NotificationSettings(userId: userId));
  }

  void updateSettings(String userId, NotificationSettings settings) {
    _settings[userId] = settings;
  }

  /// Dispatch a notification. Returns true if delivered to device, false if suppressed by quiet hours.
  bool dispatchNotification(NotificationItem item) {
    _userInbox.putIfAbsent(item.userId, () => []).add(item);

    final settings = getSettings(item.userId);
    
    // Urgent notifications bypass quiet hours (e.g. Security, Calls)
    if (item.priority == NotificationPriority.urgent) {
      return true; // Force deliver
    }

    if (settings.isCurrentlyQuietHour(DateTime.now())) {
      return false; // Suppressed from active push, but still in inbox
    }

    return true; // Delivered
  }

  /// Retrieves the user's inbox, optionally grouped by category
  List<NotificationGroup> getGroupedInbox(String userId) {
    final inbox = _userInbox[userId] ?? [];
    
    final Map<NotificationCategory, List<NotificationItem>> groups = {};
    for (var item in inbox) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }

    return groups.entries.map((e) {
      return NotificationGroup(
        groupId: 'grp_${e.key.name}',
        category: e.key,
        items: e.value,
      );
    }).toList();
  }

  /// AI calls this to generate summaries and optionally suppress clutter
  void applyAiSummaryAndSuppression(String userId, NotificationGroup group, String aiGeneratedSummary, List<String> itemIdsToSuppress) {
    if (group.category == NotificationCategory.security) {
      throw Exception('AI Block: AI must not suppress security-critical notifications without explicit policy.');
    }

    group.aiSummary = aiGeneratedSummary;

    final inbox = _userInbox[userId] ?? [];
    // Remove suppressed items from the actual inbox
    inbox.removeWhere((item) => itemIdsToSuppress.contains(item.id));
  }
}
