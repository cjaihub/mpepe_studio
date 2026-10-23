// LIVE STUDIO v2 — "On the table" controller (workstream #5).
//
// Exposes the current [TableState] from the studio session (`.states`), the
// viewer's local Join ↔ Watching flags, and the manager commands, which go
// through the `lsSetTable` / `lsPlayback` callables (server-authoritative).
//
// Ports (all overridable in tests):
// - [studioTableStateSourceProvider] → the session's `StudioState` stream;
// - [studioTableRoleProvider] → my role;
// - [studioTableRoomProvider] → the LiveKit room (screen share);
// - [studioTableApiProvider] → callables.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../session/studio_session_controller.dart';

// ─── Ports ───────────────────────────────────────────────────────────────────

final studioTableStateSourceProvider = Provider.autoDispose.family<Stream<StudioState>, String>(
    (ref, streamId) => ref.watch(studioSessionProvider(streamId).notifier).states);

final studioTableRoleProvider = Provider.autoDispose.family<StudioRole, String>(
    (ref, streamId) => ref.watch(studioMyRoleProvider(streamId)).value ?? StudioRole.viewer);

final studioTableRoomProvider = Provider.autoDispose.family<StudioRoomPort, String>(
    (ref, streamId) => ref.watch(studioRoomProvider(streamId)));

final studioTableMyUidProvider = Provider<String?>((ref) => ref.watch(studioMyUidProvider));

/// Typed wrapper over `lsSetTable` / `lsPlayback`. Both return
/// `{ok, seq, table}`; this returns the table plus its seq.
class StudioTableApi {
  StudioTableApi(this._port);
  final StudioCallPort _port;

  Future<(int, TableState)?> setTable(String streamId, TableMode mode, {Map<String, Object?>? ref}) async {
    final res = await _port.call(StudioCallables.setTable, {
      'streamId': streamId,
      'mode': mode.wire,
      'ref': ?ref,
    });
    return _parse(res);
  }

  Future<(int, TableState)?> playback(String streamId, PlaybackState state, int positionMs) async {
    final res = await _port.call(StudioCallables.playback, {
      'streamId': streamId,
      'state': state.wire,
      'positionMs': positionMs < 0 ? 0 : positionMs,
    });
    return _parse(res);
  }

  static (int, TableState)? _parse(Map<String, dynamic> res) {
    final t = res['table'];
    if (t is! Map) return null;
    final seq = res['seq'] is num ? (res['seq'] as num).toInt() : 0;
    return (seq, TableState.fromJson(Map<String, dynamic>.from(t)));
  }
}

final studioTableApiProvider =
    Provider<StudioTableApi>((ref) => StudioTableApi(ref.watch(studioCallPortProvider)));

// ─── View ────────────────────────────────────────────────────────────────────

@immutable
class StudioTableView {
  const StudioTableView({
    this.table = const TableState(),
    this.seq = -1,
    this.ready = false,
    this.role = StudioRole.viewer,
    this.joined = const <TableMode>{},
    this.busy = false,
    this.pendingMode,
    this.error,
  });

  final TableState table;
  final int seq;
  final bool ready;
  final StudioRole role;

  /// Local, per viewer: stream modes this viewer joined ("Watching").
  final Set<TableMode> joined;
  final bool busy;

  /// The mode a manager just picked, until the server confirms it.
  final TableMode? pendingMode;
  final Object? error;

  TableMode get mode => table.mode;

  /// What the pickers highlight (optimistic for managers).
  TableMode get shownMode => pendingMode ?? table.mode;
  bool get canManage => role.isManager;
  bool isJoined(TableMode m) => m.isStream && joined.contains(m);
  bool get watchingCurrent => isJoined(table.mode);

  StudioTableView copyWith({
    TableState? table,
    int? seq,
    bool? ready,
    StudioRole? role,
    Set<TableMode>? joined,
    bool? busy,
    TableMode? Function()? pendingMode,
    Object? Function()? error,
  }) =>
      StudioTableView(
        table: table ?? this.table,
        seq: seq ?? this.seq,
        ready: ready ?? this.ready,
        role: role ?? this.role,
        joined: joined ?? this.joined,
        busy: busy ?? this.busy,
        pendingMode: pendingMode == null ? this.pendingMode : pendingMode(),
        error: error == null ? this.error : error(),
      );
}

// ─── Controller ──────────────────────────────────────────────────────────────

final studioTableControllerProvider = NotifierProvider.autoDispose
    .family<StudioTableController, StudioTableView, String>(StudioTableController.new);

/// The table state alone (rebuilds only when it changes).
final studioTableStateProvider = Provider.autoDispose.family<TableState, String>(
    (ref, streamId) => ref.watch(studioTableControllerProvider(streamId).select((v) => v.table)));

class StudioTableController extends Notifier<StudioTableView> {
  StudioTableController(this.streamId);

