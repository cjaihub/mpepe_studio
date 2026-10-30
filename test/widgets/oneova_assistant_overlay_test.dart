import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/services/ai_assistant_service.dart';

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
}
