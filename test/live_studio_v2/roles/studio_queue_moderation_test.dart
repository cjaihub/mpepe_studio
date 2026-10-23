import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/roles/roles.dart';

import 'fakes/fake_roles.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FakeCallPort calls;
  late ProviderContainer c;

  setUp(() {
    db = FakeFirebaseFirestore();
    calls = FakeCallPort();
    c = ProviderContainer(
        overrides: rolesOverrides(db: db, calls: calls, room: RecordingRoom(), rejoiner: FakeRejoiner(), uid: 'host'));
    addTearDown(c.dispose);
  });

  group('request queue', () {
    test('streams pending requests oldest first', () async {
      c.listen(studioPendingRequestsProvider(kStream), (_, _) {});
      await db.doc(requestPath('b')).set(requestDoc('b', JoinRequestStatus.pending, at: 20));
      await db.doc(requestPath('a')).set(requestDoc('a', JoinRequestStatus.pending, at: 10));
      await db.doc(requestPath('x')).set(requestDoc('x', JoinRequestStatus.declined, at: 5));
      await settle();
      final list = c.read(studioPendingRequestsProvider(kStream)).value!;
      expect(list.map((r) => r.uid), ['a', 'b']);
      expect(c.read(studioPendingRequestCountProvider(kStream)), 2);
    });

    test('approve calls lsRespondRequest and parses the result', () async {
      calls.on(StudioCallables.respondRequest, (_) => {
            'ok': true,
            'status': 'approved',
            'rejoin': true,
            'placement': {'kind': 'wall', 'index': 2},
          });
      c.listen(studioRequestQueueControllerProvider(kStream), (_, _) {});
      final ctl = c.read(studioRequestQueueControllerProvider(kStream).notifier);
      final r = await ctl.approve('a');
      expect(calls.calls.single.$2, {'streamId': kStream, 'uid': 'a', 'approve': true});
      expect(r!.status, JoinRequestStatus.approved);
      expect(r.rejoin, isTrue);
      expect(r.placement, StudioPlacement.wall);
      expect(r.wallIndex, 2);
      expect(ctl.visible(const [JoinRequest(uid: 'a', displayName: 'A'), JoinRequest(uid: 'b', displayName: 'B')])
          .map((e) => e.uid), ['b']);
    });

    test('decline sends approve=false; errors surface', () async {
      c.listen(studioRequestQueueControllerProvider(kStream), (_, _) {});
      final ctl = c.read(studioRequestQueueControllerProvider(kStream).notifier);
      await ctl.decline('a');
      expect(calls.calls.single.$2['approve'], false);
      calls.on(StudioCallables.respondRequest, (_) => throw Exception('x'));
      expect(await ctl.approve('b'), isNull);
      final v = c.read(studioRequestQueueControllerProvider(kStream));
      expect(v.error, isNotNull);
      expect(v.inFlight, isEmpty);
    });
  });

  group('moderation', () {
    StudioModerationController ctl() {
      c.listen(studioModerationControllerProvider(kStream), (_, _) {});
      return c.read(studioModerationControllerProvider(kStream).notifier);
    }

    for (final op in [
      StudioModerationOp.removeFromStage,
      StudioModerationOp.block,
      StudioModerationOp.promoteCoHost,
      StudioModerationOp.demoteCoHost,
    ]) {
      test('${op.wire} requires confirmation', () async {
        final m = ctl();
        final no = FakeConfirm(false);
        expect(await m.run(op, 'g', name: 'G', confirm: no.call), isFalse);
        expect(no.prompts, hasLength(1));
        expect(calls.count(StudioCallables.moderate), 0);
        final yes = FakeConfirm(true);
        expect(await m.run(op, 'g', name: 'G', confirm: yes.call), isTrue);
        expect(calls.calls.single.$2, {'streamId': kStream, 'uid': 'g', 'action': op.wire});
      });
    }

    test('mute runs without a dialog', () async {
      final confirm = FakeConfirm(false);
      expect(await ctl().mute('g', name: 'G', confirm: confirm.call), isTrue);
      expect(confirm.prompts, isEmpty);
      expect(calls.calls.single.$2['action'], 'mute');
    });

    test('end the live requires confirmation, then lsEnd', () async {
      final m = ctl();
      expect(await m.endLive(confirm: FakeConfirm(false).call), isFalse);
      expect(calls.count(StudioCallables.end), 0);
      expect(await m.endLive(confirm: FakeConfirm(true).call), isTrue);
      expect(calls.count(StudioCallables.end), 1);
    });

    test('server refusal surfaces an error', () async {
      calls.on(StudioCallables.moderate, (_) => throw Exception('denied'));
      final m = ctl();
      expect(await m.block('g', name: 'G', confirm: FakeConfirm(true).call), isFalse);
      expect(c.read(studioModerationControllerProvider(kStream)).error, isNotNull);
    });
  });

  group('moderation policy (§6 mirror)', () {
    List<StudioModerationOp> ops(StudioRole actor, StudioRole target, {bool onStage = true, String t = 't'}) =>
        allowedModerationOps(actorUid: 'a', actorRole: actor, targetUid: t, targetRole: target, targetOnStage: onStage);

    test('host on guest / co-host', () {
      expect(ops(StudioRole.host, StudioRole.guest), [
        StudioModerationOp.mute,
        StudioModerationOp.removeFromStage,
        StudioModerationOp.promoteCoHost,
        StudioModerationOp.block,
      ]);
      expect(ops(StudioRole.host, StudioRole.coHost), contains(StudioModerationOp.demoteCoHost));
      expect(ops(StudioRole.host, StudioRole.coHost), contains(StudioModerationOp.block));
    });

    test('co-host: never the host, never blocks co-hosts, no promotions', () {
      expect(ops(StudioRole.coHost, StudioRole.host), isEmpty);
      expect(ops(StudioRole.coHost, StudioRole.coHost), isNot(contains(StudioModerationOp.block)));
      expect(ops(StudioRole.coHost, StudioRole.guest), isNot(contains(StudioModerationOp.promoteCoHost)));
      expect(ops(StudioRole.coHost, StudioRole.viewer, onStage: false), [StudioModerationOp.block]);
    });

    test('guests, viewers and self get nothing', () {
      expect(ops(StudioRole.guest, StudioRole.guest), isEmpty);
      expect(ops(StudioRole.viewer, StudioRole.guest), isEmpty);
      expect(ops(StudioRole.host, StudioRole.guest, t: 'a'), isEmpty);
    });

    test('only mute skips the dialog', () {
      for (final op in StudioModerationOp.values) {
        expect(moderationNeedsConfirm(op), op != StudioModerationOp.mute);
      }
    });
  });
}
