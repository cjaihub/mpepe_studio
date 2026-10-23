import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';
import 'package:oneova/backend/translation/models/translation_models.dart';
import 'package:oneova/backend/translation/services/translation_service.dart';

import 'translation_service_test.mocks.dart';

@GenerateMocks([OpenRouterAgentService])
void main() {
  late MockOpenRouterAgentService mockAgent;
  late TranslationService service;

  setUp(() {
    mockAgent = MockOpenRouterAgentService();
    service = TranslationService(mockAgent, config: const TranslationConfig(supportedLanguages: ['es', 'fr', 'ja']));
  });

  test('Translates text message and explicitly preserves original', () async {
    when(mockAgent.queryAgent(any, 'Hello, how are you?'))
        .thenAnswer((_) async => 'Hola, como estas?');

    final record = await service.translateMessage('msg_1', 'Hello, how are you?', 'es');

    // The original content must NOT be overwritten, it must coexist with the translation
    expect(record.originalContent, 'Hello, how are you?');
    expect(record.translatedContent, 'Hola, como estas?');
    expect(record.targetLanguage, 'es');
    expect(record.type, TranslationType.textMessage);
  });

  test('Voice processing creates TTS URL when requested', () async {
    when(mockAgent.queryAgent(any, 'Voice note transcript'))
        .thenAnswer((_) async => 'Transcripcion de nota de voz');

    final record = await service.processVoiceMessage('voice_1', 'Voice note transcript', 'es', generateTts: true);

    expect(record.originalContent, 'Voice note transcript');
    expect(record.translatedContent, 'Transcripcion de nota de voz');
    expect(record.type, TranslationType.voiceTextToSpeech);
    expect(record.translatedAudioUrl, isNotNull); // Verifies TTS requested
  });

  test('User can delete a generated translation', () async {
    when(mockAgent.queryAgent(any, 'Some text'))
        .thenAnswer((_) async => 'Texto traducido');

    final record = await service.translateMessage('msg_2', 'Some text', 'es');
    expect(service.getTranslation(record.id), isNotNull);

    // Delete it
    final deleted = service.deleteTranslation(record.id);
    expect(deleted, true);
    expect(service.getTranslation(record.id), isNull);
  });

  test('Throws exception if language not in config', () async {
    expect(
      () => service.translateMessage('msg_3', 'Hello', 'de'), // 'de' not in mock config above
      throwsException,
    );
  });
}
