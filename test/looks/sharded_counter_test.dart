import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/services/sharded_counter_service.dart';

void main() {
  group('ShardedCounterService Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ShardedCounterService counterService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      counterService = ShardedCounterService(firestore: fakeFirestore);
    });

    test('increments counter across shards and gets accurate aggregate sum', () async {
      const lookId = 'look_cyberpunk_neon';

      // Simulate 50 concurrent increments
      for (int i = 0; i < 50; i++) {
        await counterService.incrementLookLikes(lookId, numShards: 5);
      }

      final totalLikes = await counterService.getLookLikes(lookId);
      expect(totalLikes, equals(50));

      // Verify shards exist
      final shardsSnap = await fakeFirestore
          .collection('publicLooks')
          .doc(lookId)
          .collection('shards')
          .get();
      expect(shardsSnap.docs.isNotEmpty, isTrue);
      expect(shardsSnap.docs.length, lessThanOrEqualTo(5));
    });

    test('decrements counter correctly across shards', () async {
      const lookId = 'look_film_vintage';

      await counterService.incrementLookLikes(lookId);
      await counterService.incrementLookLikes(lookId);
      await counterService.decrementLookLikes(lookId);

      final totalLikes = await counterService.getLookLikes(lookId);
      expect(totalLikes, equals(1));
    });

    test('tracks look uses and streams count live', () async {
      const lookId = 'look_teal_orange';

      final stream = counterService.streamLookUses(lookId);
      final emittedValues = <int>[];
      final sub = stream.listen(emittedValues.add);

      await counterService.incrementLookUses(lookId);
      await counterService.incrementLookUses(lookId);
      await counterService.incrementLookUses(lookId);

      // Give stream time to process
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emittedValues.last, equals(3));
      await sub.cancel();
    });
  });
}
