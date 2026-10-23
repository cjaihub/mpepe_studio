import 'package:oneova/backend/unified_inbox_provider.dart'; // for SocialPlatform

enum AggregationMethod {
  sum,
  average,
  latest,
  compositeWeighted,
}

class MetricMetadata {
  final SocialPlatform source;
  final DateTime startTime;
  final DateTime endTime;
  final DateTime freshness; // Last synced time
  final double coverage; // Percentage 0.0 to 1.0 of data accounted for
  final AggregationMethod aggregationMethod;
  final String? calculationNote; // Used when combining incompatible metrics
  final String? providerError;

  const MetricMetadata({
    required this.source,
    required this.startTime,
    required this.endTime,
    required this.freshness,
    required this.coverage,
    required this.aggregationMethod,
    this.calculationNote,
    this.providerError,
  });
}

class AnalyticMetric {
  final String id;
  final String name; // e.g., 'Views', 'Watch Time'
  final double value;
  final String unit;
  final List<MetricMetadata> metadataSources;
  final bool hasErrors;

  const AnalyticMetric({
    required this.id,
    required this.name,
    required this.value,
    this.unit = 'count',
    required this.metadataSources,
    this.hasErrors = false,
  });
}

class AnalyticsDashboardData {
  final List<AnalyticMetric> metrics;
  final Map<SocialPlatform, DateTime> lastSynced;
  final Map<SocialPlatform, String> providerErrors;
  final double overallCoverage;

  const AnalyticsDashboardData({
    required this.metrics,
    required this.lastSynced,
    required this.providerErrors,
    required this.overallCoverage,
  });
}
