import 'package:cloud_firestore/cloud_firestore.dart';

enum MediaLicense {
  standard,
  creativeCommons,
  editorialOnly,
  publicDomain,
}

enum MediaVisibility {
  public,
  followers,
  closeFriends,
  subscribers,
  private,
}

class ReusePermissions {
  final bool allowDownload;
  final bool allowRemix;
  final bool allowDuet;
  final bool allowStitch;
  final bool allowRepost;
  final bool allowEmbed;
  final bool allowAIProcessing; // True means opting into ML training
  final bool allowCommercialUse;

  const ReusePermissions({
    this.allowDownload = true,
    this.allowRemix = true,
    this.allowDuet = true,
    this.allowStitch = true,
    this.allowRepost = true,
    this.allowEmbed = true,
    this.allowAIProcessing = false, // Always default to opt-out for AI
    this.allowCommercialUse = false,
  });

  factory ReusePermissions.fromMap(Map<String, dynamic> map) {
    return ReusePermissions(
      allowDownload: map['allowDownload'] ?? false,
      allowRemix: map['allowRemix'] ?? false,
      allowDuet: map['allowDuet'] ?? false,
      allowStitch: map['allowStitch'] ?? false,
      allowRepost: map['allowRepost'] ?? false,
      allowEmbed: map['allowEmbed'] ?? false,
      allowAIProcessing: map['allowAIProcessing'] ?? false,
      allowCommercialUse: map['allowCommercialUse'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'allowDownload': allowDownload,
      'allowRemix': allowRemix,
      'allowDuet': allowDuet,
      'allowStitch': allowStitch,
      'allowRepost': allowRepost,
      'allowEmbed': allowEmbed,
      'allowAIProcessing': allowAIProcessing,
      'allowCommercialUse': allowCommercialUse,
    };
  }
}

class MediaRightsProfile {
  final String mediaId; // ID of the video/post/asset
  final String ownerId; // Entity holding copyright
  final String creatorId; // Original creator (if different from owner)
  final String? sourceUrl; // If imported or aggregated
  final String? attributionRequirement; // String dictating attribution terms
  
  final MediaLicense license;
  final MediaVisibility visibility;
  final ReusePermissions permissions;
  
  final bool isRevoked; // If true, kills downstream uses (remixes, duets) where policy allows

  const MediaRightsProfile({
    required this.mediaId,
    required this.ownerId,
    required this.creatorId,
    this.sourceUrl,
    this.attributionRequirement,
    this.license = MediaLicense.standard,
    this.visibility = MediaVisibility.public,
    this.permissions = const ReusePermissions(),
    this.isRevoked = false,
  });

  factory MediaRightsProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MediaRightsProfile(
      mediaId: doc.id,
      ownerId: data['ownerId'] ?? '',
      creatorId: data['creatorId'] ?? '',
      sourceUrl: data['sourceUrl'],
      attributionRequirement: data['attributionRequirement'],
      license: MediaLicense.values.firstWhere(
        (e) => e.name == data['license'],
        orElse: () => MediaLicense.standard,
      ),
      visibility: MediaVisibility.values.firstWhere(
        (e) => e.name == data['visibility'],
        orElse: () => MediaVisibility.public,
      ),
      permissions: ReusePermissions.fromMap(data['permissions'] ?? {}),
      isRevoked: data['isRevoked'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'creatorId': creatorId,
      'sourceUrl': sourceUrl,
      'attributionRequirement': attributionRequirement,
      'license': license.name,
      'visibility': visibility.name,
      'permissions': permissions.toMap(),
      'isRevoked': isRevoked,
    };
  }
}
