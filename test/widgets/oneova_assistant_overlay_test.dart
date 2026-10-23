import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/services/ai_assistant_service.dart';
import 'package:oneova/widgets/oneova_assistant_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OneOva Assistant Service & Support Models', () {
    late FakeFirebaseFirestore fakeFirestore;
    late OneOvaAssistantService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = OneOvaAssistantService(firestore: fakeFirestore);
    });

    test('AISuggestion fromMap and toMap serialize properly', () {
      final map = {
        'text': 'Plan a safari trip',
        'type': 'creative',
        'iconType': 'sparkle',
      };
      final suggestion = AISuggestion.fromMap(map, 'doc_123');

      expect(suggestion.id, 'doc_123');
      expect(suggestion.text, 'Plan a safari trip');
      expect(suggestion.type, 'creative');
      expect(suggestion.iconType, 'sparkle');

      final serialized = suggestion.toMap();
      expect(serialized['text'], 'Plan a safari trip');
      expect(serialized['type'], 'creative');
      expect(serialized['iconType'], 'sparkle');
    });

    test('submitCommand adds interaction to Firestore with status processing', () async {
      const userId = 'user_abc';
      const prompt = 'Tell me today\'s studio schedule';

      await service.submitCommand(userId, prompt);

      final snapshot = await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('ai_interactions')
          .get();

      expect(snapshot.docs.length, 1);
      final doc = snapshot.docs.first;
      expect(doc.data()['query'], prompt);
      expect(doc.data()['status'], 'processing');
      expect(doc.data()['timestamp'], isNotNull);
    });

    test('getSuggestions streams real-time suggestions from Firestore', () async {
      const userId = 'user_abc';

      await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('ai_suggestions')
          .add({
        'text': 'Draft an Instagram caption',
        'type': 'creative',
        'iconType': 'sparkle',
        'createdAt': Timestamp.now(),
      });

      final suggestionsStream = service.getSuggestions(userId);
      final suggestions = await suggestionsStream.first;

      expect(suggestions.length, 1);
      expect(suggestions.first.text, 'Draft an Instagram caption');
      expect(suggestions.first.type, 'creative');
    });
  });

  group('OneOvaAssistantOverlay Widget Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late OneOvaAssistantService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = OneOvaAssistantService(firestore: fakeFirestore);
    });

    testWidgets('renders BackdropFilter blurred glassmorphic canvas and Oneova header', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneOvaAssistantOverlay(
              userId: 'test_user',
              assistantService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check BackdropFilter exists
      expect(find.byType(BackdropFilter), findsOneWidget);

      // Check Persona selector "Oneova ▾"
      expect(find.text('Oneova'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

      // Check default fallback suggestion chips matching screenshot
      expect(find.text('Send my recent photo to mom on WhatsApp'), findsOneWidget);
      expect(find.text('Plan a budget-friendly safari'), findsOneWidget);
      expect(find.text('Check status updates on WhatsApp'), findsOneWidget);

      // Check input row and waveform icon
      expect(find.text('Ask me anytime...'), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('tapping a suggestion populates text field and sends command', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneOvaAssistantOverlay(
              userId: 'user_456',
              assistantService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the safari suggestion chip
      final safariChip = find.text('Plan a budget-friendly safari');
      expect(safariChip, findsOneWidget);
      await tester.tap(safariChip);
      await tester.pump();

      // Check that the TextField now has the suggestion text
      expect(find.text('Plan a budget-friendly safari'), findsWidgets);

      // Tap the send '+' button
      final sendButton = find.byIcon(Icons.add);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Verify the command was written to FakeFirebaseFirestore
      final snapshot = await fakeFirestore
          .collection('users')
          .doc('user_456')
          .collection('ai_interactions')
          .get();

      expect(snapshot.docs.length, 1);
      expect(snapshot.docs.first.data()['query'], 'Plan a budget-friendly safari');
      expect(snapshot.docs.first.data()['status'], 'processing');
    });

    testWidgets('toggling voice listening changes waveform icon color state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneOvaAssistantOverlay(
              userId: 'user_789',
              assistantService: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final waveformFinder = find.byIcon(Icons.graphic_eq_rounded);
      expect(waveformFinder, findsOneWidget);

      // Initially listening is false
      Icon waveformIcon = tester.widget(waveformFinder);
      expect(waveformIcon.color, Colors.white70);

      // Tap the waveform indicator
      await tester.tap(waveformFinder);
      await tester.pump();

      // Now listening is true -> Color(0xFFE91E63)
      waveformIcon = tester.widget(waveformFinder);
      expect(waveformIcon.color, const Color(0xFFE91E63));
    });

    testWidgets('shows modal bottom sheet via static show method', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                floatingActionButton: FloatingActionButton(
                  onPressed: () {
                    OneOvaAssistantOverlay.show(context, 'user_modal', service);
                  },
                ),
              );
            },
          ),
        ),
      );

      // Tap FAB to trigger showModalBottomSheet
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(OneOvaAssistantOverlay), findsOneWidget);
      expect(find.text('Oneova'), findsOneWidget);
    });
  });
}

