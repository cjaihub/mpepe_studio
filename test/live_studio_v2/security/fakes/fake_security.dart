// Test-only fakes for the security workstream.

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/roles/studio_roles_api.dart';
import 'package:oneova/backend/live_studio/security/studio_security_api.dart';
import 'package:oneova/backend/live_studio/security/studio_security_models.dart';

import '../../session/fakes/fake_studio.dart';

export '../../session/fakes/fake_studio.dart';

const kStream = 's1';

class FakeSecuritySource implements StudioSecuritySource {
  FakeSecuritySource({this.incidents = const [], this.advisories = const []});
  List<StudioSecurityIncident> incidents;
  List<StudioAdvisory> advisories;

  @override
  Stream<List<StudioSecurityIncident>> watchIncidents(String streamId, {int limit = 50}) => Stream.value(incidents);

  @override
  Stream<List<StudioAdvisory>> watchAdvisories(String streamId, {int limit = 10}) => Stream.value(advisories);
}

class FakeConfirm {
  FakeConfirm(this.answer);
  bool answer;
  final List<StudioConfirmPrompt> prompts = [];

  Future<bool> call(StudioConfirmPrompt p) async {
    prompts.add(p);
    return answer;
  }
}

List<Override> securityOverrides({
  required FakeSecuritySource source,
  required FakeCallPort calls,
  required StreamController<StudioSecurityPacket> packets,
}) =>
    [
      studioSecuritySourceProvider.overrideWithValue(source),
      studioCallPortProvider.overrideWithValue(calls),
      studioSecurityPacketsProvider.overrideWith((ref, id) => packets.stream),
    ];

StudioAdvisory advisory({
  String id = 'adv_1',
  int atMs = 1000,
  StudioSeverity severity = StudioSeverity.warn,
  String assessment = 'One viewer is flooding the chat.',
  List<Map<String, dynamic>> actions = const [
    {'type': 'mute_user', 'targetUid': 'u1', 'targetName': 'Ana'},
    {'type': 'slow_mode'},
  ],
  bool ai = true,
}) =>
    StudioAdvisory.fromJson({
      'id': id,
      'atMs': atMs,
      'severity': severity.wire,
      'assessment': assessment,
      'actions': actions,
      'source': ai ? 'ai' : 'rules',
    });

StudioSecurityIncident incident(String id, StudioSeverity s, {int atMs = 1000, String reason = 'Something happened'}) =>
    StudioSecurityIncident.fromJson(id, {'detector': 'comment_flood_user', 'severity': s.wire, 'reason': reason, 'count': 30, 'atMs': atMs, 'uid': 'u1'});
