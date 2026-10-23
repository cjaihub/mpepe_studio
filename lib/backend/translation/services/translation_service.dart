import 'package:oneova/backend/translation/models/translation_models.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';

class TranslationService {
  final OpenRouterAgentService _agentService;
  final TranslationConfig config;
  
  // In-memory store representing Firestore collection to allow user deletion
  final Map<String, TranslationRecord> _storedTranslations = {};

  TranslationService(this._agentService, {this.config = const TranslationConfig()});

  /// Translates a text message. Never mutates original message.
  Future<TranslationRecord> translateMessage(String messageId, String originalText, String targetLanguage) async {
    if (!config.supportedLanguages.contains(targetLanguage)) {
      throw Exception('Target language \$targetLanguage is not supported by configuration.');
    }

    final systemPrompt = 'You are a professional translator. Translate the following text into \$targetLanguage. Output ONLY the translated text, absolutely nothing else.';
    final translatedText = await _agentService.queryAgent(systemPrompt, originalText) ?? 'Translation failed.';

    final record = TranslationRecord(
      id: 'trans_\${DateTime.now().millisecondsSinceEpoch}',
      targetId: messageId,
      type: TranslationType.textMessage,
      originalContent: originalText,
      translatedContent: translatedText,
      targetLanguage: targetLanguage,
      provider: 'OpenRouter-AI',
      timestamp: DateTime.now(),
    );

    _storedTranslations[record.id] = record;
    return record;
  }

  /// Drafts a reply in another language for the user to send
  Future<String> draftReplyInLanguage(String replyText, String targetLanguage) async {
    if (!config.supportedLanguages.contains(targetLanguage)) return replyText;
    
    final systemPrompt = 'You are a translation assistant. Translate this reply into \$targetLanguage. Output ONLY the translated text.';
    final result = await _agentService.queryAgent(systemPrompt, replyText);
    return result ?? replyText;
  }

  /// Simulates Speech-to-Text and translation
  Future<TranslationRecord> processVoiceMessage(String voiceMessageId, String simulatedSttText, String targetLanguage, {bool generateTts = false}) async {
    final systemPrompt = 'Translate this transcribed speech into \$targetLanguage. Output ONLY the translated text.';
    final translatedText = await _agentService.queryAgent(systemPrompt, simulatedSttText) ?? 'Audio translation failed.';

    final record = TranslationRecord(
      id: 'trans_voice_\${DateTime.now().millisecondsSinceEpoch}',
      targetId: voiceMessageId,
      type: generateTts ? TranslationType.voiceTextToSpeech : TranslationType.voiceSpeechToText,
      originalContent: simulatedSttText,
      translatedContent: translatedText,
      targetLanguage: targetLanguage,
      provider: 'OpenRouter-AI',
      timestamp: DateTime.now(),
      translatedAudioUrl: generateTts ? 'https://onerova.studio/audio_cdn/gen_\${DateTime.now().millisecondsSinceEpoch}.mp3' : null,
    );

    _storedTranslations[record.id] = record;
    return record;
  }

  /// Appends real-time live captions
  Future<TranslationRecord> processLiveCaption(String liveSessionId, String snippetText, String targetLanguage) async {
    final systemPrompt = 'Translate this live caption snippet into \$targetLanguage. Be concise. Output ONLY translated text.';
    final translatedText = await _agentService.queryAgent(systemPrompt, snippetText) ?? '';

    final record = TranslationRecord(
      id: 'caption_\${DateTime.now().millisecondsSinceEpoch}',
      targetId: liveSessionId,
      type: TranslationType.liveCaption,
      originalContent: snippetText,
      translatedContent: translatedText,
      targetLanguage: targetLanguage,
      provider: 'OpenRouter-AI',
      timestamp: DateTime.now(),
    );

    _storedTranslations[record.id] = record;
    return record;
  }

  /// Allows the user to delete a translation they do not want
  bool deleteTranslation(String translationId) {
    if (_storedTranslations.containsKey(translationId)) {
      _storedTranslations.remove(translationId);
      return true;
    }
    return false;
  }

  TranslationRecord? getTranslation(String translationId) => _storedTranslations[translationId];
}
