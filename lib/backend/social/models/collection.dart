enum CollectionType {
  playlist,
  learningSeries,
  premiumSeries,
  episodeCollection,
}

enum CollectionVisibility {
  public,
  unlisted,
  private,
}

enum AccessPolicy {
  free,
  premium,
  subscription,
}

class PlaylistItem {
  final String id;
  final String postId; // Reference to the actual video/media record
  final int orderIndex;
  
  const PlaylistItem({
    required this.id,
    required this.postId,
    required this.orderIndex,
  });
}

class MediaCollection {
  final String id;
  final String creatorId;
  final CollectionType type;
  final String title;
  final String description;
  final String coverUrl;
  final CollectionVisibility visibility;
  
  // Specific to series
  final AccessPolicy accessPolicy;
  final double? price;
  final String? previewVideoUrl;
  final double averageRating;
  final int reviewCount;

  // The actual contents referenced by ID
  final List<PlaylistItem> items;

  MediaCollection({
    required this.id,
    required this.creatorId,
    required this.type,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.visibility,
    this.accessPolicy = AccessPolicy.free,
    this.price,
    this.previewVideoUrl,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    this.items = const [],
  });

  factory MediaCollection.fromMap(String id, Map<String, dynamic> m) {
    T pick<T extends Enum>(List<T> values, Object? raw, T fallback) =>
        values.firstWhere((v) => v.name == raw, orElse: () => fallback);
    final rawItems = (m['items'] as List?) ?? const [];
    return MediaCollection(
      id: id,
      creatorId: (m['creatorId'] as String?) ?? '',
      type: pick(CollectionType.values, m['type'], CollectionType.playlist),
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      coverUrl: (m['coverUrl'] as String?) ?? '',
      visibility: pick(CollectionVisibility.values, m['visibility'], CollectionVisibility.public),
      accessPolicy: pick(AccessPolicy.values, m['accessPolicy'], AccessPolicy.free),
      price: (m['price'] as num?)?.toDouble(),
      previewVideoUrl: m['previewVideoUrl'] as String?,
      averageRating: (m['averageRating'] as num?)?.toDouble() ?? 0,
      reviewCount: (m['reviewCount'] as num?)?.toInt() ?? 0,
      items: [
        for (var i = 0; i < rawItems.length; i++)
          if (rawItems[i] is Map)
            PlaylistItem(
              id: (rawItems[i]['id'] as String?) ?? '$id-$i',
              postId: (rawItems[i]['postId'] as String?) ?? '',
              orderIndex: (rawItems[i]['orderIndex'] as num?)?.toInt() ?? i,
            ),
      ]..sort((x, y) => x.orderIndex.compareTo(y.orderIndex)),
    );
  }
}

class UserCollectionProgress {
  final String collectionId;
  final String lastWatchedPostId;
  final Duration lastWatchedPosition;
  final bool isCompleted;
  final List<String> completedPostIds;

  UserCollectionProgress({
    required this.collectionId,
    required this.lastWatchedPostId,
    required this.lastWatchedPosition,
    this.isCompleted = false,
    this.completedPostIds = const [],
  });
}
