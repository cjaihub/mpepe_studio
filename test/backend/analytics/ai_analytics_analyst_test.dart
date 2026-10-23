import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:oneova/backend/unified_inbox_provider.dart';
import 'package:oneova/backend/analytics/models/analytics_models.dart';
import 'package:oneova/backend/analytics/models/ai_analytics_models.dart';
import 'package:oneova/backend/analytics/services/ai_analytics_analyst.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';

import 'ai_analytics_analyst_test.mocks.dart';

@GenerateMocks([OpenRouterAgentService])
void main() {
  late MockOpenRouterAgentService mockAgentService;
  late AIAnalyticsAnalyst analyst;

  setUp(() {
    mockAgentService = MockOpenRouterAgentService();
    analyst = AIAnalyticsAnalyst(mockAgentService);
  });

  test('Correctly parses valid AI JSON and maps evidence properly', () async {
    // 1. Arrange canned response from agent
    const cannedResponse = '''
    ```json
    {
      "type": "performanceDriver",
      "title": "High YouTube Viewer Retention",
      "hypothesis": "The video performed well due to high retention in the first 3 seconds, heavily driven by YouTube.",
      "confidence": "high",
      "evidence": [
        {
          "metricName": "Views",
          "value": "15000",
          "isCalculated": false
        },
        {
          "metricName": "Composite Engagement",
          "value": "0.15",
          "isCalculated": true,
          "calculationNote": "Aggregated unweighted engagement rate across platforms."
        }
      ]
    }
    ```
    ''';

    when(mockAgentService.queryAgent(any, any)).thenAnswer((_) async => cannedResponse);

    // 2. Prepare dummy dashboard data
    final dashboardData = AnalyticsDashboardData(
      metrics: [
        AnalyticMetric(
          id: '1', 
          name: 'Views', 
          value: 15000, 
          metadataSources: [
            MetricMetadata(
              source: SocialPlatform.youtube,
              startTime: DateTime.now(),
              endTime: DateTime.now(),
              freshness: DateTime.now(),
              coverage: 1.0,
              aggregationMethod: AggregationMethod.sum
            )
          ]
        )
      ],
      lastSynced: {SocialPlatform.youtube: DateTime.now()},
      providerErrors: {},
      overallCoverage: 1.0,
    );

    // 3. Act
    final insight = await analyst.generateInsight("Why did this video perform well?", dashboardData);

    // 4. Assert
    expect(insight, isNotNull);
    expect(insight!.type, InsightType.performanceDriver);
    expect(insight.title, "High YouTube Viewer Retention");
    expect(insight.confidence, InsightConfidence.high);
    expect(insight.evidence.length, 2);
    
    expect(insight.evidence[0].metricName, "Views");
    expect(insight.evidence[0].isCalculated, false);

    expect(insight.evidence[1].metricName, "Composite Engagement");
    expect(insight.evidence[1].isCalculated, true);
    expect(insight.evidence[1].calculationNote, "Aggregated unweighted engagement rate across platforms.");
  });

  test('Returns null gracefully on malformed JSON response', () async {
    when(mockAgentService.queryAgent(any, any)).thenAnswer((_) async => "I am an AI. I think it performed well because it's good.");

    final dashboardData = AnalyticsDashboardData(
      metrics: [],
      lastSynced: {},
      providerErrors: {},
      overallCoverage: 1.0,
    );

    final insight = await analyst.generateInsight("Why?", dashboardData);
    expect(insight, isNull);
  });
}
