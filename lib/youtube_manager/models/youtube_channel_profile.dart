import 'dart:convert';

/// Represents the deep AI intelligence gathered about a specific YouTube channel.
/// This acts as the "document token" that the AI uses to understand the channel context.
class YouTubeChannelProfile {
  final String channelId;
  final String niche;
  final String targetAudience;
  final String toneOfVoice;
  final List<String> missingElements; // E.g., "Thumbnails lack consistent branding"
  final List<String> recommendedActions; // E.g., "Post a community poll about X"
  final DateTime lastScanned;
  final Map<String, dynamic> rawAnalyticsSnapshot; // High-level view counts, watch time, etc.

  YouTubeChannelProfile({
    required this.channelId,
    required this.niche,
    required this.targetAudience,
    required this.toneOfVoice,
    required this.missingElements,
    required this.recommendedActions,
    required this.lastScanned,
    required this.rawAnalyticsSnapshot,
  });

  Map<String, dynamic> toMap() {
    return {
      'channelId': channelId,
      'niche': niche,
      'targetAudience': targetAudience,
      'toneOfVoice': toneOfVoice,
      'missingElements': missingElements,
      'recommendedActions': recommendedActions,
      'lastScanned': lastScanned.toIso8601String(),
      'rawAnalyticsSnapshot': rawAnalyticsSnapshot,
    };
  }

  factory YouTubeChannelProfile.fromMap(Map<String, dynamic> map) {
    return YouTubeChannelProfile(
      channelId: map['channelId'] ?? '',
      niche: map['niche'] ?? '',
      targetAudience: map['targetAudience'] ?? '',
      toneOfVoice: map['toneOfVoice'] ?? '',
      missingElements: List<String>.from(map['missingElements'] ?? []),
      recommendedActions: List<String>.from(map['recommendedActions'] ?? []),
      lastScanned: DateTime.parse(map['lastScanned'] ?? DateTime.now().toIso8601String()),
      rawAnalyticsSnapshot: Map<String, dynamic>.from(map['rawAnalyticsSnapshot'] ?? {}),
    );
  }

  String toJson() => json.encode(toMap());

  factory YouTubeChannelProfile.fromJson(String source) => YouTubeChannelProfile.fromMap(json.decode(source));
}
