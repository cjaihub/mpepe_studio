import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/roles/roles.dart';

import 'fakes/fake_roles.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FakeCallPort calls;
  late RecordingRoom room;
  late FakeRejoiner rejoiner;
  late ProviderContainer c;

  ProviderContainer make({String? uid = 'me'}) {
    final container = ProviderContainer(
        overrides: rolesOverrides(db: db, calls: calls, room: room, rejoiner: rejoiner, uid: uid));
    container.listen(studioJoinControllerProvider(kStream), (_, _) {});
    addTearDown(container.dispose);
    return container;
  }

  StudioJoinView view() => c.read(studioJoinControllerProvider(kStream));
  StudioJoinController ctl() => c.read(studioJoinControllerProvider(kStream).notifier);

  setUp(() {
    db = FakeFirebaseFirestore();
    calls = FakeCallPort();
    room = RecordingRoom();
    rejoiner = FakeRejoiner(publish: true);
  });

  test('idle → request → pending (lsRequestJoin)', () async {
    c = make();
    await settle();
    expect(view().phase, StudioJoinPhase.idle);
    await ctl().request();
    expect(calls.count(StudioCallables.requestJoin), 1);
    expect(calls.calls.single.$2, {'streamId': kStream});
    expect(view().phase, StudioJoinPhase.pending);
    expect(view().busy, isFalse);
  });

  test('request failure restores idle with an error', () async {
    calls.on(StudioCallables.requestJoin, (_) => throw Exception('boom'));
    c = make();
    await settle();
    await ctl().request();
    expect(view().phase, StudioJoinPhase.idle);
    expect(view().error, isNotNull);
  });

  test('my request doc drives pending / declined / idle', () async {
    c = make();
    await db.doc(requestPath('me')).set(requestDoc('me', JoinRequestStatus.pending));
    await settle();
    expect(view().phase, StudioJoinPhase.pending);
    await db.doc(requestPath('me')).set(requestDoc('me', JoinRequestStatus.declined));
    await settle();
    expect(view().phase, StudioJoinPhase.declined);
    // Declined users may ask again.
    await ctl().request();
    expect(calls.count(StudioCallables.requestJoin), 1);
    await db.doc(requestPath('me')).delete();
    await settle();
    expect(view().phase, StudioJoinPhase.idle);
  });

  test('request.update event approves immediately and awaits the device check', () async {
    c = make();
    await db.doc(requestPath('me')).set(requestDoc('me', JoinRequestStatus.pending));
    await settle();
    room.emit(const JoinRequestEvent(JoinRequest(uid: 'me', displayName: 'Me', status: JoinRequestStatus.approved)));
    expect(view().phase, StudioJoinPhase.approved);
    expect(view().awaitingDeviceCheck, isTrue);
    expect(rejoiner.rejoins, 0, reason: 'in-place permission update: no rejoin');
  });

  test('events for other users are ignored', () async {
    c = make();
    await settle();
    room.emit(const JoinRequestEvent(JoinRequest(uid: 'other', displayName: 'O', status: JoinRequestStatus.approved)));
    expect(view().phase, StudioJoinPhase.idle);
  });

  test('approved with rejoin=true rejoins the room exactly once', () async {
    c = make();
    await db.doc(requestPath('me')).set(requestDoc('me', JoinRequestStatus.approved, rejoin: true, at: 7));
    await settle();
    expect(view().phase, StudioJoinPhase.approved);
    expect(rejoiner.rejoins, 1);
    await db.doc(requestPath('me')).update({'displayName': 'x'});
    await settle();
    expect(rejoiner.rejoins, 1);
  });

  test('members doc role: guest = approved, host = not applicable', () async {
    c = make();
    await db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest', 'displayName': 'Me'});
    await settle();
    expect(view().phase, StudioJoinPhase.approved);
    expect(view().role, StudioRole.guest);
    await db.doc(memberPath('me')).set({'uid': 'me', 'role': 'host', 'displayName': 'Me'});
    await settle();
    expect(view().phase, StudioJoinPhase.host);
  });

  test('removed from stage (role → viewer, doc deleted) returns to idle', () async {
    c = make();
    await db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest'});
    await db.doc(requestPath('me')).set(requestDoc('me', JoinRequestStatus.approved));
    await settle();
    expect(view().phase, StudioJoinPhase.approved);
    room.emit(const JoinRequestEvent(JoinRequest(uid: 'me', displayName: '', status: JoinRequestStatus.cancelled)));
    expect(view().phase, StudioJoinPhase.idle);
    await db.doc(memberPath('me')).set({'uid': 'me', 'role': 'viewer'});
    await db.doc(requestPath('me')).delete();
    await settle();
    expect(view().phase, StudioJoinPhase.idle);
  });

  test('cancel → lsCancelRequest → idle', () async {
    c = make();
    await db.doc(requestPath('me')).set(requestDoc('me', JoinRequestStatus.pending));
    await settle();
    await ctl().cancel();
    expect(calls.count(StudioCallables.cancelRequest), 1);
    expect(view().phase, StudioJoinPhase.idle);
  });

  test('goOnStage publishes cam + mic and syncs own media', () async {
    c = make();
    await db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest'});
    await settle();
    await ctl().goOnStage(micOn: true, camOn: false);
    expect(room.log, ['cam:false', 'mic:true']);
    expect(rejoiner.rejoins, 0);
    expect(view().publishing, isTrue);
    expect(view().awaitingDeviceCheck, isFalse);
    await settle();
    final own = calls.calls.where((x) => x.$1 == StudioCallables.setOwnMedia).single.$2;
    expect(own, {'streamId': kStream, 'micOn': true, 'camOn': false});
  });

  test('goOnStage rejoins first when the room has no publish permission', () async {
    rejoiner.publish = false;
    c = make();
    await db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest'});
    await settle();
    await ctl().goOnStage(micOn: true, camOn: true);
    expect(rejoiner.rejoins, 1);
    expect(room.log, ['cam:true', 'mic:true']);
  });

  test('goOnStage does nothing unless approved', () async {
    c = make();
    await settle();
    await ctl().goOnStage(micOn: true, camOn: true);
    expect(room.log, isEmpty);
  });

  test('leave stage requires confirmation', () async {
    c = make();
    await db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest'});
    await settle();
    final no = FakeConfirm(false);
    expect(await ctl().leaveStage(no.call), isFalse);
    expect(no.prompts, hasLength(1));
    expect(calls.count(StudioCallables.leaveStage), 0);
    expect(view().phase, StudioJoinPhase.approved);

    final yes = FakeConfirm(true);
    expect(await ctl().leaveStage(yes.call), isTrue);
    expect(calls.count(StudioCallables.leaveStage), 1);
    expect(room.log, ['cam:false', 'mic:false']);
    expect(view().phase, StudioJoinPhase.idle);
  });
}
