import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:oneova/backend/communities/models/community_models.dart';
import 'package:oneova/backend/communities/services/community_service.dart';
import 'package:oneova/backend/social_inbox_repository.dart';

import 'community_service_test.mocks.dart';

@GenerateMocks([SocialInboxRepository])
void main() {
  late MockSocialInboxRepository mockInbox;
  late CommunityService service;

  setUp(() {
    mockInbox = MockSocialInboxRepository();
    service = CommunityService(mockInbox);
  });

  test('Creates community mapping to canonical group', () {
    final comm = service.createCommunity(
      creatorUserId: 'founder_1',
      canonicalGroupId: 'group_abc123',
      name: 'Indie Filmmakers LA',
      description: 'Local creators',
      type: CommunityType.creator,
      privacy: CommunityPrivacy.inviteOnly,
    );

    expect(comm.name, 'Indie Filmmakers LA');
    expect(comm.canonicalGroupId, 'group_abc123'); // Fulfills "Use the canonical group/relationship system"
    expect(comm.members.length, 1);
    expect(comm.members[0].role, CommunityRole.owner); // Creator auto-assigned owner
  });

  test('Moderators can post announcements', () {
    final comm = service.createCommunity(
      creatorUserId: 'mod_1',
      canonicalGroupId: 'group_99',
      name: 'Gaming Hub',
      description: '',
      type: CommunityType.gaming,
      privacy: CommunityPrivacy.public,
    );

    // This should not throw, proving permission check passes
    expect(
      () => service.postAnnouncement(comm.id, 'mod_1', 'Welcome to the server!'),
      returnsNormally,
    );
  });

  test('Standard members cannot post announcements', () {
    final comm = service.createCommunity(
      creatorUserId: 'mod_1',
      canonicalGroupId: 'group_99',
      name: 'Gaming Hub',
      description: '',
      type: CommunityType.gaming,
      privacy: CommunityPrivacy.public,
    );
    
    // Inject a standard member
    comm.members.add(CommunityMember(userId: 'pleb_2', role: CommunityRole.member, joinedAt: DateTime.now()));

    // Must throw Unauthorized exception
    expect(
      () => service.postAnnouncement(comm.id, 'pleb_2', 'I am spamming the announcements channel!'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Unauthorized'))),
    );
  });

  test('Standard members cannot create official events', () {
    final comm = service.createCommunity(
      creatorUserId: 'mod_1',
      canonicalGroupId: 'group_99',
      name: 'Gaming Hub',
      description: '',
      type: CommunityType.gaming,
      privacy: CommunityPrivacy.public,
    );
    
    comm.members.add(CommunityMember(userId: 'pleb_2', role: CommunityRole.member, joinedAt: DateTime.now()));

    // Must throw Unauthorized exception
    expect(
      () => service.createEvent(comm.id, 'pleb_2', 'Lan Party', DateTime.now()),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Unauthorized'))),
    );
  });

  test('Standard members CAN create polls', () {
    final comm = service.createCommunity(
      creatorUserId: 'mod_1',
      canonicalGroupId: 'group_99',
      name: 'Gaming Hub',
      description: '',
      type: CommunityType.gaming,
      privacy: CommunityPrivacy.public,
    );
    
    comm.members.add(CommunityMember(userId: 'pleb_2', role: CommunityRole.member, joinedAt: DateTime.now()));

    // Members can create polls, should not throw
    final poll = service.createPoll(comm.id, 'pleb_2', 'What game next?', ['Halo', 'CoD']);
    expect(poll.question, 'What game next?');
  });
}
