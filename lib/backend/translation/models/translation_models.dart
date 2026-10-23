enum TranslationType {
  textMessage,
  voiceSpeechToText,
  voiceTextToSpeech,
  liveCaption,
}

class TranslationRecord {
  final String id;
  final String targetId; // ID of the original message/audio
  final TranslationType type;
  
  // Strict requirement: Never overwrite original message. Store it explicitly.
  final String originalContent;
  final String originalLanguage;
  
  final String translatedContent;
  final String targetLanguage;
  
  final String provider;
  final DateTime timestamp;
  
  // Voice/Live specific
  final String? translatedAudioUrl;

  const TranslationRecord({
    required this.id,
    required this.targetId,
    required this.type,
    required this.originalContent,
    this.originalLanguage = 'auto',
    required this.translatedContent,
    required this.targetLanguage,
    required this.provider,
    required this.timestamp,
    this.translatedAudioUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'targetId': targetId,
      'type': type.name,
      'originalContent': originalContent,
      'originalLanguage': originalLanguage,
      'translatedContent': translatedContent,
      'targetLanguage': targetLanguage,
      'provider': provider,
      'timestamp': timestamp.toIso8601String(),
      'translatedAudioUrl': translatedAudioUrl,
    };
  }
}

class TranslationConfig {
  final List<String> supportedLanguages;
  final String defaultTargetLanguage;

  const TranslationConfig({
    this.supportedLanguages = const ['en', 'es', 'fr', 'de', 'zh', 'ja', 'ko', 'ar', 'hi'],
    this.defaultTargetLanguage = 'en',
  });
}
