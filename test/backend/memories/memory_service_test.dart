import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/memories/models/memory_models.dart';
import 'package:oneova/backend/memories/services/memory_service.dart';

void main() {
  late MemoryService service;

  setUp(() {
    service = MemoryService();
  });

  test('Creates draft and transitions to locked', () {
    final mem = service.createMemoryDraft('owner_1', 'Trip to Bali');
    
    expect(mem.lifecycle, MemoryLifecycle.draft);
    
    service.addAsset(mem.id, 'owner_1', const MemoryAsset(id: 'a1', type: MemoryAssetType.photo, data: 'img_url'));
    
    service.lockMemory(mem.id, 'owner_1');
    expect(mem.lifecycle, MemoryLifecycle.locked);

    // Cannot add assets to locked memory
    expect(
      () => service.addAsset(mem.id, 'owner_1', const MemoryAsset(id: 'a2', type: MemoryAssetType.text, data: 'txt')),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Cannot modify locked memory'))),
    );
  });

  test('Strictly blocks unlocking without explicit publish authorization', () {
    final mem = service.createMemoryDraft('owner_1', 'Time Capsule');
    
    // Scheduled for yesterday so timer isn't the blocker
    service.lockMemory(mem.id, 'owner_1', unlockTime: DateTime.now().subtract(const Duration(days: 1)));
    
    expect(mem.lifecycle, MemoryLifecycle.scheduled);
    expect(mem.canUnlock, true); // Timer allows it

    // But it lacks user authorization!
    expect(
      () => service.executeUnlock(mem.id),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Publish Blocked: Explicit user authorization is required'))),
    );

    // Authorize and unlock
    service.authorizePublishing(mem.id, 'owner_1');
    service.executeUnlock(mem.id);

    expect(mem.lifecycle, MemoryLifecycle.unlocked);
  });

  test('Blocks premature unlock attempts', () {
    final mem = service.createMemoryDraft('owner_1', 'Future Self');
    
    // Scheduled 10 days into the future
    service.lockMemory(mem.id, 'owner_1', unlockTime: DateTime.now().add(const Duration(days: 10)));
    
    service.authorizePublishing(mem.id, 'owner_1'); // Authorized

    expect(mem.canUnlock, false); // Timer blocks it

    expect(
      () => service.executeUnlock(mem.id),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('not ready to be unlocked yet'))),
    );
  });
}
