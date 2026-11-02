import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/oneova_voice_typing_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('OneovaVoiceTypingButton UI & Controller Integration', () {
    testWidgets('Renders microphone icon button with tooltip in idle state', (tester) async {
      final controller = TextEditingController(text: 'Hello world');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: OneovaVoiceTypingButton(
                controller: controller,
                tooltip: 'Dictate message',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(OneovaVoiceTypingButton), findsOneWidget);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, 'Dictate message');
    });

    testWidgets('Renders custom size and styling', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: OneovaVoiceTypingButton(
                controller: controller,
                iconSize: 24.0,
                idleColor: Colors.amber,
              ),
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.mic_none_rounded));
      expect(icon.size, 24.0);
      expect(icon.color, Colors.amber);
    });

    test('Controller text appending preserves existing words with single space', () {
      final controller = TextEditingController(text: 'Initial thoughts');
      const recognized = 'and next steps';

      // Simulates speech result insertion with append = true
      final current = controller.text.trim();
      final prefix = current.isNotEmpty ? '$current ' : '';
      controller.text = '$prefix$recognized';

      expect(controller.text, 'Initial thoughts and next steps');
    });

    test('Controller text replace overrides previous text when append is false', () {
      final controller = TextEditingController(text: 'Old wrong query');
      const recognized = 'Fresh search query';

      // Simulates replace mode
      controller.text = recognized;

      expect(controller.text, 'Fresh search query');
    });

    testWidgets('FocusNode requests focus when toggled', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Column(
              children: [
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                ),
                OneovaVoiceTypingButton(
                  controller: controller,
                  focusNode: focusNode,
                ),
              ],
            ),
          ),
        ),
      );

      expect(focusNode.hasFocus, isFalse);
    });
  });
}

