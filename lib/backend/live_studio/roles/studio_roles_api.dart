// LIVE STUDIO v2 — roles, join requests & moderation: callables, data sources
// and shared helpers (workstream #4, ARCHITECTURE §5–§6).
//
// Callables: lsRequestJoin · lsCancelRequest · lsRespondRequest · lsModerate ·
// lsLeaveStage (functions/src/liveStudio/roles.ts).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../media/livekit_studio_room.dart';
import '../session/studio_session_controller.dart';

/// `lsModerate` actions. Superset of the contract's [ModerationAction]
/// (adds the host-only co-host promotions, pending a contract change).
enum StudioModerationOp {
  mute('mute'),
  removeFromStage('removeFromStage'),
  block('block'),
  promoteCoHost('promoteCoHost'),
  demoteCoHost('demoteCoHost');

  final String wire;
  const StudioModerationOp(this.wire);

  static StudioModerationOp fromContract(ModerationAction a) => switch (a) {
        ModerationAction.mute => mute,
        ModerationAction.removeFromStage => removeFromStage,
        ModerationAction.block => block,
      };
}

/// Where an approved guest landed.
enum StudioPlacement { wall, overflow, already, unknown }

@immutable
class StudioRespondResult {
  const StudioRespondResult({required this.status, this.rejoin = false, this.placement = StudioPlacement.unknown, this.wallIndex});
  final JoinRequestStatus status;

  /// True when the guest was not in the LiveKit room and must reconnect.
  final bool rejoin;
  final StudioPlacement placement;
  final int? wallIndex;

  factory StudioRespondResult.fromJson(Map<String, dynamic> j) {
    final p = j['placement'] is Map ? Map<String, dynamic>.from(j['placement'] as Map) : const <String, dynamic>{};
    return StudioRespondResult(
      status: JoinRequestStatus.fromWire(j['status']),
      rejoin: j['rejoin'] == true,
      placement: switch (p['kind']) {
        'wall' => StudioPlacement.wall,
        'overflow' => StudioPlacement.overflow,
        'already' => StudioPlacement.already,
        _ => StudioPlacement.unknown,
      },
      wallIndex: p['index'] is num ? (p['index'] as num).toInt() : null,
    );
  }
}

/// Typed wrappers over the roles callables.
class StudioRolesApi {
  const StudioRolesApi(this._call);
  final StudioCallPort _call;

  Future<void> requestJoin(String streamId) =>
      _call.call(StudioCallables.requestJoin, {'streamId': streamId});

  Future<void> cancelRequest(String streamId) =>
      _call.call(StudioCallables.cancelRequest, {'streamId': streamId});

  Future<StudioRespondResult> respond(String streamId, String uid, {required bool approve}) async =>
      StudioRespondResult.fromJson(await _call.call(
          StudioCallables.respondRequest, {'streamId': streamId, 'uid': uid, 'approve': approve}));

  Future<void> moderate(String streamId, String uid, StudioModerationOp op) =>
      _call.call(StudioCallables.moderate, {'streamId': streamId, 'uid': uid, 'action': op.wire});

  Future<void> leaveStage(String streamId) =>
      _call.call(StudioCallables.leaveStage, {'streamId': streamId});
}

final studioRolesApiProvider = Provider<StudioRolesApi>((ref) => StudioRolesApi(ref.watch(studioCallPortProvider)));

/// A join request doc as stored (`studio_requests/{uid}`), with the
/// server-only `rejoin` flag the contract's [JoinRequest] does not carry.
@immutable
class StudioRequestDoc {
  const StudioRequestDoc(this.request, {this.rejoin = false});
  final JoinRequest request;
  final bool rejoin;

  factory StudioRequestDoc.fromJson(String id, Map<String, dynamic> j) =>
      StudioRequestDoc(JoinRequest.fromJson({'uid': id, ...j}), rejoin: j['rejoin'] == true);
}

/// Firestore reads for requests (function-written, client read-only).
abstract class StudioRequestsSource {
  /// My own request doc (null when none).
  Stream<StudioRequestDoc?> watchMine(String streamId, String uid);

  /// Pending requests, oldest first (managers only; rules deny others).
  Stream<List<JoinRequest>> watchPending(String streamId);
}

class FirestoreStudioRequestsSource implements StudioRequestsSource {
  FirestoreStudioRequestsSource(this._db);
  final FirebaseFirestore _db;

  @override
  Stream<StudioRequestDoc?> watchMine(String streamId, String uid) =>
      _db.doc('${StudioPaths.requests(streamId)}/$uid').snapshots().map((d) {
        final data = d.data();
        return data == null ? null : StudioRequestDoc.fromJson(d.id, data);
      });

  @override
  Stream<List<JoinRequest>> watchPending(String streamId) => _db
      .collection(StudioPaths.requests(streamId))
      .where('status', isEqualTo: JoinRequestStatus.pending.wire)
      .snapshots()
      .map((q) {
        final list = [for (final d in q.docs) JoinRequest.fromJson({'uid': d.id, ...d.data()})];
        list.sort((a, b) => a.requestedAtMs.compareTo(b.requestedAtMs));
        return list;
      });
}

final studioRequestsSourceProvider =
    Provider<StudioRequestsSource>((ref) => FirestoreStudioRequestsSource(ref.watch(studioFirestoreProvider)));

/// The room port the roles controllers listen to (override in tests).
final studioRolesRoomProvider =
    Provider.autoDispose.family<StudioRoomPort, String>((ref, streamId) => ref.watch(studioRoomProvider(streamId)));

/// Reconnect hook for a role change. Only [LiveKitStudioRoom] can rejoin;
/// other ports (fakes) report false.
abstract class StudioRoomRejoiner {
  /// Whether the port already has publish permission (null = unknown).
  bool? canPublish(StudioRoomPort room);

  /// Reconnects with a fresh token. Returns false when the port cannot.
  Future<bool> rejoin(StudioRoomPort room);
}

class LiveKitStudioRoomRejoiner implements StudioRoomRejoiner {
  const LiveKitStudioRoomRejoiner();

  @override
  bool? canPublish(StudioRoomPort room) => room is LiveKitStudioRoom ? room.canPublish : null;

  @override
  Future<bool> rejoin(StudioRoomPort room) async {
    if (room is! LiveKitStudioRoom) return false;
    await room.rejoin();
    return true;
  }
}

final studioRoomRejoinerProvider = Provider<StudioRoomRejoiner>((ref) => const LiveKitStudioRoomRejoiner());

/// A confirmation the UI must show before a destructive action. The
/// controllers call [StudioConfirm] and only act on `true`.
@immutable
class StudioConfirmPrompt {
  const StudioConfirmPrompt({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = true,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
}

typedef StudioConfirm = Future<bool> Function(StudioConfirmPrompt prompt);

/// Human-readable message for a failed callable.
String studioErrorMessage(Object e) {
  if (e is FirebaseFunctionsException) {
    final m = e.message;
    if (m != null && m.isNotEmpty) return m;
    if (e.code == 'resource-exhausted') return 'Slow down a little.';
  }
  return 'Something went wrong. Try again.';
}
