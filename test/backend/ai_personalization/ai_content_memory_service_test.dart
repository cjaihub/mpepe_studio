import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/ai_personalization/models/ai_content_memory_models.dart';
import 'package:oneova/backend/ai_personalization/services/ai_content_memory_service.dart';

void main() {
  late AiContentMemoryService service;

  setUp(() {
    service = AiContentMemoryService();
  });

  test('AI cluster creation respects user settings', () {
    // 1. Fully enabled user
    final cluster1 = service.createClusterFromAi(
      'user_1',
      'Recent Trip',
      AiContentMemoryCategory.places,
      [],
    );
    expect(cluster1, isNotNull);

    // 2. Disable Location clustering specifically
    service.updateSettings('user_1', allowLocationClustering: false);
    
    final cluster2 = service.createClusterFromAi(
      'user_1',
      'Another Trip',
      AiContentMemoryCategory.places,
      [],
    );
    expect(cluster2, isNull); // AI is explicitly blocked by privacy settings

    // 3. But topics are still allowed
    final cluster3 = service.createClusterFromAi(
      'user_1',
      'Food Review',
      AiContentMemoryCategory.topics,
      [],
    );
    expect(cluster3, isNotNull);
  });

  test('Merging clusters properly dedupes and destroys source', () {
    final c1 = service.createClusterFromAi('owner_99', 'NYC 2024', AiContentMemoryCategory.places, [
      const AiContentMemoryItem(id: 'i1', type: AiContentMemoryAssetType.photo, referenceId: 'pic_1'),
    ])!;
    
    final c2 = service.createClusterFromAi('owner_99', 'New York', AiContentMemoryCategory.places, [
      const AiContentMemoryItem(id: 'i2', type: AiContentMemoryAssetType.photo, referenceId: 'pic_1'), // Duplicate underlying picture
      const AiContentMemoryItem(id: 'i3', type: AiContentMemoryAssetType.video, referenceId: 'vid_1'),
    ])!;

    // User merges "New York" (c2) into "NYC 2024" (c1)
    service.mergeClusters(c2.id, c1.id, 'owner_99');

    // c2 should be destroyed
    expect(
      () => service.renameCluster(c2.id, 'owner_99', 'Test'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('not found'))),
    );

    // c1 should have exactly 2 items (pic_1 should not be duplicated)
    expect(c1.items.length, 2);
    expect(c1.items.any((i) => i.referenceId == 'pic_1'), true);
    expect(c1.items.any((i) => i.referenceId == 'vid_1'), true);
  });
}
