import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/social/studio_social.dart';
import 'package:oneova/backend/social/repositories/relationship_repository.dart';
import 'package:share_plus/share_plus.dart';

import 'fakes/fake_social_ports.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class FakeRelationshipRepository extends RelationshipRepository {
  FakeRelationshipRepository() : super(FakeFirebaseFirestore());
  final StreamController<FollowState> states = StreamController<FollowState>.broadcast();
  final List<String> ops = [];
  Object? failWith;
  Completer<void>? gate;

  @override
  Stream<FollowState> watchFollowState(String currentUserId, String targetUserId) => states.stream;

  @override
  Future<void> followUser(String currentUserId, String targetUserId) async {
    ops.add('follow:$currentUserId>$targetUserId');
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    ops.add('unfollow:$currentUserId>$targetUserId');
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }
}

StudioState stateWith(StudioCounts counts) =>
    StudioState(streamId: 's1', hostId: 'h', stage: const StageLayout(centerUid: 'h'), counts: counts);

void main() {
  group('StudioFollowController', () {
    late FakeRelationshipRepository repo;
    late ProviderContainer c;

    ProviderContainer make(String me) {
      final container = ProviderContainer(overrides: [
        relationshipRepositoryProvider.overrideWithValue(repo),
        studioViewerIdentityProvider.overrideWithValue(StudioViewerIdentity(uid: me, name: 'Me')),
      ]);
      container.listen(studioFollowProvider('host'), (_, _) {});
      return container;
    }

    setUp(() => repo = FakeRelationshipRepository());
    tearDown(() => c.dispose());

    test('follows optimistically and confirms from the stream', () async {
      c = make('me');
      repo.states.add(FollowState.none);
      await settle();
      final gate = Completer<void>();
      repo.gate = gate;
      final f = c.read(studioFollowProvider('host').notifier).toggle();
      expect(c.read(studioFollowProvider('host')).follow, FollowState.following);
      expect(c.read(studioFollowProvider('host')).busy, isTrue);
      repo.states.add(FollowState.none); // stale stream value ignored while busy
      await settle();
      expect(c.read(studioFollowProvider('host')).isFollowing, isTrue);
      gate.complete();
      await f;
      expect(repo.ops, ['follow:me>host']);
      repo.states.add(FollowState.requested); // private account
      await settle();
      final s = c.read(studioFollowProvider('host'));
      expect(s.follow, FollowState.requested);
      expect(s.isFollowing, isTrue);
      expect(s.busy, isFalse);
    });

    test('mutual → unfollow shows followsYou; failure rolls back', () async {
      c = make('me');
      repo.states.add(FollowState.mutual);
      await settle();
      repo.failWith = Exception('blocked');
      final gate = Completer<void>();
      repo.gate = gate;
      final f = c.read(studioFollowProvider('host').notifier).toggle();
      expect(c.read(studioFollowProvider('host')).follow, FollowState.followsYou);
      gate.complete();
      await f;
      final s = c.read(studioFollowProvider('host'));
      expect(s.follow, FollowState.mutual);
      expect(s.error, isNotNull);
      expect(s.errorSeq, 1);
      expect(repo.ops, ['unfollow:me>host']);
    });

    test('self cannot follow', () async {
      c = make('host');
      await settle();
      await c.read(studioFollowProvider('host').notifier).toggle();
      expect(c.read(studioFollowProvider('host')).follow, FollowState.self);
      expect(repo.ops, isEmpty);
    });
  });

  group('StudioShareService', () {
    test('calls lsShare then shares the returned url', () async {
      final calls = FakeCallPort()..handler = (n, a) => {'url': 'https://mpepe-2b4bd.web.app/live/s1'};
      final shared = <ShareParams>[];
      final svc = StudioShareService(calls, launcher: (p) async {
        shared.add(p);
        return const ShareResult('ok', ShareResultStatus.success);
      });
      final url = await svc.share('s1', title: 'My show');
      expect(url, 'https://mpepe-2b4bd.web.app/live/s1');
      expect(calls.calls.single.name, StudioCallables.share);
      expect(calls.calls.single.args, {'streamId': 's1'});
      expect(shared.single.text, contains(url));
      expect(shared.single.subject, 'My show');
    });

    test('falls back to the canonical link when the callable fails', () async {
      final calls = FakeCallPort()..handler = (n, a) => throw StateError('offline');
      final shared = <ShareParams>[];
      final svc = StudioShareService(calls, launcher: (p) async {
        shared.add(p);
        return const ShareResult('', ShareResultStatus.dismissed);
      });
      expect(await svc.share('abc'), studioShareUrl('abc'));
      expect(shared.single.text, contains(studioShareUrl('abc')));
    });
  });

  group('StudioCountsController', () {
    late FakeRoomPort room;
    late StreamController<StudioState> states;
    late ProviderContainer c;

    setUp(() {
      room = FakeRoomPort();
      states = StreamController<StudioState>.broadcast();
      c = ProviderContainer(overrides: [
        studioSocialRoomPortProvider.overrideWith((ref, id) => room),
        studioSocialStateSourceProvider.overrideWith((ref, id) => states.stream),
      ]);
      c.listen(studioCountsProvider('s1'), (_, _) {});
    });
    tearDown(() => c.dispose());

    test('falls back to StudioState.counts until a counts event arrives', () async {
      states.add(stateWith(const StudioCounts(viewers: 10, participants: 2, loves: 5)));
      await settle();
      expect(c.read(studioCountsProvider('s1')).viewers, 10);
      expect(c.read(studioCountsProvider('s1')).loves, 5);
      room.emit(const CountsEvent(viewers: 200000, participants: 36));
      await settle();
      expect(c.read(studioCountsProvider('s1')).viewers, 200000);
      // A (stale) state snapshot no longer overrides live counts.
      states.add(stateWith(const StudioCounts(viewers: 11, participants: 3, loves: 6)));
      await settle();
      final s = c.read(studioCountsProvider('s1'));
      expect(s.viewers, 200000);
      expect(s.participants, 36);
      expect(s.loves, 6);
    });

    test('reaction aggregates update totals monotonically', () async {
      room.emit(const ReactionAggEvent(loves: 1, sparkles: 1, totals: StudioCounts(loves: 9, sparkles: 4, shares: 2)));
      await settle();
      room.emit(const ReactionAggEvent(loves: 0, sparkles: 0, totals: StudioCounts(loves: 3)));
      await settle();
      final s = c.read(studioCountsProvider('s1'));
      expect([s.loves, s.sparkles, s.shares], [9, 4, 2]);
    });
  });

  test('formatStudioCount', () {
    expect(formatStudioCount(0), '0');
    expect(formatStudioCount(999), '999');
    expect(formatStudioCount(1000), '1K');
    expect(formatStudioCount(1250), '1.2K');
    expect(formatStudioCount(12599), '12.5K');
    expect(formatStudioCount(200000), '200K');
    expect(formatStudioCount(999999), '999K');
    expect(formatStudioCount(1000000), '1M');
    expect(formatStudioCount(1250000), '1.2M');
    expect(formatStudioCount(3400000000), '3.4B');
  });
}
