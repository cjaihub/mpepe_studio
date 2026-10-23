
enum ProfileVisibility { public, contactsOnly, private }
enum MessagePermissions { everyone, contactsOnly, none }
enum OnlineVisibility { everyone, contactsOnly, nobody }
enum AILocalAgentMode { off, suggestionsOnly, drafts, autoApprove, fullAuto }

class AppSettings {
  // Security
  final bool requirePasskey;
  final bool loginAlerts;
  
  // Privacy
  final ProfileVisibility profileVisibility;
  final MessagePermissions messagePermissions;
  final OnlineVisibility onlineVisibility;
  final bool readReceipts;
  final bool typingStatus;
  final bool allowMediaAutoDownload;
  final bool dataRetentionForever;
  
  // AI
  final bool aiEnabled;
  final bool aiSuggestions;
  final AILocalAgentMode autoMode;
  final bool backgroundAgentEnabled;
  final String voiceSelection;
  final bool aiPersonalization;
  
  // Appearance
  final bool isDarkMode;
  final String language;

  const AppSettings({
    this.requirePasskey = false,
    this.loginAlerts = true,
    this.profileVisibility = ProfileVisibility.public,
    this.messagePermissions = MessagePermissions.everyone,
    this.onlineVisibility = OnlineVisibility.everyone,
    this.readReceipts = true,
    this.typingStatus = true,
    this.allowMediaAutoDownload = true,
    this.dataRetentionForever = true,
    this.aiEnabled = true,
    this.aiSuggestions = true,
    this.autoMode = AILocalAgentMode.off,
    this.backgroundAgentEnabled = false,
    this.voiceSelection = 'default',
    this.aiPersonalization = true,
    this.isDarkMode = true,
    this.language = 'en',
  });

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      requirePasskey: map['requirePasskey'] ?? false,
      loginAlerts: map['loginAlerts'] ?? true,
      profileVisibility: ProfileVisibility.values.firstWhere((e) => e.name == map['profileVisibility'], orElse: () => ProfileVisibility.public),
      messagePermissions: MessagePermissions.values.firstWhere((e) => e.name == map['messagePermissions'], orElse: () => MessagePermissions.everyone),
      onlineVisibility: OnlineVisibility.values.firstWhere((e) => e.name == map['onlineVisibility'], orElse: () => OnlineVisibility.everyone),
      readReceipts: map['readReceipts'] ?? true,
      typingStatus: map['typingStatus'] ?? true,
      allowMediaAutoDownload: map['allowMediaAutoDownload'] ?? true,
      dataRetentionForever: map['dataRetentionForever'] ?? true,
      aiEnabled: map['aiEnabled'] ?? true,
      aiSuggestions: map['aiSuggestions'] ?? true,
      autoMode: AILocalAgentMode.values.firstWhere((e) => e.name == map['autoMode'], orElse: () => AILocalAgentMode.off),
      backgroundAgentEnabled: map['backgroundAgentEnabled'] ?? false,
      voiceSelection: map['voiceSelection'] ?? 'default',
      aiPersonalization: map['aiPersonalization'] ?? true,
      isDarkMode: map['isDarkMode'] ?? true,
      language: map['language'] ?? 'en',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requirePasskey': requirePasskey,
      'loginAlerts': loginAlerts,
      'profileVisibility': profileVisibility.name,
      'messagePermissions': messagePermissions.name,
      'onlineVisibility': onlineVisibility.name,
      'readReceipts': readReceipts,
      'typingStatus': typingStatus,
      'allowMediaAutoDownload': allowMediaAutoDownload,
      'dataRetentionForever': dataRetentionForever,
      'aiEnabled': aiEnabled,
      'aiSuggestions': aiSuggestions,
      'autoMode': autoMode.name,
      'backgroundAgentEnabled': backgroundAgentEnabled,
      'voiceSelection': voiceSelection,
      'aiPersonalization': aiPersonalization,
      'isDarkMode': isDarkMode,
      'language': language,
    };
  }

  AppSettings copyWith({
    bool? requirePasskey,
    bool? loginAlerts,
    ProfileVisibility? profileVisibility,
    MessagePermissions? messagePermissions,
    OnlineVisibility? onlineVisibility,
    bool? readReceipts,
    bool? typingStatus,
    bool? allowMediaAutoDownload,
    bool? dataRetentionForever,
    bool? aiEnabled,
    bool? aiSuggestions,
    AILocalAgentMode? autoMode,
    bool? backgroundAgentEnabled,
    String? voiceSelection,
    bool? aiPersonalization,
    bool? isDarkMode,
    String? language,
  }) {
    return AppSettings(
      requirePasskey: requirePasskey ?? this.requirePasskey,
      loginAlerts: loginAlerts ?? this.loginAlerts,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      messagePermissions: messagePermissions ?? this.messagePermissions,
      onlineVisibility: onlineVisibility ?? this.onlineVisibility,
      readReceipts: readReceipts ?? this.readReceipts,
      typingStatus: typingStatus ?? this.typingStatus,
      allowMediaAutoDownload: allowMediaAutoDownload ?? this.allowMediaAutoDownload,
      dataRetentionForever: dataRetentionForever ?? this.dataRetentionForever,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      aiSuggestions: aiSuggestions ?? this.aiSuggestions,
      autoMode: autoMode ?? this.autoMode,
      backgroundAgentEnabled: backgroundAgentEnabled ?? this.backgroundAgentEnabled,
      voiceSelection: voiceSelection ?? this.voiceSelection,
      aiPersonalization: aiPersonalization ?? this.aiPersonalization,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      language: language ?? this.language,
    );
  }
}
