import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/session/studio_clock.dart';
import 'package:oneova/backend/live_studio/session/studio_session_controller.dart';
import 'package:oneova/backend/live_studio/session/studio_state_sync.dart';
import 'package:oneova/backend/live_studio/settings/studio_settings_controller.dart';
import 'package:oneova/backend/live_studio/social/studio_social_ports.dart';

import 'fakes/fake_studio.dart';

StatePatchEvent title(int seq, String t) => StatePatchEvent(seq, 'title', t);

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('StudioStateSync', () {
    test('buffers until a base, then drains patches above it', () {
      final s = StudioStateSync();
      expect(s.applyPatch(title(3, 'c')), StudioPatchOutcome.buffered);
      expect(s.applyPatch(title(2, 'b')), StudioPatchOutcome.buffered);
      expect(s.applyFull(testState(seq: 1, title: 'a')), isTrue);
      expect(s.state!.seq, 3);
      expect(s.state!.title, 'c');
      expect(s.hasGap, isFalse);
    });

    test('applies in order, ignores old and duplicate seq', () {
      final s = StudioStateSync()..applyFull(testState(seq: 5));
      expect(s.applyPatch(title(6, 'x')), StudioPatchOutcome.applied);
      expect(s.applyPatch(title(6, 'dup')), StudioPatchOutcome.stale);
      expect(s.applyPatch(title(2, 'old')), StudioPatchOutcome.stale);
      expect(s.state!.title, 'x');
      expect(s.state!.seq, 6);
    });

    test('gap is buffered and fills when the missing patch arrives', () {
      final s = StudioStateSync()..applyFull(testState(seq: 1));
      expect(s.applyPatch(title(3, 'c')), StudioPatchOutcome.gap);
      expect(s.hasGap, isTrue);
      expect(s.state!.seq, 1);
      expect(s.applyPatch(title(2, 'b')), StudioPatchOutcome.applied);
      expect(s.state!.seq, 3);
      expect(s.state!.title, 'c');
      expect(s.hasGap, isFalse);
    });

    test('full state closes a gap and keeps newer buffered patches', () {
      final s = StudioStateSync()..applyFull(testState(seq: 1));
      s.applyPatch(title(4, 'd'));
      s.applyPatch(title(6, 'f'));
      expect(s.applyFull(testState(seq: 3, title: 'c')), isTrue);
      expect(s.state!.seq, 4);
      expect(s.hasGap, isTrue); // 5 still missing
      expect(s.applyFull(testState(seq: 6, title: 'F')), isTrue);
      expect(s.state!.title, 'F');
      expect(s.hasGap, isFalse);
    });

    test('older full state is ignored', () {
      final s = StudioStateSync()..applyFull(testState(seq: 8, title: 'new'));
      expect(s.applyFull(testState(seq: 7, title: 'old')), isFalse);
      expect(s.state!.title, 'new');
    });

    test('patch sections replace state parts', () {
      final s = StudioStateSync()..applyFull(testState(seq: 0));
      s.applyPatch(const StatePatchEvent(1, 'stage', {'centerUid': 'g1', 'wall': ['host']}));
      s.applyPatch(const StatePatchEvent(2, 'status', 'ended'));
      expect(s.state!.stage.centerUid, 'g1');
      expect(s.state!.stage.wall.first, 'host');
      expect(s.state!.status, StudioStatus.ended);
    });
  });

  group('CallableStudioClock', () {
    test('keeps the offset of the lowest-RTT sample of 5', () async {
      var local = 1000;
      final rtts = [120, 40, 300, 60, 80];
      var i = 0;
      final calls = FakeCallPort().on(StudioCallables.time, (_) {
        final rtt = rtts[i++];
        final server = local + rtt ~/ 2 + 5000; // true offset +5000
        local += rtt;
        return {'serverMs': server + (rtt == 40 ? 0 : rtt)}; // noisy except the best
      });
      final c = CallableStudioClock(calls, localNowMs: () => local);
      await c.calibrate();
      expect(calls.count(StudioCallables.time), 5);
      expect(c.bestRttMs, 40);
      expect(c.offsetMs, 5000);
      expect(c.serverNowMs(), local + 5000);
    });

    test('failures keep the previous offset', () async {
      final calls = FakeCallPort().on(StudioCallables.time, (_) => throw StateError('offline'));
      final c = CallableStudioClock(calls, localNowMs: () => 0);
      await c.calibrate();
      expect(c.calibrated, isFalse);
      expect(c.offsetMs, 0);
    });
  });

  group('StudioSessionController', () {
    late FakeRoom room;
    late FakeCallPort calls;
    late ProviderContainer container;
    late int seqOnServer;
    StudioState? firestoreState;

    setUp(() {
      room = FakeRoom();
      seqOnServer = 1;
      firestoreState = null;
      calls = FakeCallPort().on(StudioCallables.stateFull,
          (_) => {'state': testState(seq: seqOnServer, title: 'srv$seqOnServer').toJson()});
      container = ProviderContainer(overrides: [
        studioRoomProvider.overrideWith((ref, id) => room),
        studioCallPortProvider.overrideWithValue(calls),
        studioStateReaderProvider.overrideWithValue((_) async => firestoreState),
        studioGapResyncDelayProvider.overrideWithValue(() => Duration.zero),
      ]);
    });
    tearDown(() => container.dispose());

    Future<StudioState> ready() async {
      final sub = container.listen(studioStateProvider('s1'), (_, _) {});
      addTearDown(sub.close);
      for (var i = 0; i < 10 && !container.read(studioStateProvider('s1')).hasValue; i++) {
        await pump();
      }
      return container.read(studioStateProvider('s1')).requireValue;
    }

    StudioState now() => container.read(studioStateProvider('s1')).requireValue;

    test('initial state from lsStateFull, then patches in seq order', () async {
      expect((await ready()).seq, 1);
      room.emit(title(2, 'two'));
      expect(now().title, 'two');
      room.emit(title(2, 'dup'));
      room.emit(title(1, 'old'));
      expect(now().title, 'two');
      expect(calls.count(StudioCallables.stateFull), 1);
    });

    test('out-of-order patch fills without a resync', () async {
      await ready();
      room.emit(title(3, 'three'));
      room.emit(title(2, 'two'));
      await pump();
      await pump();
      expect(now().seq, 3);
      expect(calls.count(StudioCallables.stateFull), 1);
    });

    test('a real gap calls lsStateFull', () async {
      await ready();
      seqOnServer = 5;
      room.emit(title(5, 'five'));
      for (var i = 0; i < 5; i++) {
        await pump();
      }
      expect(calls.count(StudioCallables.stateFull), 2);
      expect(now().seq, 5);
      expect(now().title, 'srv5');
    });

    test('state.full event replaces state', () async {
      await ready();
      room.emit(StateFullEvent(testState(seq: 9, title: 'full')));
      expect(now().title, 'full');
      room.emit(StateFullEvent(testState(seq: 4, title: 'stale')));
      expect(now().title, 'full');
    });

    test('falls back to a Firestore get when lsStateFull fails', () async {
      calls.on(StudioCallables.stateFull, (_) => throw StateError('functions down'));
      firestoreState = testState(seq: 7, title: 'fs');
      expect((await ready()).title, 'fs');
    });

    test('reconnect (lost → good) resyncs', () async {
      await ready();
      seqOnServer = 4;
      room.setQuality(StudioLinkQuality.lost);
      room.setQuality(StudioLinkQuality.good);
      for (var i = 0; i < 5; i++) {
        await pump();
      }
      expect(calls.count(StudioCallables.stateFull), 2);
      expect(now().seq, 4);
    });

    test('states stream replays the current state and follows patches', () async {
      await ready();
      final seen = <int>[];
      final sub = container.read(studioStateProvider('s1').notifier).states.listen((s) => seen.add(s.seq));
      await pump();
      room.emit(title(2, 'x'));
      await pump();
      expect(seen, [1, 2]);
      await sub.cancel();
    });

    test('wires into the social and settings state hooks', () async {
      final wired = ProviderContainer(parent: container, overrides: [
        studioSocialRoomPortProvider.overrideWith((ref, id) => ref.watch(studioRoomProvider(id))),
        studioSocialStateSourceProvider
            .overrideWith((ref, id) => ref.watch(studioSessionProvider(id).notifier).states),
        studioSettingsStateSourceProvider
            .overrideWith((ref, id) => ref.watch(studioSessionProvider(id).notifier).states),
      ]);
      addTearDown(wired.dispose);
      expect(wired.read(studioSocialRoomPortProvider('s1')), same(room));
      final first = await wired.read(studioSettingsStateSourceProvider('s1')).first;
      expect(first.streamId, 's1');
      final social = await wired.read(studioSocialStateSourceProvider('s1'))!.first;
      expect(social.seq, first.seq);
    });
  });

  group('members / role providers', () {
    test('role from my members doc, members in join order', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('${StudioPaths.members('s1')}/me').set(
          const StageMember(uid: 'me', displayName: 'Me', role: StudioRole.guest, joinedAtMs: 20).toJson());
      await db.doc('${StudioPaths.members('s1')}/host').set(
          const StageMember(uid: 'host', displayName: 'H', role: StudioRole.host, joinedAtMs: 10).toJson());
      final c = ProviderContainer(overrides: [
        studioFirestoreProvider.overrideWithValue(db),
        studioMyUidProvider.overrideWithValue('me'),
      ]);
      addTearDown(c.dispose);

      final roles = <StudioRole>[];
      c.listen(studioMyRoleProvider('s1'), (_, v) => v.whenData(roles.add), fireImmediately: true);
      final mSub = c.listen(studioMembersProvider('s1'), (_, _) {});
      addTearDown(mSub.close);
      final members = await c.read(studioMembersProvider('s1').future);
      expect(members.map((m) => m.uid), ['host', 'me']);
      await pump();
      expect(roles.last, StudioRole.guest);

      await db.doc('${StudioPaths.members('s1')}/me').update({'role': 'coHost'});
      await pump();
      expect(roles.last, StudioRole.coHost);
    });

    test('signed out → viewer', () async {
      final c = ProviderContainer(overrides: [
        studioFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        studioMyUidProvider.overrideWithValue(null),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(studioMyRoleProvider('s1'), (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(studioMyRoleProvider('s1').future), StudioRole.viewer);
    });
  });

  test('clock provider calibrates through lsTime', () async {
    final calls = FakeCallPort().on(StudioCallables.time, (_) => {'serverMs': DateTime.now().millisecondsSinceEpoch});
    final c = ProviderContainer(overrides: [studioCallPortProvider.overrideWithValue(calls)]);
    addTearDown(c.dispose);
    final clock = c.read(studioClockProvider) as CallableStudioClock;
    await clock.calibrate();
    expect(calls.count(StudioCallables.time), 5);
    expect(clock.offsetMs.abs(), lessThan(1000));
    expect(clock, isA<StudioClockPort>());
  });
}
