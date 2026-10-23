enum AiContentMemoryCategory {
  people,
  places,
  projects,
  events,
  topics,
  sounds,
}

enum AiContentMemoryAssetType {
  video,
  photo,
  message,
  place,
  event,
  project,
}

class AiContentMemoryItem {
  final String id;
  final AiContentMemoryAssetType type;
  final String referenceId; // Maps to actual video/photo/message ID

  const AiContentMemoryItem({
    required this.id,
    required this.type,
    required this.referenceId,
  });
}

class AiContentMemoryCluster {
  final String id;
  final String ownerId;
  String title;
  AiContentMemoryCategory category;
  List<AiContentMemoryItem> items;
  final DateTime createdAt;

  AiContentMemoryCluster({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.category,
    required this.items,
    required this.createdAt,
  });
}

class AiContentMemorySettings {
  final String userId;
  bool isAiOrganizationEnabled;
  bool allowPeopleClustering;
  bool allowLocationClustering;

  AiContentMemorySettings({
    required this.userId,
    this.isAiOrganizationEnabled = true,
    this.allowPeopleClustering = true,
    this.allowLocationClustering = true,
  });
}
