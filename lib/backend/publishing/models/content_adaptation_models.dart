enum AdaptationStatus {
  suggested,
  userEdited,
  approved,
}

class ContentVariant {
  final String caption;
  final List<String> hashtags;
  final String thumbnailUrl;
  final String aspectRatio; // e.g. '9:16', '16:9', '1:1'
  final int durationSec;
  final String audioId;
  final Map<String, dynamic> metadata;
  final String privacy; // e.g. 'public', 'private', 'unlisted'
  final List<String> mentions;

  const ContentVariant({
    required this.caption,
    this.hashtags = const [],
    required this.thumbnailUrl,
    required this.aspectRatio,
    required this.durationSec,
    required this.audioId,
    this.metadata = const {},
    this.privacy = 'public',
    this.mentions = const [],
  });

  ContentVariant copyWith({
    String? caption,
    List<String>? hashtags,
    String? thumbnailUrl,
    String? aspectRatio,
    int? durationSec,
    String? audioId,
    Map<String, dynamic>? metadata,
    String? privacy,
    List<String>? mentions,
  }) {
    return ContentVariant(
      caption: caption ?? this.caption,
      hashtags: hashtags ?? this.hashtags,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      durationSec: durationSec ?? this.durationSec,
      audioId: audioId ?? this.audioId,
      metadata: metadata ?? this.metadata,
      privacy: privacy ?? this.privacy,
      mentions: mentions ?? this.mentions,
    );
  }
}

class DestinationAdaptation {
  final String masterContentId;
  final String destinationPlatform; // 'YouTube', 'TikTok', 'Instagram'
  final ContentVariant variant;
  final AdaptationStatus status;

  const DestinationAdaptation({
    required this.masterContentId,
    required this.destinationPlatform,
    required this.variant,
    this.status = AdaptationStatus.suggested,
  });

  DestinationAdaptation copyWith({
    String? masterContentId,
    String? destinationPlatform,
    ContentVariant? variant,
    AdaptationStatus? status,
  }) {
    return DestinationAdaptation(
      masterContentId: masterContentId ?? this.masterContentId,
      destinationPlatform: destinationPlatform ?? this.destinationPlatform,
      variant: variant ?? this.variant,
      status: status ?? this.status,
    );
  }
}
