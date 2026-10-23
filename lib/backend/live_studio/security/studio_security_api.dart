// LIVE STUDIO v2 — security reads and action calls (security workstream).
//
// Reads: incidents and advisories from Firestore (function-written; rules let
// only host / co-hosts / moderators read them). Live advisories also arrive
// on the `security` data topic (LiveKitStudioRoom.securityPackets).
// Actions: the allow-listed advisory actions, mapped to existing callables
// (lsModerate, lsMuteChat, lsEnd) and two requested ones (lsSetChatMode,
// lsSetJoinRequests).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../media/livekit_studio_room.dart';
import '../media/studio_media_api.dart';
import '../roles/studio_roles_api.dart';
import '../session/studio_session_controller.dart';
import 'studio_security_models.dart';

abstract class StudioSecuritySource {
  /// Newest first.
  Stream<List<StudioSecurityIncident>> watchIncidents(String streamId, {int limit = 50});

  /// Newest first.
  Stream<List<StudioAdvisory>> watchAdvisories(String streamId, {int limit = 10});
}

class FirestoreStudioSecuritySource implements StudioSecuritySource {
  FirestoreStudioSecuritySource(this._db);
  final FirebaseFirestore _db;

  @override
  Stream<List<StudioSecurityIncident>> watchIncidents(String streamId, {int limit = 50}) => _db
      .collection(StudioSecurityWire.incidents(streamId))
      .orderBy('atMs', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => [for (final d in q.docs) StudioSecurityIncident.fromJson(d.id, d.data())]);

  @override
  Stream<List<StudioAdvisory>> watchAdvisories(String streamId, {int limit = 10}) => _db
      .collection(StudioSecurityWire.advisories(streamId))
      .orderBy('atMs', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => [for (final d in q.docs) StudioAdvisory.fromJson(d.data(), id: d.id)]);
}

final studioSecuritySourceProvider =
    Provider<StudioSecuritySource>((ref) => FirestoreStudioSecuritySource(ref.watch(studioFirestoreProvider)));

final studioSecurityIncidentsProvider = StreamProvider.autoDispose.family<List<StudioSecurityIncident>, String>(
    (ref, streamId) => ref.watch(studioSecuritySourceProvider).watchIncidents(streamId));

final studioSecurityAdvisoriesProvider = StreamProvider.autoDispose.family<List<StudioAdvisory>, String>(
    (ref, streamId) => ref.watch(studioSecuritySourceProvider).watchAdvisories(streamId));

/// `security` topic packets of the live room (empty for non-LiveKit ports).
final studioSecurityPacketsProvider = Provider.autoDispose.family<Stream<StudioSecurityPacket>, String>((ref, streamId) {
  final room = ref.watch(studioRoomProvider(streamId));
  return room is LiveKitStudioRoom ? room.securityPackets : const Stream<StudioSecurityPacket>.empty();
});

/// Chat mute length used by the "Mute chat" advisory action.
const int kAdvisoryMuteMinutes = 10;

/// Slow-mode interval used by the "Slow mode" advisory action.
const int kAdvisorySlowModeSeconds = 10;

class StudioSecurityApi {
  const StudioSecurityApi(this._call, this._roles, this._media);
  final StudioCallPort _call;
  final StudioRolesApi _roles;
  final StudioMediaApi _media;

  /// Runs one allow-listed action. Throws on callable failure.
  Future<void> run(String streamId, StudioAdvisoryAction a) async {
    final uid = a.targetUid ?? '';
    switch (a.type) {
      case StudioAdvisoryActionType.muteUser:
        await _call.call(StudioCallables.muteChat, {'streamId': streamId, 'uid': uid, 'minutes': kAdvisoryMuteMinutes});
      case StudioAdvisoryActionType.removeFromStage:
        await _roles.moderate(streamId, uid, StudioModerationOp.removeFromStage);
      case StudioAdvisoryActionType.blockUser:
        await _roles.moderate(streamId, uid, StudioModerationOp.block);
      case StudioAdvisoryActionType.slowMode:
        await _call.call(StudioSecurityWire.setChatMode,
            {'streamId': streamId, 'mode': 'slow', 'slowSeconds': kAdvisorySlowModeSeconds});
      case StudioAdvisoryActionType.followersOnly:
        await _call.call(StudioSecurityWire.setChatMode, {'streamId': streamId, 'mode': 'followers'});
      case StudioAdvisoryActionType.pauseJoinRequests:
        await _call.call(StudioSecurityWire.setJoinRequests, {'streamId': streamId, 'open': false});
      case StudioAdvisoryActionType.endLive:
        await _media.end(streamId);
    }
  }
}

final studioSecurityApiProvider = Provider<StudioSecurityApi>((ref) => StudioSecurityApi(
      ref.watch(studioCallPortProvider),
      ref.watch(studioRolesApiProvider),
      ref.watch(studioMediaApiProvider),
    ));

/// The confirmation shown before [a] runs. Every advisory action is confirmed.
StudioConfirmPrompt advisoryPrompt(StudioAdvisoryAction a) {
  final who = a.targetName.isEmpty ? 'this person' : a.targetName;
  return switch (a.type) {
    StudioAdvisoryActionType.muteUser => StudioConfirmPrompt(
        title: 'Mute $who in chat?',
        message: 'They cannot comment for $kAdvisoryMuteMinutes minutes.',
        confirmLabel: 'Mute',
      ),
    StudioAdvisoryActionType.removeFromStage => StudioConfirmPrompt(
        title: 'Remove $who from the stage?',
        message: 'Their camera and mic stop. They stay in the live as a viewer.',
        confirmLabel: 'Remove',
      ),
    StudioAdvisoryActionType.blockUser => StudioConfirmPrompt(
        title: 'Block $who?',
        message: 'They leave the live and cannot come back to it.',
        confirmLabel: 'Block',
      ),
    StudioAdvisoryActionType.slowMode => const StudioConfirmPrompt(
        title: 'Turn on slow mode?',
        message: 'Everyone can comment once every $kAdvisorySlowModeSeconds seconds.',
        confirmLabel: 'Turn on',
        destructive: false,
      ),
    StudioAdvisoryActionType.followersOnly => const StudioConfirmPrompt(
        title: 'Followers-only chat?',
        message: 'Only people who follow you can comment.',
        confirmLabel: 'Turn on',
        destructive: false,
      ),
    StudioAdvisoryActionType.pauseJoinRequests => const StudioConfirmPrompt(
        title: 'Pause join requests?',
        message: 'No one can ask to join the stage until you open requests again.',
        confirmLabel: 'Pause',
      ),
    StudioAdvisoryActionType.endLive => const StudioConfirmPrompt(
        title: 'End the live?',
        message: 'Everyone leaves the studio and the live stops for all viewers.',
        confirmLabel: 'End live',
      ),
  };
}
