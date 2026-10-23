import 'package:oneova/backend/briefs/models/daily_brief_models.dart';

// In a real implementation, these would be injected repositories.
// We stub them here to represent the "All information must come from real connected sources" constraint.
abstract class RealSourceConnector {
  int getUnreadMessageCount(String userId);
  int getMissedCallCount(String userId);
  int getPendingTaskCount(String userId);
  double getPerformanceMetric(String userId);
}

class DailyBriefService {
  final Map<String, DailyBriefSettings> _settings = {};
  final RealSourceConnector _sources;

  DailyBriefService(this._sources);

  DailyBriefSettings getSettings(String userId) {
    return _settings.putIfAbsent(userId, () => DailyBriefSettings(userId: userId));
  }

  void updateSettings(String userId, DailyBriefSettings settings) {
    _settings[userId] = settings;
  }

  DailyBrief? generateMorningBrief(String userId) {
    final s = getSettings(userId);
    if (!s.isMorningBriefEnabled) return null;

    final insights = <BriefInsight>[];

    // FACT: Directly pulled from connected sources
    final unreadMessages = _sources.getUnreadMessageCount(userId);
    insights.add(BriefInsight(
      id: 'insight_${DateTime.now().microsecondsSinceEpoch}_1',
      category: 'messages',
      content: 'You have $unreadMessages important unread messages.',
      confidenceType: BriefInsightConfidence.fact,
    ));

    final missedCalls = _sources.getMissedCallCount(userId);
    if (missedCalls > 0) {
      insights.add(BriefInsight(
        id: 'insight_${DateTime.now().microsecondsSinceEpoch}_2',
        category: 'calls',
        content: 'You missed $missedCalls calls overnight.',
        confidenceType: BriefInsightConfidence.fact,
      ));
    }

    // CALCULATION: AI interprets real data
    final tasks = _sources.getPendingTaskCount(userId);
    final hoursNeeded = (tasks * 1.5).round(); // AI estimates 1.5 hrs per task
    insights.add(BriefInsight(
      id: 'insight_${DateTime.now().microsecondsSinceEpoch}_3',
      category: 'tasks',
      content: 'You have $tasks unfinished tasks. It will take approximately $hoursNeeded hours to complete them.',
      confidenceType: BriefInsightConfidence.calculation,
    ));

    // RECOMMENDATION: AI provides advice based on state
    insights.add(BriefInsight(
      id: 'insight_${DateTime.now().microsecondsSinceEpoch}_4',
      category: 'schedule',
      content: 'Consider tackling your $tasks pending tasks before checking your $unreadMessages messages.',
      confidenceType: BriefInsightConfidence.recommendation,
    ));

    return DailyBrief(
      id: 'brief_m_${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      timeOfDay: BriefTime.morning,
      generatedAt: DateTime.now(),
      insights: insights,
    );
  }

  DailyBrief? generateEveningBrief(String userId) {
    final s = getSettings(userId);
    if (!s.isEveningBriefEnabled) return null;

    final insights = <BriefInsight>[];

    // FACT
    final performance = _sources.getPerformanceMetric(userId);
    insights.add(BriefInsight(
      id: 'insight_${DateTime.now().microsecondsSinceEpoch}_1',
      category: 'performance',
      content: 'Your content reached $performance% more users today.',
      confidenceType: BriefInsightConfidence.fact,
    ));

    // CALCULATION
    final unreadMessages = _sources.getUnreadMessageCount(userId);
    final estimatedTime = (unreadMessages * 2).round(); // 2 mins per reply
    insights.add(BriefInsight(
      id: 'insight_${DateTime.now().microsecondsSinceEpoch}_2',
      category: 'messages',
      content: 'You have $unreadMessages unanswered conversations taking an estimated $estimatedTime minutes to clear.',
      confidenceType: BriefInsightConfidence.calculation,
    ));

    // RECOMMENDATION
    insights.add(BriefInsight(
      id: 'insight_${DateTime.now().microsecondsSinceEpoch}_3',
      category: 'planning',
      content: 'Schedule tomorrow\'s posts tonight to maintain your growth momentum.',
      confidenceType: BriefInsightConfidence.recommendation,
    ));

    return DailyBrief(
      id: 'brief_e_${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      timeOfDay: BriefTime.evening,
      generatedAt: DateTime.now(),
      insights: insights,
    );
  }
}
