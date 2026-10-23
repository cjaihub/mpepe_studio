import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:oneova/backend/creator_marketplace/models/creator_marketplace_models.dart';
import 'package:oneova/backend/creator_marketplace/services/creator_marketplace_service.dart';
import 'package:oneova/backend/social_inbox_repository.dart';

import 'creator_marketplace_service_test.mocks.dart';

@GenerateMocks([SocialInboxRepository])
void main() {
  late MockSocialInboxRepository mockInbox;
  late CreatorMarketplaceService service;

  setUp(() {
    mockInbox = MockSocialInboxRepository();
    service = CreatorMarketplaceService(mockInbox);
  });

  test('Guards private contact information', () {
    final profile = CreatorMarketplaceProfile(
      userId: 'creator_1',
      displayName: 'Alice Editor',
      skills: ['Premiere Pro'],
      services: [],
      portfolioUrls: [],
      isAvailable: true,
      locationScope: 'Remote',
      languages: ['en'],
      categories: ['Video Editing'],
      privateEmail: 'alice@hidden.com',
      privatePhone: '555-0000',
      allowDirectContact: false,
    );

    expect(profile.contactEmail, isNull);
    expect(profile.contactPhone, isNull);
  });

  test('Searches and filters creators correctly', () {
    service.registerProfile(CreatorMarketplaceProfile(
      userId: 'creator_1',
      displayName: 'Alice Editor',
      skills: ['Premiere Pro', 'After Effects'],
      services: [],
      portfolioUrls: [],
      isAvailable: true,
      locationScope: 'Remote',
      languages: ['en', 'fr'],
      categories: ['Video Editing'],
      privateEmail: 'a@a.com',
      privatePhone: '1',
    ));
    
    service.registerProfile(CreatorMarketplaceProfile(
      userId: 'creator_2',
      displayName: 'Bob Sound',
      skills: ['Logic Pro'],
      services: [],
      portfolioUrls: [],
      isAvailable: false, // Busy
      locationScope: 'Local',
      languages: ['en'],
      categories: ['Audio Engineering'],
      privateEmail: 'b@b.com',
      privatePhone: '2',
    ));

    final availableEditors = service.searchCreators(category: 'Video Editing');
    expect(availableEditors.length, 1);
    expect(availableEditors.first.displayName, 'Alice Editor');

    final audioEngineers = service.searchCreators(category: 'Audio Engineering', requireAvailable: false);
    expect(audioEngineers.length, 1);
    expect(audioEngineers.first.displayName, 'Bob Sound');
    
    final busyEngineers = service.searchCreators(category: 'Audio Engineering', requireAvailable: true);
    expect(busyEngineers.isEmpty, true);
  });

  test('Can submit collaboration request securely', () {
    service.registerProfile(CreatorMarketplaceProfile(
      userId: 'creator_1',
      displayName: 'Alice Editor',
      skills: ['Premiere Pro'],
      services: [
        CreatorServiceListing(id: 'svc_1', title: 'Color Grading', description: 'Basic grade', price: 150),
      ],
      portfolioUrls: [],
      isAvailable: true,
      locationScope: 'Remote',
      languages: ['en'],
      categories: ['Video Editing'],
      privateEmail: 'a@a.com',
      privatePhone: '1',
    ));

    final request = service.requestCollaboration(
      requestorId: 'biz_1',
      targetCreatorId: 'creator_1',
      serviceId: 'svc_1',
      message: 'Can you grade my film?',
    );

    expect(request.status, CollaborationStatus.pending);
    expect(request.agreedPrice, 150);
  });
}
