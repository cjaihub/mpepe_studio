import 'package:oneova/backend/unified_inbox_provider.dart';
import 'package:oneova/backend/analytics/models/analytics_models.dart';

class AnalyticsEngine {
  /// Aggregates metrics from multiple external platform payloads into a single unified Dashboard model.
  /// Enforces that incompatible metrics are either kept distinct or mathematically reconciled with a logged calculationNote.
  AnalyticsDashboardData compileDashboard(Map<SocialPlatform, Map<String, dynamic>> providerPayloads) {
    List<AnalyticMetric> metrics = [];
    Map<SocialPlatform, DateTime> lastSynced = {};
    Map<SocialPlatform, String> providerErrors = {};
    
    // Core categories we want to extract
    double totalViews = 0;
    List<MetricMetadata> viewSources = [];

    double totalRevenue = 0;
    List<MetricMetadata> revenueSources = [];

    // Engagement is inherently incompatible between platforms (e.g., TikTok saves vs FB shares)
    // We must document the calculation when aggregating.
    double compositeEngagement = 0;
    List<MetricMetadata> engagementSources = [];

    providerPayloads.forEach((platform, payload) {
      final freshness = payload['freshness'] as DateTime? ?? DateTime.now();
      lastSynced[platform] = freshness;

      if (payload.containsKey('error')) {
        providerErrors[platform] = payload['error'];
        // Continue aggregating what we can, but note the error
      }

      // 1. Views (Compatible standard count)
      if (payload.containsKey('views')) {
        totalViews += (payload['views'] as num).toDouble();
        viewSources.add(MetricMetadata(
          source: platform,
          startTime: payload['start_time'] ?? DateTime.now().subtract(const Duration(days: 7)),
          endTime: payload['end_time'] ?? DateTime.now(),
          freshness: freshness,
          coverage: payload['coverage'] ?? 1.0,
          aggregationMethod: AggregationMethod.sum,
          providerError: payload['error'],
        ));
      }

      // 2. Revenue (Compatible currency sum, assuming normalized to USD prior to engine ingestion)
      if (payload.containsKey('revenue')) {
        totalRevenue += (payload['revenue'] as num).toDouble();
        revenueSources.add(MetricMetadata(
          source: platform,
          startTime: payload['start_time'] ?? DateTime.now().subtract(const Duration(days: 7)),
          endTime: payload['end_time'] ?? DateTime.now(),
          freshness: freshness,
          coverage: payload['coverage'] ?? 1.0,
          aggregationMethod: AggregationMethod.sum,
          providerError: payload['error'],
        ));
      }

      // 3. Engagement (Incompatible definitions)
      if (payload.containsKey('engagement_rate')) {
        // We will combine 'engagement_rate' into a composite score, but we MUST document it.
        final rate = (payload['engagement_rate'] as num).toDouble();
        compositeEngagement += rate; // Very naive composite for example, real would weight by impressions
        engagementSources.add(MetricMetadata(
          source: platform,
          startTime: payload['start_time'] ?? DateTime.now().subtract(const Duration(days: 7)),
          endTime: payload['end_time'] ?? DateTime.now(),
          freshness: freshness,
          coverage: payload['coverage'] ?? 1.0,
          aggregationMethod: AggregationMethod.compositeWeighted,
          calculationNote: 'Aggregated unweighted engagement rate across platforms. (TikTok weight != FB weight).',
          providerError: payload['error'],
        ));
      }
    });

    metrics.add(AnalyticMetric(
      id: 'metric_views',
      name: 'Views',
      value: totalViews,
      metadataSources: viewSources,
      hasErrors: viewSources.any((s) => s.providerError != null),
    ));

    metrics.add(AnalyticMetric(
      id: 'metric_revenue',
      name: 'Revenue',
      value: totalRevenue,
      unit: 'USD',
      metadataSources: revenueSources,
      hasErrors: revenueSources.any((s) => s.providerError != null),
    ));

    metrics.add(AnalyticMetric(
      id: 'metric_engagement',
      name: 'Composite Engagement',
      value: compositeEngagement,
      unit: 'rate',
      metadataSources: engagementSources,
      hasErrors: engagementSources.any((s) => s.providerError != null),
    ));

    // Calculate global coverage
    double totalCov = 0.0;
    int count = viewSources.length;
    for (var s in viewSources) {
      totalCov += s.coverage;
    }
    double overallCoverage = count > 0 ? (totalCov / count) : 0.0;

    return AnalyticsDashboardData(
      metrics: metrics,
      lastSynced: lastSynced,
      providerErrors: providerErrors,
      overallCoverage: overallCoverage,
    );
  }
}
