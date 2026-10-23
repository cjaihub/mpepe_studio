// LIVE STUDIO v2 — viewer side of "Request to join" (workstream #4).
//
// Phases: idle → pending → approved (on stage) / declined. Sources, merged:
// - my role (members doc): guest/coHost = approved, host = not applicable;
// - my `studio_requests/{uid}` doc (status + server `rejoin` flag);
// - `request.new/update` events on the room port (fast path).
// On approval with `rejoin`, the LiveKit room reconnects with a fresh token
// (publish grants). [goOnStage] starts publishing after the device check.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../media/studio_media_api.dart';
import '../session/studio_session_controller.dart';
import 'studio_roles_api.dart';

enum StudioJoinPhase {
  /// The host: the join flow does not apply.
  host,
  idle,
  pending,

  /// Approved / on stage (guest or co-host).
  approved,
  declined,
}

@immutable
class StudioJoinView {
  const StudioJoinView({
    this.phase = StudioJoinPhase.idle,
    this.role = StudioRole.viewer,
    this.publishing = false,
    this.busy = false,
    this.error,
  });

  final StudioJoinPhase phase;
  final StudioRole role;

  /// True once this client went on stage (camera/mic requested) after approval.
  final bool publishing;
  final bool busy;
  final String? error;

  bool get onStage => phase == StudioJoinPhase.approved;

  /// Approved but the guest has not confirmed the device check yet.
  bool get awaitingDeviceCheck => onStage && !publishing && role != StudioRole.coHost;

