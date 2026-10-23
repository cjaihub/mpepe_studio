import 'package:cloud_firestore/cloud_firestore.dart';

enum PreferenceSource {
  observed,
  userConfirmed,
  aiSuggested,
}

enum PreferenceCategory {
  language,
  style,
  greeting,
  responseLength,
  emoji,
  punctuation,
  responseTime,
  phrase,
  signOff,
  formatting,
  professionalTone,
  friendlyTone,
  businessTone,
  channel,
  drafting,
}

class CommunicationPreference {
  final String id;
  final PreferenceCategory category;
  final String value;
  final PreferenceSource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  CommunicationPreference({
    required this.id,
    required this.category,
    required this.value,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommunicationPreference.fromMap(Map<String, dynamic> map, String id) {
    return CommunicationPreference(
      id: id,
      category: PreferenceCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => PreferenceCategory.style,
      ),
      value: map['value'] as String,
      source: PreferenceSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => PreferenceSource.observed,
      ),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category.name,
      'value': value,
      'source': source.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}

class PersonalizationSettings {
  final bool personalizationEnabled;
  final bool learnFromMessages;
  final bool learnFromApprovedConversations;
  final bool learnFromEdits;
  final bool learnFromReactions;
  final DateTime? lastReset;

  PersonalizationSettings({
    this.personalizationEnabled = false,
    this.learnFromMessages = false,
    this.learnFromApprovedConversations = false,
    this.learnFromEdits = false,
    this.learnFromReactions = false,
    this.lastReset,
  });

  factory PersonalizationSettings.fromMap(Map<String, dynamic> map) {
    return PersonalizationSettings(
      personalizationEnabled: map['personalizationEnabled'] ?? false,
      learnFromMessages: map['learnFromMessages'] ?? false,
      learnFromApprovedConversations: map['learnFromApprovedConversations'] ?? false,
      learnFromEdits: map['learnFromEdits'] ?? false,
      learnFromReactions: map['learnFromReactions'] ?? false,
      lastReset: (map['lastReset'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'personalizationEnabled': personalizationEnabled,
      'learnFromMessages': learnFromMessages,
      'learnFromApprovedConversations': learnFromApprovedConversations,
      'learnFromEdits': learnFromEdits,
      'learnFromReactions': learnFromReactions,
      if (lastReset != null) 'lastReset': Timestamp.fromDate(lastReset!),
    };
  }

  PersonalizationSettings copyWith({
    bool? personalizationEnabled,
    bool? learnFromMessages,
    bool? learnFromApprovedConversations,
    bool? learnFromEdits,
    bool? learnFromReactions,
    DateTime? lastReset,
  }) {
    return PersonalizationSettings(
      personalizationEnabled: personalizationEnabled ?? this.personalizationEnabled,
      learnFromMessages: learnFromMessages ?? this.learnFromMessages,
      learnFromApprovedConversations: learnFromApprovedConversations ?? this.learnFromApprovedConversations,
      learnFromEdits: learnFromEdits ?? this.learnFromEdits,
      learnFromReactions: learnFromReactions ?? this.learnFromReactions,
      lastReset: lastReset ?? this.lastReset,
    );
  }
}
