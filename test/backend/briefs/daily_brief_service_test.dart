import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/briefs/models/daily_brief_models.dart';
import 'package:oneova/backend/briefs/services/daily_brief_service.dart';

// Mock connector supplying real data to the brief service
class MockSourceConnector implements RealSourceConnector {
  @override
  int getUnreadMessageCount(String userId) => 12;

  @override
  int getMissedCallCount(String userId) => 2;

  @override
  int getPendingTaskCount(String userId) => 4;

  @override
  double getPerformanceMetric(String userId) => 15.5;
}

void main() {
  late DailyBriefService service;
  late MockSourceConnector mockConnector;

  setUp(() {
    mockConnector = MockSourceConnector();
    service = DailyBriefService(mockConnector);
  });

  test('Morning brief pulls real data and strictly classifies insights', () {
    final brief = service.generateMorningBrief('user_99')!;
    
    expect(brief.timeOfDay, BriefTime.morning);
    expect(brief.insights.length, 4);

    // Insight 1: FACT (Unread messages)
    expect(brief.insights[0].confidenceType, BriefInsightConfidence.fact);
    expect(brief.insights[0].content, contains('12 important unread messages'));

    // Insight 2: FACT (Missed calls)
    expect(brief.insights[1].confidenceType, BriefInsightConfidence.fact);
    expect(brief.insights[1].content, contains('missed 2 calls'));

    // Insight 3: CALCULATION (Tasks * 1.5 hrs)
    expect(brief.insights[2].confidenceType, BriefInsightConfidence.calculation);
    expect(brief.insights[2].content, contains('6 hours to complete'));

    // Insight 4: RECOMMENDATION
    expect(brief.insights[3].confidenceType, BriefInsightConfidence.recommendation);
    expect(brief.insights[3].content, contains('Consider tackling'));
  });

  test('Evening brief aggregates performance and predicts workload', () {
    final brief = service.generateEveningBrief('user_99')!;
    
    expect(brief.timeOfDay, BriefTime.evening);

    final performanceInsight = brief.insights.firstWhere((i) => i.category == 'performance');
    expect(performanceInsight.confidenceType, BriefInsightConfidence.fact);
    expect(performanceInsight.content, contains('15.5% more users'));

    final workloadInsight = brief.insights.firstWhere((i) => i.category == 'messages');
    expect(workloadInsight.confidenceType, BriefInsightConfidence.calculation);
    // 12 unread * 2 mins = 24 mins
    expect(workloadInsight.content, contains('24 minutes to clear'));
  });
}
