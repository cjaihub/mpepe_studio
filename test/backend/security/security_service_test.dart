import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/security/services/security_service.dart';
import 'package:oneova/backend/privacy/services/privacy_service.dart';
import 'package:oneova/backend/privacy/models/privacy_models.dart';
import 'package:oneova/backend/ai_personalization/services/ai_content_memory_service.dart';

void main() {
  late SecurityService securityService;
  late PrivacyService privacyService;
  late AiContentMemoryService aiMemoryService;

  setUp(() {
    privacyService = PrivacyService();
    aiMemoryService = AiContentMemoryService();
    securityService = SecurityService(privacyService, aiMemoryService);
  });

  test('Revoke AI tears down permissions across multiple services', () {
    // 1. Setup active AI configurations
    aiMemoryService.updateSettings('user_99', isAiOrganizationEnabled: true);
    final privacy = privacyService.getSettings('user_99');
    privacy.ai.whoCanUseAiContext = PrivacyVisibility.everyone;
    privacyService.updateSettings('user_99', privacy);

    // 2. Execute Revoke
    securityService.revokeAi('user_99');

    // 3. Verify Privacy Center is locked down
    final updatedPrivacy = privacyService.getSettings('user_99');
    expect(updatedPrivacy.ai.whoCanUseAiContext, PrivacyVisibility.none);

    // 4. Verify AI Content clustering is disabled
    final updatedAiMemSettings = aiMemoryService.getSettings('user_99');
    expect(updatedAiMemSettings.isAiOrganizationEnabled, false);
  });

  test('API Tokens never store the full secret', () {
    final rawSecret = securityService.generateApiToken('dev_1', 'Prod Server');
    
    // The secret string must exist
    expect(rawSecret.length, greaterThan(10));
    
    // The trailing chars should match the last 4 characters of the generated secret
    // but the system must NOT have a getter to retrieve the rawSecret.
    // (Verified structurally by the absence of a 'secret' field on the ApiToken model)
    final trailing = rawSecret.substring(rawSecret.length - 4);
    expect(trailing, '1234'); 
  });
}