  final String streamId;
  late StudioTableApi _api;
  int _inFlight = 0;

  @override
  StudioTableView build() {
    _api = ref.watch(studioTableApiProvider);
    final role = ref.watch(studioTableRoleProvider(streamId));
    final source = ref.watch(studioTableStateSourceProvider(streamId));
    final sub = source.listen(_onState, onError: (Object _) {});
    ref.onDispose(sub.cancel);
    _inFlight = 0;
    return StudioTableView(role: role);
  }

  void _onState(StudioState s) {
    if (s.seq < state.seq) return;
    _apply(s.seq, s.table);
  }

  void _apply(int seq, TableState t) {
    if (seq < state.seq) return;
    final pending = state.pendingMode;
    state = state.copyWith(
      table: t,
      seq: seq,
      ready: true,
      pendingMode: () => pending != null && pending != t.mode && _inFlight > 0 ? pending : null,
    );
  }

  // ── Local (viewer) ──

  /// Join ↔ Watching for a stream mode. Local only.
  void toggleJoin([TableMode? mode]) {
    final m = mode ?? state.table.mode;
    if (!m.isStream) return;
    final next = Set<TableMode>.of(state.joined);
    if (!next.remove(m)) next.add(m);
    state = state.copyWith(joined: next);
  }

  void setJoined(TableMode mode, bool on) {
    if (state.isJoined(mode) != on) toggleJoin(mode);
  }

  // ── Manager commands (no-ops for viewers/guests) ──

  /// Switches the table; the server picks the default content for the mode
  /// (goods: Biz first then stream list; match/movie: first valid catalog
  /// entry or none; screen: me as publisher).
  Future<bool> setMode(TableMode mode) => _set(mode, null);

  Future<bool> putGoods(GoodsRef goods) => _set(TableMode.goods, goods.toJson());

  Future<bool> putWatch(TableMode mode, String catalogId) {
    assert(mode.isWatchParty);
    return _set(mode, {'catalogId': catalogId});
  }

  Future<bool> putScreen({String? publisherUid}) =>
      _set(TableMode.screen, publisherUid == null ? null : {'publisherUid': publisherUid});

  Future<bool> play(int positionMs) => _playback(PlaybackState.playing, positionMs);
  Future<bool> pause(int positionMs) => _playback(PlaybackState.paused, positionMs);
  Future<bool> end(int positionMs) => _playback(PlaybackState.ended, positionMs);

  /// Seeks keeping the current play/pause state.
  Future<bool> seek(int positionMs) =>
      _playback(state.table.watch?.state ?? PlaybackState.paused, positionMs);

  /// Starts my screen share, then puts it on the table. Stops the share again
  /// if the table could not be set.
  Future<bool> shareScreenToTable() async {
    if (!state.canManage) return false;
    final room = ref.read(studioTableRoomProvider(streamId));
    try {
      await room.startTableScreenShare();
    } catch (e) {
      state = state.copyWith(error: () => e);
      return false;
    }
    final ok = await _set(TableMode.screen, null);
    if (!ok) {
      try {
        await room.stopTableScreenShare();
      } catch (_) {}
    }
    return ok;
  }

  Future<void> stopScreenShare() async {
    try {
      await ref.read(studioTableRoomProvider(streamId)).stopTableScreenShare();
    } catch (e) {
      state = state.copyWith(error: () => e);
    }
  }

  Future<bool> _set(TableMode mode, Map<String, Object?>? r) async {
    if (!state.canManage) return false;
    _begin(pending: mode);
    try {
      final res = await _api.setTable(streamId, mode, ref: r);
      if (!ref.mounted) return true;
      _end();
      if (res != null) _apply(res.$1, res.$2);
      state = state.copyWith(pendingMode: () => null, error: () => null);
      return true;
    } catch (e) {
      if (!ref.mounted) return false;
      _end();
      state = state.copyWith(pendingMode: () => null, error: () => e);
      return false;
    }
  }

  Future<bool> _playback(PlaybackState s, int positionMs) async {
    if (!state.canManage || !state.table.mode.isWatchParty || state.table.watch == null) return false;
    _begin();
    try {
      final res = await _api.playback(streamId, s, positionMs);
      if (!ref.mounted) return true;
      _end();
      if (res != null) _apply(res.$1, res.$2);
      state = state.copyWith(error: () => null);
      return true;
    } catch (e) {
      if (!ref.mounted) return false;
      _end();
      state = state.copyWith(error: () => e);
      return false;
    }
  }

  void _begin({TableMode? pending}) {
    _inFlight++;
    state = state.copyWith(busy: true, pendingMode: pending == null ? null : () => pending);
  }

  void _end() {
    _inFlight = (_inFlight - 1).clamp(0, 1 << 30);
    state = state.copyWith(busy: _inFlight > 0);
  }
}
