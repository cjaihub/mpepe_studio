import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_adaptation_models.dart';
import '../../ai_agents/openrouter_agent_service.dart';

final contentAdaptationServiceProvider = Provider<ContentAdaptationService>((ref) {
  final agentService = ref.watch(openRouterAgentServiceProvider);
  return ContentAdaptationService(agentService);
});

class ContentAdaptationService {
  // ignore: unused_field
  final OpenRouterAgentService _aiAgent;

  ContentAdaptationService(this._aiAgent);

  /// Generates initial AI-suggested adaptations for a master asset across target destinations.
  /// Strictly NEVER mutates the master asset.
  Future<List<DestinationAdaptation>> suggestAdaptations({
    required String masterContentId,
    required String masterCaption,
    required String masterVideoUrl,
    required int masterDurationSec,
    required List<String> targetPlatforms,
  }) async {
    final List<DestinationAdaptation> adaptations = [];

    for (final platform in targetPlatforms) {
      // Simulate AI context parsing & tailoring per platform rules
      // E.g. TikTok loves #fyp, short captions. YouTube loves comprehensive descriptions.
      
      final tailoredCaption = await _generatePlatformCaption(platform, masterCaption);
      final recommendedAspectRatio = _getOptimalAspectRatio(platform);
      final privacyRules = _getDefaultPrivacy(platform);

      adaptations.add(
        DestinationAdaptation(
          masterContentId: masterContentId,
          destinationPlatform: platform,
          status: AdaptationStatus.suggested,
          variant: ContentVariant(
            caption: tailoredCaption,
            hashtags: _generatePlatformHashtags(platform),
            thumbnailUrl: 'https://cdn.onerova.com/derived_thumb_${platform.toLowerCase()}.jpg',
            aspectRatio: recommendedAspectRatio,
            durationSec: masterDurationSec, // Could be trimmed by video pipeline if needed
            audioId: 'original_audio_id',
            privacy: privacyRules,
          ),
        ),
      );
    }

    return adaptations;
  }

  /// Called when a user explicitly edits a suggested variant.
  DestinationAdaptation applyUserEdit(
    DestinationAdaptation original,
    ContentVariant editedVariant,
  ) {
    // We enforce that the master is never mutated, we simply update the distinct adaptation object.
    return original.copyWith(
      variant: editedVariant,
      status: AdaptationStatus.userEdited,
    );
  }
  
  /// Called when a user or auto-pilot approves the final variant for publishing.
  DestinationAdaptation approveVariant(DestinationAdaptation adaptation) {
    return adaptation.copyWith(status: AdaptationStatus.approved);
  }

  Future<String> _generatePlatformCaption(String platform, String baseCaption) async {
    // In production, this proxies out to `_aiAgent`
    await Future.delayed(const Duration(milliseconds: 100));
    if (platform == 'TikTok') {
      return '$baseCaption 🚀'; // Shorter, punchier
    } else if (platform == 'YouTube') {
      return 'Check out this full video! $baseCaption\n\nDon\'t forget to subscribe.'; // Longer, SEO optimized
    } else if (platform == 'Instagram') {
      return '$baseCaption ✨';
    }
    return baseCaption;
  }

  List<String> _generatePlatformHashtags(String platform) {
    if (platform == 'TikTok') return ['#fyp', '#viral'];
    if (platform == 'Instagram') return ['#reels', '#explore'];
    if (platform == 'YouTube') return ['#shorts'];
    return [];
  }

  String _getOptimalAspectRatio(String platform) {
    if (['TikTok', 'Instagram', 'YouTube Shorts'].contains(platform)) {
      return '9:16';
    }
    return '16:9'; // Standard YouTube / Facebook Feed
  }

  String _getDefaultPrivacy(String platform) {
    return 'public';
  }
}
