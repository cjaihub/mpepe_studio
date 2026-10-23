enum AiComposerAction {
  improve,
  shorten,
  expand,
  makeProfessional,
  makeFriendly,
  translate,
  reply,
  summarize,
  rewrite,
  voiceDraft,
}

enum AiSuggestionState {
  suggestion,
  accepted,
  edited,
  rejected,
  regenerating,
}

enum AutoModeLevel {
  off,
  suggestionsOnly,
  draftAutomatically,
  autoSendApprovedScenarios,
  fullAutoMode,
}

enum SensitiveTopicCategory {
  financialCommitments,
  passwordSecurityChanges,
  accountDeletion,
  legalAgreements,
  identityVerification,
  medicalDecisions,
  highImpactPersonalDecisions,
  none,
}

class AutoModeConfig {
  final AutoModeLevel level;
  final List<String> allowedContacts;
  final List<String> blockedContacts;
  final List<String> allowedConversations;
  final List<String> blockedConversations;
  final List<String> allowedHours; // e.g., ["09:00-17:00"]
  final int maxMessagesPerDay;
  final int maxAiActionsPerDay;
  final List<String> allowedChannels;
  final bool escalateToHuman;

  const AutoModeConfig({
    this.level = AutoModeLevel.off,
    this.allowedContacts = const [],
    this.blockedContacts = const [],
    this.allowedConversations = const [],
    this.blockedConversations = const [],
    this.allowedHours = const [],
    this.maxMessagesPerDay = 50,
    this.maxAiActionsPerDay = 100,
    this.allowedChannels = const [],
    this.escalateToHuman = true,
  });

  factory AutoModeConfig.fromJson(Map<String, dynamic> json) {
    return AutoModeConfig(
      level: AutoModeLevel.values.firstWhere(
        (e) => e.name == json['level'],
        orElse: () => AutoModeLevel.off,
      ),
      allowedContacts: List<String>.from(json['allowedContacts'] ?? []),
      blockedContacts: List<String>.from(json['blockedContacts'] ?? []),
      allowedConversations: List<String>.from(json['allowedConversations'] ?? []),
      blockedConversations: List<String>.from(json['blockedConversations'] ?? []),
      allowedHours: List<String>.from(json['allowedHours'] ?? []),
      maxMessagesPerDay: json['maxMessagesPerDay'] ?? 50,
      maxAiActionsPerDay: json['maxAiActionsPerDay'] ?? 100,
      allowedChannels: List<String>.from(json['allowedChannels'] ?? []),
      escalateToHuman: json['escalateToHuman'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'level': level.name,
      'allowedContacts': allowedContacts,
      'blockedContacts': blockedContacts,
      'allowedConversations': allowedConversations,
      'blockedConversations': blockedConversations,
      'allowedHours': allowedHours,
      'maxMessagesPerDay': maxMessagesPerDay,
      'maxAiActionsPerDay': maxAiActionsPerDay,
      'allowedChannels': allowedChannels,
      'escalateToHuman': escalateToHuman,
    };
  }

  AutoModeConfig copyWith({
    AutoModeLevel? level,
    List<String>? allowedContacts,
    List<String>? blockedContacts,
    List<String>? allowedConversations,
    List<String>? blockedConversations,
    List<String>? allowedHours,
    int? maxMessagesPerDay,
    int? maxAiActionsPerDay,
    List<String>? allowedChannels,
    bool? escalateToHuman,
  }) {
    return AutoModeConfig(
      level: level ?? this.level,
      allowedContacts: allowedContacts ?? this.allowedContacts,
      blockedContacts: blockedContacts ?? this.blockedContacts,
      allowedConversations: allowedConversations ?? this.allowedConversations,
      blockedConversations: blockedConversations ?? this.blockedConversations,
      allowedHours: allowedHours ?? this.allowedHours,
      maxMessagesPerDay: maxMessagesPerDay ?? this.maxMessagesPerDay,
      maxAiActionsPerDay: maxAiActionsPerDay ?? this.maxAiActionsPerDay,
      allowedChannels: allowedChannels ?? this.allowedChannels,
      escalateToHuman: escalateToHuman ?? this.escalateToHuman,
    );
  }
}
