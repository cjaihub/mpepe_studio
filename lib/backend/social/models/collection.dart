import 'package:uuid/uuid.dart';

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

  factory MediaCollection.mockPlaylist() {
    return MediaCollection(
      id: const Uuid().v4(),
      creatorId: 'user_1',
      type: CollectionType.playlist,
      title: 'Cinematic Vlogs 2026',
      description: 'A collection of all my cinematic vlogs from this year.',
      coverUrl: 'https://picsum.photos/400/400?random=10',
      visibility: CollectionVisibility.public,
      items: [
        PlaylistItem(id: const Uuid().v4(), postId: 'post_1', orderIndex: 0),
        PlaylistItem(id: const Uuid().v4(), postId: 'post_2', orderIndex: 1),
      ],
    );
  }

  factory MediaCollection.mockPremiumSeries() {
    return MediaCollection(
      id: const Uuid().v4(),
      creatorId: 'user_2',
      type: CollectionType.premiumSeries,
      title: 'Advanced Video Editing Masterclass',
      description: 'Learn how to edit like a pro using ONEROVA.',
      coverUrl: 'https://picsum.photos/400/400?random=11',
      visibility: CollectionVisibility.public,
      accessPolicy: AccessPolicy.premium,
      price: 29.99,
      previewVideoUrl: 'https://sample-videos.com/video123/mp4/720/big_buck_bunny_720p_1mb.mp4',
      averageRating: 4.8,
      reviewCount: 124,
      items: [
        PlaylistItem(id: const Uuid().v4(), postId: 'post_10', orderIndex: 0),
        PlaylistItem(id: const Uuid().v4(), postId: 'post_11', orderIndex: 1),
        PlaylistItem(id: const Uuid().v4(), postId: 'post_12', orderIndex: 2),
      ],
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