  StudioJoinView copyWith({
    StudioJoinPhase? phase,
    StudioRole? role,
    bool? publishing,
    bool? busy,
    String? error,
    bool clearError = false,
  }) =>
      StudioJoinView(
        phase: phase ?? this.phase,
        role: role ?? this.role,
        publishing: publishing ?? this.publishing,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

final studioJoinControllerProvider =
    NotifierProvider.autoDispose.family<StudioJoinController, StudioJoinView, String>(StudioJoinController.new);

class StudioJoinController extends Notifier<StudioJoinView> {
  StudioJoinController(this.streamId);
  final String streamId;

  StreamSubscription<StudioEvent>? _eventsSub;
  StreamSubscription<StudioRequestDoc?>? _docSub;
  StudioRequestDoc? _doc;
  StudioRole _role = StudioRole.viewer;
  int? _rejoinedFor;
  Future<void>? _rejoining;

  StudioRolesApi get _api => ref.read(studioRolesApiProvider);

  @override
  StudioJoinView build() {
    final uid = ref.watch(studioMyUidProvider);
    final room = ref.watch(studioRolesRoomProvider(streamId));
    _eventsSub = room.events.listen((e) {
      if (e is JoinRequestEvent && e.request.uid == uid) _onEvent(e.request);
    });
    if (uid != null && uid.isNotEmpty) {
      _docSub = ref.read(studioRequestsSourceProvider).watchMine(streamId, uid).listen((d) {
        _doc = d;
        _recompute();
        if (d != null && d.rejoin && d.request.status == JoinRequestStatus.approved) _maybeRejoin(d.request);
      }, onError: (_) {});
    }
    ref.listen<AsyncValue<StudioRole>>(studioMyRoleProvider(streamId), (_, next) {
      final r = next.value;
      if (r == null) return;
      _role = r;
      _recompute();
    }, fireImmediately: true);
    ref.onDispose(() {
      unawaited(_eventsSub?.cancel());
      unawaited(_docSub?.cancel());
    });
    return const StudioJoinView();
  }

  StudioJoinPhase _phaseFor(StudioRole role, JoinRequestStatus? status) {
    if (role == StudioRole.host) return StudioJoinPhase.host;
    if (role == StudioRole.guest || role == StudioRole.coHost) return StudioJoinPhase.approved;
    return switch (status) {
      JoinRequestStatus.pending => StudioJoinPhase.pending,
      JoinRequestStatus.approved => StudioJoinPhase.approved,
      JoinRequestStatus.declined => StudioJoinPhase.declined,
      JoinRequestStatus.cancelled || null => StudioJoinPhase.idle,
    };
  }

  void _recompute() {
    if (!ref.mounted) return;
    final phase = _phaseFor(_role, _doc?.request.status);
    state = state.copyWith(
      phase: phase,
      role: _role,
      publishing: phase == StudioJoinPhase.approved ? state.publishing || _role == StudioRole.coHost : false,
    );
  }

  void _onEvent(JoinRequest r) {
    if (!ref.mounted) return;
    // A server `cancelled` after approval means "taken off stage".
    final doc = StudioRequestDoc(r, rejoin: _doc?.rejoin ?? false);
    _doc = r.status == JoinRequestStatus.cancelled ? null : doc;
    if (r.status == JoinRequestStatus.cancelled && _role.canPublish && _role != StudioRole.host) {
      _role = StudioRole.viewer; // the members doc follows
    }
    _recompute();
  }

  void _maybeRejoin(JoinRequest r) {
    if (_rejoinedFor == r.requestedAtMs) return;
    _rejoinedFor = r.requestedAtMs;
    _rejoining = _rejoin();
  }

  Future<void> _rejoin() async {
    try {
      await ref.read(studioRoomRejoinerProvider).rejoin(ref.read(studioRolesRoomProvider(streamId)));
    } catch (_) {}
  }

  /// Asks to join the stage.
  Future<void> request() async {
    if (state.busy || (state.phase != StudioJoinPhase.idle && state.phase != StudioJoinPhase.declined)) return;
    final before = state;
    state = state.copyWith(busy: true, phase: StudioJoinPhase.pending, clearError: true);
    try {
      await _api.requestJoin(streamId);
      if (ref.mounted) state = state.copyWith(busy: false);
    } catch (e) {
      if (ref.mounted) state = before.copyWith(busy: false, error: studioErrorMessage(e));
    }
  }

  /// Withdraws a pending request.
  Future<void> cancel() async {
    if (state.busy || state.phase != StudioJoinPhase.pending) return;
    state = state.copyWith(busy: true, phase: StudioJoinPhase.idle, clearError: true);
    try {
      await _api.cancelRequest(streamId);
      if (ref.mounted) state = state.copyWith(busy: false);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, phase: StudioJoinPhase.pending, error: studioErrorMessage(e));
    }
  }

  /// After the device check: publish camera/mic. Reconnects first when the
  /// room still lacks publish permission (server asked to rejoin, or the
  /// in-place permission update has not arrived).
  Future<void> goOnStage({required bool micOn, required bool camOn}) async {
    if (!state.onStage || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final room = ref.read(studioRolesRoomProvider(streamId));
      final rejoiner = ref.read(studioRoomRejoinerProvider);
      if (_rejoining != null) await _rejoining;
      if (rejoiner.canPublish(room) == false) await rejoiner.rejoin(room);
      await room.setCameraEnabled(camOn);
      await room.setMicEnabled(micOn);
      unawaited(ref
          .read(studioMediaApiProvider)
          .setOwnMedia(streamId, micOn: micOn, camOn: camOn)
          .then((_) {}, onError: (_) {}));
      if (ref.mounted) state = state.copyWith(busy: false, publishing: true);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: studioErrorMessage(e));
    }
  }

  /// Leaves the stage after [confirm] returns true. Returns whether it left.
  Future<bool> leaveStage(StudioConfirm confirm) async {
    if (!state.onStage || state.busy) return false;
    final ok = await confirm(const StudioConfirmPrompt(
      title: 'Leave the stage?',
      message: 'Your camera and mic stop. You keep watching the live.',
      confirmLabel: 'Leave stage',
    ));
    if (!ok || !ref.mounted) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final room = ref.read(studioRolesRoomProvider(streamId));
      await _api.leaveStage(streamId);
      await room.setCameraEnabled(false);
      await room.setMicEnabled(false);
      _role = StudioRole.viewer; // the members doc follows
      _doc = null;
      if (ref.mounted) state = state.copyWith(busy: false, phase: StudioJoinPhase.idle, publishing: false);
      return true;
    } catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: studioErrorMessage(e));
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}
