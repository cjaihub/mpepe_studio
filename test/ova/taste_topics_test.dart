import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/recommendation/ova_taste_learner.dart';

void main() {
  test('keeps clean interest words, drops sensitive ones and junk', () {
    final t = OvaTasteLearner.cleanTopics(['#Afrobeats', 'Cooking', 'church music', 'politics', 'mental health', 'x', 'Arsenal FC!', 42, 'loan offers']);
    expect(t, ['afrobeats', 'cooking', 'arsenalfc']);
  });

  test('caps at eight and tolerates bad input', () {
    expect(OvaTasteLearner.cleanTopics(null), isEmpty);
    expect(OvaTasteLearner.cleanTopics([for (var i = 0; i < 20; i++) 'topic$i']).length, 8);
  });
}
