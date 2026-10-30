import 'dart:math';

/// Status of an episodic execution outcome
enum EpisodeOutcome {
  success,
  failure,
  partial,
}

/// Record of an autonomous agent execution episode
/// Used for "Learn from past mistakes" (Episodic Memory)
class EpisodicMemoryRecord {
  final String id;
  final String userId;
  final String scenarioKey;
  final String triggerPrompt;
  final List<String> executedSteps;
  final EpisodeOutcome outcome;
  final String? failureReason;
  final String? mistakeDetected;
  final String? preventativeGuidance;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  EpisodicMemoryRecord({
    required this.id,
    required this.userId,
    required this.scenarioKey,
    required this.triggerPrompt,
    required this.executedSteps,
    required this.outcome,
    this.failureReason,
    this.mistakeDetected,
    this.preventativeGuidance,
    this.metadata = const {},
    required this.timestamp,
  });

  bool get hadMistake => outcome == EpisodeOutcome.failure && mistakeDetected != null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'scenarioKey': scenarioKey,
        'triggerPrompt': triggerPrompt,
        'executedSteps': executedSteps,
        'outcome': outcome.name,
        'failureReason': failureReason,
        'mistakeDetected': mistakeDetected,
        'preventativeGuidance': preventativeGuidance,
        'metadata': metadata,
        'timestamp': timestamp.toIso8601String(),
      };

  factory EpisodicMemoryRecord.fromMap(Map<String, dynamic> map) {
    return EpisodicMemoryRecord(
      id: map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      scenarioKey: map['scenarioKey'] as String? ?? 'general',
      triggerPrompt: map['triggerPrompt'] as String? ?? '',
      executedSteps: List<String>.from(map['executedSteps'] as List? ?? []),
      outcome: EpisodeOutcome.values.firstWhere(
        (e) => e.name == map['outcome'],
        orElse: () => EpisodeOutcome.success,
      ),
      failureReason: map['failureReason'] as String?,
      mistakeDetected: map['mistakeDetected'] as String?,
      preventativeGuidance: map['preventativeGuidance'] as String?,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Mistake Avoidance Rule synthesized from Episodic Memory
class MistakeAvoidanceRule {
  final String scenarioKey;
  final String mistake;
  final String correctiveAction;
  final double confidence;

  MistakeAvoidanceRule({
    required this.scenarioKey,
    required this.mistake,
    required this.correctiveAction,
    this.confidence = 1.0,
  });
}

/// Entity Node in Semantic Knowledge Graph
class KnowledgeNode {
  final String id;
  final String type; // e.g. 'User', 'Reel', 'Hardware', 'Preference', 'Customer', 'Order'
  final String label;
  final Map<String, dynamic> properties;

  KnowledgeNode({
    required this.id,
    required this.type,
    required this.label,
    this.properties = const {},
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'label': label,
        'properties': properties,
      };

  factory KnowledgeNode.fromMap(Map<String, dynamic> map) {
    return KnowledgeNode(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? 'General',
      label: map['label'] as String? ?? '',
      properties: Map<String, dynamic>.from(map['properties'] as Map? ?? {}),
    );
  }
}

/// Directed Relationship Edge in Semantic Knowledge Graph
class KnowledgeEdge {
  final String id;
  final String sourceId;
  final String targetId;
  final String relation; // e.g. 'PREFERS', 'OWNS', 'CONTAINS', 'PLACED', 'STREAMED_ON'
  final double weight;
  final Map<String, dynamic> metadata;

  KnowledgeEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relation,
    this.weight = 1.0,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sourceId': sourceId,
        'targetId': targetId,
        'relation': relation,
        'weight': weight,
        'metadata': metadata,
      };

  factory KnowledgeEdge.fromMap(Map<String, dynamic> map) {
    return KnowledgeEdge(
      id: map['id'] as String? ?? '',
      sourceId: map['sourceId'] as String? ?? '',
      targetId: map['targetId'] as String? ?? '',
      relation: map['relation'] as String? ?? 'RELATED_TO',
      weight: (map['weight'] as num?)?.toDouble() ?? 1.0,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
    );
  }
}

/// Vector-Indexed Semantic Knowledge item
class SemanticVectorItem {
  final String id;
  final String content;
  final List<double> embedding;
  final String category;
  final DateTime createdAt;

  SemanticVectorItem({
    required this.id,
    required this.content,
    required this.embedding,
    required this.category,
    required this.createdAt,
  });

  /// Computes cosine similarity against a query vector
  double cosineSimilarity(List<double> query) {
    if (embedding.length != query.length || embedding.isEmpty) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < embedding.length; i++) {
      dotProduct += embedding[i] * query[i];
      normA += embedding[i] * embedding[i];
      normB += query[i] * query[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'content': content,
        'embedding': embedding,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SemanticVectorItem.fromMap(Map<String, dynamic> map) {
    return SemanticVectorItem(
      id: map['id'] as String? ?? '',
      content: map['content'] as String? ?? '',
      embedding: (map['embedding'] as List? ?? []).map((e) => (e as num).toDouble()).toList(),
      category: map['category'] as String? ?? 'general',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Real-time emotional state detected from user interaction
enum OvaEmotionValence {
  excited,      // High energy, visionary, celebratory
  creativeFlow, // Ideation, brainstorming, fluid
  focused,      // Analytical, concise, task-oriented
  frustrated,   // Stressed, experiencing roadblocks, needs calm solution
  reflective,   // Thoughtful, warm, relaxed
}

/// Snapshot of user emotion and tone modulation instructions
class OvaEmotionSnapshot {
  final OvaEmotionValence valence;
  final double intensity; // 0.0 to 1.0
  final String primaryEmotionLabel;
  final String toneGuidance;
  final DateTime timestamp;

  OvaEmotionSnapshot({
    required this.valence,
    required this.intensity,
    required this.primaryEmotionLabel,
    required this.toneGuidance,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'valence': valence.name,
        'intensity': intensity,
        'primaryEmotionLabel': primaryEmotionLabel,
        'toneGuidance': toneGuidance,
        'timestamp': timestamp.toIso8601String(),
      };

  factory OvaEmotionSnapshot.fromMap(Map<String, dynamic> map) {
    return OvaEmotionSnapshot(
      valence: OvaEmotionValence.values.firstWhere(
        (e) => e.name == map['valence'],
        orElse: () => OvaEmotionValence.creativeFlow,
      ),
      intensity: (map['intensity'] as num?)?.toDouble() ?? 0.8,
      primaryEmotionLabel: map['primaryEmotionLabel'] as String? ?? 'Creative Flow',
      toneGuidance: map['toneGuidance'] as String? ?? 'Warm, collaborative, executive',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Rolling session summary that condenses long context into < 120 tokens
class OvaRollingSummary {
  final String sessionId;
  final String userId;
  final String summaryText;
  final List<String> keyDecisions;
  final List<String> activeEntities;
  final int turnCount;
  final DateTime updatedAt;

  OvaRollingSummary({
    required this.sessionId,
    required this.userId,
    required this.summaryText,
    required this.keyDecisions,
    required this.activeEntities,
    required this.turnCount,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'userId': userId,
        'summaryText': summaryText,
        'keyDecisions': keyDecisions,
        'activeEntities': activeEntities,
        'turnCount': turnCount,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory OvaRollingSummary.fromMap(Map<String, dynamic> map) {
    return OvaRollingSummary(
      sessionId: map['sessionId'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      summaryText: map['summaryText'] as String? ?? '',
      keyDecisions: List<String>.from(map['keyDecisions'] as List? ?? []),
      activeEntities: List<String>.from(map['activeEntities'] as List? ?? []),
      turnCount: (map['turnCount'] as num?)?.toInt() ?? 0,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
