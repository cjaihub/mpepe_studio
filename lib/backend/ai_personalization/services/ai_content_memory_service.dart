import 'package:oneova/backend/ai_personalization/models/ai_content_memory_models.dart';

class AiContentMemoryService {
  final Map<String, AiContentMemoryCluster> _clusters = {};
  final Map<String, AiContentMemorySettings> _settings = {};

  AiContentMemorySettings getSettings(String userId) {
    return _settings.putIfAbsent(userId, () => AiContentMemorySettings(userId: userId));
  }

  void updateSettings(String userId, {
    bool? isAiOrganizationEnabled,
    bool? allowPeopleClustering,
    bool? allowLocationClustering,
  }) {
    final s = getSettings(userId);
    if (isAiOrganizationEnabled != null) s.isAiOrganizationEnabled = isAiOrganizationEnabled;
    if (allowPeopleClustering != null) s.allowPeopleClustering = allowPeopleClustering;
    if (allowLocationClustering != null) s.allowLocationClustering = allowLocationClustering;

    // If disabled, we aggressively purge the clusters immediately to ensure no hidden profiling exists.
    if (!s.isAiOrganizationEnabled) {
      _purgeUserClusters(userId);
    } else {
      if (!s.allowPeopleClustering) _purgeUserClusters(userId, category: AiContentMemoryCategory.people);
      if (!s.allowLocationClustering) _purgeUserClusters(userId, category: AiContentMemoryCategory.places);
    }
  }

  void _purgeUserClusters(String userId, {AiContentMemoryCategory? category}) {
    _clusters.removeWhere((id, cluster) {
      if (cluster.ownerId != userId) return false;
      if (category != null && cluster.category != category) return false;
      return true;
    });
  }

  /// AI calls this endpoint to organize content. It strictly validates user opt-in flags.
  AiContentMemoryCluster? createClusterFromAi(
    String ownerId,
    String title,
    AiContentMemoryCategory category,
    List<AiContentMemoryItem> items,
  ) {
    final s = getSettings(ownerId);
    
    // Core authorization firewall
    if (!s.isAiOrganizationEnabled) return null; // AI organization is globally disabled
    if (category == AiContentMemoryCategory.people && !s.allowPeopleClustering) return null;
    if (category == AiContentMemoryCategory.places && !s.allowLocationClustering) return null;

    final cluster = AiContentMemoryCluster(
      id: 'cluster_${DateTime.now().microsecondsSinceEpoch}',
      ownerId: ownerId,
      title: title,
      category: category,
      items: items,
      createdAt: DateTime.now(),
    );

    _clusters[cluster.id] = cluster;
    return cluster;
  }

  void renameCluster(String clusterId, String ownerId, String newTitle) {
    final cluster = _clusters[clusterId];
    if (cluster == null) throw Exception('Cluster not found');
    if (cluster.ownerId != ownerId) throw Exception('Unauthorized');

    cluster.title = newTitle;
  }

  void mergeClusters(String sourceId, String targetId, String ownerId) {
    final source = _clusters[sourceId];
    final target = _clusters[targetId];

    if (source == null || target == null) throw Exception('Cluster not found');
    if (source.ownerId != ownerId || target.ownerId != ownerId) throw Exception('Unauthorized');

    // Merge items
    for (var item in source.items) {
      // Prevent exact duplicates during merge
      if (!target.items.any((i) => i.referenceId == item.referenceId)) {
        target.items.add(item);
      }
    }

    _clusters.remove(sourceId); // Destroy source after merge
  }

  void deleteCluster(String clusterId, String ownerId) {
    final cluster = _clusters[clusterId];
    if (cluster == null) return;
    if (cluster.ownerId != ownerId) throw Exception('Unauthorized');

    _clusters.remove(clusterId);
  }
}
