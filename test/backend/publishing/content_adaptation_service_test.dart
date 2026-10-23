import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/publishing/models/content_adaptation_models.dart';
import 'package:oneova/backend/publishing/services/content_adaptation_service.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';

void main() {
  late ContentAdaptationService service;

  setUp(() {
    // Stub OpenRouter for test
    service = ContentAdaptationService(OpenRouterAgentService());
  });

  test('Suggests platform-tailored adaptations from master', () async {
    final suggestions = await service.suggestAdaptations(
      masterContentId: 'master_1',
      masterCaption: 'My beautiful vacation',
      masterVideoUrl: 'https://cdn.com/master.mp4',
      masterDurationSec: 15,
      targetPlatforms: ['TikTok', 'YouTube', 'Facebook'],
    );

    expect(suggestions.length, 3);
    
    final tiktok = suggestions.firstWhere((s) => s.destinationPlatform == 'TikTok');
    expect(tiktok.status, AdaptationStatus.suggested);
    expect(tiktok.variant.aspectRatio, '9:16');
    expect(tiktok.variant.hashtags.contains('#fyp'), true);
    
    final youtube = suggestions.firstWhere((s) => s.destinationPlatform == 'YouTube');
    expect(youtube.variant.aspectRatio, '16:9'); // Since it's full YouTube, not explicitly Shorts in this test case
    expect(youtube.variant.caption.contains('subscribe'), true);
  });

  test('Allows user editing without mutating master ID or destination mapping', () {
    final original = DestinationAdaptation(
      masterContentId: 'master_1',
      destinationPlatform: 'TikTok',
      status: AdaptationStatus.suggested,
      variant: const ContentVariant(
        caption: 'Hello',
        thumbnailUrl: 't.jpg',
        aspectRatio: '9:16',
        durationSec: 10,
        audioId: 'a_1',
      ),
    );

    final updatedVariant = original.variant.copyWith(caption: 'Custom User Caption');
    
    final result = service.applyUserEdit(original, updatedVariant);
    
    expect(result.masterContentId, 'master_1');
    expect(result.status, AdaptationStatus.userEdited);
    expect(result.variant.caption, 'Custom User Caption');
    
    // Original object properties prove the master state model was isolated
    expect(original.variant.caption, 'Hello');
  });
}
