import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/share_models.dart';

final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService();
});

class ShareService {
  final Map<String, ShareAnalytics> _mockAnalytics = {};

  Future<ShareSettings> getShareSettings(String postId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return ShareSettings(postId: postId);
  }

  Future<ShareAnalytics> getAnalytics(String postId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return _mockAnalytics[postId] ?? ShareAnalytics(postId: postId);
  }

  Future<bool> executeShare({
    required String postId,
    required String authorId,
    required String currentUserId,
    required ShareDestination destination,
    String? quoteText,
  }) async {
    // 1. Fetch settings to enforce constraints
    final settings = await getShareSettings(postId);

    // 2. Enforce constraints
    if (settings.isPrivateContent) {
      if (destination == ShareDestination.repost || 
          destination == ShareDestination.quoteRepost || 
          destination == ShareDestination.embed || 
          destination == ShareDestination.externalNetwork) {
        throw Exception('Private content cannot be shared publicly.');
      }
    }

    if (!settings.allowRepost && (destination == ShareDestination.repost || destination == ShareDestination.quoteRepost)) {
      throw Exception('Creator has disabled reposting.');
    }

    if (!settings.allowEmbed && destination == ShareDestination.embed) {
      throw Exception('Creator has disabled embedding.');
    }

    // 3. Process sharing (mocked)
    await Future.delayed(const Duration(milliseconds: 400));
    
    // 4. Update Analytics
    _incrementAnalytics(postId, destination);

    return true;
  }

  void _incrementAnalytics(String postId, ShareDestination destination) {
    final current = _mockAnalytics[postId] ?? ShareAnalytics(postId: postId);
    
    _mockAnalytics[postId] = ShareAnalytics(
      postId: postId,
      totalShares: current.totalShares + 1,
      reposts: destination == ShareDestination.repost ? current.reposts + 1 : current.reposts,
      quoteReposts: destination == ShareDestination.quoteRepost ? current.quoteReposts + 1 : current.quoteReposts,
      directMessageShares: destination == ShareDestination.privateChat ? current.directMessageShares + 1 : current.directMessageShares,
      copyLinkCount: destination == ShareDestination.copyLink ? current.copyLinkCount + 1 : current.copyLinkCount,
      externalShares: destination == ShareDestination.externalNetwork ? current.externalShares + 1 : current.externalShares,
      embeds: destination == ShareDestination.embed ? current.embeds + 1 : current.embeds,
    );
  }
}
