import 'package:cloud_firestore/cloud_firestore.dart';

enum InteractionType {
  watchDuration,
  completion,
  rewatch,
  skip,
  like,
  dislike,
  notInterested,
  share,
  save,
  comment,
  follow,
  unfollow,
  search,
  soundInteraction,
  topicInteraction
}

class UserInteractionEvent {
  final String id;
  final String userId;
  final String targetId;
  final InteractionType type;
  final double weight; // e.g., watch duration in seconds, or 1.0 for a like
  final DateTime timestamp;
  final Map<String, dynamic>? sessionContext; // locale, region, device type

  const UserInteractionEvent({
    required this.id,
    required this.userId,
    required this.targetId,
    required this.type,
    this.weight = 1.0,
    required this.timestamp,
    this.sessionContext,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'targetId': targetId,
      'type': type.name,
      'weight': weight,
      'timestamp': timestamp,
      if (sessionContext != null) 'sessionContext': sessionContext,
    };
  }
}

class RecommendationExplanation {
  final String videoId;
  final List<String> reasons;

  const RecommendationExplanation({
    required this.videoId,
    required this.reasons,
  });
}

class RecommendationPreferences {
  final String userId;
  final List<String> hiddenTopics;
  final List<String> hiddenCreators;
  final Map<String, double> explicitInterests; // topic -> weight (0.0 to 1.0)
  final bool dataCollectionEnabled;
  final DateTime lastResetTime;

  const RecommendationPreferences({
    required this.userId,
    this.hiddenTopics = const [],
    this.hiddenCreators = const [],
    this.explicitInterests = const {},
    this.dataCollectionEnabled = true,
    required this.lastResetTime,
  });

  factory RecommendationPreferences.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) {
      return RecommendationPreferences(
        userId: doc.id,
        lastResetTime: DateTime.now(),
      );
    }
    final data = doc.data() as Map<String, dynamic>;
    return RecommendationPreferences(
      userId: doc.id,
      hiddenTopics: List<String>.from(data['hiddenTopics'] ?? []),
      hiddenCreators: List<String>.from(data['hiddenCreators'] ?? []),
      explicitInterests: Map<String, double>.from(data['explicitInterests'] ?? {}),
      dataCollectionEnabled: data['dataCollectionEnabled'] ?? true,
      lastResetTime: (data['lastResetTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hiddenTopics': hiddenTopics,
      'hiddenCreators': hiddenCreators,
      'explicitInterests': explicitInterests,
      'dataCollectionEnabled': dataCollectionEnabled,
      'lastResetTime': lastResetTime,
    };
  }
}
