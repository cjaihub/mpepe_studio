import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a persistent post draft saved across sessions.
class PostDraft {
  final String id;
  final String userId;
  final String mediaPath;
  final bool isVideo;
  final String title;
  final String caption;
  final String? coverImagePath;
  final int coverTimeMs;
  final List<String> hashtags;
  final List<String> collaborators;
  final List<String> taggedUsers;
  final String privacy; // 'public', 'followers', 'private'
  final String ageRestriction; // 'all', '13+', '16+', '18+'
  final bool allowComments;
  final bool allowDuet;
  final bool allowStitch;
  final bool allowRemix;
  final bool allowDownload;
  final bool isAiGenerated;
  final bool isBrandedContent;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String geoRadiusTier; // 'local_10km', 'city_50km', 'regional', 'global'
  final String? link;
  final List<String> destinations; // ['internal', 'tiktok', 'instagram', ...]
  final bool isFastTrendBoosted;
  final DateTime updatedAt;
  final DateTime createdAt;

  const PostDraft({
    required this.id,
    required this.userId,
    required this.mediaPath,
    required this.isVideo,
    this.title = '',
    this.caption = '',
    this.coverImagePath,
    this.coverTimeMs = 0,
    this.hashtags = const [],
    this.collaborators = const [],
    this.taggedUsers = const [],
    this.privacy = 'public',
    this.ageRestriction = 'all',
    this.allowComments = true,
    this.allowDuet = true,
    this.allowStitch = true,
    this.allowRemix = true,
    this.allowDownload = true,
    this.isAiGenerated = false,
    this.isBrandedContent = false,
    this.location,
    this.latitude,
    this.longitude,
    this.geoRadiusTier = 'global',
    this.link,
    this.destinations = const ['internal'],
    this.isFastTrendBoosted = true,
    required this.updatedAt,
    required this.createdAt,
  });

  PostDraft copyWith({
    String? id,
    String? userId,
    String? mediaPath,
    bool? isVideo,
    String? title,
    String? caption,
    String? coverImagePath,
    int? coverTimeMs,
    List<String>? hashtags,
    List<String>? collaborators,
    List<String>? taggedUsers,
    String? privacy,
    String? ageRestriction,
    bool? allowComments,
    bool? allowDuet,
    bool? allowStitch,
    bool? allowRemix,
    bool? allowDownload,
    bool? isAiGenerated,
    bool? isBrandedContent,
    String? location,
    double? latitude,
    double? longitude,
    String? geoRadiusTier,
    String? link,
    List<String>? destinations,
    bool? isFastTrendBoosted,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    return PostDraft(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      mediaPath: mediaPath ?? this.mediaPath,
      isVideo: isVideo ?? this.isVideo,
      title: title ?? this.title,
      caption: caption ?? this.caption,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      coverTimeMs: coverTimeMs ?? this.coverTimeMs,
      hashtags: hashtags ?? this.hashtags,
      collaborators: collaborators ?? this.collaborators,
      taggedUsers: taggedUsers ?? this.taggedUsers,
      privacy: privacy ?? this.privacy,
      ageRestriction: ageRestriction ?? this.ageRestriction,
      allowComments: allowComments ?? this.allowComments,
      allowDuet: allowDuet ?? this.allowDuet,
      allowStitch: allowStitch ?? this.allowStitch,
      allowRemix: allowRemix ?? this.allowRemix,
      allowDownload: allowDownload ?? this.allowDownload,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      isBrandedContent: isBrandedContent ?? this.isBrandedContent,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geoRadiusTier: geoRadiusTier ?? this.geoRadiusTier,
      link: link ?? this.link,
      destinations: destinations ?? this.destinations,
      isFastTrendBoosted: isFastTrendBoosted ?? this.isFastTrendBoosted,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'mediaPath': mediaPath,
      'isVideo': isVideo,
      'title': title,
      'caption': caption,
      'coverImagePath': coverImagePath,
      'coverTimeMs': coverTimeMs,
      'hashtags': hashtags,
      'collaborators': collaborators,
      'taggedUsers': taggedUsers,
      'privacy': privacy,
      'ageRestriction': ageRestriction,
      'allowComments': allowComments,
      'allowDuet': allowDuet,
      'allowStitch': allowStitch,
      'allowRemix': allowRemix,
      'allowDownload': allowDownload,
      'isAiGenerated': isAiGenerated,
      'isBrandedContent': isBrandedContent,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'geoRadiusTier': geoRadiusTier,
      'link': link,
      'destinations': destinations,
      'isFastTrendBoosted': isFastTrendBoosted,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory PostDraft.fromMap(Map<String, dynamic> map, String id) {
    return PostDraft(
      id: id,
      userId: map['userId'] as String? ?? '',
      mediaPath: map['mediaPath'] as String? ?? '',
      isVideo: map['isVideo'] as bool? ?? true,
      title: map['title'] as String? ?? '',
      caption: map['caption'] as String? ?? '',
      coverImagePath: map['coverImagePath'] as String?,
      coverTimeMs: (map['coverTimeMs'] as num?)?.toInt() ?? 0,
      hashtags: (map['hashtags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      collaborators: (map['collaborators'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      taggedUsers: (map['taggedUsers'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      privacy: map['privacy'] as String? ?? 'public',
      ageRestriction: map['ageRestriction'] as String? ?? 'all',
      allowComments: map['allowComments'] as bool? ?? true,
      allowDuet: map['allowDuet'] as bool? ?? true,
      allowStitch: map['allowStitch'] as bool? ?? true,
      allowRemix: map['allowRemix'] as bool? ?? true,
      allowDownload: map['allowDownload'] as bool? ?? true,
      isAiGenerated: map['isAiGenerated'] as bool? ?? false,
      isBrandedContent: map['isBrandedContent'] as bool? ?? false,
      location: map['location'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      geoRadiusTier: map['geoRadiusTier'] as String? ?? 'global',
      link: map['link'] as String?,
      destinations: (map['destinations'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const ['internal'],
      isFastTrendBoosted: map['isFastTrendBoosted'] as bool? ?? true,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory PostDraft.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PostDraft.fromMap(data, doc.id);
  }
}
