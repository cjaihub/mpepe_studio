enum MemoryMode {
  private,
  friends,
  group,
}

enum MemoryLifecycle {
  draft,
  locked,      // Captured but not scheduled for public unlock
  scheduled,   // Locked with a future unlock time
  unlocked,    // Available to view
  expired,
  deleted,
}

enum MemoryAssetType {
  photo,
  video,
  voice,
  text,
  location,
  people,
  music,
}

class MemoryAsset {
  final String id;
  final MemoryAssetType type;
  final String data; // URL, text content, location coordinates, etc.

  const MemoryAsset({
    required this.id,
    required this.type,
    required this.data,
  });
}

class PrivateMemory {
  final String id;
  final String ownerId;
  final String title;
  
  MemoryMode mode;
  MemoryLifecycle lifecycle;
  
  final List<MemoryAsset> assets;
  final DateTime createdAt;
  DateTime? scheduledUnlockTime;
  
  bool isUserAuthorizedForPublish;

  PrivateMemory({
    required this.id,
    required this.ownerId,
    required this.title,
    this.mode = MemoryMode.private,
    this.lifecycle = MemoryLifecycle.draft,
    List<MemoryAsset>? assets,
    required this.createdAt,
    this.scheduledUnlockTime,
    this.isUserAuthorizedForPublish = false, // Must be explicitly set to true by owner
  }) : assets = assets ?? [];

  bool get canUnlock {
    if (lifecycle == MemoryLifecycle.unlocked || lifecycle == MemoryLifecycle.deleted) return false;
    if (scheduledUnlockTime == null) return false;
    return DateTime.now().isAfter(scheduledUnlockTime!);
  }
}
