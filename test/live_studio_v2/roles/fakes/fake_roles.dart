// Test-only fakes for the roles / join workstream.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/roles/studio_roles_api.dart';
import 'package:oneova/backend/live_studio/session/studio_session_controller.dart';

import '../../session/fakes/fake_studio.dart';

export '../../session/fakes/fake_studio.dart';

/// Room fake that records local publish calls.
class RecordingRoom extends FakeRoom {
  final List<String> log = [];

  @override
  Future<void> setMicEnabled(bool on) async => log.add('mic:$on');
  @override
  Future<void> setCameraEnabled(bool on) async => log.add('cam:$on');
}

class FakeRejoiner implements StudioRoomRejoiner {
  FakeRejoiner({this.publish});

  /// What [canPublish] reports (null = unknown port).
  bool? publish;
  int rejoins = 0;

  @override
  bool? canPublish(StudioRoomPort room) => publish;

  @override
  Future<bool> rejoin(StudioRoomPort room) async {
    rejoins++;
    publish = true;
    return true;
  }
}

/// Records every confirmation and answers with [answer].
class FakeConfirm {
  FakeConfirm(this.answer);
  bool answer;
  final List<StudioConfirmPrompt> prompts = [];

  Future<bool> call(StudioConfirmPrompt p) async {
    prompts.add(p);
    return answer;
  }
}

const kStream = 's1';

String requestPath(String uid) => '${StudioPaths.requests(kStream)}/$uid';
String memberPath(String uid) => '${StudioPaths.members(kStream)}/$uid';

Map<String, dynamic> requestDoc(String uid, JoinRequestStatus status, {bool? rejoin, int at = 1}) => {
      'uid': uid,
      'displayName': 'User $uid',
      'avatarUrl': '',
      'status': status.wire,
      'requestedAtMs': at,
      'rejoin': ?rejoin,
    };

List<Override> rolesOverrides({
  required FakeFirebaseFirestore db,
  required FakeCallPort calls,
  required StudioRoomPort room,
  required StudioRoomRejoiner rejoiner,
  String? uid = 'me',
}) =>
    [
      studioFirestoreProvider.overrideWithValue(db),
      studioMyUidProvider.overrideWithValue(uid),
      studioCallPortProvider.overrideWithValue(calls),
      studioRolesRoomProvider.overrideWith((ref, id) => room),
      studioRoomRejoinerProvider.overrideWithValue(rejoiner),
    ];

/// Lets Firestore fake snapshots and microtasks run.
Future<void> settle([int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
