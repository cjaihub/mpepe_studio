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

  /// Tiny (about 16 px wide) JPEG as base64, shown blurred while the video
  /// loads. Written by the reels worker, so it costs no extra download.
  final String? tinyPreview;

  /// Size in bytes of the first segment of the lowest rung. Used to budget
  /// preloading on cellular.
  final int? firstSegmentBytes;

  /// Heights of the HLS rungs, lowest first (e.g. [640, 960, 1280]).
  final List<int> rungHeights;

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
    this.tinyPreview,
    this.firstSegmentBytes,
    this.rungHeights = const [],
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
      tinyPreview: data['tinyPreview'] as String?,
      firstSegmentBytes: (data['firstSegmentBytes'] as num?)?.toInt(),
      rungHeights: List<num>.from(data['rungHeights'] ?? const [])
          .map((e) => e.toInt())
          .toList(),
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
      'tinyPreview': tinyPreview,
      'firstSegmentBytes': firstSegmentBytes,
      'rungHeights': rungHeights,
    };
  }
}

/// Processing state of an uploaded video. Only [ready] videos are shown in
/// feeds. Documents written before this field existed count as [ready].
enum ContentStatus { uploading, processing, ready, failed }

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
  final String visibility; // 'public', 'private', 'friends', 'close_friends'

  // Engagement Counts (must not be faked)
  final int viewCount;
  final int commentCount;
  final int likeCount;
  final int reactionCount;
  final int shareCount;
  final int saveCount;
  final int repostCount;
  
  final bool downloadsPermitted;

  final DateTime createdAt;

  final ContentStatus status;

  bool get isReady => status == ContentStatus.ready;

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
    this.visibility = 'public',
    this.viewCount = 0,
    this.commentCount = 0,
    this.likeCount = 0,
    this.reactionCount = 0,
    this.shareCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.downloadsPermitted = true,
    required this.createdAt,
    this.status = ContentStatus.ready,
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
      visibility: data['visibility'] ?? 'public',
      viewCount: data['viewCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      likeCount: data['likeCount'] ?? 0,
      reactionCount: data['reactionCount'] ?? 0,
      shareCount: data['shareCount'] ?? 0,
      saveCount: data['saveCount'] ?? 0,
      repostCount: data['repostCount'] ?? 0,
      downloadsPermitted: data['downloadsPermitted'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: ContentStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => ContentStatus.ready,
      ),
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
      'status': status.name,
    };
  }
}
