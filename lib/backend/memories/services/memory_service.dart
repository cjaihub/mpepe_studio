import 'package:oneova/backend/memories/models/memory_models.dart';

class MemoryService {
  final Map<String, PrivateMemory> _memories = {};

  PrivateMemory createMemoryDraft(String ownerId, String title) {
    final memory = PrivateMemory(
      id: 'mem_${DateTime.now().microsecondsSinceEpoch}',
      ownerId: ownerId,
      title: title,
      createdAt: DateTime.now(),
      lifecycle: MemoryLifecycle.draft,
    );
    _memories[memory.id] = memory;
    return memory;
  }

  void addAsset(String memoryId, String ownerId, MemoryAsset asset) {
    final mem = _memories[memoryId];
    if (mem == null) throw Exception('Memory not found');
    if (mem.ownerId != ownerId) throw Exception('Unauthorized');
    if (mem.lifecycle != MemoryLifecycle.draft) throw Exception('Cannot modify locked memory');
    
    mem.assets.add(asset);
  }

  void lockMemory(String memoryId, String ownerId, {DateTime? unlockTime, MemoryMode mode = MemoryMode.private}) {
    final mem = _memories[memoryId];
    if (mem == null) throw Exception('Memory not found');
    if (mem.ownerId != ownerId) throw Exception('Unauthorized');
    if (mem.lifecycle != MemoryLifecycle.draft) throw Exception('Invalid state transition');

    mem.mode = mode;
    mem.scheduledUnlockTime = unlockTime;
    
    if (unlockTime != null) {
      mem.lifecycle = MemoryLifecycle.scheduled;
    } else {
      mem.lifecycle = MemoryLifecycle.locked;
    }
  }

  /// CRITICAL CONSTRAINT: "Never publish automatically without user authorization."
  void authorizePublishing(String memoryId, String ownerId) {
    final mem = _memories[memoryId];
    if (mem == null) throw Exception('Memory not found');
    if (mem.ownerId != ownerId) throw Exception('Unauthorized');
    
    mem.isUserAuthorizedForPublish = true;
  }

  /// System cron or user manually unlocking a scheduled memory
  void executeUnlock(String memoryId) {
    final mem = _memories[memoryId];
    if (mem == null) throw Exception('Memory not found');

    if (!mem.isUserAuthorizedForPublish) {
      throw Exception('Publish Blocked: Explicit user authorization is required before unlocking.');
    }

    if (!mem.canUnlock) {
      throw Exception('Memory is not ready to be unlocked yet.');
    }

    mem.lifecycle = MemoryLifecycle.unlocked;
    
    // In real app, trigger notifications/feed updates based on mem.mode (private, friends, group)
  }

  void deleteMemory(String memoryId, String ownerId) {
    final mem = _memories[memoryId];
    if (mem == null) return;
    if (mem.ownerId != ownerId) throw Exception('Unauthorized');

    mem.lifecycle = MemoryLifecycle.deleted;
    _memories.remove(memoryId);
  }

  PrivateMemory? getMemory(String id) => _memories[id];
}
