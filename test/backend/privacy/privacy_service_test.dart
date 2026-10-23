import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/privacy/models/privacy_models.dart';
import 'package:oneova/backend/privacy/services/privacy_service.dart';

// Test override for relationship mocking
class TestPrivacyService extends PrivacyService {
  @override
  bool areUsersMutuals(String userA, String userB) {
    if (userA == 'alice' && userB == 'bob') return true;
    if (userA == 'bob' && userB == 'alice') return true;
    return false;
  }

  @override
  bool isUserFollowing(String userA, String userB) {
    if (userA == 'charlie' && userB == 'alice') return true;
    return false;
  }
}

void main() {
  late TestPrivacyService service;

  setUp(() {
    service = TestPrivacyService();

    // Alice locks down her account
    service.updateSettings('alice', PrivacyCenterSettings(
      userId: 'alice',
      profile: ProfilePrivacy(
        whoCanSee: PrivacyVisibility.followers,
        whoCanFollow: PrivacyVisibility.everyone,
      ),
      content: ContentPrivacy(
        whoCanComment: PrivacyVisibility.mutuals,
        whoCanDownload: PrivacyVisibility.none,
      ),
      location: LocationPrivacy(
        whoCanSeeLocation: PrivacyVisibility.none,
      ),
      ai: AiPrivacy(
        whoCanUseAiContext: PrivacyVisibility.none,
      )
    ));
  });

  test('Backend enforces granular profile and content privacy', () {
    // 1. Profile visibility
    // Charlie follows Alice. He can see her profile.
    expect(service.canSeeProfile('alice', 'charlie'), true);
    // Dave does NOT follow Alice. He cannot see her profile.
    expect(service.canSeeProfile('alice', 'dave'), false);

    // 2. Comments
    // Charlie follows Alice, but they are not mutuals. He cannot comment.
    expect(service.canComment('alice', 'charlie'), false);
    // Bob and Alice are mutuals. Bob CAN comment.
    expect(service.canComment('alice', 'bob'), true);

    // 3. Absolute block (Location & Download)
    // No one can see Alice's location except herself.
    expect(service.canSeeLocation('alice', 'bob'), false);
    expect(service.canSeeLocation('alice', 'alice'), true);

    expect(service.canDownload('alice', 'bob'), false);
    
    // 4. AI block
    expect(service.canUseAiContext('alice', 'ai_system'), false);
  });
}
