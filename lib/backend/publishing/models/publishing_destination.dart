enum CreationType {
  video,
  photo,
  story,
  post,
  live,
  poll,
  event,
  message,
}

enum PlatformDestination {
  internal, // "Your Platform" (Oneova)
  instagram,
  facebook,
  youtube,
  tiktok,
  whatsappBusiness,
  twitter,
}

class PublishingCapabilities {
  final List<CreationType> supportedTypes;
  final bool supportsDrafts;
  final bool supportsScheduling;
  final bool supportsCollab;
  final bool supportsTags;
  final int maxCaptionLength;
  final int maxMediaCount;
  
  const PublishingCapabilities({
    required this.supportedTypes,
    this.supportsDrafts = false,
    this.supportsScheduling = false,
    this.supportsCollab = false,
    this.supportsTags = false,
    this.maxCaptionLength = 0,
    this.maxMediaCount = 1,
  });

  bool canPublish(CreationType type) => supportedTypes.contains(type);
}

class ConnectedAccount {
  final String accountId;
  final PlatformDestination platform;
  final String accountName;
  final String avatarUrl;
  final bool isAuthorized;

  const ConnectedAccount({
    required this.accountId,
    required this.platform,
    required this.accountName,
    required this.avatarUrl,
    this.isAuthorized = true,
  });

  PublishingCapabilities get capabilities {
    switch (platform) {
      case PlatformDestination.internal:
        return const PublishingCapabilities(
          supportedTypes: [
            CreationType.video,
            CreationType.photo,
            CreationType.story,
            CreationType.post,
            CreationType.live,
            CreationType.poll,
            CreationType.event,
            CreationType.message,
          ],
          supportsDrafts: true,
          supportsScheduling: true,
          supportsCollab: true,
          supportsTags: true,
          maxCaptionLength: 4000,
          maxMediaCount: 10,
        );
      case PlatformDestination.instagram:
        return const PublishingCapabilities(
          supportedTypes: [
            CreationType.video,
            CreationType.photo,
            CreationType.story,
            CreationType.post,
            CreationType.live,
          ],
          supportsDrafts: true,
          supportsScheduling: true,
          supportsCollab: true,
          supportsTags: true,
          maxCaptionLength: 2200,
          maxMediaCount: 10,
        );
      case PlatformDestination.facebook:
        return const PublishingCapabilities(
          supportedTypes: [
            CreationType.video,
            CreationType.photo,
            CreationType.story,
            CreationType.post,
            CreationType.live,
            CreationType.event,
          ],
          supportsDrafts: true,
          supportsScheduling: true,
          supportsCollab: false,
          supportsTags: true,
          maxCaptionLength: 63206,
          maxMediaCount: 80,
        );
      case PlatformDestination.youtube:
        return const PublishingCapabilities(
          supportedTypes: [
            CreationType.video,
            CreationType.post,
            CreationType.live,
            CreationType.poll,
          ],
          supportsDrafts: true,
          supportsScheduling: true,
          supportsCollab: false,
          supportsTags: true,
          maxCaptionLength: 5000,
          maxMediaCount: 1, // Usually 1 video or a few images in community post
        );
      case PlatformDestination.tiktok:
        return const PublishingCapabilities(
          supportedTypes: [
            CreationType.video,
            CreationType.photo,
            CreationType.story,
            CreationType.live,
          ],
          supportsDrafts: true,
          supportsScheduling: true,
          supportsCollab: true,
          supportsTags: true,
          maxCaptionLength: 4000,
          maxMediaCount: 35,
        );
      case PlatformDestination.whatsappBusiness:
        return const PublishingCapabilities(
          supportedTypes: [
            CreationType.story, // Status
            CreationType.message,
            CreationType.photo,
            CreationType.video,
          ],
          supportsDrafts: false,
          supportsScheduling: false,
          supportsCollab: false,
          supportsTags: false,
          maxCaptionLength: 1024,
          maxMediaCount: 1,
        );
      case PlatformDestination.twitter:
        return const PublishingCapabilities(
          supportedTypes: [
            CreationType.video,
            CreationType.photo,
            CreationType.story,
            CreationType.post,
            CreationType.poll,
          ],
          supportsDrafts: true,
          supportsScheduling: true,
          supportsCollab: false,
          supportsTags: true,
          maxCaptionLength: 280,
          maxMediaCount: 4,
        );
    }
  }
}

extension PlatformDestinationHelper on PlatformDestination {
  String get displayName {
    switch (this) {
      case PlatformDestination.internal:
        return 'Oneova';
      case PlatformDestination.tiktok:
        return 'TikTok';
      case PlatformDestination.instagram:
        return 'Instagram Reels';
      case PlatformDestination.youtube:
        return 'YouTube Shorts';
      case PlatformDestination.twitter:
        return 'X (Twitter)';
      case PlatformDestination.facebook:
        return 'Facebook Reels';
      case PlatformDestination.whatsappBusiness:
        return 'WhatsApp Business';
    }
  }
}
