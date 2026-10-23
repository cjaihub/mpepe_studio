

enum TonePreference {
  professional,
  friendly,
  casual,
  academic,
  empathetic,
  humorous,
}

enum ExplanationDepth {
  concise,    // "Yes, Sarah replied."
  standard,   // "Sarah replied 20 mins ago, she will send files tonight."
  detailed,   // "Sarah replied at 4:20 PM. She mentioned she'll send the 3 files tonight."
}

class UserLanguageProfile {
  final String primaryLanguage;
  final List<String> secondaryLanguages;
  final bool autoMatchLanguage;
  
  const UserLanguageProfile({
    this.primaryLanguage = 'en',
    this.secondaryLanguages = const [],
    this.autoMatchLanguage = true,
  });

  Map<String, dynamic> toJson() => {
    'primaryLanguage': primaryLanguage,
    'secondaryLanguages': secondaryLanguages,
    'autoMatchLanguage': autoMatchLanguage,
  };

  factory UserLanguageProfile.fromJson(Map<String, dynamic> json) => UserLanguageProfile(
    primaryLanguage: json['primaryLanguage'] as String? ?? 'en',
    secondaryLanguages: (json['secondaryLanguages'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    autoMatchLanguage: json['autoMatchLanguage'] as bool? ?? true,
  );
}

class ToneProfile {
  final TonePreference primaryTone;
  final bool adaptToContext;
  final bool useEmojis;
  final String punctuationStyle; // e.g., 'standard', 'minimal'
  
  const ToneProfile({
    this.primaryTone = TonePreference.friendly,
    this.adaptToContext = true,
    this.useEmojis = false,
    this.punctuationStyle = 'standard',
  });

  Map<String, dynamic> toJson() => {
    'primaryTone': primaryTone.name,
    'adaptToContext': adaptToContext,
    'useEmojis': useEmojis,
    'punctuationStyle': punctuationStyle,
  };

  factory ToneProfile.fromJson(Map<String, dynamic> json) {
    return ToneProfile(
      primaryTone: TonePreference.values.firstWhere(
        (e) => e.name == json['primaryTone'],
        orElse: () => TonePreference.friendly,
      ),
      adaptToContext: json['adaptToContext'] as bool? ?? true,
      useEmojis: json['useEmojis'] as bool? ?? false,
      punctuationStyle: json['punctuationStyle'] as String? ?? 'standard',
    );
  }

  ToneProfile copyWith({
    TonePreference? primaryTone,
    bool? adaptToContext,
    bool? useEmojis,
    String? punctuationStyle,
  }) {
    return ToneProfile(
      primaryTone: primaryTone ?? this.primaryTone,
      adaptToContext: adaptToContext ?? this.adaptToContext,
      useEmojis: useEmojis ?? this.useEmojis,
      punctuationStyle: punctuationStyle ?? this.punctuationStyle,
    );
  }
}

class ResponsePreference {
  final ExplanationDepth explanationDepth;
  final bool askFollowUpQuestions; // Only when useful
  final bool confirmActions;
  
  const ResponsePreference({
    this.explanationDepth = ExplanationDepth.standard,
    this.askFollowUpQuestions = false,
    this.confirmActions = true,
  });

  Map<String, dynamic> toJson() => {
    'explanationDepth': explanationDepth.name,
    'askFollowUpQuestions': askFollowUpQuestions,
    'confirmActions': confirmActions,
  };

  factory ResponsePreference.fromJson(Map<String, dynamic> json) {
    return ResponsePreference(
      explanationDepth: ExplanationDepth.values.firstWhere(
        (e) => e.name == json['explanationDepth'],
        orElse: () => ExplanationDepth.standard,
      ),
      askFollowUpQuestions: json['askFollowUpQuestions'] as bool? ?? false,
      confirmActions: json['confirmActions'] as bool? ?? true,
    );
  }

  ResponsePreference copyWith({
    ExplanationDepth? explanationDepth,
    bool? askFollowUpQuestions,
    bool? confirmActions,
  }) {
    return ResponsePreference(
      explanationDepth: explanationDepth ?? this.explanationDepth,
      askFollowUpQuestions: askFollowUpQuestions ?? this.askFollowUpQuestions,
      confirmActions: confirmActions ?? this.confirmActions,
    );
  }
}

class ConversationStyleProfile {
  final String preferredName;
  final String greetingStyle;
  final ToneProfile toneProfile;
  final ResponsePreference responsePreference;
  final UserLanguageProfile languageProfile;
  final List<String> commonPhrases;

  const ConversationStyleProfile({
    required this.preferredName,
    this.greetingStyle = 'natural',
    this.toneProfile = const ToneProfile(),
    this.responsePreference = const ResponsePreference(),
    this.languageProfile = const UserLanguageProfile(),
    this.commonPhrases = const [],
  });

  Map<String, dynamic> toJson() => {
    'preferredName': preferredName,
    'greetingStyle': greetingStyle,
    'toneProfile': toneProfile.toJson(),
    'responsePreference': responsePreference.toJson(),
    'languageProfile': languageProfile.toJson(),
    'commonPhrases': commonPhrases,
  };

  factory ConversationStyleProfile.fromJson(Map<String, dynamic> json) {
    return ConversationStyleProfile(
      preferredName: json['preferredName'] as String? ?? 'User',
      greetingStyle: json['greetingStyle'] as String? ?? 'natural',
      toneProfile: json['toneProfile'] != null 
          ? ToneProfile.fromJson(json['toneProfile'] as Map<String, dynamic>) 
          : const ToneProfile(),
      responsePreference: json['responsePreference'] != null 
          ? ResponsePreference.fromJson(json['responsePreference'] as Map<String, dynamic>) 
          : const ResponsePreference(),
      languageProfile: json['languageProfile'] != null 
          ? UserLanguageProfile.fromJson(json['languageProfile'] as Map<String, dynamic>) 
          : const UserLanguageProfile(),
      commonPhrases: (json['commonPhrases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  ConversationStyleProfile copyWith({
    String? preferredName,
    String? greetingStyle,
    ToneProfile? toneProfile,
    ResponsePreference? responsePreference,
    UserLanguageProfile? languageProfile,
    List<String>? commonPhrases,
  }) {
    return ConversationStyleProfile(
      preferredName: preferredName ?? this.preferredName,
      greetingStyle: greetingStyle ?? this.greetingStyle,
      toneProfile: toneProfile ?? this.toneProfile,
      responsePreference: responsePreference ?? this.responsePreference,
      languageProfile: languageProfile ?? this.languageProfile,
      commonPhrases: commonPhrases ?? this.commonPhrases,
    );
  }
}

class InteractionContext {
  final String currentTopic;
  final List<String> authorizedContextIds; // e.g., thread IDs, doc IDs
  final DateTime lastInteraction;
  final Map<String, dynamic> shortTermMemory; // Key entities mentioned recently

  const InteractionContext({
    required this.currentTopic,
    required this.authorizedContextIds,
    required this.lastInteraction,
    required this.shortTermMemory,
  });

  Map<String, dynamic> toJson() => {
    'currentTopic': currentTopic,
    'authorizedContextIds': authorizedContextIds,
    'lastInteraction': lastInteraction.toIso8601String(),
    'shortTermMemory': shortTermMemory,
  };

  factory InteractionContext.fromJson(Map<String, dynamic> json) {
    return InteractionContext(
      currentTopic: json['currentTopic'] as String? ?? '',
      authorizedContextIds: (json['authorizedContextIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      lastInteraction: json['lastInteraction'] != null 
          ? DateTime.tryParse(json['lastInteraction'] as String) ?? DateTime.now()
          : DateTime.now(),
      shortTermMemory: json['shortTermMemory'] as Map<String, dynamic>? ?? const {},
    );
  }
}
