import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/publishing/models/publishing_destination.dart';
import 'package:oneova/backend/publishing/services/universal_creation_service.dart';

void main() {
  late UniversalCreationService service;

  setUp(() {
    service = UniversalCreationService();
  });

  test('Filters destinations correctly based on CreationType capabilities', () async {
    // Event is NOT supported by Instagram or TikTok
    // Event IS supported by Internal and Facebook
    final destinations = await service.getAvailableDestinationsFor('user_1', CreationType.event);
    
    expect(destinations.any((d) => d.platform == PlatformDestination.internal), true);
    expect(destinations.any((d) => d.platform == PlatformDestination.facebook), true);
    
    expect(destinations.any((d) => d.platform == PlatformDestination.instagram), false);
    expect(destinations.any((d) => d.platform == PlatformDestination.tiktok), false);
  });
  
  test('Filters destinations correctly for Video', () async {
    // Video should be supported by almost everything except WhatsApp only supports it under certain constraints, but our capability mapping says it does.
    final destinations = await service.getAvailableDestinationsFor('user_1', CreationType.video);
    
    expect(destinations.any((d) => d.platform == PlatformDestination.internal), true);
    expect(destinations.any((d) => d.platform == PlatformDestination.instagram), true);
    expect(destinations.any((d) => d.platform == PlatformDestination.facebook), true);
    expect(destinations.any((d) => d.platform == PlatformDestination.tiktok), true);
  });
  
  test('Publishes only to supported destinations even if bypassed', () async {
    final allAccounts = await service.getConnectedAccounts('user_1');
    
    final request = CrossPlatformPublishRequest(
      type: CreationType.event,
      mediaUrl: 'https://event.com/img.jpg',
      caption: 'Come to my event!',
      selectedDestinations: allAccounts, // Forcing all accounts, including invalid ones
    );
    
    final results = await service.publishToDestinations(request);
    
    expect(results.containsKey(PlatformDestination.internal), true);
    expect(results.containsKey(PlatformDestination.facebook), true);
    
    // It should have safely dropped Instagram and TikTok
    expect(results.containsKey(PlatformDestination.instagram), false);
    expect(results.containsKey(PlatformDestination.tiktok), false);
  });
}
