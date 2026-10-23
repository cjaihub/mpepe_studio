import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/layout/layout.dart';

import 'fakes/fake_ports.dart';

StageMember co(String uid, int joined) =>
    StageMember(uid: uid, displayName: uid, role: StudioRole.coHost, joinedAtMs: joined);

StudioState state({SpeakerMode mode = SpeakerMode.autoActiveSpeaker, StageLayout? stage}) => StudioState(
      streamId: 's1',
      hostId: 'host',
      status: StudioStatus.live,
      settings: StudioSettings(speakerMode: mode),
      stage: stage ?? stage6(),
    );

void main() {
  group('electLayoutLeader', () {
    final members = [co('c2', 200), co('c1', 100), co('c0', 100), const StageMember(uid: 'g1', displayName: 'g1', role: StudioRole.guest)];

    test('host connected → host', () {
      expect(
          electLayoutLeader(hostId: 'host', members: members, connected: {'host', 'c1'}, hostAbsentSinceMs: null, nowMs: 0),
          'host');
    });

    test('host gone < 10 s → nobody; ≥ 10 s → longest-serving connected coHost', () {
      String? at(int now, Set<String> c) =>
          electLayoutLeader(hostId: 'host', members: members, connected: c, hostAbsentSinceMs: 0, nowMs: now);
      expect(at(9999, {'c0', 'c1', 'c2'}), isNull);
      expect(at(10000, {'c0', 'c1', 'c2'}), 'c0'); // tie on joinedAt → uid
      expect(at(10000, {'c1', 'c2'}), 'c1');
      expect(at(10000, {'c2', 'g1'}), 'c2');
      expect(at(10000, {'g1'}), isNull); // guests never lead
    });
  });

  group('LayoutLeader', () {
    late FakeClock clock;
    late FakeRoom room;
    late FakeCallPort port;
    late StreamController<void> ticks;

    LayoutLeader make(String self) => LayoutLeader(
          selfUid: self,
          room: room,
          commands: LayoutCommands(port, 's1'),
          nowMs: clock.now,
          ticks: ticks.stream,
        );

    setUp(() {
      clock = FakeClock();
      room = FakeRoom();
      port = FakeCallPort();
      ticks = StreamController<void>.broadcast(sync: true);
    });

    Future<void> tickFor(int ms) async {
      for (var t = 0; t < ms; t += 50) {
        clock.advance(50);
        ticks.add(null);
      }
      await Future<void>.delayed(Duration.zero);
    }

    test('host leader promotes after 1.5 s via lsSetLayout autoPromote', () async {
      final l = make('host');
      l.updateState(state());
      l.updatePresence({'host', 'g1'});
      await tickFor(4000); // initial hold
      room.speak(['g2']);
      await tickFor(1400);
      expect(port.calls, isEmpty);
      await tickFor(200);
      expect(port.calls.single.$1, StudioCallables.setLayout);
      expect(port.calls.single.$2, {'streamId': 's1', 'op': 'autoPromote', 'uid': 'g2'});
      await l.dispose();
    });

    test('non-leaders and non-auto modes never call', () async {
      final guest = make('g1');
      guest.updateState(state());
      guest.updatePresence({'host', 'g1'});
      final hostPinned = make('host');
      hostPinned.updateState(state(mode: SpeakerMode.hostPinned));
      hostPinned.updatePresence({'host'});
      room.speak(['g2']);
      await tickFor(10000);
      expect(port.calls, isEmpty);
      await guest.dispose();
      await hostPinned.dispose();
    });

    test('coHost takes over 10 s after the host leaves', () async {
      final l = make('c1');
      l.updateState(state());
      l.updateMembers({'c1': co('c1', 5)});
      l.updatePresence({'host', 'c1'});
      expect(l.isLeader, isFalse);
      l.updatePresence({'c1'});
      room.speak(['g3']);
      await tickFor(9900);
      expect(l.isLeader, isFalse);
      expect(port.calls, isEmpty);
      await tickFor(200);
      expect(l.isLeader, isTrue);
      expect(port.calls.single.$2['uid'], 'g3');
      // Host returns → coHost steps down.
      l.updatePresence({'c1', 'host'});
      expect(l.isLeader, isFalse);
      await l.dispose();
    });

    test('a coHost without presence info never leads', () async {
      final l = make('c1');
      l.updateState(state());
      l.updateMembers({'c1': co('c1', 5)});
      room.speak(['g3']);
      await tickFor(20000);
      expect(port.calls, isEmpty);
      await l.dispose();
    });

    test('pin blocks; one call per promotion; hold respected', () async {
      final l = make('host');
      l.updateState(state(stage: stage6(pinned: 'host')));
      l.updatePresence({'host'});
      room.speak(['g1', 'g2']);
      await tickFor(8000);
      expect(port.calls, isEmpty);
      l.updateState(state()); // unpinned
      await tickFor(100);
      expect(l.sent, ['g1']);
      await tickFor(3000);
      expect(l.sent, ['g1']); // hold
      await l.dispose();
    });
  });
}
