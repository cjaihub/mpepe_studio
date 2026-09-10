import 'package:flutter/foundation.dart';

enum PlatformType {
  youtube,
  tiktok,
  facebook,
  instagram,
}

/// Represents a unified upload target (e.g. a YouTube channel, FB Page, etc.)
class ConnectedDestination {
  final String id;
  final String name;
  final String? profileImageUrl;
  final PlatformType platform;
  
  // Platform-specific internal IDs (e.g. Google Account ID, Meta Page Access Token)
  final String internalId;
  final String parentAccountId;

  const ConnectedDestination({
    required this.id,
    required this.name,
    this.profileImageUrl,
    required this.platform,
    required this.internalId,
    required this.parentAccountId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'profileImageUrl': profileImageUrl,
      'platform': platform.name,
      'internalId': internalId,
      'parentAccountId': parentAccountId,
    };
  }

  factory ConnectedDestination.youtube({
    required String channelId,
    required String channelTitle,
    required String googleId,
    String? thumbnailUrl,
  }) {
    return ConnectedDestination(
      id: channelId,
      name: channelTitle,
      profileImageUrl: thumbnailUrl,
      platform: PlatformType.youtube,
      internalId: channelId,
      parentAccountId: googleId,
    );
  }

  factory ConnectedDestination.meta({
    required String pageId,
    required String pageName,
    required String metaUserId,
    required PlatformType platform,
    String? profileUrl,
  }) {
    return ConnectedDestination(
      id: pageId,
      name: pageName,
      profileImageUrl: profileUrl,
      platform: platform,
      internalId: pageId,
      parentAccountId: metaUserId,
    );
  }

  factory ConnectedDestination.tiktok({
    required String tiktokUserId,
    required String username,
    String? avatarUrl,
  }) {
    return ConnectedDestination(
      id: tiktokUserId,
      name: username,
      profileImageUrl: avatarUrl,
      platform: PlatformType.tiktok,
      internalId: tiktokUserId,
      parentAccountId: tiktokUserId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectedDestination &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          platform == other.platform;

  @override
  int get hashCode => id.hashCode ^ platform.hashCode;
}
