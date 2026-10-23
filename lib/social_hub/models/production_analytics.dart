class ProductionAnalytics {
  final int messagesSent; // Raw
  final int activeConversations; // Raw
  final int unreadConversations; // Estimated
  final int newContacts; // Raw
  final int aiUsage; // Raw
  final int automation; // Estimated
  final int calls; // Raw
  final int notifications; // Raw
  final int userEngagementScore; // Calculated
  final double averageResponseTimeMinutes; // Estimated
  final int channelActivityScore; // Estimated

  const ProductionAnalytics({
    this.messagesSent = 0,
    this.activeConversations = 0,
    this.unreadConversations = 0,
    this.newContacts = 0,
    this.aiUsage = 0,
    this.automation = 0,
    this.calls = 0,
    this.notifications = 0,
    this.userEngagementScore = 0,
    this.averageResponseTimeMinutes = 0.0,
    this.channelActivityScore = 0,
  });

  factory ProductionAnalytics.fromMap(Map<String, dynamic> map) {
    return ProductionAnalytics(
      messagesSent: map['messagesSent'] ?? 0,
      activeConversations: map['activeConversations'] ?? 0,
      unreadConversations: map['unreadConversations'] ?? 0,
      newContacts: map['newContacts'] ?? 0,
      aiUsage: map['aiUsage'] ?? 0,
      automation: map['automation'] ?? 0,
      calls: map['calls'] ?? 0,
      notifications: map['notifications'] ?? 0,
      userEngagementScore: map['userEngagementScore'] ?? 0,
      averageResponseTimeMinutes: (map['averageResponseTimeMinutes'] ?? 0).toDouble(),
      channelActivityScore: map['channelActivityScore'] ?? 0,
    );
  }
}

enum MetricType {
  raw,
  calculated,
  estimated
}

class AnalyticsMetricDescriptor {
  final String label;
  final String value;
  final MetricType type;

  const AnalyticsMetricDescriptor({
    required this.label,
    required this.value,
    required this.type,
  });
}
