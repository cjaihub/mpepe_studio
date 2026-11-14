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
  final List<String> imageUrls;

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
    this.imageUrls = const [],
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
      imageUrls: List<String>.from(data['imageUrls'] ?? data['mediaUrls'] ?? []),
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
      if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
    };
  }
}

/// Validated destination link of a post (functions/src/feed/destinationLinks.ts).
class ContentDestination {
  final String kind; // product | shop | profile | live | web
  final String? url;
  final String? host;
  final String? route; // in-app go_router path
  final String? productId;
  final String label;
  final String verdict; // safe | suspicious | dangerous

  const ContentDestination({
    required this.kind,
    this.url,
    this.host,
    this.route,
    this.productId,
    required this.label,
    this.verdict = 'safe',
  });

  bool get isInApp => route != null && route!.startsWith('/');

  static ContentDestination? fromMap(Object? raw) {
    if (raw is! Map) return null;
    if (raw['status'] != 'ok') return null;
    final route = raw['route'] as String?;
    final url = raw['url'] as String?;
    if ((route == null || route.isEmpty) && (url == null || url.isEmpty)) return null;
    return ContentDestination(
      kind: raw['kind'] as String? ?? 'web',
      url: url,
      host: raw['host'] as String?,
      route: route,
      productId: raw['productId'] as String?,
      label: (raw['label'] as String?)?.trim().isNotEmpty == true ? raw['label'] as String : 'Open link',
      verdict: raw['verdict'] as String? ?? 'safe',
    );
  }
}

class Content {
  final String id;
  final String authorId;
  final String? title;
  final String description; // The caption/body text
  final ContentType type;
  
  // Adaptive media path (e.g. m3u8 playlist URL or mp4 URL)
  final String mediaUrl; 
  final List<String> mediaUrls;
  final MediaMetadata mediaMetadata;

  bool get isPhotoOrCarousel =>
      type == ContentType.photo ||
      type == ContentType.carousel ||
      (mediaUrls.length > 1 &&
          !mediaUrl.toLowerCase().contains('.mp4') &&
          !mediaUrl.toLowerCase().contains('.m3u8') &&
          !mediaUrl.toLowerCase().contains('.mov'));

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

  /// Product / shop / web link on the post, written only by the server
  /// (`contentSetDestination`); null when none or not validated yet.
  final ContentDestination? destination;
  final int destinationClicks;

  Content({
    required this.id,
    required this.authorId,
    this.title,
    required this.description,
    this.type = ContentType.short_video,
    required this.mediaUrl,
    this.mediaUrls = const [],
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
    this.destination,
    this.destinationClicks = 0,
  });

  factory Content.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawType = (data['type'] as String?)?.toLowerCase();
    final parsedType = (rawType == 'reel' || rawType == 'reels' || rawType == 'video' || rawType == 'short_video')
        ? ContentType.short_video
        : ContentType.values.firstWhere(
            (e) => e.name.toLowerCase() == rawType,
            orElse: () => ContentType.short_video,
          );
    final meta = MediaMetadata.fromMap(data['mediaMetadata'] as Map<String, dynamic>?);
    final primaryUrl = (data['mediaUrl'] as String?)?.trim() ?? '';
    final rawUrls = <String>[
      ...List<String>.from(data['mediaUrls'] ?? data['imageUrls'] ?? const []),
      ...meta.imageUrls,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (rawUrls.isEmpty && primaryUrl.isNotEmpty) {
      rawUrls.add(primaryUrl);
    }
    return Content(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      title: (data['title'] as String?)?.trim(),
      description: data['description'] ?? '',
      type: parsedType,
      mediaUrl: primaryUrl.isNotEmpty ? primaryUrl : (rawUrls.isNotEmpty ? rawUrls.first : ''),
      mediaUrls: rawUrls,
      mediaMetadata: meta,
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
      destination: ContentDestination.fromMap(data['destination']),
      destinationClicks: (data['destinationClicks'] as num?)?.toInt() ?? 0,
      permissions: CreatorPermissions.fromMap(data['permissions']),
      attribution: ContentAttribution.fromMap(data['attribution']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
      'description': description,
      'type': type.name,
      'mediaUrl': mediaUrl,
      if (mediaUrls.isNotEmpty) 'mediaUrls': mediaUrls,
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

  /// Posts saved before remixes had their own switch follow Duet.
  factory CreatorPermissions.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    final duet = m['allowDuet'] as bool? ?? true;
    return CreatorPermissions(
      allowDuet: duet,
      allowStitch: m['allowStitch'] as bool? ?? true,
      allowRemix: m['allowRemix'] as bool? ?? duet,
      allowSharing: m['allowSharing'] as bool? ?? true,
    );
  }
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

  static ContentAttribution? fromMap(Object? raw) {
    if (raw is! Map || raw['originalContentId'] is! String) return null;
    return ContentAttribution(
      originalContentId: raw['originalContentId'] as String,
      originalAuthorId: raw['originalAuthorId'] as String? ?? '',
      derivativeType: DerivativeType.values.where((t) => t.name == raw['derivativeType']).firstOrNull ?? DerivativeType.remix,
    );
  }
}
