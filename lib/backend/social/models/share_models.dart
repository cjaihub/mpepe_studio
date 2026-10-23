import 'package:uuid/uuid.dart';

enum ShareDestination {
  repost,
  quoteRepost,
  followers,
  friends,
  privateChat,
  copyLink,
  externalNetwork,
  embed,
}

class ShareSettings {
  final String postId;
  final bool allowRepost;
  final bool allowQuote;
  final bool allowEmbed;
  final bool allowDownload; // sometimes related to share
  final bool isPrivateContent;

  const ShareSettings({
    required this.postId,
    this.allowRepost = true,
    this.allowQuote = true,
    this.allowEmbed = true,
    this.allowDownload = true,
    this.isPrivateContent = false,
  });
}

class ShareAnalytics {
  final String postId;
  final int totalShares;
  final int reposts;
  final int quoteReposts;
  final int directMessageShares;
  final int copyLinkCount;
  final int externalShares;
  final int embeds;

  const ShareAnalytics({
    required this.postId,
    this.totalShares = 0,
    this.reposts = 0,
    this.quoteReposts = 0,
    this.directMessageShares = 0,
    this.copyLinkCount = 0,
    this.externalShares = 0,
    this.embeds = 0,
  });
}

class RepostData {
  final String id;
  final String originalPostId;
  final String originalAuthorId;
  final String reposterId;
  final String? quoteText; // null if just a regular repost
  final DateTime repostedAt;

  const RepostData({
    required this.id,
    required this.originalPostId,
    required this.originalAuthorId,
    required this.reposterId,
    this.quoteText,
    required this.repostedAt,
  });

  factory RepostData.create({
    required String originalPostId,
    required String originalAuthorId,
    required String reposterId,
    String? quoteText,
  }) {
    return RepostData(
      id: const Uuid().v4(),
      originalPostId: originalPostId,
      originalAuthorId: originalAuthorId,
      reposterId: reposterId,
      quoteText: quoteText,
      repostedAt: DateTime.now(),
    );
  }
}
