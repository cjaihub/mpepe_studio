import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/unified_inbox_provider.dart';
import 'package:oneova/backend/analytics/models/analytics_models.dart';
import 'package:oneova/backend/analytics/services/analytics_engine.dart';

void main() {
  late AnalyticsEngine engine;

  setUp(() {
    engine = AnalyticsEngine();
  });

  test('Properly sums compatible metrics and retains individual source metadata', () {
    final payload = {
      SocialPlatform.youtube: {
        'views': 5000,
        'revenue': 150.0,
        'freshness': DateTime(2023, 1, 1),
        'coverage': 1.0,
      },
      SocialPlatform.tiktok: {
        'views': 12000,
        'revenue': 20.0,
        'freshness': DateTime(2023, 1, 1),
        'coverage': 0.9,
      }
    };

    final dashboard = engine.compileDashboard(payload);

    final viewMetric = dashboard.metrics.firstWhere((m) => m.id == 'metric_views');
    expect(viewMetric.value, 17000); // 5000 + 12000
    expect(viewMetric.metadataSources.length, 2);
    expect(viewMetric.metadataSources.firstWhere((s) => s.source == SocialPlatform.youtube).coverage, 1.0);
    expect(viewMetric.metadataSources.firstWhere((s) => s.source == SocialPlatform.tiktok).coverage, 0.9);

    expect(dashboard.overallCoverage, 0.95); // Average of 1.0 and 0.9
  });

  test('Documents calculations for incompatible metrics (Engagement)', () {
    final payload = {
      SocialPlatform.meta: {
        'engagement_rate': 0.05,
      },
      SocialPlatform.instagram: {
        'engagement_rate': 0.08,
      }
    };

    final dashboard = engine.compileDashboard(payload);
    
    final engMetric = dashboard.metrics.firstWhere((m) => m.id == 'metric_engagement');
    expect(engMetric.value, 0.13); // Naive sum composite

    final fbSource = engMetric.metadataSources.firstWhere((s) => s.source == SocialPlatform.meta);
    expect(fbSource.aggregationMethod, AggregationMethod.compositeWeighted);
    expect(fbSource.calculationNote, isNotNull); // MUST document the calculation
    expect(fbSource.calculationNote!.contains('unweighted'), true);
  });

  test('Propagates provider errors properly', () {
    final payload = {
      SocialPlatform.youtube: {
        'views': 500,
        'error': 'Quota Exceeded',
      },
      SocialPlatform.tiktok: {
        'views': 1000,
      }
    };

    final dashboard = engine.compileDashboard(payload);
    
    expect(dashboard.providerErrors[SocialPlatform.youtube], 'Quota Exceeded');
    
    final viewMetric = dashboard.metrics.firstWhere((m) => m.id == 'metric_views');
    expect(viewMetric.hasErrors, true); // It flags the metric block as containing partial error data
  });
}
