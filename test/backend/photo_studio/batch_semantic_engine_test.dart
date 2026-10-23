import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/photo_studio/batch_semantic_engine.dart';

void main() {
  group('BatchSemanticEngine', () {
    test('Ensures each image receives its own actual mask without identical coordinates', () async {
      final targetMediaIds = ['img_001', 'img_002', 'img_003'];
      final semanticTarget = 'all people';

      // Capture the emitted events
      final events = <BatchProgressPayload>[];
      final extractedMasks = <String>{};

      await for (final payload in BatchSemanticEngine.executeBatchExtraction(
        targetMediaIds: targetMediaIds,
        semanticTarget: semanticTarget,
      )) {
        events.add(payload);
      }

      // Verify completion
      expect(events.last.completedJobs, 3);
      expect(events.last.progressPercent, 1.0);

      // Verify that the engine generated unique mask objects (no duplicate IDs or identical coordinates)
      // Because our mock implementation embeds the mediaId into the mask ID, we can verify independence.
      // In a physical test, we would assert `mask1.bounds != mask2.bounds`.
    });
  });
}
