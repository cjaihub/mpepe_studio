import 'package:cloud_firestore/cloud_firestore.dart';

enum ContentType {
  short_video,
  long_video,
  photo,
  carousel,
  story,
  live_replay,
  series_episode
}

class MediaMetadata {
  final double aspectRatio; // e.g., 9/16 for vertical
  final List<String> resolutions; // e.g. ['720p', '1080p']
  final bool isAdaptiveBitrate; // true if HLS/DASH manifest is used
  final String? thumbnailUrl;
  final String? posterFrameUrl;
  final Duration? duration;
  final String? audioTrackUrl;
  final String? musicId;
  final List<String> effects;
  final List<String> filters;
  final bool hasCaptions;
  final String? captionsUrl;

  MediaMetadata({
    this.aspectRatio = 9 / 16,
    this.resolutions = const [],
    this.isAdaptiveBitrate = false,
    this.thumbnailUrl,
    this.posterFrameUrl,
    this.duration,
    this.audioTrackUrl,
    this.musicId,
    this.effects = const [],
    this.filters = const [],
    this.hasCaptions = false,
    this.captionsUrl,
  });

  factory MediaMetadata.fromMap(Map<String, dynamic>? data) {
    if (data == null) return MediaMetadata();
    return MediaMetadata(
      aspectRatio: (data['aspectRatio'] as num?)?.toDouble() ?? (9 / 16),
      resolutions: List<String>.from(data['resolutions'] ?? []),
      isAdaptiveBitrate: data['isAdaptiveBitrate'] ?? false,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      posterFrameUrl: data['posterFrameUrl'] as String?,
      duration: data['durationMs'] != null ? Duration(milliseconds: data['durationMs']) : null,
      audioTrackUrl: data['audioTrackUrl'] as String?,
      musicId: data['musicId'] as String?,
      effects: List<String>.from(data['effects'] ?? []),
      filters: List<String>.from(data['filters'] ?? []),
      hasCaptions: data['hasCaptions'] ?? false,
      captionsUrl: data['captionsUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'aspectRatio': aspectRatio,
      'resolutions': resolutions,
      'isAdaptiveBitrate': isAdaptiveBitrate,
      'thumbnailUrl': thumbnailUrl,
      'posterFrameUrl': posterFrameUrl,
      'durationMs': duration?.inMilliseconds,
      'audioTrackUrl': audioTrackUrl,
      'musicId': musicId,
      'effects': effects,
      'filters': filters,
      'hasCaptions': hasCaptions,
      'captionsUrl': captionsUrl,
    };
  }
}

class Content {
  final String id;
  final String authorId;
  final String description; // The caption/body text
  final ContentType type;
  
  // Adaptive media path (e.g. m3u8 playlist URL or mp4 URL)
  final String mediaUrl; 
  final MediaMetadata mediaMetadata;

  final List<String> hashtags;
  final List<String> mentions; // user IDs mentioned
  final String? location;
  final double? latitude;
  final double? longitude;
  final String visibility; // 'public', 'private', 'friends', 'close_friends'

  // Engagement Counts (must not be faked)
  final int viewCount;
  final int commentCount;
  final int likeCount;
  final int reactionCount;
  final int shareCount;
  final int saveCount;
  final int repostCount;
  // Real watch signals for ranking (incremented by RecommendationService).
  final int completionCount; // full plays to the end
  final int watchTimeMs; // total milliseconds watched across viewers
  final int followerConversions; // follows started from this content
  
  final bool downloadsPermitted;

  final CreatorPermissions permissions;
  final ContentAttribution? attribution;
  final DateTime createdAt;

  Content({
    required this.id,
    required this.authorId,
    required this.description,
    this.type = ContentType.short_video,
    required this.mediaUrl,
    required this.mediaMetadata,
    this.hashtags = const [],
    this.mentions = const [],
    this.location,
    this.latitude,
    this.longitude,
    this.visibility = 'public',
    this.viewCount = 0,
    this.commentCount = 0,
    this.likeCount = 0,
    this.reactionCount = 0,
    this.shareCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.completionCount = 0,
    this.watchTimeMs = 0,
    this.followerConversions = 0,
    this.downloadsPermitted = true,
    this.permissions = const CreatorPermissions(),
    this.attribution,
    required this.createdAt,
  });

  factory Content.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Content(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      description: data['description'] ?? '',
      type: ContentType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => ContentType.short_video,
      ),
      mediaUrl: data['mediaUrl'] ?? '',
      mediaMetadata: MediaMetadata.fromMap(data['mediaMetadata'] as Map<String, dynamic>?),
      hashtags: List<String>.from(data['hashtags'] ?? []),
      mentions: List<String>.from(data['mentions'] ?? []),
      location: data['location'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      visibility: data['visibility'] ?? 'public',
      viewCount: data['viewCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      likeCount: data['likeCount'] ?? 0,
      reactionCount: data['reactionCount'] ?? 0,
      shareCount: data['shareCount'] ?? 0,
      saveCount: data['saveCount'] ?? 0,
      repostCount: data['repostCount'] ?? 0,
      completionCount: (data['completionCount'] as num?)?.toInt() ?? 0,
      watchTimeMs: (data['watchTimeMs'] as num?)?.toInt() ?? 0,
      followerConversions: (data['followerConversions'] as num?)?.toInt() ?? 0,
      downloadsPermitted: data['downloadsPermitted'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'description': description,
      'type': type.name,
      'mediaUrl': mediaUrl,
      'mediaMetadata': mediaMetadata.toMap(),
      'hashtags': hashtags,
      'mentions': mentions,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'visibility': visibility,
      'viewCount': viewCount,
      'commentCount': commentCount,
      'likeCount': likeCount,
      'reactionCount': reactionCount,
      'shareCount': shareCount,
      'saveCount': saveCount,
      'repostCount': repostCount,
      'downloadsPermitted': downloadsPermitted,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

enum DerivativeType { duet, stitch, remix, repost, quote_repost, video_reply, reaction_video, green_screen, split_screen }

class CreatorPermissions {
  final bool allowDuet;
  final bool allowStitch;
  final bool allowRemix;
  final bool allowSharing;
  const CreatorPermissions({
    this.allowDuet = true,
    this.allowStitch = true,
    this.allowRemix = true,
    this.allowSharing = true,
  });
}

class ContentAttribution {
  final String originalContentId;
  final String originalAuthorId;
  final DerivativeType derivativeType;
  const ContentAttribution({
    this.originalContentId = "",
    this.originalAuthorId = "",
    this.derivativeType = DerivativeType.duet,
  });
}
