
enum AutoModeLevel {
  off,
  suggestionsOnly,
  draftAutomatically,
  autoSendApprovedScenarios,
  fullAutoMode,
}

class AutoModeSettings {
  final AutoModeLevel level;
  final List<String> allowedContacts;
  final List<String> blockedContacts;
  final List<String> allowedConversations;
  final List<String> blockedConversations;
  final String allowedHours; // Format e.g., "09:00-17:00" or "always"
  final int maxMessagesPerDay;
  final int maxAiActionsPerDay;
  final List<String> allowedChannels;
  final bool escalateToHuman;

  AutoModeSettings({
    this.level = AutoModeLevel.off,
    this.allowedContacts = const [],
    this.blockedContacts = const [],
    this.allowedConversations = const [],
    this.blockedConversations = const [],
    this.allowedHours = 'always',
    this.maxMessagesPerDay = 50,
    this.maxAiActionsPerDay = 100,
    this.allowedChannels = const ['all'],
    this.escalateToHuman = true,
  });

  factory AutoModeSettings.fromMap(Map<String, dynamic> map) {
    return AutoModeSettings(
      level: AutoModeLevel.values.firstWhere(
        (e) => e.name == map['level'],
        orElse: () => AutoModeLevel.off,
      ),
      allowedContacts: List<String>.from(map['allowedContacts'] ?? []),
      blockedContacts: List<String>.from(map['blockedContacts'] ?? []),
      allowedConversations: List<String>.from(map['allowedConversations'] ?? []),
      blockedConversations: List<String>.from(map['blockedConversations'] ?? []),
      allowedHours: map['allowedHours'] as String? ?? 'always',
      maxMessagesPerDay: map['maxMessagesPerDay'] as int? ?? 50,
      maxAiActionsPerDay: map['maxAiActionsPerDay'] as int? ?? 100,
      allowedChannels: List<String>.from(map['allowedChannels'] ?? ['all']),
      escalateToHuman: map['escalateToHuman'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
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

  AutoModeSettings copyWith({
    AutoModeLevel? level,
    List<String>? allowedContacts,
    List<String>? blockedContacts,
    List<String>? allowedConversations,
    List<String>? blockedConversations,
    String? allowedHours,
    int? maxMessagesPerDay,
    int? maxAiActionsPerDay,
    List<String>? allowedChannels,
    bool? escalateToHuman,
  }) {
    return AutoModeSettings(
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
