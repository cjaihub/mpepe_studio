import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/shared/services/oneova_language_service.dart';
import 'package:oneova/shared/widgets/oneova_language_action_sheet.dart';
import 'package:oneova/shared/widgets/oneova_voice_typing_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OneovaLanguageService Auto-Detection Tests', () {
    test('Detects Swahili correctly from conversational words', () {
      final res = OneovaLanguageService.instance.detectLanguage('Habari yako rafiki, asante sana kwa kazi nzuri');
      expect(res.code, 'sw');
      expect(res.name, 'Swahili');
      expect(res.flag, '🇰🇪');
      expect(res.confidence > 0.6, isTrue);
    });

    test('Detects French correctly from conversational words', () {
      final res = OneovaLanguageService.instance.detectLanguage('Bonjour mon ami, merci beaucoup pour votre aide');
      expect(res.code, 'fr');
      expect(res.name, 'French');
      expect(res.flag, '🇫🇷');
      expect(res.confidence > 0.6, isTrue);
    });

    test('Detects Spanish correctly from conversational words', () {
      final res = OneovaLanguageService.instance.detectLanguage('Hola amigo, muchas gracias por todo');
      expect(res.code, 'es');
      expect(res.name, 'Spanish');
      expect(res.flag, '🇪🇸');
    });

    test('Detects Arabic script correctly', () {
      final res = OneovaLanguageService.instance.detectLanguage('مرحبا كيف حالك شكرا جزيلا');
      expect(res.code, 'ar');
      expect(res.name, 'Arabic');
      expect(res.language.isRtl, isTrue);
    });

    test('Detects Chinese CJK script correctly', () {
      final res = OneovaLanguageService.instance.detectLanguage('你好，谢谢你的帮助');
      expect(res.code, 'zh');
      expect(res.name, 'Chinese');
    });

    test('Detects Yoruba keywords correctly', () {
      final res = OneovaLanguageService.instance.detectLanguage('Bawo ni ore mi, eku ise adupe');
      expect(res.code, 'yo');
      expect(res.name, 'Yoruba');
    });

    test('Detects Zulu keywords correctly', () {
      final res = OneovaLanguageService.instance.detectLanguage('Sawubona mngane, ngiyabonga kakhulu');
      expect(res.code, 'zu');
      expect(res.name, 'Zulu');
    });

    test('Detects English as default/fallback', () {
      final res = OneovaLanguageService.instance.detectLanguage('Welcome to Oneova creator studio feed');
      expect(res.code, 'en');
      expect(res.name, 'English');
    });
  });

  group('OneovaLanguageService Translation & Polish Tests', () {
    test('Offline fallback translates Swahili to English correctly', () async {
      final translated = await OneovaLanguageService.instance.translateText(
        'Habari za jioni',
        targetLanguageCode: 'en',
        sourceLanguageCode: 'sw',
      );
      expect(translated, 'Good evening');
    });

    test('Offline fallback translates English to Swahili correctly', () async {
      final translated = await OneovaLanguageService.instance.translateText(
        'Thank you very much',
        targetLanguageCode: 'sw',
        sourceLanguageCode: 'en',
      );
      expect(translated, 'Asante sana');
    });

    test('Offline fallback translates French to English correctly', () async {
      final translated = await OneovaLanguageService.instance.translateText(
        'Merci beaucoup',
        targetLanguageCode: 'en',
        sourceLanguageCode: 'fr',
      );
      expect(translated, 'Thank you very much');
    });

    test('Local AI polish cleans and capitalizes sentences', () async {
      final polished = await OneovaLanguageService.instance.polishText('hello oneova team we are ready');
      expect(polished.startsWith('Hello'), isTrue);
      expect(polished.endsWith('.'), isTrue);
    });
  });

  group('OneovaTranslateButton & OneovaLanguageActionSheet Widget Tests', () {
    testWidgets('OneovaTranslateButton displays language flag and translate icon', (tester) async {
      final controller = TextEditingController(text: 'Habari yako');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneovaTranslateButton(controller: controller),
          ),
        ),
      );

      expect(find.byIcon(Icons.translate_rounded), findsOneWidget);
      expect(find.text('🇰🇪'), findsOneWidget);
    });

    testWidgets('OneovaLanguageActionSheet renders detected language and target options', (tester) async {
      final controller = TextEditingController(text: 'Asante sana');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneovaLanguageActionSheet(controller: controller),
          ),
        ),
      );

      // Verify detected badge
      expect(find.textContaining('Detected: Swahili'), findsOneWidget);
      expect(find.text('CURRENT INPUT'), findsOneWidget);
      expect(find.text('TRANSLATE TO'), findsOneWidget);
      expect(find.text('AI POLISH & TONE TIDY'), findsOneWidget);

      // Verify target language options are available
      expect(find.text('🇺🇸 English'), findsOneWidget);
      expect(find.text('🇫🇷 French'), findsOneWidget);
    });
  });
}

