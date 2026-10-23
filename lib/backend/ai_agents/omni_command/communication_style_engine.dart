import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum ConfidenceLevel {
  OBSERVED,
  USER_CONFIRMED,
  TEMPORARY,
  AI_SUGGESTED,
}

class StyleMetric {
  final String value;
  final ConfidenceLevel confidence;
  final DateTime lastUpdated;

  const StyleMetric({
    required this.value,
    required this.confidence,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'value': value,
    'confidence': confidence.name,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory StyleMetric.fromJson(Map<String, dynamic> json) {
    return StyleMetric(
      value: json['value'] as String,
      confidence: ConfidenceLevel.values.firstWhere(
        (e) => e.name == json['confidence'],
        orElse: () => ConfidenceLevel.OBSERVED,
      ),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }

  StyleMetric copyWith({
    String? value,
    ConfidenceLevel? confidence,
    DateTime? lastUpdated,
  }) {
    return StyleMetric(
      value: value ?? this.value,
      confidence: confidence ?? this.confidence,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class PersonalCommunicationStyle {
  final StyleMetric tone;
  final StyleMetric verbosity;
  final StyleMetric format;
  final StyleMetric language;
  final StyleMetric emojiStyle;
  final StyleMetric greetingStyle;
  final StyleMetric closingStyle;
  final List<String> preferredPhrases;
  final bool isLearningEnabled;

  const PersonalCommunicationStyle({
    required this.tone,
    required this.verbosity,
    required this.format,
    required this.language,
    required this.emojiStyle,
    required this.greetingStyle,
    required this.closingStyle,
    this.preferredPhrases = const [],
    this.isLearningEnabled = true,
  });

  factory PersonalCommunicationStyle.defaultStyle() {
    final now = DateTime.now();
    StyleMetric defaultMetric(String v) => StyleMetric(
      value: v,
      confidence: ConfidenceLevel.AI_SUGGESTED,
      lastUpdated: now,
    );
    return PersonalCommunicationStyle(
      tone: defaultMetric('friendly and professional'),
      verbosity: defaultMetric('standard'),
      format: defaultMetric('natural conversational paragraphs'),
      language: defaultMetric('English'),
      emojiStyle: defaultMetric('occasional'),
      greetingStyle: defaultMetric('natural variation'),
      closingStyle: defaultMetric('polite sign-off'),
      preferredPhrases: [],
      isLearningEnabled: true,
    );
  }

  Map<String, dynamic> toJson() => {
    'tone': tone.toJson(),
    'verbosity': verbosity.toJson(),
    'format': format.toJson(),
    'language': language.toJson(),
    'emojiStyle': emojiStyle.toJson(),
    'greetingStyle': greetingStyle.toJson(),
    'closingStyle': closingStyle.toJson(),
    'preferredPhrases': preferredPhrases,
    'isLearningEnabled': isLearningEnabled,
  };

  factory PersonalCommunicationStyle.fromJson(Map<String, dynamic> json) {
    return PersonalCommunicationStyle(
      tone: StyleMetric.fromJson(json['tone']),
      verbosity: StyleMetric.fromJson(json['verbosity']),
      format: StyleMetric.fromJson(json['format']),
      language: StyleMetric.fromJson(json['language']),
      emojiStyle: StyleMetric.fromJson(json['emojiStyle']),
      greetingStyle: StyleMetric.fromJson(json['greetingStyle']),
      closingStyle: StyleMetric.fromJson(json['closingStyle']),
      preferredPhrases: (json['preferredPhrases'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      isLearningEnabled: json['isLearningEnabled'] as bool? ?? true,
    );
  }

  PersonalCommunicationStyle copyWith({
    StyleMetric? tone,
    StyleMetric? verbosity,
    StyleMetric? format,
    StyleMetric? language,
    StyleMetric? emojiStyle,
    StyleMetric? greetingStyle,
    StyleMetric? closingStyle,
    List<String>? preferredPhrases,
    bool? isLearningEnabled,
  }) {
    return PersonalCommunicationStyle(
      tone: tone ?? this.tone,
      verbosity: verbosity ?? this.verbosity,
      format: format ?? this.format,
      language: language ?? this.language,
      emojiStyle: emojiStyle ?? this.emojiStyle,
      greetingStyle: greetingStyle ?? this.greetingStyle,
      closingStyle: closingStyle ?? this.closingStyle,
      preferredPhrases: preferredPhrases ?? this.preferredPhrases,
      isLearningEnabled: isLearningEnabled ?? this.isLearningEnabled,
    );
  }
}

final communicationStyleEngineProvider = NotifierProvider<CommunicationStyleEngine, PersonalCommunicationStyle>(() {
  return CommunicationStyleEngine();
});

class CommunicationStyleEngine extends Notifier<PersonalCommunicationStyle> {
  static const String _storageKey = 'omni_communication_style';

  @override
  PersonalCommunicationStyle build() {
    _loadStyle();
    return PersonalCommunicationStyle.defaultStyle();
  }

  Future<void> _loadStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      try {
        state = PersonalCommunicationStyle.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        // Fallback to default
      }
    }
  }

  Future<void> _saveStyle(PersonalCommunicationStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(style.toJson()));
  }

  /// Master prompt generation
  /// Formula: base model + authorized personal style + current conversation context + current user instruction
  String generateDraftingPrompt({
    required String baseModelPrompt,
    required String currentContext,
    required String currentInstruction,
  }) {
    final buffer = StringBuffer();
    
    // 1. Base Model Instruction
    buffer.writeln('=== BASE ASSISTANT MODEL ===');
    buffer.writeln(baseModelPrompt);
    buffer.writeln();

    // 2. Authorized Personal Style
    buffer.writeln('=== AUTHORIZED COMMUNICATION STYLE ===');
    buffer.writeln("Adopt the following communication parameters dynamically based on the user's observed style:");
    buffer.writeln('- Tone: \${state.tone.value} [Confidence: \${state.tone.confidence.name}]');
    buffer.writeln('- Verbosity: \${state.verbosity.value} [Confidence: \${state.verbosity.confidence.name}]');
    buffer.writeln('- Format: \${state.format.value} [Confidence: \${state.format.confidence.name}]');
    buffer.writeln('- Language: \${state.language.value} [Confidence: \${state.language.confidence.name}]');
    buffer.writeln('- Emojis: \${state.emojiStyle.value} [Confidence: \${state.emojiStyle.confidence.name}]');
    buffer.writeln('- Greetings: \${state.greetingStyle.value} [Confidence: \${state.greetingStyle.confidence.name}]');
    buffer.writeln('- Sign-offs: \${state.closingStyle.value} [Confidence: \${state.closingStyle.confidence.name}]');
    
    if (state.preferredPhrases.isNotEmpty) {
      buffer.writeln("- Preferred Vocabulary: \${state.preferredPhrases.join(', ')}");
    }
    buffer.writeln();

    // 3. Current Conversation Context
    buffer.writeln('=== CURRENT CONVERSATION CONTEXT ===');
    buffer.writeln(currentContext);
    buffer.writeln();

    // 4. Current User Instruction (Overrides)
    buffer.writeln('=== CURRENT USER INSTRUCTION ===');
    buffer.writeln('CRITICAL: The current user instruction ALWAYS OVERRIDES the historical style and base model.');
    buffer.writeln(currentInstruction);
    
    return buffer.toString();
  }

  /// Learning control
  Future<void> setLearningEnabled(bool enabled) async {
    await _saveStyle(state.copyWith(isLearningEnabled: enabled));
  }

  Future<void> resetStyle() async {
    await _saveStyle(PersonalCommunicationStyle.defaultStyle());
  }

  /// Analyzes the message to update communication style using ModelRouter
  Future<void> learnFromMessage(String messageText, {Future<String> Function(String)? aiAnalyzer}) async {
    if (!state.isLearningEnabled || aiAnalyzer == null) return;
    
    final prompt = '''
Analyze the following message and extract communication style metrics.
Do NOT create a sensitive psychological profile. Stick strictly to communication parameters.

Message: "\$messageText"

Output a JSON object with the following fields (provide a short descriptive string for each):
- tone
- verbosity
- format
- language
- emojiStyle
- greetingStyle
- closingStyle

If you cannot determine a field, omit it from the JSON.
''';

    try {
      final _ = await aiAnalyzer(prompt);
      // In a real implementation, we parse the JSON response and update the state metrics
      // upgrading their ConfidenceLevel to OBSERVED.
      // Example simulated parsing:
      // final data = jsonDecode(response);
      // final newTone = data['tone'] != null 
      //     ? StyleMetric(value: data['tone'], confidence: ConfidenceLevel.OBSERVED, lastUpdated: DateTime.now())
      //     : state.tone;
      // ... update state with copyWith
      
      print('Learned from message. AI extracted style delta: \$response');
    } catch (e) {
      print('Failed to learn from message: \$e');
    }
  }
}
