import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:oneova/backend/sync_sessions/models/sync_session_models.dart';
import 'package:oneova/backend/sync_sessions/services/sync_session_service.dart';
import 'package:oneova/backend/social_inbox_repository.dart';

import 'sync_session_service_test.mocks.dart';

@GenerateMocks([SocialInboxRepository])
void main() {
  late MockSocialInboxRepository mockInbox;
  late SyncSessionService service;

  setUp(() {
    mockInbox = MockSocialInboxRepository();
    service = SyncSessionService(mockInbox);
  });

  test('Host controls state and late joiners get calculated time', () async {
    final session = service.createSession(
      hostId: 'host_1',
      title: 'Movie Night',
      type: SyncSessionType.watchParty,
      contentId: 'vid_777',
    );

    // Initial state is paused at zero
    expect(session.playback.state, PlaybackState.paused);
    expect(session.playback.currentPosition, Duration.zero);

    // Joiner 1 connects at the start
    final joinOffset1 = service.joinSession(session.id, 'viewer_1');
    expect(joinOffset1, Duration.zero);

    // Host hits play
    service.play(session.id, 'host_1');
    expect(session.playback.state, PlaybackState.playing);

    // Wait 100 milliseconds artificially
    await Future.delayed(const Duration(milliseconds: 100));

    // Joiner 2 late joins while it's playing. Their offset should dynamically calculate to ~100ms
    final joinOffset2 = service.joinSession(session.id, 'viewer_2');
    expect(joinOffset2.inMilliseconds, greaterThanOrEqualTo(95));
  });

  test('Non-hosts cannot control playback', () {
    final session = service.createSession(
      hostId: 'host_1',
      title: 'Study Session',
      type: SyncSessionType.learningSession,
      contentId: 'vid_123',
    );

    service.joinSession(session.id, 'viewer_1');

    // Viewer tries to pause
    expect(
      () => service.pause(session.id, 'viewer_1', const Duration(seconds: 5)),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Unauthorized'))),
    );

    // Verify it didn't pause
    expect(session.playback.state, PlaybackState.paused); // Initial state
    
    // Viewer tries to seek
    expect(
      () => service.seek(session.id, 'viewer_1', const Duration(seconds: 10)),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Unauthorized'))),
    );
  });

  test('Private sessions reject unauthorized users', () {
    final session = service.createSession(
      hostId: 'host_1',
      title: 'Private Premiere',
      type: SyncSessionType.creatorPremiere,
      contentId: 'vid_555',
      isPrivate: true,
    );

    // Random user tries to join without being invited
    expect(
      () => service.joinSession(session.id, 'rando_hacker'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Unauthorized: Private session'))),
    );
  });
}
