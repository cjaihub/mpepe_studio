enum BriefTime {
  morning,
  evening,
}

enum BriefInsightConfidence {
  fact,
  calculation,
  recommendation,
}

class BriefInsight {
  final String id;
  final String category; // e.g. 'messages', 'performance', 'tasks'
  final String content;
  final BriefInsightConfidence confidenceType; // Must explicitly classify the insight

  const BriefInsight({
    required this.id,
    required this.category,
    required this.content,
    required this.confidenceType,
  });
}

class DailyBrief {
  final String id;
  final String userId;
  final BriefTime timeOfDay;
  final DateTime generatedAt;
  
  final List<BriefInsight> insights;
  
  const DailyBrief({
    required this.id,
    required this.userId,
    required this.timeOfDay,
    required this.generatedAt,
    required this.insights,
  });
}

class DailyBriefSettings {
  final String userId;
  bool isMorningBriefEnabled;
  bool isEveningBriefEnabled;
  int morningTimeTarget; // Hour (e.g. 7 for 7 AM)
  int eveningTimeTarget; // Hour (e.g. 20 for 8 PM)

  DailyBriefSettings({
    required this.userId,
    this.isMorningBriefEnabled = true,
    this.isEveningBriefEnabled = true,
    this.morningTimeTarget = 7,
    this.eveningTimeTarget = 20,
  });
}
