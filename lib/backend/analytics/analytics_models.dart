
enum MetricType {
  rawCount,
  calculated,
  estimated,
}

enum AnalyticsDateRange {
  today,
  last7Days,
  last30Days,
  last90Days,
  custom,
}

class AnalyticsMetric {
  final String title;
  final num value;
  final String unit;
  final MetricType type;

  const AnalyticsMetric({
    required this.title,
    required this.value,
    this.unit = '',
    required this.type,
  });
}

class AnalyticsReport {
  final DateTime startDate;
  final DateTime endDate;
  final AnalyticsDateRange range;
  
  // Sections
  final List<AnalyticsMetric> messagesMetrics;
  final List<AnalyticsMetric> responseTimeMetrics;
  final List<AnalyticsMetric> conversationMetrics; // active, unread
  final List<AnalyticsMetric> contactMetrics; // new contacts
  final List<AnalyticsMetric> channelMetrics;
  final List<AnalyticsMetric> aiUsageMetrics;
  final List<AnalyticsMetric> automationMetrics;
  final List<AnalyticsMetric> callMetrics;
  final List<AnalyticsMetric> notificationMetrics;
  final List<AnalyticsMetric> userEngagementMetrics;
  final List<double> timeSeriesData;

  const AnalyticsReport({
    required this.startDate,
    required this.endDate,
    required this.range,
    required this.messagesMetrics,
    required this.responseTimeMetrics,
    required this.conversationMetrics,
    required this.contactMetrics,
    required this.channelMetrics,
    required this.aiUsageMetrics,
    required this.automationMetrics,
    required this.callMetrics,
    required this.notificationMetrics,
    required this.userEngagementMetrics,
    this.timeSeriesData = const [],
  });
}
