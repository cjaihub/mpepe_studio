import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:oneova/backend/projects/services/collaborative_room_service.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:oneova/backend/social_inbox_repository.dart';

import 'collaborative_room_service_test.mocks.dart';

@GenerateMocks([ProjectRepository, SocialInboxRepository])
void main() {
  late MockProjectRepository mockProjectRepo;
  late MockSocialInboxRepository mockInboxRepo;
  late CollaborativeRoomService service;

  setUp(() {
    mockProjectRepo = MockProjectRepository();
    mockInboxRepo = MockSocialInboxRepository();
    service = CollaborativeRoomService(mockProjectRepo, mockInboxRepo);
  });

  test('Room chat correctly targets Canonical Group and verifies membership', () async {
    final project = StudioProject(
      id: 'proj_1',
      category: 'Video',
      title: 'Collab Room',
      status: 'Scripting',
      completedSteps: 0,
      createdAt: DateTime.now(),
      ownerId: 'owner_1',
      memberIds: ['member_1'],
      canonicalGroupId: 'group_abc',
    );

    // Member 1 can chat
    expect(
      () async => await service.sendRoomMessage(project, 'member_1', 'Hello room'),
      returnsNormally,
    );

    // Random non-member cannot chat
    expect(
      () async => await service.sendRoomMessage(project, 'rando_5', 'Spam spam'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Unauthorized'))),
    );
  });
}
