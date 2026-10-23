import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedLayoutMode {
  algorithmic,
  chronological,
  followingOnly,
  reducedRecommendations,
}

class DigitalWellbeingPreferences {
  final String userId;
  final bool screenTimeRemindersEnabled;
  final int screenTimeLimitMinutes; // Daily limit before hard/soft lock
  
  final bool breakRemindersEnabled;
  final int breakReminderIntervalMinutes; // Remind every X minutes of continuous scrolling
  
  final bool quietModeEnabled; // Suppresses non-essential notifications
  final int quietHoursStart; 
  final int quietHoursEnd;
  
  final FeedLayoutMode feedMode;
  
  final List<String> contentFilters; // Filter out specific tags or words

  const DigitalWellbeingPreferences({
    required this.userId,
    this.screenTimeRemindersEnabled = false,
    this.screenTimeLimitMinutes = 120,
    this.breakRemindersEnabled = true,
    this.breakReminderIntervalMinutes = 30,
    this.quietModeEnabled = true,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 8,
    this.feedMode = FeedLayoutMode.algorithmic,
    this.contentFilters = const [],
  });

  factory DigitalWellbeingPreferences.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) {
      return DigitalWellbeingPreferences(userId: doc.id);
    }
    final data = doc.data() as Map<String, dynamic>;
    return DigitalWellbeingPreferences(
      userId: doc.id,
      screenTimeRemindersEnabled: data['screenTimeRemindersEnabled'] ?? false,
      screenTimeLimitMinutes: data['screenTimeLimitMinutes'] ?? 120,
      breakRemindersEnabled: data['breakRemindersEnabled'] ?? true,
      breakReminderIntervalMinutes: data['breakReminderIntervalMinutes'] ?? 30,
      quietModeEnabled: data['quietModeEnabled'] ?? true,
      quietHoursStart: data['quietHoursStart'] ?? 22,
      quietHoursEnd: data['quietHoursEnd'] ?? 8,
      feedMode: FeedLayoutMode.values.firstWhere(
        (e) => e.name == data['feedMode'],
        orElse: () => FeedLayoutMode.algorithmic,
      ),
      contentFilters: List<String>.from(data['contentFilters'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'screenTimeRemindersEnabled': screenTimeRemindersEnabled,
      'screenTimeLimitMinutes': screenTimeLimitMinutes,
      'breakRemindersEnabled': breakRemindersEnabled,
      'breakReminderIntervalMinutes': breakReminderIntervalMinutes,
      'quietModeEnabled': quietModeEnabled,
      'quietHoursStart': quietHoursStart,
      'quietHoursEnd': quietHoursEnd,
      'feedMode': feedMode.name,
      'contentFilters': contentFilters,
    };
  }
}
